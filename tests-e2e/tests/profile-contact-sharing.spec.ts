/**
 * Profile, Neighbour profile, contact sharing.
 *
 * Source runbook: C:\Users\srathjen\.cursor\plans\profile_neighbour_contact_sharing_qa.plan.md
 * Tag mapping: P1 -> @smoke, P2 -> @regression, P3 -> @polish.
 *
 * Contact sharing creates Shared_Contact_Info__c records anchored by name where
 * possible; cleanup.afterEach sweeps them. SCI without a [E2E] anchor falls
 * back to deletion via Response__c parent (also anchored).
 */
import { test, expect } from '../playwright/fixtures/cleanup';
import { gotoHome, openHeaderMenuItem } from '../playwright/helpers/navigation';

test.describe('Profile @smoke', () => {
  test('P1: Profile page loads for the acting persona', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'profile_neighbour_contact_sharing_qa.plan.md P1 profile' });
    await gotoHome(ownerPage);
    await openHeaderMenuItem(ownerPage, /^profile$/i);
    await expect(ownerPage).toHaveURL(/\/profile/);
    // Profile content is rendered by the page-level LWC bound in Experience Builder;
    // we just need confirmation that the route resolved to a populated page (something
    // beyond the global header).
    await expect(ownerPage.locator('main, [role="main"], .profile, .fimby-profile').first()).toBeVisible({
      timeout: 30_000,
    });
  });

  test('P1: Neighbour profile reachable from a feed card avatar', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'profile_neighbour_contact_sharing_qa.plan.md P1 neighbour' });
    await gotoHome(ownerPage);
    // Feed cards expose neighbour profile entry points either as <a href="/neighbour/...">
    // or as a button with a name ending in the neighbour's display name. We accept
    // either; if neither is present the persona's feed has no posts and the test skips.
    const link = ownerPage.locator('a[href*="/neighbour/"]').first();
    if ((await link.count()) === 0) {
      test.skip(true, 'No neighbour avatar links visible in current feed for this persona.');
    }
    await link.click();
    await expect(ownerPage).toHaveURL(/\/neighbour/);
  });
});

test.describe('Contact sharing @regression', () => {
  test('P2: Share contact info modal opens from a response thread (if any exists)', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'profile_neighbour_contact_sharing_qa.plan.md P2 share' });
    await gotoHome(ownerPage);
    test.fixme(
      true,
      'Share Contact Info modal needs an active Response__c thread. Wire after lending-lifecycle P1-B unblocks the borrow path.',
    );
  });
});

test.describe('Profile polish @polish', () => {
  test('P3: Profile shows acting-as identity banner when switched', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'profile_neighbour_contact_sharing_qa.plan.md P3 acting-as' });
    test.fixme(
      true,
      'Requires an Approved Support_Relationship__c for the owner persona. Wire in shakedown after seed data is confirmed.',
    );
    expect(ownerPage).toBeTruthy();
  });
});
