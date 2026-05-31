import {
  type Browser,
  type BrowserContext,
  type BrowserContextOptions,
  type Page,
} from '@playwright/test';
import { personaStoragePath, type PersonaKey } from '../global-setup';
import { test as uiHealthTest, type UiHealthFixtures } from './ui-health';

export interface PersonaFixtures extends UiHealthFixtures {
  ownerPage: Page;
  r1Page: Page;
  r2Page: Page;
  ownerContext: BrowserContext;
  r1Context: BrowserContext;
  r2Context: BrowserContext;
}

/**
 * Build a persona context that inherits viewport / device emulation from the
 * active project (`chromium-desktop` or `chromium-mobile` in playwright.config.ts).
 * Each spec therefore runs once at desktop and once at mobile, catching layout
 * collisions and breakpoint regressions without per-test code.
 */
async function buildPersonaContext(
  browser: Browser,
  key: PersonaKey,
  use: BrowserContextOptions,
): Promise<BrowserContext> {
  return browser.newContext({
    storageState: personaStoragePath(key),
    viewport: use.viewport,
    userAgent: use.userAgent,
    deviceScaleFactor: use.deviceScaleFactor,
    isMobile: use.isMobile,
    hasTouch: use.hasTouch,
    locale: use.locale,
    timezoneId: use.timezoneId,
  });
}

export const test = uiHealthTest.extend<Omit<PersonaFixtures, keyof UiHealthFixtures>>({
  ownerContext: async (
    { browser, viewport, userAgent, deviceScaleFactor, isMobile, hasTouch, locale, timezoneId },
    use,
  ) => {
    const ctx = await buildPersonaContext(browser, 'owner', {
      viewport,
      userAgent,
      deviceScaleFactor,
      isMobile,
      hasTouch,
      locale,
      timezoneId,
    });
    await use(ctx);
    await ctx.close();
  },
  r1Context: async (
    { browser, viewport, userAgent, deviceScaleFactor, isMobile, hasTouch, locale, timezoneId },
    use,
  ) => {
    const ctx = await buildPersonaContext(browser, 'r1', {
      viewport,
      userAgent,
      deviceScaleFactor,
      isMobile,
      hasTouch,
      locale,
      timezoneId,
    });
    await use(ctx);
    await ctx.close();
  },
  r2Context: async (
    { browser, viewport, userAgent, deviceScaleFactor, isMobile, hasTouch, locale, timezoneId },
    use,
  ) => {
    const ctx = await buildPersonaContext(browser, 'r2', {
      viewport,
      userAgent,
      deviceScaleFactor,
      isMobile,
      hasTouch,
      locale,
      timezoneId,
    });
    await use(ctx);
    await ctx.close();
  },
  ownerPage: async ({ ownerContext, uiHealth }, use) => {
    const page = await ownerContext.newPage();
    uiHealth.attach(page, 'owner');
    await use(page);
    await page.close();
  },
  r1Page: async ({ r1Context, uiHealth }, use) => {
    const page = await r1Context.newPage();
    uiHealth.attach(page, 'r1');
    await use(page);
    await page.close();
  },
  r2Page: async ({ r2Context, uiHealth }, use) => {
    const page = await r2Context.newPage();
    uiHealth.attach(page, 'r2');
    await use(page);
    await page.close();
  },
});

export { expect } from '@playwright/test';
