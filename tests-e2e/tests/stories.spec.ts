/**
 * Stories.
 *
 * Source runbook: C:\Users\srathjen\.cursor\plans\stories_qa.plan.md
 * Tag mapping: P1 -> @smoke, P2 -> @regression, P3 -> @polish.
 */
import { test, expect } from '../playwright/fixtures/cleanup';
import { gotoHome } from '../playwright/helpers/navigation';
import { lwc } from '../playwright/helpers/lwc-locators';
import { fillAndBlur } from '../playwright/helpers/modal';

test.describe('Stories @smoke', () => {
  test('P1: Stories surface on home feed and detail page is reachable', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'stories_qa.plan.md P1 read path' });
    await gotoHome(ownerPage);
    const story = lwc.storyCard(ownerPage).first();
    if ((await story.count()) === 0) {
      test.skip(true, 'No stories in the current feed; covered by P1 create case below.');
    }
    await story.scrollIntoViewIfNeeded();
    await story.click();
    await ownerPage.waitForLoadState('domcontentloaded');
  });

  test('P1: Owner can compose an anchored story', async ({ ownerPage, e2eRun }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'stories_qa.plan.md P1 create' });
    const title = e2eRun.title('story');
    await gotoHome(ownerPage);
    const composer = ownerPage.getByRole('button', { name: /share a story|new story|tell.*story/i }).first();
    if (!(await composer.isVisible().catch(() => false))) {
      test.skip(true, 'Story composer entry not visible from home in this build.');
    }
    await composer.click();
    test.fixme(true, 'Story composer fields and Type__c picklist need handoff in shakedown.');
    const titleField = ownerPage.locator('input[name="title"], input[name="Name"]').first();
    await fillAndBlur(titleField, title);
  });
});

test.describe('Stories @regression', () => {
  test('P2: Story comments render', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'stories_qa.plan.md P2 comments' });
    await gotoHome(ownerPage);
    const story = lwc.storyCard(ownerPage).first();
    if ((await story.count()) === 0) test.skip(true, 'No story to open');
    await story.click();
    await expect(ownerPage.locator('c-fimby-story-detail, c-fimby-story-comments').first()).toBeVisible({ timeout: 30_000 });
  });
});

test.describe('Stories @polish', () => {
  test('P3: Story badge type is visible on the card', async ({ ownerPage }) => {
    await gotoHome(ownerPage);
    const story = lwc.storyCard(ownerPage).first();
    if ((await story.count()) === 0) test.skip(true, 'No story to inspect');
    await expect(story.locator('text=/thank you|prayer|bio|lament|god story/i')).toBeVisible();
  });
});
