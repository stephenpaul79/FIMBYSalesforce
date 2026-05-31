# FIMBY end-to-end suite (Playwright)

Persistent automated regression suite for the FIMBY1 Experience Cloud site at `https://our.fimby.com`. Translates the QA runbooks at `C:\Users\srathjen\.cursor\plans\*_qa.plan.md` into deterministic Playwright specs that run after every deploy and nightly in CI.

This is **not** a replacement for the exploratory `cursor-ide-browser` MCP — that is still the right tool for one-off poking and visual investigation. Playwright is the gate that catches regressions.

## Layout

```
tests-e2e/
  package.json                  # scripts + Playwright dep
  playwright.config.ts          # baseURL, two projects (desktop + mobile), trace on failure
  tsconfig.json
  .env.example                  # copy to .env
  playwright/
    global-setup.ts             # logs in 3 personas once, caches storageState
    refresh-auth.ts             # CLI to re-mint storageState
    .auth/                      # gitignored: owner.json, r1.json, r2.json
    fixtures/
      personas.ts               # ownerPage / r1Page / r2Page (pre-authed)
      cleanup.ts                # afterEach -> sf apex run FimbyTestDataCleanup
      anchored-data.ts          # [E2E] prefix + per-test runId
    helpers/
      navigation.ts             # UI-first navigation (no URL hacking)
      identity-switch.ts        # acting-as switching helpers
      modal.ts                  # shadow-DOM-aware modal interactions
      lwc-locators.ts           # locators keyed to LWC names from QA tech maps
      salesforce-cli.ts         # wraps `sf apex run`
      cleanup-cli.ts            # tsx entry: dryrun / cleanupRun / cleanupPrefix
  scripts/
    cleanup-run.apex.template
    cleanup-prefix.apex.template
  tests/                        # one spec per QA runbook (see mapping below)
```

## Setup (first time)

```powershell
cd C:\Users\srathjen\FIMBY\tests-e2e
npm install
npx playwright install --with-deps chromium
Copy-Item .env.example .env
# edit .env, set persona password and SF_ORG_ALIAS
sf org login web -a fimby-prod    # one-time SF CLI auth for cleanup
npm run auth:refresh              # mint persona storageState files
```

## Common commands

| Goal | Command |
| --- | --- |
| Smoke (P1, gates a deploy) | `npm run test:smoke` |
| Smoke → plain `last-smoke.log` (no ANSI; use after `auth:refresh` if image URLs fail) | `npm run test:smoke:log` |
| Smoke, Playwright UI mode | `npm run test:smoke:ui` |
| Search @smoke only, UI mode (fast sanity after auth) | `npm run test:search:ui` |
| Smoke + Regression (nightly) | `npm run test:regression` |
| Polish only | `npm run test:polish` |
| One spec | `npx playwright test tests/lending-lifecycle.spec.ts` |
| Headed (watch the browser) | `npm run test:headed` |
| Open last report | `npm run report` |
| Re-mint persona auth | `npm run auth:refresh` |
| Dry run cleanup (count `[E2E]` records) | `npm run cleanup:dryrun` |
| Auth refresh: “no rendition image” on home | Set `FIMBY_FILE_PREWARM_URL` in `.env` (copy a full `renditionDownload` URL from a feed image’s `img[src]`; see `.env.example`) |
| Desktop only (fast loop) | `npx playwright test --project=chromium-desktop --grep @smoke` |
| Mobile only (fast loop) | `npx playwright test --project=chromium-mobile --grep @smoke` |

## Viewports

Every spec runs at **two** viewports — Playwright manages this via projects in `playwright.config.ts`:

| Project | Size | Emulation | What it catches |
| --- | --- | --- | --- |
| `chromium-desktop` | 1280×800 | Desktop Chrome | Standard layout, header tabs |
| `chromium-mobile` | 393×851 | Pixel 5 (`isMobile`, `hasTouch`, mobile UA) | Bottom-nav, narrow-screen overflow, breakpoint collisions |

The FIMBY breakpoint is 892px, so the mobile project sits squarely in mobile-mode rendering. A failure that only shows up in `chromium-mobile` is a real responsive bug.

To gate a single test to one orientation (rare — usually the layout difference is the bug):

```ts
test('admin-only grid', async ({ ownerPage }, testInfo) => {
  test.skip(testInfo.project.name === 'chromium-mobile', 'Admin grid is desktop-only');
  // ...
});
```

## Persona model

Per `qa-testing-login.mdc` (desktop only):

| Fixture | Role | Email |
| --- | --- | --- |
| `ownerPage` | Owner / poster | `desktop@fimby.com` |
| `r1Page` | Responder 1 | `mobiletester@fimby.com` |
| `r2Page` | Responder 2 | `sftester@fimby.com` |

All three share `dtes4Jesus!`. `global-setup.ts` logs in each once and writes `playwright/.auth/{owner,r1,r2}.json`. Specs request fixtures and get a pre-authed page.

## QA runbook -> spec mapping

P1 -> `@smoke`, P2 -> `@regression`, P3 -> `@polish`. Every test that creates data must use `[E2E]` prefix + `runId` from `anchored-data` fixture so cleanup can find it.

| QA runbook (`C:\Users\srathjen\.cursor\plans\`) | Spec (`tests/`) |
| --- | --- |
| `core_site_qa_docs_index.plan.md` | (index, no spec) |
| `homepage_qa_plan_1a29942d.plan.md` | `homepage.spec.ts` |
| `ask_offer_event_bulkbuy_qa.plan.md` | `ask-offer-event-bulkbuy.spec.ts` |
| `lending_browsing_lifecycle_qa.plan.md` | `lending-lifecycle.spec.ts` |
| `stories_qa.plan.md` | `stories.spec.ts` |
| `messages_qa.plan.md` | `messages.spec.ts` |
| `mystuff_qa.plan.md` | `mystuff.spec.ts` |
| `kebab_search_qa.plan.md` | `kebab-search.spec.ts` |
| `notifications_qa.plan.md` | `notifications.spec.ts` |
| `profile_contact_sharing_qa.plan.md` | `profile-contact-sharing.spec.ts` |

## Test data hygiene

- Records are anchored with title prefix `[E2E] <runId> <human label>` and a stamped `External_Id__c` where the object supports it.
- After each test, `cleanup.ts` shells `sf apex run` with `scripts/cleanup-run.apex.template` to invoke `FimbyTestDataCleanup.cleanupRun(runId)`.
- After the full run, an outer hook calls `cleanupPrefix('[E2E] ')` to mop residue.
- `FimbyTestDataCleanup` (Apex) refuses blank or short prefixes, deletes children before parents, and never touches `Account` or `Contact`.
- A green run leaves zero `[E2E]` records in the org. Verify with `npm run cleanup:dryrun`.

## Troubleshooting

- **Persona login fails** -> session expired; run `npm run auth:refresh`.
- **`auth:refresh` / global-setup: no rendition on home** -> set `FIMBY_FILE_PREWARM_URL` to a full `https://fimby.file.force.com/.../renditionDownload?...` URL, or wait until the home feed shows an image for the persona; home-feed scrape wait is 30s.
- **`sf` not found** -> install Salesforce CLI and run `sf org login web -a fimby-prod`.
- **Shadow DOM click misses** -> Playwright pierces shadow roots natively; verify the locator with `--debug` (`npx playwright test --debug`). For LWC-specific quirks see `playwright/helpers/lwc-locators.ts`.
- **Date off-by-one** -> per `qa-testing-login.mdc`, log it in `C:\Users\srathjen\FIMBY\.cursor\defect-log.md` rather than retrying.
- **CI cleanup failed** -> check the `playwright-report` artifact and the `sf` step logs. Re-run `cleanupPrefix` locally if needed.

## CI

`.github/workflows/playwright.yml` runs:

- **Push to any branch** -> `@smoke` only.
- **Nightly cron** -> `@smoke|@regression`.
- **`workflow_dispatch`** -> manual `grep` and `spec` inputs.

The workflow authenticates Salesforce CLI from `secrets.SF_AUTH_URL`, runs the suite, and uploads the HTML report and any traces as artifacts.
