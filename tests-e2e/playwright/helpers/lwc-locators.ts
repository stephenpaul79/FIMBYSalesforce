import type { Locator, Page } from '@playwright/test';

/**
 * Locators keyed to the LWC names called out in the QA tech maps
 * (C:\Users\srathjen\.cursor\plans\*_qa.plan.md). Playwright pierces shadow
 * DOM natively so you can use `page.locator('c-fimby-foo input[name="x"]')`
 * directly; this file just centralizes the conventional handles so specs read
 * like the QA plans.
 *
 * Add new entries here when a new LWC enters a spec — never inline LWC tag
 * names in the spec files.
 */

export const lwc = {
  universalHeader: (page: Page): Locator => page.locator('c-fimby-universal-header'),
  homeFeed: (page: Page): Locator => page.locator('c-fimby-home-feed, c-fimby-need-offer-feed').first(),
  needOfferCard: (page: Page): Locator => page.locator('c-fimby-need-offer-card'),
  bulkBuyCard: (page: Page): Locator => page.locator('c-fimby-bulk-buy-card'),
  storyCard: (page: Page): Locator => page.locator('c-fimby-story-card'),
  libraryItemCard: (page: Page): Locator => page.locator('c-fimby-library-item-card'),
  libraryBrowser: (page: Page): Locator => page.locator('c-fimby-library-browser'),
  conversationList: (page: Page): Locator => page.locator('c-fimby-conversation-list, c-fimby-messages-list').first(),
  conversationThread: (page: Page): Locator => page.locator('c-fimby-conversation-thread'),
  notificationsList: (page: Page): Locator => page.locator('c-fimby-notifications-list'),
  responseDetail: (page: Page): Locator => page.locator('c-fimby-response-detail'),
  responseReply: (page: Page): Locator => page.locator('c-fimby-response-reply'),
  manageIdentities: (page: Page): Locator => page.locator('c-fimby-manage-identities'),
  tosFlowScreen: (page: Page): Locator => page.locator('c-fimby-tos-flow-screen'),
  recordEditModal: (page: Page): Locator => page.locator('c-fimby-record-edit-modal'),
  imageUploader: (page: Page): Locator => page.locator('c-fimby-image-uploader'),
  responsiveList: (page: Page): Locator => page.locator('c-fimby-responsive-list'),
  infiniteScroll: (page: Page): Locator => page.locator('c-fimby-infinite-scroll'),
} as const;

/** Find a card in any feed by its visible heading text. */
export function cardByHeading(page: Page, heading: string | RegExp): Locator {
  return page
    .locator(
      'c-fimby-need-offer-card, c-fimby-bulk-buy-card, c-fimby-story-card, c-fimby-library-item-card, lightning-card, article',
    )
    .filter({ hasText: heading })
    .first();
}
