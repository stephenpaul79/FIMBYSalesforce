/**
 * Kebab menus + Search.
 *
 * Source runbook: C:\Users\srathjen\.cursor\plans\kebab_search_qa.plan.md
 * Tag mapping: P1 -> @smoke, P2 -> @regression, P3 -> @polish.
 *
 * Header search lives in fimbyUniversalHeader:
 *   trigger:   button.search-button[aria-label="Search"]
 *   input:     input[data-id="search-modal-input"]
 *   submit:    button.search-modal-submit[aria-label="Search"]
 *   clear:     button.search-modal-clear[aria-label="Clear search"]
 * Submit (or Enter) navigates to /search?q=<term> handled by fimbySearch.
 */
import { test, expect } from '../playwright/fixtures/cleanup';
import { gotoHome } from '../playwright/helpers/navigation';

test.describe('Search @smoke', () => {
  test('P1: Header search opens, accepts a query, and routes to /search?q=...', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'kebab_search_qa.plan.md P1 search lifecycle' });
    await gotoHome(ownerPage);

    await ownerPage.locator('button.search-button:visible').first().click();
    const input = ownerPage.locator('input[data-id="search-modal-input"]');
    await expect(input).toBeVisible();
    await input.fill('library');
    await input.press('Enter');

    await ownerPage.waitForURL(/\/search\?q=library/i, { timeout: 15_000 });
    await expect(ownerPage).toHaveURL(/\/search\?q=library/i);
  });
});

test.describe('Search @regression', () => {
  test('P2: Submit button (not just Enter) also routes to /search', async ({ ownerPage }) => {
    await gotoHome(ownerPage);
    await ownerPage.locator('button.search-button:visible').first().click();
    const input = ownerPage.locator('input[data-id="search-modal-input"]');
    await input.fill('offer');
    await ownerPage.locator('button.search-modal-submit').first().click();
    await ownerPage.waitForURL(/\/search\?q=offer/i, { timeout: 15_000 });
  });

  test('P2: Clear button empties the input', async ({ ownerPage }) => {
    await gotoHome(ownerPage);
    await ownerPage.locator('button.search-button:visible').first().click();
    const input = ownerPage.locator('input[data-id="search-modal-input"]');
    await input.fill('borrowing');
    const clear = ownerPage.locator('button.search-modal-clear');
    await expect(clear).toBeVisible();
    await clear.click();
    await expect(input).toHaveValue('');
  });
});

test.describe('Kebab menus @regression', () => {
  test('P2: Card kebab opens a menu when surfaced', async ({ ownerPage }) => {
    test.info().annotations.push({ type: 'qa-source', description: 'kebab_search_qa.plan.md P2 kebab' });
    test.fixme(
      true,
      'fimbyCard.showMenu defaults to false; the home feed Need/Offer/Story cards do not surface the More-options kebab. ' +
        'The kebab on My Posts / Post detail uses a different LWC. Wire this case once we author the My Posts list spec ' +
        'and can locate a card with showMenu=true. See fimbyCard.html line 25 (button.card-menu, aria-label="More options").',
    );
  });
});

test.describe('Search polish @polish', () => {
  test('P3: Empty-query submit shows guidance copy, not a crash', async ({ ownerPage }) => {
    await gotoHome(ownerPage);
    await ownerPage.locator('button.search-button:visible').first().click();
    const input = ownerPage.locator('input[data-id="search-modal-input"]');
    await expect(input).toBeVisible();
    // Hit Enter with no query and confirm the modal does not navigate (defensive: an empty-query
    // crash on /search would be a P1 regression). Either the URL stays put OR /search renders
    // a guidance state.
    await input.press('Enter');
    await ownerPage.waitForTimeout(500);
    const onSearchPage = /\/search/.test(ownerPage.url());
    if (onSearchPage) {
      await expect(
        ownerPage.locator('text=/start typing|search for|try|enter a search/i').first(),
      ).toBeVisible({ timeout: 10_000 });
    } else {
      await expect(input).toBeVisible();
    }
  });
});
