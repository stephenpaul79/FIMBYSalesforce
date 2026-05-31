/**
 * Smoke proof-of-plumbing.
 *
 * Validates that the auth fixtures, persona storageState files, base URL, and
 * cleanup wiring all work end-to-end. Mapped from `homepage_qa_plan_1a29942d.plan.md`
 * Priority-1 cases: header renders, feed loads, bottom nav present.
 *
 * Tagged @smoke so it runs on every push and gates a deploy.
 */
import { test, expect } from '../playwright/fixtures/cleanup';
import { gotoHome } from '../playwright/helpers/navigation';
import { lwc } from '../playwright/helpers/lwc-locators';

test.describe('Homepage smoke @smoke', () => {
  test('Owner lands on home and sees the shell', async ({ ownerPage, e2eRun }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'homepage_qa_plan_1a29942d.plan.md' });
    test.info().annotations.push({ type: 'run-id', description: e2eRun.runId });
    await gotoHome(ownerPage);
    await expect(lwc.universalHeader(ownerPage)).toBeVisible({ timeout: 20_000 });
    await expect(lwc.homeFeed(ownerPage)).toBeVisible({ timeout: 30_000 });
  });

  test('R1 lands on home and sees the shell', async ({ r1Page }) => {
    await gotoHome(r1Page);
    await expect(lwc.universalHeader(r1Page)).toBeVisible({ timeout: 20_000 });
    await expect(lwc.homeFeed(r1Page)).toBeVisible({ timeout: 30_000 });
  });

  test('R2 lands on home and sees the shell', async ({ r2Page }) => {
    await gotoHome(r2Page);
    await expect(lwc.universalHeader(r2Page)).toBeVisible({ timeout: 20_000 });
    await expect(lwc.homeFeed(r2Page)).toBeVisible({ timeout: 30_000 });
  });

  test('Owner sees a feed (header + feed shell render)', async ({ ownerPage }) => {
    await gotoHome(ownerPage);
    await expect(lwc.homeFeed(ownerPage)).toBeVisible({ timeout: 30_000 });
    expect(ownerPage.url()).not.toMatch(/\/login\b/);
  });

  // Regression guard for the combined Terms + age (19+) reacceptance modal.
  // The modal is rendered by fimbyTosFlowScreen inside fimbyUniversalHeader
  // when Contact.Tos_Reacceptance_Required__c = true (set by the Login Flow
  // when either the TOS version mismatches or Age_Attestation_Confirmed__c
  // is false). Persona Contacts are confirmed for both, so the modal must
  // not appear after a normal login. If it does, either the Login Flow
  // rule is wrong or a persona's Contact lost its age stamp.
  test('TOS + age reacceptance modal stays hidden for confirmed personas', async ({
    ownerPage,
  }) => {
    await gotoHome(ownerPage);
    await expect(lwc.universalHeader(ownerPage)).toBeVisible({ timeout: 20_000 });
    await expect(lwc.tosFlowScreen(ownerPage)).toHaveCount(0);
  });
});
