# WordPress deploy handoff (user)

All website work lives in `FIMBY Website/`.

## Agent live inject (Respira MCP)

Follow the 8-step recipe in `.cursor/rules/respira-wordpress-inject.mdc` (build → sanity-check → `CallMcpTool` in-thread → verify → delete staging).

### SEO inject (2026-07-04)

| Local HTML | Page ID | Markers |
|------------|---------|---------|
| `home-revised.html` | 26 | `MobileApplication,platform-bridge` |
| `faq.html` | 59 | `FAQPage,faq-page-inset` |

Also paste `custom-css.css` delta (`.platform-bridge`) and `footer.html` into WP template parts. Full checklist: `seo/README.md`.

Apply AIOSEO values from `seo/aioseo-setup.md` (WP Admin — not injectable via Respira).

## After local edits

1. Paste/rebuild each page from the matching `.html` (or sync from `pages/*.md` drafts).
2. **Before live page HTML pushes:** paste all of `publish-css-delta.css` at the end of Additional CSS (How It Works rules omitted — already on live). Optional: enqueue `fimby-scroll-sections.js` if using scroll fade-in.
3. Upload changed CSS/JS as needed: `custom-css.css` (full source), `fimby-scroll-sections.css`, `fimby-scroll-sections.js`, `hamburger-menu-css.css`.
4. Upload new Impact Icons to Media Library; update `img src` URLs; log in `media/inventory.json`.
5. Update All in One SEO site description from `site.json`.
6. Spot-check: home, how-it-works, contact-us, header/footer CTAs.
7. Apply Experience Cloud sign-up notes from `pages/signup-alignment-notes.md` (manual).
8. Upload `JacksonAve.png` or preferred DTES photo if swapping credibility image on home.

## File map

| Local | WordPress target |
|-------|------------------|
| `home.html` | Home page |
| `header.html` / `site-header-template-part.html` | Header template part |
| `footer.html` | Footer template part |
| `how-it-works.html` | How it works |
| `contact.html` | Contact / Bring FIMBY |
| `our-approach.html`, `vision.html`, `faq.html` | Respective pages |

## Sign-up (Experience Cloud)

See `pages/signup-alignment-notes.md` for copy aligned with marketing site (not editable in this folder).
