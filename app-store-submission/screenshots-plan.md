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
| 2 | **Ask for help. Offer what you have.** | **Ask/Offer detail page** | Posted badge, hero photo, Ask meta, FOR author, body, Respond CTA, Details accordion | `--fimby-earth-sage` `#5B8760` |
| 3 | **Borrow the drill. Skip the store.** | **Library list** `/library-list` | Category chips + item rows (thumb, title, owner, badge, availability) | `--fimby-earth-driftwood` `#8D7B6A` |
| 4 | **Dinners, block parties, gatherings.** | **Event detail (Gathering)** | Reply Received badge, hero photo, EVENT meta, HOSTED BY, date/location, body, RSVP, Details accordion | `--fimby-earth-teal` `#448E9E` |
| 5 | **Every conversation in one place.** | **Messages list** `/messages` | Thread rows (avatar, name, last message, context badge, time) | `--fimby-earth-slate` `#5E7B92` |
| 6 | **Tell neighbours how to care for you well.** | **Care preferences** (onboarding) | Progress dots, heading, optional intro, support checkboxes, Back · Next | `--fimby-earth-dusty-violet` `#7E7495` |
| 7 | **A doorbell, not a slot machine.** | **Quiet-hours panda** (native app screen) | Panda video, caption, dismiss buttons | `--fimby-earth-ochre` `#A38045` |
| 8 | **No ads. No tracking. Community-owned.** | **Share Contact Info modal** (My Stuff → My Neighbours) | Modal title, recipient pill, per-field checkboxes (Email · Phone · Address), Cancel · Share | `--fimby-earth-moss` `#6B7D54` |

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
| **Sarah Chen** | 34 | Chinese-Canadian | F | `sarah@fimby.com` — the viewer; we capture as her |
| **Rosa Alvarez** | 67 | Mexican-Canadian | F | `rosa@fimby.com` |
| **Marcus Bell** | 45 | Black Canadian | M | `marcus@fimby.com` |
| **Amir Haddad** | 31 | Lebanese-Canadian | M | `amir@fimby.com` |
| **Joan Whitecloud** | 70 | Coast Salish (Indigenous) | F | `joan@fimby.com` |
| **Appy Review** | — | — | — | `reviewer@fimby.com` — app-store reviewer / moderator flows only |

### Content per screen

**Screen 1 — Home feed (1 hero + peek), captured as Sarah**
- Greeting: "Good morning, Sarah" (time-of-day greeting is fine)
- Filter pills: All · Shared Life · Ask & Offer
- **Hero — Offer · Rosa:** title *"Tomato & basil seedlings to share"*; body *"Started way too many this spring. Free to good homes, just stop by the porch."*; OFFER badge; *2 Responses*; 📷 seedling tray; **Respond** CTA
- **Peek — Thank you · Marcus → Amir:** title *"Thank you Amir!"*; first line *"Amir brought my bins back before I was even up… 🙏"*; THANK YOU badge (top of second card only)

**Screen 2 — Ask/Offer detail page (Ask · Amir), captured as Sarah**
- Breadcrumb: Home › Ask Details
- Title: *"Could anyone lend a folding table this Saturday?"*
- Body: *"I'm hosting my daughter's 6th birthday in the backyard and I'm one table short for the food. I'd grab it Saturday morning and have it back to you Sunday. Thank you, neighbours."*
- Posted badge · Ask · Posted · **FOR Amir Haddad** · 📷 folding table · **Respond** CTA · Details accordion
- Sarah response seeded in org (*"I've got a folding table you can use. I'll message you."*) — optional below fold; capture uses clean ask detail
- **iPad framed export:** paste sage explainer from `raw/ipad/explainer-box-msg2.html` into empty space beside/below the detail card → `export-02-ask-offer.html` → **`screenshots/Ipad/Screen 2.png`**

**Screen 3 — Library list (`/library-list`), captured as Sarah**
Category chips: All · Filter. List view. Item rows:
1. **Cordless Drill and Impact Driver** — Marcus — Tools — Available — 📷 DeWalt drill + impact driver
2. **Immersion Blender** — Sarah — Kitchen Supplies — Available — 📷
3. **Pressure / Slow Cooker** — Sarah — Kitchen Supplies — Available — 📷 (peek at bottom of viewport)
- **iPad framed export:** `raw/ipad/export-03-library.html` → **`screenshots/Ipad/Screen 3.png`**

**Screen 4 — Event detail (Gathering · Joan), captured as Sarah**
- Breadcrumb: Home › Event Details
- Title: *"Tea & bannock on the porch"* · **HOSTED BY Joan Whitecloud**
- Reply Received badge · EVENT · Posted · **Jun 6, 2:00 pm · 248 Jackson Ave (porch)**
- Body: *"Come sit a while. I'll have tea on and fresh bannock. Bring nothing but yourself. Little ones welcome."*
- 📷 tea + bannock (in org) · **RSVP** CTA · Details · Availability accordions
- **iPad framed export:** paste teal explainer from `raw/ipad/explainer-box-msg4.html` into empty space beside/below the event card → `export-04-event.html` → **`screenshots/Ipad/Screen 4.png`**

**Screen 5 — Messages list (`/messages`), captured as Sarah**
- Messaging as: Sarah Chen · All · Unread · Archived · New
Thread rows:
1. **Rosa Alvarez (4)** — *"Wonderful, I'll leave a tray on the porch for you."* · Direct Msg · 2:06 PM
2. **Amir Haddad** — *"Could anyone lend a folding table this Saturday?"* · Ask / Offer · 11:30 AM
3. **Joan Whitecloud** — *"Joan Whitecloud asked Sarah Chen to vouch."* · Vouch · Tue
4. **Backyard Movie Night** — *"Swing by at 8."* · Event · May 5
5. **Heinz Tomato Ketchup (3 Pack) (2)** — *"Marcus reserved 3 shares"* · Bulk Buy · Apr 4
6. **Rosa Alvarez** — *"Handoff recorded — Cordless Drill… is now on loan"* · Lending · Mar 31
7. **Rosa Alvarez** — *"Spaghetti Dinner 🍝"* · Gathering · Mar 20
- **iPad framed export:** paste teal explainer from `raw/ipad/explainer-box-msg5.html` into raw blank space → `export-05-messages.html` → **`screenshots/Ipad/Screen 5.png`**

**Screen 6 — Care preferences onboarding (Sarah), captured on onboarding step**
- Heading: *"How can your neighbours care for you well?"* · progress dots (step 4 of 7) · hands icon
- Intro: built on neighbours looking out for each other · everything optional · update later
- Question: *"What kind of support is usually welcome?"*
- **A check-in message** ✓ (only one checked); meal drop-off · errands · ride · help at home · company · thinking things through · prayer · other visible unchecked
- **Back** · **Next**
- **iPad framed export (optional):** paste explainer from `raw/ipad/explainer-box-msg6.html` into empty space beside/below the form → `export-06-care.html` → **`screenshots/Ipad/Screen 6.png`**

**Screen 7 — Quiet-hours panda (native), captured via HTML preview**
- Source: `fimby-mobile-app` quiet-hours interstitial (replica: `preview-screen-7-quiet-panda.html`)
- Sleeping panda video · caption *"FIMBY is resting right now,* / *but you're always welcome."* (two lines)
- **Come on in** · **Come back in the morning** · dark `#14100D` background
- **iPhone capture:** `?device=iphone&capture=1` · 430×932 @ DPR 3 → 1290×2796
- **iPad capture:** `preview-screen-7-quiet-panda.html?device=ipad` · DevTools 1032×1376 @ DPR 2 → save **`raw/ipad/Screen 7.png`** · frame via `raw/ipad/export-07-quiet-hours.html` → **`screenshots/Ipad/Screen 7.png`**

**Screen 8 — Share Contact Info modal (Sarah → Joan), captured as Sarah**
- Route: **My Stuff → My Neighbours** · tabs Received · Shared · Revoked · **Share Info** pill
- Modal: **Share Contact Info** · recipient **Joan Whitecloud** · *Select what to share:*
- Email ✓ · Phone ✓ · Address ✓ (granular field checkboxes; caption carries “no ads / community-owned”)
- **Cancel** · **Share** · dimmed My Neighbours list behind modal
- Story: consent-by-field, per-neighbour sharing — not a privacy settings page (none exists)
- **iPad framed export:** paste moss explainer from `raw/ipad/explainer-box-msg8.html` into empty space beside/below the modal → `export-08-share-contact.html` → **`screenshots/Ipad/Screen 8.png`**

### Images to generate (~12)

Warm, natural light, candid, consistent style; no text overlays; squarish/4:3 to fit card photo areas.

- **Post / list photos (7):** seedling tray (in org) · folding table (in org) · cordless drill (DeWalt, in org) · immersion blender (in org) · tea & bannock (in org)
- **Avatars (5):** Sarah, Rosa, Marcus, Amir, Joan — done
- Peeks (Screen 1 thank-you) show only the card header, so need no photo.

---

## 4. Visual template spec

One reusable composer template, brand-faithful to `custom-css.css`.

- **Canvas:** exact store size per device (1290 × 2796 / 2064 × 2752 / 1080 × 1920).
- **Background:** warm cream vertical gradient `#F0EBE3 → #EBE6DD`, with a soft radial wash
  of the screen's accent token at ~8% opacity behind the device (ties each shot to its category).
- **Caption:** Inter bold, `--fimby-text-primary` `#4A3526` (website `.hero h1`), ~76px, letter-spacing `-0.045em`. Screen 1: `FIMBYwGrass.png` wordmark above caption.
  One short line; wrap to two lines max. Generous letter-spacing `-0.02em` to match site headings.
- **Device:** clean rounded-corner phone/tablet frame (light bezel or borderless rounded screen,
  `--fimby-radius-xl`+ corner) holding the real capture. Soft shadow `--fimby-shadow-card-hover`.
- **Screen 1 only:** include the `FIMBYwGrass` wordmark above the caption for brand recognition.
- **Consistency:** identical caption position, type size, device size, and margins across all 8
  so the set reads as one family in the gallery.
- **In-frame blank fill (Screen 5 iPad only):** when the messages list has empty cream below “You’re all caught up”, composite the homepage-style teal strip manually — **`raw/ipad/explainer-box-msg5.html`** (shrink-wrapped `.message-strip.dark`) pasted into the raw PNG, then frame via `export-05-messages.html`. Do **not** add fake thread badges; the capture already shows real inbox styling.
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
3. **Frame each raw PNG** — open `raw/iphone/export-*.html` (or `raw/ipad/`) next to the PNG;
   headline + `<img>` + `export.css` in the same folder; screenshot at store size, no server.
4. **Render** (browser screenshot at exact pixel size) → save framed finals to
   `app-store-submission/screenshots/Iphone/` (1290×2796) and `.../Ipad/` (2064×2752).
5. **Resize/crop** screens 1–5 for Play phone → `.../play-phone/` (1080×1920) when ready.
6. **Design once, export many** — only the canvas size and frame change between targets.

Suggested folder layout:

```
app-store-submission/
  listing-copy.md
  screenshots-plan.md
  screenshots/
    raw/
      iphone/         # PNG + export-*.html + export.css per screen
      ipad/           # explainer-box-msg2/4/5/6/8.html (Screens 2, 4, 5, 6, 8)
    Iphone/           # final framed PNGs, 1290×2796 — Screen 1.png … Screen 8.png
    Ipad/             # final framed PNGs, 2064×2752 — Screen 1.png … Screen 8.png
    play-phone/       # 5 final PNGs, 1080×1920
    feature-graphic/  # 1024×500
    icons/            # 1024 (Apple) + 512 (Play)
    composer/         # optional legacy preview; export HTML lives in raw/
```

---

## 6. Asset checklist

- [x] Cast personas live (`sarah@`, `rosa@`, `marcus@`, `amir@`, `joan@`, `reviewer@`)
- [x] 5 avatars
- [x] Screen 1 home feed seeded (Rosa offer hero + Marcus thank-you peek)
- [x] Screen 2 ask/offer detail seeded (Amir folding-table ask + photo + Sarah response)
- [x] Screen 3 library list seeded (Marcus drill row 1, Sarah kitchen row 2)
- [x] Screen 4 event detail seeded (Joan tea & bannock gathering + photo)
- [x] Screen 7 quiet-hours panda captured (`preview-screen-7-quiet-panda.html`, DPR 3, `?capture=1`)
- [x] Screen 8 share-contact modal captured (My Neighbours · Share Info · Joan)
- [x] Screen 6 care preferences captured (onboarding support step · check-in message checked)
- [x] Screen 5 messages list captured (badge variety · Rosa porch DM hero · cast threads)
- [x] iPhone framed set — 8 × 1290 × 2796 → `screenshots/Iphone/Screen 1.png` … `Screen 8.png`
- [x] iPad Screen 1 framed → `screenshots/Ipad/Screen 1.png`
- [x] iPad Screen 5 framed → `screenshots/Ipad/Screen 5.png` (explainer composited from `explainer-box-msg5.html`)
- [ ] All 8 raw iPhone captures saved to `screenshots/raw/iphone/`
- [ ] iPad WebView responsive layout verified at tablet width
- [ ] Remaining iPad framed set — 6 of 8 → `screenshots/Ipad/Screen 2.png` … `Screen 8.png`
- [x] Export HTML beside raw PNGs (`raw/iphone/export-*.html`, `raw/ipad/`)
- [ ] Play phone set — 5 × 1080 × 1920 → `screenshots/play-phone/`
- [ ] Feature graphic — 1024 × 500
- [ ] App icon — 1024 × 1024 (no alpha, square) for Apple
- [ ] App icon — 512 × 512 for Play
- [ ] Final pass: every screen is a real capture, captions match this doc, no em dashes, consistent layout
