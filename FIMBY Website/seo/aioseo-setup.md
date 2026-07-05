# AIOSEO setup — fimby.com

Step-by-step for **All in One SEO 4.x** (Free/Lite) on fimby.com. Menu paths match the plugin’s left sidebar in WP Admin.

**Official docs hub:** [aioseo.com/docs](https://aioseo.com/docs/)

**FIMBY copy values:** [`canonical.json`](canonical.json) — use `canonicalParagraph` for **meta descriptions and store listings only**, not the homepage hero (see `homepageHeroLead` there).

---

## Before you start — find the plugin in WP Admin

1. Log in to WordPress at `https://fimby.com/wp-admin/`
2. In the **left sidebar**, look for **All in One SEO** (rocket icon)
3. Click it — you get a **sub-menu** like this:

| Sub-menu item | What it controls |
|---------------|------------------|
| **Dashboard** | Setup wizard, quick links |
| **General Settings** | Webmaster Tools, breadcrumbs, RSS, etc. |
| **Search Appearance** | Knowledge Graph, title/description templates |
| **Social Networks** | Social profile URLs + Facebook/Twitter OG defaults |
| **Sitemaps** | XML sitemap (and other sitemap tabs) |
| **Link Assistant**, **Redirects**, etc. | Pro / add-ons — ignore unless installed |

**Block editor note:** When editing a Page, AIOSEO usually appears as **AIOSEO Settings** below the content area, or in the **right sidebar** (top-right **AIOSEO** button → **General**). If missing: editor **⋮** (three dots) → **Preferences** → **Panels** → enable **AIOSEO Settings**.  
Doc: [Setting the SEO Title and Description for Your Content](https://aioseo.com/docs/setting-the-seo-title-and-description-for-your-content/)

---

## Part 1 — Knowledge Graph (Organization schema)

**Path:** **All in One SEO → Search Appearance → Global Settings** tab  
Doc: [Configuring the Schema Settings](https://aioseo.com/docs/configuring-the-schema-settings-in-all-in-one-seo/)

Scroll down to the **Knowledge Graph** section.

### 1a. Website name fields (top of Knowledge Graph)

| UI label | What to enter |
|----------|----------------|
| **Website Name** | `FIMBY` (defaults from WP **Settings → General → Site Title** — override if needed) |
| **Alternate Website Name** | `Family In My Backyard` |

Google may use these in mobile results; they are separate from per-page SEO titles.

### 1b. Person or Organization

| UI label | What to select |
|----------|----------------|
| **Person or Organization** | **Organization** |

Selecting **Organization** reveals the fields below.

### 1c. Organization fields

| UI label | FIMBY value |
|----------|-------------|
| **Organization Name** | `FIMBY` |
| **Organization Description** | Paste from `canonical.json` → `canonicalParagraph` (optional but helpful) |
| **Email Address** | `help@fimby.com` (optional) |
| **Phone Number** | leave blank unless you want a public listing number |
| **Logo** | Upload or paste URL: `https://fimby.com/wp-content/uploads/2026/03/FIMBYwGrass.png` |

Logo requirements (per AIOSEO): min **112×112 px**, crawlable URL, JPEG/PNG/SVG/WEBP/GIF.

Click **Save Changes** (top or bottom of screen).

**What this does:** AIOSEO outputs `Organization` + `WebSite` JSON-LD site-wide. Homepage embedded JSON-LD references `@id` `https://fimby.com/#organization` — do **not** add a second Organization block in page HTML.

---

## Part 2 — Social profiles (`sameAs`)

**Path:** **All in One SEO → Social Networks → Social Profiles** tab  
Doc: [Displaying Your Social Media Profiles in Knowledge Panel](https://aioseo.com/docs/displaying-your-social-media-profiles-in-knowledge-panel/)

This is **not** under Search Appearance — it is its own top-level menu item.

| UI label | Full URL |
|----------|----------|
| **Facebook** | `https://www.facebook.com/profile.php?id=100083517094655` |
| **Instagram** | `https://www.instagram.com/fimby.family/` |

Scroll to **Additional Profiles** (text box at bottom) — one URL per line:

```
https://our.fimby.com/
https://apps.apple.com/app/fimby/id6776707632
https://play.google.com/store/apps/details?id=com.fimby.app
```

AIOSEO includes Additional Profiles in Knowledge Panel schema as `sameAs`.  
Click **Save Changes**.

---

## Part 3 — Default title/description for Pages (global template)

**Path:** **All in One SEO → Search Appearance → Content Types** tab  
Doc: [Setting the SEO Title and Description Format for Pages](https://aioseo.com/docs/setting-the-seo-title-and-description-format-for-pages/)

Find the **Pages** section (not Posts).

| UI label | Recommended setting |
|----------|----------------------|
| **Show in Search Results** | **Yes** (if No, title/description fields hide) |
| **Page Title** | `#post_title — FIMBY` — type `#` in the field to pick smart tags, or click **Post Title** tag + type ` — FIMBY` |
| **Meta Description** | Leave blank or use `#post_excerpt` — **we override important pages individually** (Part 5) |

The **Preview** box above those fields shows an example SERP snippet.

**Free vs Pro:** The **Schema Markup** sub-tab under Pages (Article vs Web Page, etc.) is **Pro only**. On Free, page-level schema defaults are fine; FIMBY FAQ schema is hand-embedded in `faq.html` instead.

Click **Save Changes**.

---

## Part 4 — XML Sitemap

**Path:** **All in One SEO → Sitemaps → General Sitemap** tab  
Doc: [How to Create an XML Sitemap](https://aioseo.com/docs/how-to-create-an-xml-sitemap/)

| UI label | Recommended |
|----------|-------------|
| **Enable Sitemap** | **On** |
| **Enable Sitemap Indexes** | **On** (default — fine for fimby.com size) |
| **Links Per Sitemap** | Default **1000** |
| **Include All Post Types** | On (or ensure **Pages** included) |
| **Include Date Archives / Author Archives** | **Off** (AIOSEO default recommendation) |

Click **Open Sitemap** — should open `https://fimby.com/sitemap.xml` in a new tab.

**If sitemap returns 404/500:** confirm **Enable Sitemap** is on, save again, check for conflicting SEO plugins, and flush permalinks (**Settings → Permalinks → Save** without changes). See [`verify-checklist.md`](verify-checklist.md).

Click **Save Changes**.

---

## Part 5 — Open Graph / Twitter (social previews)

**There is no “Open Graph” item in the AIOSEO sidebar.** Open Graph is a *setting inside* **Social Networks**, on the **Facebook** tab. AIOSEO groups Facebook + Open Graph together because Facebook invented the OG standard.

### How to get there (matches your sidebar)

1. Left sidebar → **All in One SEO**
2. Click **Social Networks** (not Search Appearance, not Sitemaps)
3. At the **top of the Social Networks screen**, you’ll see horizontal tabs — click **Facebook**
4. The first toggle on that page is **Enable Open Graph Markup** — turn it **On**

Doc: [Beginners Guide to Social Networks Settings for Facebook](https://aioseo.com/docs/beginners-guide-to-social-networks-settings-for-facebook/)

```
All in One SEO
  └── Social Networks          ← click this in the sidebar
        ├── Social Profiles    ← Part 2 (profile URLs) — different tab
        ├── Facebook           ← Open Graph lives HERE
        └── Twitter            ← Twitter card settings
```

### Facebook tab — what to set

| UI label | Setting |
|----------|---------|
| **Enable Open Graph Markup** | **On** — this is the Open Graph switch |
| **Default Post Facebook Image** / **Image Source** | Set after you upload a share image — see [`og-image.md`](og-image.md) |

Scroll down on the same **Facebook** tab for **Home Page Settings** (title, description, image when your homepage is shared). fimby.com uses a static front page, so check here first before hunting on the page editor.

### Twitter tab

Still under **Social Networks** — click the **Twitter** tab next to Facebook.

| Setting | Recommendation |
|---------|------------------|
| Card type | **Summary with large image** (if shown) |
| **Use Data from Facebook Tab** | Leave **on** until you have a default OG image on the Facebook tab |

### Per-page social preview (optional override)

When editing a single page: **Pages → Edit** → **AIOSEO Settings** → **Social** tab → **Facebook** / **Twitter** sub-tabs. Overrides the global defaults from above.

Click **Save Changes** on the Social Networks screens after editing.

---

## Part 6 — Per-page SEO titles & meta descriptions

**Path:** **Pages → All Pages → Edit** (each page) → **AIOSEO Settings** → **General** tab  
Doc: [Setting the SEO Title and Description for Your Content](https://aioseo.com/docs/setting-the-seo-title-and-description-for-your-content/)

Use the **SERP Preview** / **Title** / **Meta Description** fields. Whatever you enter **overrides** the global template from Part 3.

**SEO meta copy reference** (not homepage hero):

- **Canonical paragraph:** `canonical.json` → `canonicalParagraph`
- **Bridge sentence:** `canonical.json` → `bridgeSentence`

### Home — *Family In My Backyard* (Post ID **26**, slug `family-in-my-backyard`, URL `/`)

| Field | Value |
|-------|-------|
| **Title** | `FIMBY — Family In My Backyard \| Neighbourhood mutual aid` |
| **Meta Description** | `FIMBY helps neighbours ask, offer, lend, and gather locally — not a city-wide feed. Web at our.fimby.com or free iPhone & Android app. Same account.` |

### How It Works (Post ID **30**, `/how-it-works/`)

| Field | Value |
|-------|-------|
| **Title** | `How FIMBY works — ask, offer, lend, gather locally` |
| **Meta Description** | `See how FIMBY works: post asks and offers, borrow from the lending library, RSVP to gatherings, and message neighbours. Available on web and mobile.` |

### Our Approach (Post ID **431**, `/our-approach/`)

| Field | Value |
|-------|-------|
| **Title** | `Our approach — belonging over performance` |
| **Meta Description** | `FIMBY is built for neighbours, not audiences. Local scope, no ads, no algorithm, dignity over efficiency. See why FIMBY is different from social feeds and marketplaces.` |

### FAQ (Post ID **59**, `/faq/`)

| Field | Value |
|-------|-------|
| **Title** | `Frequently asked questions — FIMBY` |
| **Meta Description** | `Is FIMBY an app or a website? Both — our.fimby.com and free iPhone & Android apps, same account. FAQ on sign-up, lending, vouching, privacy, and who can join.` |

### Contact (Post ID **210**, slug `contact-us`, URL `/contact-us/`)

| Field | Value |
|-------|-------|
| **Title** | `Bring FIMBY to your neighbourhood` |
| **Meta Description** | `Interested in launching FIMBY where you live? Contact the FIMBY team. Currently live in Vancouver V6A; growing neighbourhood by neighbourhood.` |

**Optional (Free):** **Focus Keyphrase** on each page — e.g. Home: `FIMBY neighbourhood app`. Analysis is advisory only on Free.

**Update / Publish** each page after editing AIOSEO fields.

### Legal pages (edit when convenient)

| Page | Title suggestion |
|------|------------------|
| Privacy Policy | `Privacy Policy — FIMBY` |
| Terms of Service | `Terms of Service — FIMBY` |
| Delete account | `Delete your FIMBY account` |

Store listings should link privacy to `https://fimby.com/privacy-policy/`.

---

## Part 7 — Google Search Console & Bing

**Path:** **All in One SEO → General Settings → Webmaster Tools** tab  
Doc: [How to Verify Your Site with Google Search Console](https://aioseo.com/docs/how-to-verify-your-site-with-google-search-console/)

### Google (easiest)

1. Open the **Google Search Console** block
2. Click **Connect to Google Search Console**
3. Sign in with Google → allow AIOSEO → **Complete Connection**

AIOSEO can verify ownership and submit the sitemap automatically.

### Manual verification (alternative)

If you prefer not to OAuth-connect: copy the **HTML meta tag** from Google Search Console → paste into the **Google Verification Code** field on the same **Webmaster Tools** tab.

### Bing

Same tab — **Bing Webmaster Tools** block → paste verification code from Bing.

### After verification

1. In Google Search Console: **Sitemaps** → submit `https://fimby.com/sitemap.xml`
2. **URL Inspection** → request indexing for `/` and `/faq/` after JSON-LD inject

Full checklist: [`verify-checklist.md`](verify-checklist.md)

---

## Part 8 — What AIOSEO Free does *not* do (FIMBY handles elsewhere)

| Feature | AIOSEO Free | FIMBY approach |
|---------|-------------|----------------|
| Per content-type Schema Markup tab | Pro | Default WebPage is fine |
| FAQPage schema UI | Pro | Embedded in [`faq.html`](../faq.html) |
| MobileApplication / WebApplication schema | Not built-in | Embedded in [`home-revised.html`](../home-revised.html) |
| GSC performance inside WP | Pro | Use search.google.com directly on Free |

---

## Quick reference — menu → task

| I want to… | Go to… |
|------------|--------|
| Set Organization + logo | **Search Appearance → Global Settings → Knowledge Graph** |
| Add Facebook / Instagram / store URLs | **Social Networks → Social Profiles** (+ Additional Profiles) |
| Default “Page title — FIMBY” template | **Search Appearance → Content Types → Pages** |
| Fix sitemap | **Sitemaps → General Sitemap** |
| **Open Graph** (not in sidebar — use Facebook tab) | **Social Networks → Facebook → Enable Open Graph Markup** |
| Facebook OG defaults | **Social Networks → Facebook** |
| Twitter card defaults | **Social Networks → Twitter** |
| Edit one page’s Google snippet | **Pages → Edit → AIOSEO Settings → General** |
| Connect Google | **General Settings → Webmaster Tools** |

---

## Official documentation links (bookmark these)

- [Configuring the Schema Settings (Knowledge Graph)](https://aioseo.com/docs/configuring-the-schema-settings-in-all-in-one-seo/)
- [Social profiles / Knowledge Panel](https://aioseo.com/docs/displaying-your-social-media-profiles-in-knowledge-panel/)
- [Page title & description templates](https://aioseo.com/docs/setting-the-seo-title-and-description-format-for-pages/)
- [Per-page title & description](https://aioseo.com/docs/setting-the-seo-title-and-description-for-your-content/)
- [Smart tags (`#post_title`, etc.)](https://aioseo.com/docs/using-the-smart-tags-in-titles-and-descriptions/)
- [XML Sitemap](https://aioseo.com/docs/how-to-create-an-xml-sitemap/)
- [Facebook / Open Graph](https://aioseo.com/docs/beginners-guide-to-social-networks-settings-for-facebook/)
- [Google Search Console verification](https://aioseo.com/docs/how-to-verify-your-site-with-google-search-console/)
