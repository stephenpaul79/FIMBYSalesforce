# Raw captures + export HTML

## Marketing text (matches fimby.com)

- **Font:** Inter (same stack as `FIMBY Website/custom-css.css`).
- **Headline:** `.hero h1` styling — umber `#4A3526`, ~76px, tight line-height, `-0.045em` tracking.
- **Screen 1 wordmark:** `FIMBYwGrass.png` in this folder (from website header), not plain text.

## Layout

- **Top band:** store caption on cream. Screen 1 is slightly taller for the grass wordmark + headline.
- **Rest:** **portrait** phone/tablet with **dark bezel** (`device-frame`). iPhone frame aspect **1290∶2796**; iPad **2064∶2752**.
- Your PNG is scaled inside the screen area (same aspect as the frame).

iPad raws are **portrait 2064×2752** (App Store iPad 13"); canvas matches in `ipad/export.css`.

## Workflow

**iPhone:** open `iphone/export-01-home.html` → full-page screenshot at **1290×2796** → save to `../Iphone/Screen 1.png` (etc.).

**iPad:** open `ipad/export-01-home.html` → full-page screenshot at **2064×2752** → save to `../Ipad/Screen 1.png` (etc.).

## Files

| HTML | PNG (same folder) |
|------|-------------------|
| `iphone/export-01-home.html` | `Screen 1 Home feed.png` |
| `ipad/export-01-home.html` | `Screen 1.png` |
| `ipad/export-02-ask-offer.html` | `Screen 2.png` (composited raw with explainer) |
| `ipad/export-03-library.html` | `Screen 3.png` |
| `ipad/export-04-event.html` | `Screen 4.png` (composited raw with explainer) |
| `ipad/export-05-messages.html` | `Screen 5 Messages list.png` |
| `ipad/export-06-care.html` | `Screen 6.png` (composited raw with explainer) |
| `ipad/export-07-quiet-hours.html` | `Screen 7.png` |
| `ipad/export-08-share-contact.html` | `Screen 8.png` (composited raw with explainer) |

**Drop-in explainers (manual paste into iPad raw PNG):** `explainer-box-msg2.html`, `explainer-box-msg4.html`, `explainer-box-msg5.html`, `explainer-box-msg6.html`, `explainer-box-msg8.html`

`export.css` in each folder sets canvas size (iPhone vs iPad).

## Optional: sharper app in frame

Re-capture the app at a **shorter** viewport (e.g. 1290×2100) so less scaling is needed. Not required — current HTML handles full-height captures.
