import type { Locator, Page } from '@playwright/test';
import { expect } from '@playwright/test';

/**
 * UI-first navigation primitives. Per qa-testing-login.mdc, tests should reach
 * pages by clicking visible UI, not by typing internal routes. The single
 * exception is the entry point `/` after login which is normal app behaviour.
 */

export async function gotoHome(page: Page): Promise<void> {
  await page.goto('/');
  await page.waitForLoadState('domcontentloaded');
  await expect(page).toHaveURL(/\/(home|s|s\/)?$|\/$/);
}

/**
 * Open the bottom-tab nav by name. Tab names mirror TAB_ROUTES in fimbyUniversalHeader.
 *
 * Both `fimbyUniversalHeader` (desktop) and `fimbyBottomNavigation` (mobile) render
 * a button with `data-tab="<tab>" aria-label="<Label>"`. CSS hides one or the other
 * by viewport. We use `[data-tab=...]:visible` so the click hits whichever is
 * actually rendered at the current project viewport.
 */
export async function openBottomTab(page: Page, tab: 'home' | 'library' | 'messages' | 'mine'): Promise<void> {
  const button = page.locator(`[data-tab="${tab}"]:visible`).first();
  await button.click();
  await page.waitForLoadState('domcontentloaded');
}

/**
 * Open the universal-header kebab menu (the flyout that contains Profile,
 * Settings, Help, Feedback, Logout). Works at both desktop and mobile because
 * the menu button shares a single `aria-label="Menu"`.
 */
export async function openHeaderMenu(page: Page): Promise<void> {
  await page.getByRole('button', { name: /^menu$/i }).first().click();
  await page.getByRole('button', { name: /^profile$/i }).first().waitFor({ state: 'visible' });
}

/** Click an item inside the header kebab menu by its aria-label / visible name. */
export async function openHeaderMenuItem(page: Page, name: RegExp | string): Promise<void> {
  await openHeaderMenu(page);
  await page.getByRole('button', { name }).first().click();
  await page.waitForLoadState('domcontentloaded');
}

/** Click a card by visible heading text, scoped to a feed/list region. */
export async function openCardByHeading(page: Page, heading: string | RegExp): Promise<void> {
  const card = page
    .locator('article, [role="article"], .fimby-card, lightning-card')
    .filter({ hasText: heading })
    .first();
  await card.scrollIntoViewIfNeeded();
  await card.click();
  await page.waitForLoadState('domcontentloaded');
}

/** Scroll until a locator is visible and not blocked by fixed footers. */
export async function scrollUntilVisible(target: Locator, page: Page, maxAttempts = 10): Promise<void> {
  for (let i = 0; i < maxAttempts; i += 1) {
    if (await target.isVisible().catch(() => false)) {
      await target.scrollIntoViewIfNeeded();
      return;
    }
    await page.mouse.wheel(0, 600);
    await page.waitForTimeout(250);
  }
  await target.scrollIntoViewIfNeeded();
}
