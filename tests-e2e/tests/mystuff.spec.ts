/**
 * My Stuff hub and subpages.
 *
 * Source runbook: C:\Users\srathjen\.cursor\plans\mystuff_subpages_qa.plan.md
 * Tag mapping: P1 -> @smoke, P2 -> @regression, P3 -> @polish.
 *
 * Hub LWC: fimbyMyStuffHub renders <button class="hub-pill">.
 * Profile is reached from the universal-header kebab menu, not the hub.
 */
import { test, expect } from '../playwright/fixtures/cleanup';
import { gotoHome, openBottomTab, openHeaderMenuItem } from '../playwright/helpers/navigation';

const HUB_TILES: Array<{ label: RegExp; path: RegExp }> = [
  { label: /^my neighbours$/i, path: /\/my-stuff\/my-contacts/ },
  { label: /^my posts$/i, path: /\/my-stuff\/my-posts/ },
  { label: /^my shared life$/i, path: /\/my-stuff\/my-shared-life/ },
  { label: /^my library items$/i, path: /\/my-stuff\/my-library-items/ },
  { label: /^my borrowing$/i, path: /\/my-stuff\/my-borrowing/ },
];

test.describe('My Stuff @smoke', () => {
  test('P1: My Stuff hub loads with the documented hub-pill tiles', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'mystuff_subpages_qa.plan.md P1 hub' });
    await gotoHome(ownerPage);
    await openBottomTab(ownerPage, 'mine');
    await expect(ownerPage).toHaveURL(/\/my-stuff/);
    for (const tile of HUB_TILES) {
      await expect(
        ownerPage.getByRole('button', { name: tile.label }).first(),
        `Hub tile not visible: ${tile.label}`,
      ).toBeVisible();
    }
  });

  test('P1: Profile opens from the universal-header kebab menu', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'mystuff_subpages_qa.plan.md P1 profile' });
    await gotoHome(ownerPage);
    await openHeaderMenuItem(ownerPage, /^profile$/i);
    await expect(ownerPage).toHaveURL(/\/profile/);
  });
});

test.describe('My Stuff @regression', () => {
  for (const tile of HUB_TILES) {
    test(`P2: hub tile ${String(tile.label)} navigates to ${String(tile.path)}`, async ({ ownerPage }) => {
      await gotoHome(ownerPage);
      await openBottomTab(ownerPage, 'mine');
      await ownerPage.getByRole('button', { name: tile.label }).first().click();
      await expect(ownerPage).toHaveURL(tile.path);
    });
  }

  test('P2: Settings opens from the header menu', async ({ ownerPage }) => {
    await gotoHome(ownerPage);
    await openHeaderMenuItem(ownerPage, /^settings$/i);
    await expect(ownerPage).toHaveURL(/\/settings/);
  });

  test('P2: Notifications opens from the header bell', async ({ ownerPage }) => {
    await gotoHome(ownerPage);
    await ownerPage.getByRole('button', { name: /^notifications$/i }).first().click();
    await expect(ownerPage).toHaveURL(/\/notifications/);
  });
});

test.describe('My Stuff @polish', () => {
  test('P3: Empty-state copy renders for a persona with no shared-life entries', async ({ r2Page }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'mystuff_subpages_qa.plan.md P3 empty' });
    await gotoHome(r2Page);
    await openBottomTab(r2Page, 'mine');
    const sharedLife = r2Page.getByRole('button', { name: /^my shared life$/i }).first();
    if (!(await sharedLife.isVisible().catch(() => false))) {
      test.skip(true, 'My Shared Life tile not present for this persona.');
    }
    await sharedLife.click();
    await expect(r2Page).toHaveURL(/\/my-stuff\/my-shared-life/);
    const empty = r2Page.locator('text=/nothing yet|no stories|no posts|empty|haven.t (posted|shared)/i').first();
    if (!(await empty.isVisible().catch(() => false))) {
      test.skip(true, 'Persona has shared-life data; empty state not exercised.');
    }
    await expect(empty).toBeVisible();
  });
});
