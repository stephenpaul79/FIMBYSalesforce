# AIOSEO setup — fimby.com

Apply in **WP Admin → All in One SEO**. Values come from [`canonical.json`](canonical.json).

## Global — Search Appearance → Global Settings

### Knowledge Graph

| Field | Value |
|-------|-------|
| Person or Organization | **Organization** |
| Organization Name | `FIMBY` |
| Logo | `https://fimby.com/wp-content/uploads/2026/03/FIMBYwGrass.png` |

AIOSEO Free emits `Organization` + `WebSite` schema on every page from this. Embedded JSON-LD on the homepage references `@id` `https://fimby.com/#organization` — do not duplicate Organization in page bodies.

### Social Networks

Add every URL below (each becomes `sameAs` on the Organization):

| Network | URL |
|---------|-----|
| Facebook | `https://www.facebook.com/profile.php?id=100083517094655` |
| Instagram | `https://www.instagram.com/fimby.family/` |
| Additional profile 1 | `https://our.fimby.com/` |
| Additional profile 2 | `https://apps.apple.com/app/fimby/id6776707632` |
| Additional profile 3 | `https://play.google.com/store/apps/details?id=com.fimby.app` |

If AIOSEO only allows Facebook + Instagram, the store + web-app URLs are still covered by homepage `MobileApplication` / `WebApplication` JSON-LD.

### Content Types → Pages

- **Show in search results:** Yes  
- **Title format:** `#post_title — FIMBY` (or `#post_title \| FIMBY`)  
- **Meta description:** leave default off; set per page below  

### Sitemap

- Enable XML sitemap → confirm live at `https://fimby.com/sitemap.xml`  
- Submit URL in Google Search Console + Bing (see [`verify-checklist.md`](verify-checklist.md))

### Social → Facebook / Twitter

- Enable Open Graph  
- Default OG image: see [`og-image.md`](og-image.md) — **needs creation**  
- Twitter card type: Summary with large image  

---

## Per-page titles + meta descriptions

Edit each page → **AIOSEO panel** (below editor). Use these exact values.

**Canonical paragraph (reference):**  
*FIMBY (Family In My Backyard) is a neighbourhood mutual-aid platform for the people who actually live near you — ask for help, offer what you have, lend and borrow, gather, and share life in small everyday ways. Not a city-wide feed. Just the people around you.*

**Bridge sentence:**  
*FIMBY works in any browser at our.fimby.com and as a free app for iPhone and Android — same account, same neighbourhood.*

### Home (Post ID 26, `/`)

| Field | Value |
|-------|-------|
| Title | `FIMBY — Family In My Backyard \| Neighbourhood mutual aid` |
| Meta description | Canonical paragraph + space + bridge sentence (≤160 chars if truncated: use first sentence + bridge) |
| Focus keyphrase (optional) | `FIMBY neighbourhood app` |

**Suggested meta (155 chars):**  
`FIMBY helps neighbours ask, offer, lend, and gather locally — not a city-wide feed. Web at our.fimby.com or free iPhone & Android app. Same account.`

### How It Works (Post ID 30, `/how-it-works/`)

| Field | Value |
|-------|-------|
| Title | `How FIMBY works — ask, offer, lend, gather locally` |
| Meta description | `See how FIMBY works: post asks and offers, borrow from the lending library, RSVP to gatherings, and message neighbours. Available on web and mobile.` |

### Our Approach (Post ID 431, `/our-approach/`)

| Field | Value |
|-------|-------|
| Title | `Our approach — belonging over performance` |
| Meta description | `FIMBY is built for neighbours, not audiences. Local scope, no ads, no algorithm, dignity over efficiency. See why FIMBY is different from social feeds and marketplaces.` |

### FAQ (Post ID 59, `/faq/`)

| Field | Value |
|-------|-------|
| Title | `Frequently asked questions — FIMBY` |
| Meta description | `Is FIMBY an app or a website? Both — our.fimby.com and free iPhone & Android apps, same account. FAQ on sign-up, lending, vouching, privacy, and who can join.` |

### Contact (Post ID 210, `/contact-us/`)

| Field | Value |
|-------|-------|
| Title | `Bring FIMBY to your neighbourhood` |
| Meta description | `Interested in launching FIMBY where you live? Contact the FIMBY team. Currently live in Vancouver V6A; growing neighbourhood by neighbourhood.` |

---

## Webmaster Tools

**All in One SEO → General Settings → Webmaster Tools**

- Paste Google Search Console verification meta tag (or use DNS verification)  
- Paste Bing Webmaster verification code  

After verification, submit `https://fimby.com/sitemap.xml`.

---

## Pages not in Respira inject set

Set AIOSEO meta manually for legal/support pages if they rank:

| Page | Suggested title |
|------|-----------------|
| Privacy Policy | `Privacy Policy — FIMBY` |
| Terms of Service | `Terms of Service — FIMBY` |
| Delete account | `Delete your FIMBY account` |

Point privacy URL in store listings to `https://fimby.com/privacy-policy/`.
