# FIMBY SEO — web presence control

Single source of truth for search/AI entity consistency across **fimby.com**, **our.fimby.com**, and store listings.

## Files

| File | Purpose |
|------|---------|
| [`canonical.json`](canonical.json) | Canonical paragraph, bridge sentence, URLs, `sameAs`, schema `@id`s |
| [`aioseo-setup.md`](aioseo-setup.md) | **Admin:** All in One SEO configuration (copy/paste values) |
| [`store-listings.md`](store-listings.md) | **Admin:** App Store + Play Console description copy |
| [`domain-strategy.md`](domain-strategy.md) | Three-domain roles + Experience Cloud meta suggestions |
| [`og-image.md`](og-image.md) | **Action required:** 1200×630 OG share image spec |
| [`verify-checklist.md`](verify-checklist.md) | Post-deploy verification steps |
| [`faq-schema.ldjson.html`](faq-schema.ldjson.html) | Generated FAQPage block (regenerate via `scripts/build-faq-schema.mjs`) |

## Code changes (local)

- [`home-revised.html`](../home-revised.html) — `MobileApplication` + `WebApplication` JSON-LD, platform bridge line (**homepage hero copy unchanged**)
- [`faq.html`](../faq.html) — `FAQPage` JSON-LD (27 Q&As), aligned app/website answer
- [`footer.html`](../footer.html) — platform bridge line
- [`custom-css.css`](../custom-css.css) — `.platform-bridge` styles
- [`site.json`](../site.json) — updated `site_description` + `seo` block

## Live deploy (Respira + WP Admin)

1. **Inject pages** (staging ready in `.respira/staging/`):
   ```powershell
   node "FIMBY Website/scripts/build-gutenberg-inject.mjs" --html home-revised.html --page-id 26 --markers MobileApplication,platform-bridge
   node "FIMBY Website/scripts/build-gutenberg-inject.mjs" --html faq.html --page-id 59 --markers FAQPage,faq-page-inset
   ```
   Then inject via Respira MCP (`respira_inject_builder_content`, `edit_target: live`).

2. **WordPress Admin — Additional CSS:** paste/update from [`custom-css.css`](../custom-css.css) (`.platform-bridge` block).

3. **Footer template part:** paste [`footer.html`](../footer.html) into the site footer template.

4. **AIOSEO:** follow [`aioseo-setup.md`](aioseo-setup.md).

5. **Store listings:** follow [`store-listings.md`](store-listings.md).

6. **Verify:** follow [`verify-checklist.md`](verify-checklist.md).

## Regenerate FAQ schema after FAQ edits

```powershell
node "FIMBY Website/scripts/build-faq-schema.mjs"
```

Copy output from `seo/faq-schema.ldjson.html` into the top of `faq.html`, then rebuild inject payload.
