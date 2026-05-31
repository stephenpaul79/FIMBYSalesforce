# FIMBY — App Store & Play Store Screenshots Plan

Production plan for the App Store / Play Store screenshot sets. Pairs with
[`listing-copy.md`](listing-copy.md) and Phase 3 of the launch plan
(`.cursor/plans/fimby_app_store_launch_cac0fad0.plan.md`).

**Decisions locked in:**

- Style: **branded framed + captioned** (warm cream background, headline caption, device frame around a *real* app screen).
- iPad: **kept** (`supportsTablet: true` stays) — we produce the iPad 13" set too.
- Count: **8 iPhone screenshots** (full set).
- Captions: the drafted lines below, **as-is**.

---

## 1. Hard requirements (the box the creative fits in)

### Apple App Store

| Asset | Dimensions (px) | Required? | Count |
|---|---|---|---|
| 6.7" iPhone | **1290 × 2796** (portrait) | Yes | 8 |
| iPad 13" | **2064 × 2752** (portrait) | Yes (because `supportsTablet: true`) | 8 |
| 6.5" iPhone | 1242 × 2688 | Optional — Apple reuses 6.7" if absent | skip |
| App icon | 1024 × 1024 PNG, no alpha, no rounded corners | Yes | 1 |

- PNG or JPEG, RGB, no transparency. sRGB color.
- **Golden rule:** the *screen content* inside the frame must be a genuine capture of the running app (from the seeded Reviewer's Neighbourhood). Caption + device frame + background are marketing and may be fully branded. Pure mockups get rejected; framed real screens are standard and fine.

### Google Play

| Asset | Dimensions (px) | Required? | Count |
|---|---|---|---|
| Phone screenshots | **1080 × 1920** (or 1080 × 2400) | Yes (min 2) | 5 (reuse Apple 1–5) |
| 7" tablet | 1024 × 600+ | Only if "Designed for tablets" | optional (reuse iPad) |
| 10" tablet | 1080 × 1920+ | Only if "Designed for tablets" | optional (reuse iPad) |
| **Feature graphic** | **1024 × 500** | **Yes — mandatory** | 1 |
| App icon | 512 × 512 PNG (32-bit, alpha ok) | Yes | 1 |

- PNG or JPEG, max 8 MB each, min dimension 320 px, max 3840 px.
- Play is lenient about mockups, but we keep screenshots real for consistency with Apple.

---

## 2. The storyboard (8 screens)

Read like a comic strip — slots 1–3 surface in search results, so the hook leads.
Each screen pairs a **real captured app screen** with a branded caption and a subtle
accent drawn from the in-app category color, so marketing echoes the product.

| # | Real screen to capture | Caption (use as-is) | Accent token |
|---|---|---|---|
| 1 | **Home feed** — mixed asks / offers / story / thank-you cards, greeting header, FIMBY wordmark | **Neighbours who know your name** | `--fimby-brand-teal` `#67BBD2` |
| 2 | **Quick Post (+) → Ask & Offer** type selector / ask compose | **Ask for help. Offer what you have.** | `--fimby-earth-sage` `#5B8760` |
| 3 | **Lending Library** — category chips, item cards with colour badges | **Borrow the drill. Skip the store.** | `--fimby-earth-driftwood` `#8D7B6A` |
| 4 | **Gather / Events** — gathering / open event / community event | **Dinners, block parties, gatherings.** | `--fimby-earth-teal` `#448E9E` |
| 5 | **Messages / inbox** — thread list + one conversation | **Every conversation in one place.** | `--fimby-earth-slate` `#5E7B92` |
| 6 | **Care preferences (onboarding)** — "how would you like to be cared for" checklist | **Tell neighbours how to care for you well.** | `--fimby-earth-dusty-violet` `#7E7495` |
| 7 | **Quiet hours / panda screen** — do-not-disturb state | **A doorbell, not a slot machine.** | `--fimby-earth-ochre` `#A38045` |
| 8 | **Privacy / community-owned settings** | **No ads. No tracking. Community-owned.** | `--fimby-earth-moss` `#6B7D54` |

**iPhone set:** all 8.
**iPad set:** same 8 captions, recomposed for the wider 2064 × 2752 canvas (real iPad-width captures — verify the WebView responsive layout looks good at tablet width before capturing).
**Play phone set:** reuse screens **1–5** (strongest converting five), re-exported at 1080 × 1920.

---

## 3. Visual template spec

One reusable composer template, brand-faithful to `custom-css.css`.

- **Canvas:** exact store size per device (1290 × 2796 / 2064 × 2752 / 1080 × 1920).
- **Background:** warm cream vertical gradient `#F0EBE3 → #EBE6DD`, with a soft radial wash
  of the screen's accent token at ~8% opacity behind the device (ties each shot to its category).
- **Caption:** Inter, bold, `--fimby-text-strong` `#261A11`, top ~22% of the canvas.
  One short line; wrap to two lines max. Generous letter-spacing `-0.02em` to match site headings.
- **Device:** clean rounded-corner phone/tablet frame (light bezel or borderless rounded screen,
  `--fimby-radius-xl`+ corner) holding the real capture. Soft shadow `--fimby-shadow-card-hover`.
- **Screen 1 only:** include the `FIMBYwGrass` wordmark above the caption for brand recognition.
- **Consistency:** identical caption position, type size, device size, and margins across all 8
  so the set reads as one family in the gallery.
- **No em dashes** in any caption (matches the listing-copy voice rule).

### Feature graphic (Play, 1024 × 500)

Not a screenshot — a brand banner:

- Background: same warm cream gradient with a light earth-tone motif.
- `FIMBYwGrass` wordmark + tagline **"Turn the place you live into a place you belong."**
- Optional: a faint device peek or neighbourhood illustration on the right third.
- Keep text well inside safe margins (Play overlays UI on edges in some placements).

---

## 4. Production pipeline

Order matters — capture depends on seeded data.

1. **Seed the Reviewer's Neighbourhood first** (launch plan Phase 5): sample posts across
   asks/offers/story/thank-you/library/event, one conversation with 2–3 messages, photogenic
   fictional neighbours. Screenshots are only as good as this seed data.
2. **Capture real screens** at device resolution from the running app / Experience Cloud WebView
   for each of the 8 screens → save raw PNGs to `app-store-submission/screenshots/raw/`.
   - iPhone captures at 1290-wide device viewport.
   - iPad captures at iPad-13 width — first confirm the responsive WebView layout looks clean at tablet width.
3. **Build the composer template** (HTML/CSS reusing `FIMBY Website/custom-css.css` tokens):
   a single page at the target viewport that drops a raw PNG into the caption + device frame.
4. **Render headlessly** (Playwright / Puppeteer screenshot at exact pixel size) → export to
   `app-store-submission/screenshots/iphone-6.7/`, `.../ipad-13/`, `.../play-phone/`.
5. **Re-template** the same raw captures for iPad; **resize/crop** screens 1–5 for Play phone.
6. **Design once, export many** — only the canvas size and frame change between targets.

Suggested folder layout:

```
app-store-submission/
  listing-copy.md
  screenshots-plan.md
  screenshots/
    raw/              # real captures, one per screen
    composer/         # HTML/CSS template + render script
    iphone-6.7/       # 8 final PNGs, 1290x2796
    ipad-13/          # 8 final PNGs, 2064x2752
    play-phone/       # 5 final PNGs, 1080x1920
    feature-graphic/  # 1024x500
    icons/            # 1024 (Apple) + 512 (Play)
```

---

## 5. Asset checklist

- [ ] Reviewer's Neighbourhood seeded (blocks all captures)
- [ ] iPad WebView responsive layout verified at tablet width
- [ ] 8 raw iPhone captures (home, ask/offer, library, gather, messages, care prefs, quiet hours, privacy)
- [ ] 8 raw iPad captures (same screens)
- [ ] Composer template built on brand tokens
- [ ] iPhone 6.7" set — 8 × 1290 × 2796
- [ ] iPad 13" set — 8 × 2064 × 2752
- [ ] Play phone set — 5 × 1080 × 1920
- [ ] Feature graphic — 1024 × 500
- [ ] App icon — 1024 × 1024 (no alpha, square) for Apple
- [ ] App icon — 512 × 512 for Play
- [ ] Final pass: every screen is a real capture, captions match this doc, no em dashes, consistent layout
