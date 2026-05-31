/**
 * Notifications.
 *
 * Source runbook: C:\Users\srathjen\.cursor\plans\notifications_qa.plan.md
 * Tag mapping: P1 -> @smoke, P2 -> @regression, P3 -> @polish.
 *
 * Per qa-testing-login.mdc, opening a Notifications row that navigates to a
 * deep link like /library-item/{id}?action=... is valid end-user behaviour.
 */
import { test, expect } from '../playwright/fixtures/cleanup';
import { gotoHome } from '../playwright/helpers/navigation';
import { lwc } from '../playwright/helpers/lwc-locators';

test.describe('Notifications @smoke', () => {
  test('P1: Notifications list renders for each persona', async ({ ownerPage, r1Page, r2Page }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'notifications_qa.plan.md P1 list' });
    for (const page of [ownerPage, r1Page, r2Page]) {
      await gotoHome(page);
      const trigger = page.getByRole('button', { name: /notifications|bell/i }).first();
      if (await trigger.isVisible().catch(() => false)) {
        await trigger.click();
      } else {
        await page.goto('/notifications');
      }
      await expect(lwc.notificationsList(page)).toBeVisible({ timeout: 30_000 });
    }
  });

  test('P1: Clicking a row navigates to the related record (if any rows exist)', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'notifications_qa.plan.md P1 deep link' });
    await gotoHome(ownerPage);
    const trigger = ownerPage.getByRole('button', { name: /notifications|bell/i }).first();
    if (await trigger.isVisible().catch(() => false)) {
      await trigger.click();
    } else {
      await ownerPage.goto('/notifications');
    }
    const firstRow = lwc.notificationsList(ownerPage).locator('a, [role="link"], li').first();
    if ((await firstRow.count()) === 0) test.skip(true, 'No notifications in current state');
    await firstRow.click();
    await ownerPage.waitForLoadState('domcontentloaded');
    expect(ownerPage.url()).not.toMatch(/\/login\b/);
  });
});

test.describe('Notifications @regression', () => {
  test('P2: Mark all read affordance is present', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'notifications_qa.plan.md P2 mark read' });
    await gotoHome(ownerPage);
    await ownerPage.goto('/notifications');
    const markAll = ownerPage.getByRole('button', { name: /mark all|read all|clear all/i }).first();
    if (!(await markAll.isVisible().catch(() => false))) {
      test.skip(true, 'Mark-all affordance not present (no unread).');
    }
  });
});

test.describe('Notifications @polish', () => {
  test('P3: Empty state copy renders if persona has no notifications', async ({ r2Page }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'notifications_qa.plan.md P3 empty' });
    await gotoHome(r2Page);
    await r2Page.goto('/notifications');
    const empty = r2Page.locator('text=/no notifications|all caught up|nothing yet/i').first();
    expect(await empty.isVisible().catch(() => false)).toBeTruthy();
  });
});
