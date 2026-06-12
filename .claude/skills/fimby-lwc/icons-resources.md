# FIMBY Impact Icons & Resources

Load before editing `**/lwc/**/*.js`. Use `Impact_Icons` for all **brand-specific, content-type, and navigational** icons (pills, chip filters, feed-type badges, tab bars, header/footer nav, section headers, story-type indicators). `<lightning-icon>` with `utility:*` is fine for generic function affordances: back/forward arrows, close/X, chevrons, spinners, checkmarks.

**Never use these utility icons in action buttons — use the Impact equivalent:**
| Action | Impact Icon | Replaces |
|--------|-------------|----------|
| Edit | `edit.png` | `utility:edit` |
| Photo/Upload | `photo.png` | `utility:image` |
| Delete/Trash | `trash.png` | `utility:delete` |

**Exception:** small icon-only inline edit pencils (`.edit-pencil`) keep `<lightning-icon icon-name="utility:edit">` — the branded icon is too loud there.

## Import & usage
```js
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
get settingsIconUrl() { return `${IMPACT_ICONS}/gear.png`; }

const TAB_ICONS = { home: { active: 'NeighborhoodActive.png', inactive: 'NeighborhoodInactive.png' } };
get homeIconUrl() { return `${IMPACT_ICONS}/${this.isActive ? TAB_ICONS.home.active : TAB_ICONS.home.inactive}`; }
```
```html
<img src={settingsIconUrl} alt="" class="section-icon">
```

## Icon index

**Navigation (Active / Inactive pairs):** Home/Neighbourhood `NeighborhoodActive.png`/`NeighborhoodInactive.png`; Library/Toolbox `ToolboxActive`/`ToolboxInactive`; Messages `SpeechBubbleActive`/`SpeechBubbleInactive`; Profile/My Stuff `ProfileActive`/`ProfileInactive`; Notifications `BellActive`/`BellInactive`; Stories `StoriesActive`/`StoriesInactive`; Bulletin Board `BulletinBoardActive`/`BulletinBoardInactive`.

**Story types (Active / Inactive):** Thank You `ThankYouActive`/`ThankYouInactive`; God Story `GodStoryActive`/`GodStoryInactive`; Prayer `PrayActive`/`PrayInactive`; Bio `BioActive`/`BioInactive`; Lament `LamentActive`/`LamentInactive`.

**Actions & UI:** Add `add.png`; Search `Magnify.png`; Kebab (universal header only) `Kebab.png`; horizontal dots (subheaders, feed cards, comment menus) `utility:threedots` (lightning-icon); Comment `comment.png`; Reply `reply.png`; RSVP `rsvp.png`; Borrow `borrow.png` / `BorrowActive.png`; Settings `gear.png`; Edit `edit.png`; Photo `photo.png`; Delete `trash.png`; Warning `warning.png`.

**People & contact:** People `people.png`; Contact/Sign `sign.png`; Chat/About `chat.png`; Care `care.png`; Accessibility `accessibility.png`; No Profile Photo `NoProfilePhoto.png`; No Photo `NoPhoto.png`.

**Settings & account:** Account/Key `key.png`; Email `email.png`; Globe `globe.png`; Appearance `day-and-night.png`; Block User `block-user.png`; Deactivation `deactivation.png`; Lightbulb `lightbulb.png`.

**Ask & Offer:** Need `needsm.png`; Gift/Offer `giftsm.png`; Planner/Event `plannersm.png`.

**Status & badges:** `Member.png`, `Volunteer.png`, `Donor.png`, `Grantmaker.png`, `Major.png`, `Board.png`, `Matching.png`, `FormerMember.png`, `Alive.png`, `Deceased.png`, `DoNotContact.png`, `DoNotTakePictures.png`, `NoPhotoEmail.png`.

**Decorative/misc:** FIMBY logo `FIMBYwGrass.png`; `confetti.png`; `Thanks.png`; `ThanksPeople.png`; `thankyou.png`; `biography.png`; `pray.png`; `sad.png`; `GreenCircle.png`; `RedCircle.png`; `YellowCircle.png`.

## Library categories (icons & badge colors)
`import { getCategoryIconUrl, getCategoryStyle, getCategoryColor, CATEGORY_COLORS } from 'c/fimbyLibraryCategoryConfig';`

Used on library pages (`fimbyLibraryBrowser`, `fimbyLibraryItemDetail`, `fimbyLibraryItemCard`, `fimbyMyStuffPage`, `fimbyBorrowHistory`). The **home feed** uses one generic "Library" badge (`ToolboxActive.png`, `rgba(141,123,106,0.9)`). All badge colors are WCAG AA with white text.

| Category | Icon | Color |
|----------|------|-------|
| Art & Craft Supplies | `palette.png` | `#7D6234` |
| Baby & Children | `onesie.png` | `#7A5270` |
| Bikes | `bicycle.png` | `#357280` |
| Books | `stack-of-books.png` | `#2E4466` |
| Camping Gear | `camping.png` | `#5A6838` |
| Clothing | `male-clothes.png` | `#6A5278` |
| Electronics | `electronic-devices.png` | `#4E5E78` |
| Fitness & Wellness | `sport.png` | `#2A6842` |
| Games & Toys | `toys.png` | `#885840` |
| Gardening | `gardening.png` | `#3A5C2C` |
| Home Improvement & DIY | `remodeling.png` | `#8A5936` |
| Household Items | `house-cleaning.png` | `#6B5E50` |
| Kitchen Supplies | `cookware.png` | `#7A4340` |
| Music Instruments | `music-instrument.png` | `#6E6530` |
| Office Supplies | `stapler.png` | `#4E5858` |
| Outdoors & Recreation | `deck-chair.png` | `#2E7460` |
| Party & Events | `party.png` | `#7A4A5E` |
| Pet Supplies | `pets.png` | `#7A4E52` |
| Photography & AV | `music.png` | `#44406A` |
| Sports Equipment | `sports.png` | `#3E6E48` |
| Tools | `tools.png` | `#555048` |
| Travel & Luggage | `luggage.png` | `#3A5E7A` |
| Other / fallback | `unknown.png` | `#736B5C` |

## Custom Property Editors (CPE) for Experience Builder
When an LWC exposes `<property>` entries in `js-meta.xml`, evaluate whether a CPE improves admin config (GA Spring '26).

| Property pattern | CPE solution |
|---|---|
| String with fixed values (`cardType`) | visual picker / button group |
| String for icon reference | icon picker |
| SF object/field API name | schema-populated dropdown |
| Integer min/max | slider |
| Multiple related properties | Custom Property Type w/ tabs |
| Conditionally visible property | CPE with conditional rendering |

Implementation: target `lightning__PropertyEditor` in `js-meta.xml`; public props `label`, `description`, `required`, `value`, `errors`, `schema`; dispatch `CustomEvent('valuechange', { detail: { value } })`; grouped panels use `ExperiencePropertyTypeBundle` with `schema.json` + `design.json`. Backlog: P1 `fimbyRecordDetailCard`, `fimbyCard`; P2 `fimbyImageUploader`, `fimbyInfiniteScroll`, `fimbyQuickPostForm`; P3 `fimbyUniversalHeader`/`fimbyBottomNavigation`, `fimbyStoriesFeed`, `fimbyMessagesList`.
