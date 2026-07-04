# SEO verification checklist

Run after AIOSEO config + Respira injects for homepage and FAQ JSON-LD.

## Local verification (2026-07-04 — pre-live inject)

- [x] Homepage staging payload includes `MobileApplication`, `#web-app`, `platform-bridge` (43,199 chars)
- [x] FAQ staging payload includes `FAQPage`, bridge sentence in app/website answer (36,859 chars, 27 Q&As)
- [ ] **Live inject pending** — Respira MCP was unavailable this session; run inject per `seo/README.md`
- [ ] `https://fimby.com/sitemap.xml` returned **500** when checked — fix in AIOSEO before Search Console submit

## Immediate (day 0)

### 1. Rich Results Test

- [ ] `https://fimby.com/` — expect `MobileApplication`, `WebApplication`, `Organization` (AIOSEO), `WebSite` (AIOSEO)  
- [ ] `https://fimby.com/faq/` — expect `FAQPage` with 27 questions, plus AIOSEO Organization  

Tool: https://search.google.com/test/rich-results

### 2. Live DOM check

View page source on live URLs and confirm:

- [ ] Homepage contains `"@type": "MobileApplication"` and `"@id": "https://fimby.com/#mobile-app"`  
- [ ] Homepage `publisher` references `https://fimby.com/#organization`  
- [ ] FAQ contains `"@type": "FAQPage"` and question *Is FIMBY an app or a website?*

### 3. Sitemap

- [ ] `https://fimby.com/sitemap.xml` returns 200  
- [ ] Includes `/`, `/faq/`, `/how-it-works/`, `/our-approach/`, `/contact-us/`

### 4. Search Console + Bing

- [ ] Domain verified in Google Search Console  
- [ ] Domain verified in Bing Webmaster Tools  
- [ ] Sitemap submitted in both  
- [ ] Request indexing for `/` and `/faq/` (URL inspection → Request indexing)

### 5. Open Graph (after OG image uploaded)

- [ ] Facebook Sharing Debugger: https://developers.facebook.com/tools/debug/  
- [ ] Enter `https://fimby.com/` — confirm title, description, image

### 6. Store listing spot-check

- [ ] App Store description opening matches canonical paragraph  
- [ ] Play Store short description mentions neighbourhood + web/app  
- [ ] Both list `https://fimby.com/privacy-policy/`

---

## 2–4 week follow-up

Calendar reminder: **~2026-07-25**

- [ ] Google search: `FIMBY app`, `Family In My Backyard`, `FIMBY neighbourhood Vancouver`  
- [ ] Note whether AI Overview / snippet mentions **web + app** together  
- [ ] Search Console → Performance: impressions/clicks for brand terms  
- [ ] Fix any new crawl errors in Search Console  

---

## Known limits

- Entity graph updates can take weeks; consistency matters more than re-submitting.  
- AIOSEO Free may not show all schema types in Rich Results Test UI — FAQPage and MobileApplication from embedded JSON-LD still count.  
- Experience Cloud (`our.fimby.com`) meta must be set manually in Builder (see [`domain-strategy.md`](domain-strategy.md)).

---

## Respira inject verification (per page)

After each live inject:

1. Extract page via Respira — confirm JSON-LD block present, not truncated  
2. Assert markers from build script survived  
3. Optional: WebFetch public URL and grep for `@type`
