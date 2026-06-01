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

## 2. The storyboard (8 screens, surface-driven)

Read like a comic strip — slots 1–3 surface in search results, so the hook leads.
Each screen pairs a **real captured app screen** with a branded caption and a subtle
accent drawn from the in-app category color, so marketing echoes the product.

**Content only works in the context of its surface.** A feed card, a detail page, a
list row, and a form each render different fields, so every screen is pinned to an
explicit surface first; the seed content is written to fit that surface. The set is
deliberately spread across surface *types* (feed / detail / list / detail / list /
form / native / settings) so the gallery doesn't read as one screen eight times.

**Mobile real estate is small.** A feed card with a photo fills the viewport — you see
**one post, plus the top of a second**. So only the home feed uses "1 hero + peek";
detail pages show a single full post; lists show several compact rows.

| # | Caption (as-is) | Surface / route | Renders | Accent token |
|---|---|---|---|---|
| 1 | **Neighbours who know your name** | **Home feed** `/` | Greeting + filter pills + feed cards. **1 hero + peek.** | `--fimby-brand-teal` `#67BBD2` |
| 2 | **Ask for help. Offer what you have.** | **Need/Offer detail page** | Author, large photo, full description, meta, Respond CTA, responses | `--fimby-earth-sage` `#5B8760` |
| 3 | **Borrow the drill. Skip the store.** | **Library list** `/library-list` | Category chips + item rows (thumb, title, owner, badge, availability) | `--fimby-earth-driftwood` `#8D7B6A` |
| 4 | **Dinners, block parties, gatherings.** | **Event detail (Gathering)** | Event photo, title, host, date/time, location, RSVP, "X going", description | `--fimby-earth-teal` `#448E9E` |
| 5 | **Every conversation in one place.** | **Messages list** `/messages` | Thread rows (avatar, name, last message, context badge, time) | `--fimby-earth-slate` `#5E7B92` |
| 6 | **Tell neighbours how to care for you well.** | **Care-preferences screen** (onboarding step or Profile edit) | Progress/section header, question, checkbox options, Next | `--fimby-earth-dusty-violet` `#7E7495` |
| 7 | **A doorbell, not a slot machine.** | **Quiet-hours panda** (native app screen) | Panda video, caption, dismiss buttons | `--fimby-earth-ochre` `#A38045` |
| 8 | **No ads. No tracking. Community-owned.** | **Settings → Privacy** `/settings` | Contact-sharing toggles, blocking, privacy framing | `--fimby-earth-moss` `#6B7D54` |

**iPhone set:** all 8.
**iPad set:** same 8 captions, recomposed for the wider 2064 × 2752 canvas (real iPad-width captures — verify the WebView responsive layout looks good at tablet width before capturing).
**Play phone set:** reuse screens **1–5** (strongest converting five), re-exported at 1080 × 1920.

---

## 3. Seed content & cast

What actually has to exist in the Reviewer's Neighbourhood for each surface to look
alive and warm. Written to fit the surface in section 2.

### Cast

Short, easy-to-read names spread across gender, ethnicity, and age (two elders is
intentional — on-brand for a care-focused app). Login **emails stay the same**; only
Contact names change, so QA isn't disrupted. Each persona needs a **profile photo**.

| Persona | Age | Background | Gender | Account |
|---|---|---|---|---|
| **Sarah Chen** | 34 | Chinese-Canadian | F | `reviewer@fimby.com` — the viewer; we capture as her |
| **Rosa Alvarez** | 67 | Mexican-Canadian | F | rename `mobiletester@fimby.com` |
| **Marcus Bell** | 45 | Black Canadian | M | rename `desktop@fimby.com` |
| **Amir Haddad** | 31 | Lebanese-Canadian | M | rename `sftester@fimby.com` |
| **Joan Whitecloud** | 70 | Coast Salish (Indigenous) | F | **new Contact** |

### Content per screen

**Screen 1 — Home feed (1 hero + peek), captured as Sarah**
- Greeting: "Good afternoon, Sarah"
- **Hero — Offer · Rosa:** title *"Tomato & basil seedlings to share"*; body *"Started way too many this spring. Free to good homes, just stop by the porch."*; OFFER badge; engagement *"4 neighbours interested"*; 📷 seedling tray.
- **Peek — Thank you · Marcus → Amir:** header + first line *"Amir brought my bins back before I was even up…"*; THANK YOU badge. (Only the top shows; no photo needed.)

**Screen 2 — Need/Offer detail page (Ask · Amir)**
- Title: *"Could anyone lend a folding table this Saturday?"*
- Body: *"I'm hosting my daughter's 6th birthday in the backyard and I'm one table short for the food. I'd grab it Saturday morning and have it back to you Sunday. Thank you, neighbours."*
- ASK badge · 📷 backyard birthday prep · **Respond** CTA · "Posting as Amir"
- One response shown — **Sarah:** *"I've got a folding table you can use. I'll message you."*

**Screen 3 — Library list (`/library-list`)**
Category chips: All · Tools · Kitchen · Outdoor · Books · Kids. Item rows:
1. **Cordless drill** — Marcus — Tools — Available — 📷
2. **Stand mixer** — Sarah — Kitchen — Available — 📷
3. **Folding camp chairs (set of 4)** — Amir — Outdoor — Available — 📷
4. **6 ft step ladder** — Joan — Tools — On loan (due Jun 12) — 📷

**Screen 4 — Event detail, Gathering (Joan)**
- Title: *"Tea & bannock on the porch"* · Host: Joan Whitecloud
- When: Sunday, June 7, 2:00–4:00 PM · Where: Jackson Ave porch
- Body: *"Come sit a while. I'll have tea on and fresh bannock. Bring nothing but yourself. Little ones welcome."*
- 📷 porch tea + bannock · **RSVP** · *"5 going · 3 seats left"* (capacity 8)

**Screen 5 — Messages list (`/messages`), as Sarah**
1. **Rosa** — *"Wonderful, I'll leave a tray on the porch for you."* · Offer · 9:14 AM · unread
2. **Marcus** — *"They're by the front gate, help yourself."* · Offer · Yesterday
3. **Amir** — *"Thank you so much, you're a lifesaver."* · Ask · Yesterday
4. **"Soup night" (group)** — *"Joan: I'll bring the bannock!"* · Event · 3 people · Fri

**Screen 6 — Care preferences (Sarah)**
- Header: *"How can neighbours care for you well?"* · sub: *"All optional, change it anytime."*
- Checked: *A warm hello when we pass* · *A hand with errands now and then* · *Prayer, if it's offered*
- Unchecked (visible): *Help with rides* · *A meal when things are hard*
- Boundary field: *"Anything you'd rather neighbours avoid?"* → *"Please send a text before dropping by."*

**Screen 7 — Quiet-hours panda** — native; no seed content.

**Screen 8 — Settings → Privacy (Sarah)** — clean state: contact-sharing off (per-neighbour), visible in search on, blocked list empty; the "no ads, never sells your info" framing visible.

### Images to generate (~12)

Warm, natural light, candid, consistent style; no text overlays; squarish/4:3 to fit card photo areas.

- **Post / list photos (7):** seedling tray · backyard birthday prep · cordless drill · stand mixer · folding camp chairs · step ladder · porch tea & bannock
- **Avatars (5):** Sarah, Rosa, Marcus, Amir, Joan
- Peeks (Screen 1 thank-you) show only the card header, so need no photo.

---

## 4. Visual template spec

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

## 5. Production pipeline

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

## 6. Asset checklist

- [ ] Cast renamed (Rosa/Marcus/Amir on existing test logins) + Joan created + Sarah on `reviewer@fimby.com`
- [ ] 5 avatars + 7 post/list photos generated
- [ ] Reviewer's Neighbourhood seeded per section 3 (blocks all captures)
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
