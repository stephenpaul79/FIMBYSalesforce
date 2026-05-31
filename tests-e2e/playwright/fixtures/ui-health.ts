/**
 * UI health monitor.
 *
 * Functional E2E tests verify behaviour (URL changed, button clicked, modal
 * opened) but happily ignore visual regressions like broken icons or 404'd
 * assets. The `uiHealth` fixture closes that gap by watching every persona
 * page for:
 *
 *   1. requestfailed   - any image / stylesheet / font that 404s or errors.
 *                        This is the most common cause of "all the icons are
 *                        broken" and other obvious UI regressions.
 *   2. pageerror       - any uncaught JS exception on the page.
 *   3. broken <img>    - after the test runs, walk every <img> in the DOM and
 *                        fail if its naturalWidth is 0 (it loaded but rendered
 *                        as the broken-image glyph). Catches cases where the
 *                        request "succeeded" with a non-image payload.
 *
 * Console errors are *also* collected, but only annotated (not failed) by
 * default - Salesforce Experience Cloud emits a fair amount of platform noise
 * on the console that we cannot control. Set `failOnConsoleError` to true on a
 * specific test if you want to lock that down for that case.
 *
 * Opting out
 * ----------
 * If a test legitimately expects a failure (e.g. negative test for a 404
 * route), tag it before the assertion:
 *
 *   test.info().annotations.push({ type: 'ui-health', description: 'opt-out' });
 *
 * To allow specific URL substrings to fail without breaking the test (e.g. a
 * known-broken third-party tracker pixel that is not our problem), add to
 * `KNOWN_FAILURE_ALLOWLIST` below.
 */
import { test as base, type Page } from '@playwright/test';

export interface UiHealthIssue {
  kind: 'asset-failed' | 'console-error' | 'page-error' | 'broken-image';
  page: string;
  detail: string;
}

export interface UiHealthFixture {
  attach(page: Page, label: string): void;
  snapshot(page: Page): Promise<void>;
  issues: UiHealthIssue[];
  setFailOnConsoleError(value: boolean): void;
}

export interface UiHealthFixtures {
  uiHealth: UiHealthFixture;
}

const ASSET_TYPES = new Set(['image', 'stylesheet', 'font']);

/**
 * Substrings we tolerate in a failed-request URL. Add reluctantly: anything
 * here is a UI defect we have decided not to gate on.
 *
 * Each entry MUST have a comment naming the defect-log ID (DEF-YYYY-NNN) it
 * corresponds to and the fix-condition that allows the entry to be removed.
 * When the underlying defect is resolved, delete the entry so the gate is
 * restored.
 */
const KNOWN_FAILURE_ALLOWLIST: readonly string[] = [
  // Legacy: very old posts saved Google Drive image links directly. These can
  // never load as <img> sources (ORB blocks them) and the posts pre-date the
  // current image-upload flow. Treated as historical noise; do not gate on.
  'drive.google.com/uc',
  // NOTE: fimby.file.force.com is intentionally NOT allowlisted. global-setup
  // pre-warms the cross-domain session cookie by navigating to a known
  // rendition URL during login, so tests should see these load successfully.
  // If the file domain starts failing again, it's a real regression — either
  // the warm-up broke (check global-setup logs for `pre-warmed
  // fimby.file.force.com`) or Salesforce changed something on the file domain.
];

/**
 * Substrings we tolerate in a console.error message. Salesforce Experience
 * Cloud is noisy; the goal is to filter platform chatter and keep app-level
 * signal.
 */
const CONSOLE_NOISE_ALLOWLIST: readonly string[] = [
  'aura:initialized',
  'Loaded module',
  'WebSocket connection',
  'Lightning Out',
];

function isAllowedFailure(url: string): boolean {
  return KNOWN_FAILURE_ALLOWLIST.some((needle) => url.includes(needle));
}

function isConsoleNoise(message: string): boolean {
  return CONSOLE_NOISE_ALLOWLIST.some((needle) => message.includes(needle));
}

export const test = base.extend<UiHealthFixtures>({
  uiHealth: async ({}, use, testInfo) => {
    const issues: UiHealthIssue[] = [];
    const attached = new Map<Page, string>();
    let failOnConsoleError = false;

    const fixture: UiHealthFixture = {
      issues,
      setFailOnConsoleError(value: boolean) {
        failOnConsoleError = value;
      },
      attach(page: Page, label: string) {
        if (attached.has(page)) return;
        attached.set(page, label);

        page.on('requestfailed', (req) => {
          if (!ASSET_TYPES.has(req.resourceType())) return;
          const failure = req.failure();
          const errorText = failure?.errorText ?? 'unknown';
          if (/aborted|cancel|ERR_ABORTED/i.test(errorText)) return;
          if (isAllowedFailure(req.url())) return;
          issues.push({
            kind: 'asset-failed',
            page: label,
            detail: `${req.resourceType()} ${req.url()} -> ${errorText}`,
          });
        });

        page.on('pageerror', (err) => {
          issues.push({
            kind: 'page-error',
            page: label,
            detail: err.message,
          });
        });

        page.on('console', (msg) => {
          if (msg.type() !== 'error') return;
          const text = msg.text();
          if (/Failed to load resource/i.test(text)) return; // covered by requestfailed
          if (isConsoleNoise(text)) return;
          issues.push({ kind: 'console-error', page: label, detail: text });
        });
      },
      async snapshot(page: Page) {
        const label = attached.get(page) ?? 'page';
        let broken: Array<{ src: string; alt: string }>;
        try {
          broken = await page.$$eval('img', (imgs) =>
            imgs
              .filter((img: HTMLImageElement) => {
                if (img.hasAttribute('data-allow-broken')) return false;
                if (!img.complete) return false;
                if (img.naturalWidth > 0) return false;
                const src = img.getAttribute('src') || '';
                if (!src) return false;
                return true;
              })
              .map((img: HTMLImageElement) => ({
                src: img.getAttribute('src') || '<inline>',
                alt: img.getAttribute('alt') || '',
              })),
          );
        } catch {
          return; // page may have been closed
        }
        for (const { src, alt } of broken) {
          if (isAllowedFailure(src)) continue;
          const detail = alt ? `${src} (alt="${alt}")` : src;
          issues.push({ kind: 'broken-image', page: label, detail });
        }
      },
    };

    await use(fixture);

    for (const [page] of attached) {
      if (page.isClosed()) continue;
      await fixture.snapshot(page);
    }

    const optedOut = testInfo.annotations.some(
      (a) => a.type === 'ui-health' && a.description === 'opt-out',
    );
    if (optedOut) return;

    const blocking = issues.filter((i) => {
      if (i.kind === 'console-error') return failOnConsoleError;
      return true;
    });

    if (blocking.length > 0) {
      const summary = blocking
        .map((i) => `  [${i.kind}] (${i.page}) ${i.detail}`)
        .join('\n');
      testInfo.annotations.push({
        type: 'ui-health-issues',
        description: `${blocking.length} blocking issue(s):\n${summary}`,
      });
      throw new Error(
        `UI health issues detected on ${testInfo.title}:\n${summary}\n\n` +
          `These are real UI regressions (404s on asset URLs, JS errors, or images that ` +
          `loaded but rendered broken). Fix them or, if intentional, add the URL substring ` +
          `to KNOWN_FAILURE_ALLOWLIST in playwright/fixtures/ui-health.ts.`,
      );
    }
    if (issues.length > 0) {
      // Non-blocking issues (console errors) - annotate so they show in the report.
      const summary = issues
        .map((i) => `  [${i.kind}] (${i.page}) ${i.detail}`)
        .join('\n');
      testInfo.annotations.push({
        type: 'ui-health-warnings',
        description: `${issues.length} non-blocking issue(s):\n${summary}`,
      });
    }
  },
});
