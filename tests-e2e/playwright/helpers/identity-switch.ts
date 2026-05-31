import type { Page } from '@playwright/test';
import { expect } from '@playwright/test';

/**
 * Helpers for switching the "acting as" identity through the visible UI.
 * Backed by `fimbyManageIdentities` at /manage-identities, which is reached
 * from the Profile/My Stuff menu in real user flows.
 *
 * These never click directly to /manage-identities — they navigate through
 * the user-visible affordance.
 */

/** Open the identity switcher from anywhere in the app via the header avatar. */
export async function openIdentityMenu(page: Page): Promise<void> {
  const avatar = page
    .getByRole('button', { name: /account|profile|identity|menu/i })
    .first();
  await avatar.click();
}

/** Switch to a represented identity by display name. Returns when the page reflects the new acting-as banner. */
export async function switchActingAs(page: Page, displayName: string | RegExp): Promise<void> {
  await openIdentityMenu(page);
  const manage = page.getByRole('link', { name: /manage identities|switch identity/i }).first();
  if ((await manage.count()) > 0) {
    await manage.click();
    await page.waitForURL(/\/manage-identities/);
  }
  const row = page
    .locator('[data-identity-row], li, tr, .slds-card')
    .filter({ hasText: displayName })
    .first();
  await row.scrollIntoViewIfNeeded();
  const switchBtn = row.getByRole('button', { name: /switch|use this|act as/i }).first();
  await switchBtn.click();
  await expect(page.getByText(/posting as|acting as|responding as/i)).toBeVisible({ timeout: 15_000 });
}

/** Return to the real user identity. */
export async function switchToSelf(page: Page): Promise<void> {
  await openIdentityMenu(page);
  const link = page.getByRole('link', { name: /manage identities|switch identity/i }).first();
  if ((await link.count()) > 0) await link.click();
  const myselfRow = page
    .locator('[data-identity-row], li, tr, .slds-card')
    .filter({ hasText: /myself|my account/i })
    .first();
  const switchBtn = myselfRow.getByRole('button', { name: /switch|use this|act as/i }).first();
  await switchBtn.click();
}
