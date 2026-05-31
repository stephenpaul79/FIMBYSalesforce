import { defineConfig, devices } from '@playwright/test';
import dotenv from 'dotenv';
import path from 'node:path';

dotenv.config({ path: path.resolve(__dirname, '.env') });

const BASE_URL = process.env.FIMBY_BASE_URL ?? 'https://our.fimby.com';
const isCI = !!process.env.CI;

export default defineConfig({
  testDir: './tests',
  globalSetup: './playwright/global-setup.ts',
  fullyParallel: false,
  workers: 1,
  retries: isCI ? 1 : 0,
  timeout: 90_000,
  expect: { timeout: 15_000 },
  forbidOnly: isCI,
  reporter: isCI
    ? [['github'], ['html', { open: 'never', outputFolder: 'playwright-report' }], ['list']]
    : [['list'], ['html', { open: 'never', outputFolder: 'playwright-report' }]],
  use: {
    baseURL: BASE_URL,
    viewport: { width: 1280, height: 800 },
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    actionTimeout: 15_000,
    navigationTimeout: 30_000,
  },
  projects: [
    {
      name: 'chromium-desktop',
      use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 800 } },
    },
    {
      name: 'chromium-mobile',
      // Pixel 5 -> 393x851, isMobile, hasTouch, mobile UA. Catches collisions and
      // mobile-only layout drift that desktop never sees. The FIMBY architecture
      // breakpoint is 892px (qa runbooks treat <892 as mobile), so 393 sits
      // squarely in the mobile range.
      use: { ...devices['Pixel 5'] },
    },
  ],
  outputDir: 'test-results',
});
