import { chromium, type FullConfig } from '@playwright/test';
import dotenv from 'dotenv';
import fs from 'node:fs';
import path from 'node:path';

dotenv.config({ path: path.resolve(__dirname, '..', '.env') });

export type PersonaKey = 'owner' | 'r1' | 'r2';

export interface PersonaConfig {
  key: PersonaKey;
  email: string;
  storagePath: string;
  label: string;
}

const AUTH_DIR = path.resolve(__dirname, '.auth');

export function personaStoragePath(key: PersonaKey): string {
  return path.join(AUTH_DIR, `${key}.json`);
}

export function loadPersonas(): PersonaConfig[] {
  const password = process.env.FIMBY_PERSONA_PASSWORD;
  if (!password) {
    throw new Error('FIMBY_PERSONA_PASSWORD missing. Copy .env.example to .env and fill it in.');
  }
  const owner = process.env.FIMBY_OWNER_EMAIL ?? 'desktop@fimby.com';
  const r1 = process.env.FIMBY_R1_EMAIL ?? 'mobiletester@fimby.com';
  const r2 = process.env.FIMBY_R2_EMAIL ?? 'sftester@fimby.com';
  return [
    { key: 'owner', email: owner, storagePath: personaStoragePath('owner'), label: 'Owner / Desktop Tester' },
    { key: 'r1', email: r1, storagePath: personaStoragePath('r1'), label: 'R1 / Mobile Tester' },
    { key: 'r2', email: r2, storagePath: personaStoragePath('r2'), label: 'R2 / SF Tester' },
  ];
}

/**
 * Logs a persona in via the visible /login form and saves storageState.
 * Reuses an existing storage file if it is fresh (<6h) unless forceRefresh.
 */
export async function loginPersona(persona: PersonaConfig, opts: { forceRefresh?: boolean } = {}): Promise<void> {
  const baseURL = process.env.FIMBY_BASE_URL ?? 'https://our.fimby.com';
  const password = process.env.FIMBY_PERSONA_PASSWORD!;
  fs.mkdirSync(AUTH_DIR, { recursive: true });

  if (!opts.forceRefresh && fs.existsSync(persona.storagePath)) {
    const ageMs = Date.now() - fs.statSync(persona.storagePath).mtimeMs;
    if (ageMs < 6 * 60 * 60 * 1000) {
      console.log(`[auth] reusing fresh session for ${persona.label} (${Math.round(ageMs / 60000)} min old)`);
      return;
    }
  }

  console.log(`[auth] logging in ${persona.label} (${persona.email})`);
  const browser = await chromium.launch();
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();
  try {
    await page.goto(`${baseURL}/login`, { waitUntil: 'domcontentloaded' });

    const emailField = page
      .locator('input[type="email"], input[name="username"], input[autocomplete="username"]')
      .first();
    await emailField.waitFor({ state: 'visible', timeout: 30_000 });
    await emailField.fill(persona.email);

    const passwordField = page
      .locator('input[type="password"], input[name="password"], input[autocomplete="current-password"]')
      .first();
    await passwordField.fill(password);
    await passwordField.blur();

    const submit = page
      .getByRole('button', { name: /log in|sign in|continue/i })
      .first();
    await Promise.all([
      page.waitForURL((url) => !/\/login\b/.test(url.pathname), { timeout: 45_000 }),
      submit.click(),
    ]);

    await page.waitForLoadState('networkidle', { timeout: 30_000 }).catch(() => undefined);

    // Pre-warm the Salesforce file domain (`fimby.file.force.com`) so cross-domain
    // ContentVersion rendition fetches succeed in tests. Real users get this cookie
    // passively the first time their browser loads any rendition image. Playwright
    // only navigates `our.fimby.com` during login, so without this step the saved
    // storageState lacks the file-domain session cookie and every <img src=
    // "https://fimby.file.force.com/...renditionDownload..."> fails with ERR_FAILED.
    //
    // Strategy: open the home feed, find a real rendition URL, then `goto()` it
    // in a fresh page so the browser performs Salesforce's cross-domain handshake
    // organically. The resulting cookies persist into context.storageState below.
    //
    // If we cannot find a rendition URL, FAIL LOUDLY. Optional: set
    // FIMBY_FILE_PREWARM_URL to a full renditionDownload URL so pre-warm does not
    // depend on the home feed (lazy LWC, modals, timing).
    const RENDITION_HOST = 'fimby.file.force.com/sfc/dist/version/renditionDownload';
    const envPrewarm = process.env.FIMBY_FILE_PREWARM_URL?.trim() ?? '';

    let renditionUrl: string | null = null;
    if (envPrewarm) {
      if (!envPrewarm.startsWith('https://fimby.file.force.com/')) {
        throw new Error(
          `[auth] FIMBY_FILE_PREWARM_URL must start with https://fimby.file.force.com/ (got ${envPrewarm.substring(0, 64)}…).`,
        );
      }
      if (!envPrewarm.includes('renditionDownload')) {
        throw new Error('[auth] FIMBY_FILE_PREWARM_URL should be a ContentVersion rendition URL (include renditionDownload).');
      }
      renditionUrl = envPrewarm;
      console.log(`[auth] ${persona.label}: using FIMBY_FILE_PREWARM_URL for file-domain pre-warm.`);
    } else {
      await page.goto(`${baseURL}/`, { waitUntil: 'domcontentloaded' });
      await page.waitForLoadState('networkidle', { timeout: 30_000 }).catch(() => undefined);

      const renditionLocator = page.locator(`img[src*="${RENDITION_HOST}"]`).first();
      renditionUrl = await renditionLocator
        .waitFor({ state: 'attached', timeout: 30_000 })
        .then(() => renditionLocator.getAttribute('src'))
        .catch(() => null);
    }

    if (!renditionUrl) {
      throw new Error(
        `[auth] ${persona.label}: cannot pre-warm fimby.file.force.com — no rendition image on the home feed ` +
          `within 30s. Set FIMBY_FILE_PREWARM_URL in .env to a full ` +
          `https://fimby.file.force.com/.../renditionDownload?... URL (open DevTools on any feed image, copy src), ` +
          `or ensure a post with an image is visible on / for this persona after login.`,
      );
    }

    const filePage = await context.newPage();
    try {
      const response = await filePage.goto(renditionUrl, { waitUntil: 'load', timeout: 30_000 });
      const status = response?.status();
      if (!status || status >= 400) {
        throw new Error(
          `[auth] ${persona.label}: pre-warm navigation to ${renditionUrl} returned HTTP ${status ?? 'no-response'}. ` +
            `Cross-domain auth handshake to fimby.file.force.com failed; tests will see broken renditions.`,
        );
      }
      const source = envPrewarm ? 'env URL' : 'home feed';
      console.log(
        `[auth] ${persona.label}: pre-warmed fimby.file.force.com (HTTP ${status}, ${source}) — file-domain cookies captured.`,
      );
    } finally {
      await filePage.close();
    }

    await context.storageState({ path: persona.storagePath });
    console.log(`[auth] saved storageState for ${persona.label} -> ${persona.storagePath}`);
  } finally {
    await context.close();
    await browser.close();
  }
}

export default async function globalSetup(_config: FullConfig): Promise<void> {
  const personas = loadPersonas();
  for (const persona of personas) {
    await loginPersona(persona);
  }
}
