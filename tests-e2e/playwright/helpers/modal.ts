import type { Locator, Page } from '@playwright/test';
import { expect } from '@playwright/test';

/**
 * Shadow-DOM-aware modal interaction. Lightning's `lightning-modal` and the
 * FIMBY `fimbyRecordEditModal` both render through SLDS modal overlays; clicks
 * sometimes intercept on the host. Playwright pierces shadow DOM natively, so
 * targeting by role + name works, but we still need to disambiguate when the
 * page has an active modal layered over a form behind it.
 */

export function activeModal(page: Page): Locator {
  return page
    .locator('[role="dialog"]:not([aria-hidden="true"]), .slds-modal.slds-fade-in-open')
    .last();
}

export async function expectModalOpen(page: Page, headingText?: string | RegExp): Promise<Locator> {
  const modal = activeModal(page);
  await expect(modal).toBeVisible({ timeout: 15_000 });
  if (headingText) {
    await expect(modal.getByRole('heading', { name: headingText })).toBeVisible();
  }
  return modal;
}

export async function clickModalButton(page: Page, name: string | RegExp): Promise<void> {
  const modal = activeModal(page);
  const button = modal.getByRole('button', { name }).first();
  await button.scrollIntoViewIfNeeded();
  await button.click();
}

/** Lightning inputs need blur to enable Submit; this helper fills then blurs. */
export async function fillAndBlur(target: Locator, value: string): Promise<void> {
  await target.click();
  await target.fill(value);
  await target.blur();
}

export async function dismissToast(page: Page): Promise<void> {
  const toast = page.locator('.slds-notify_toast .slds-notify__close, [data-key="close"]').first();
  if (await toast.isVisible().catch(() => false)) {
    await toast.click().catch(() => undefined);
  }
}
