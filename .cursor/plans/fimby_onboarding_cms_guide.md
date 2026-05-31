# FIMBY Onboarding Walkthrough — CMS Content Guide

> **⚠️ DEPRECATED — Walkthrough is no longer CMS-driven**
>
> As of the **Onboarding & Walkthrough Overhaul** PR, the 5 walkthrough screens (Phase 2)
> are **hard-coded** in the `fimbyOnboardingPage` LWC bundle. Specifically:
>
> - Screen content lives in `force-app/main/default/lwc/fimbyOnboardingPage/fimbyWalkthroughContent.js`
> - Layouts (vision, feed-mock, ask/offer tiles, carousel, library cards) are baked into the LWC template
> - The `getWalkthroughSlides` Apex method on `FimbyOnboardingController` is now a **deprecated stub** returning an empty list; it remains only to keep the legacy `fimbyOnboardingModal` bundle compiling until that bundle is removed in a follow-up cleanup PR
>
> **To update walkthrough copy or visuals**, edit `fimbyWalkthroughContent.js` and the
> matching markup in `fimbyOnboardingPage.html` — _not_ CMS.
>
> The `fimby_onboarding_slide` managed content type and any existing CMS records can be
> left in place (they no longer affect runtime behaviour) or deleted in a future cleanup.
>
> The rest of this document is kept **for historical reference only** and to inform
> patterns for _other_ CMS content (e.g. the FAQ on `fimbyHelpSupportPage`).

---

## Prerequisites

- You have access to the **Digital Experiences** app in Salesforce Setup
- The **FIMBY Onboarding Slide** content type has been deployed (this is already done)
- Your CMS workspace is connected to the FIMBY1 site channel

---

## 1. Access the CMS Workspace

1. In Salesforce Setup, search for **Digital Experiences** in the left sidebar
2. Click **All Sites**, then click the **Builder** link next to FIMBY
3. In Experience Builder, click the **CMS** tab in the left panel (the page icon)
4. Alternatively: go to **App Launcher** → search for **CMS Home** → select your workspace

---

## 2. Create the Onboarding Folder

If you haven't already created the folder:

1. In the CMS workspace, click **Folders** in the left sidebar
2. Click **New Folder**
3. Name it **Onboarding**
4. Click **Save**

All walkthrough slides should live in this folder for organization.

---

## 3. Create a Walkthrough Slide

1. In the CMS workspace, click **Create** (top right)
2. Select content type: **FIMBY Onboarding Slide**
3. Fill in the fields (described below)
4. Click **Save** → then **Publish**

### Field Reference

| Field | Required | Description |
|-------|----------|-------------|
| **Title** | Yes | The heading displayed on the slide (e.g., "Welcome to FIMBY!") |
| **Body** | No | Rich text content — supports bold, italic, lists, links, and inline images |
| **Hero Image** | No | A large image displayed above the text. Use screenshots, illustrations, or feature photos. Recommended size: 960×540px or similar 16:9 aspect ratio |
| **Page Order** | Yes | Controls which "page" this slide belongs to. Use zero-padded numbers with gaps: `010`, `020`, `030`, etc. |
| **Slide Order** | Yes | Controls the position within a page. Use `010`, `020`, `030`, etc. Only matters for carousel (multi-slide) pages |
| **Page Title** | No | Short label shown in the progress indicator (e.g., "The Library"). Only needed for carousel pages |
| **Button Label** | No | Text for an optional call-to-action button (e.g., "Explore the Library"). Leave blank for no button |
| **Button URL** | No | Where the CTA button links to (e.g., `/library-list`). Only used if Button Label is set |

---

## 4. Understanding Page Order and Slide Order

These two fields control the entire structure of the walkthrough. The key concept:

**Slides that share the same Page Order value appear together on one page.**

### Single-Page Slides

If only **one** slide has a given Page Order value, it renders as a full-page layout:

```
Page Order: 010    Slide Order: 010    Title: "Welcome to FIMBY!"
```

This creates a standalone page with the hero image, title, and body content displayed in a simple centered layout.

### Multi-Slide (Carousel) Pages

If **two or more** slides share the same Page Order value, they form a carousel:

```
Page Order: 020    Slide Order: 010    Title: "Your Neighbourhood Feed"
Page Order: 020    Slide Order: 020    Title: "Shared Life & Stories"
Page Order: 020    Slide Order: 030    Title: "Asks & Offers"
```

This creates a single page with left/right arrows. The user swipes or clicks arrows to move between the three slides within that page, then clicks "Next" to advance to the next page.

### Why Zero-Padded Numbers with Gaps?

Using `010`, `020`, `030` (instead of `1`, `2`, `3`) gives you room to insert new slides later without renumbering everything:

- Need a new page between 010 and 020? Use `015`
- Need a new slide between 020 and 030 within a carousel? Use `025`

---

## 5. Recommended Initial Content

Here's a starter set of walkthrough content. You can customize the text and images to match your neighbourhood:

| Page Order | Slide Order | Title | Type | Suggested Content |
|------------|-------------|-------|------|-------------------|
| 010 | 010 | Welcome to FIMBY! | Single page | Brief intro to what FIMBY is. Hero image: FIMBY logo or neighbourhood photo |
| 020 | 010 | Your Neighbourhood Feed | Carousel | Explain the home feed. Screenshot of the feed |
| 020 | 020 | Shared Life & Stories | Carousel | Explain stories/posts. Screenshot of a story |
| 020 | 030 | Asks & Offers | Carousel | Explain the marketplace. Screenshot of asks & offers |
| 030 | 010 | The Library | Single page | Explain the lending library. Screenshot of library. Optional CTA button: "Browse the Library" → `/library-list` |
| 040 | 010 | Messages & Connections | Single page | Explain messaging. Screenshot of a conversation |
| 050 | 010 | You're All Set! | Single page | Encouraging closing message. No hero image needed — use warm copy like "You're ready to meet your neighbours!" |

---

## 6. Editing Existing Content

1. Navigate to the CMS workspace
2. Find the slide you want to edit (use the folder filter or search by title)
3. Click the content item to open it
4. Make your changes
5. Click **Save**
6. Click **Publish** — changes are not visible until published

**Important:** The walkthrough LWC reads published content in real time. As soon as you publish, the next user who opens the walkthrough will see the updated content.

---

## 7. Adding a New Page

To add a new page to the walkthrough:

1. Create a new **FIMBY Onboarding Slide** content item
2. Set **Page Order** to a value that places it where you want in the sequence
   - Between existing pages 020 and 030? Use `025`
   - After all existing pages but before the final "You're All Set" page? Use a number between the last feature page and the closing page
3. Set **Slide Order** to `010` (it's the only slide on this page)
4. Fill in Title, Body, and optionally Hero Image
5. Save and Publish

No code changes needed — the LWC automatically picks up the new page and adds it to the walkthrough.

---

## 8. Converting a Single Page to a Carousel

Want to expand a single-page slide into multiple slides?

1. Open the existing slide and note its **Page Order** (e.g., `030`)
2. The existing slide already has Slide Order `010` — this becomes the first carousel slide
3. Create additional slides with the **same Page Order** (`030`) but different Slide Orders (`020`, `030`, etc.)
4. Optionally set a **Page Title** on the first slide — this appears as a header above the carousel
5. Publish all slides

The LWC sees multiple slides with the same Page Order and automatically renders them as a carousel with navigation arrows and dot indicators.

---

## 9. Removing a Page

To remove a page from the walkthrough:

1. Navigate to the content item in the CMS workspace
2. **Unpublish** the content item (this removes it from the walkthrough immediately)
3. Optionally delete it, or keep it unpublished for future use

If removing one slide from a carousel (leaving 2+ slides), the carousel continues to work with the remaining slides. If you remove slides until only one remains, it automatically renders as a single page.

---

## 10. Reordering Pages

To change the order of pages:

1. Open each slide you want to reorder
2. Change the **Page Order** value
3. Save and Publish

Example — swapping "The Library" (030) and "Messages" (040):
- Edit "The Library" → change Page Order to `040`
- Edit "Messages" → change Page Order to `030`
- Publish both

---

## 11. Images and Media

### Hero Images
- Upload images through the CMS media library or directly in the Hero Image field
- Recommended dimensions: **960×540px** (16:9 ratio) for best display
- The image is displayed with `object-fit: contain`, so it won't be cropped — but wider images fill the space better
- Keep file sizes reasonable (under 500KB) for fast loading on mobile

### Inline Images in Body
- The Body field supports rich text, so you can insert images directly in the content
- Use this for smaller supporting images, icons, or annotated screenshots
- Hero Image is better for the primary visual

### Tips
- Use real screenshots of FIMBY features — they're more helpful than stock photos
- Add annotations or callouts to screenshots to highlight key UI elements
- Consider using illustrations for the welcome and closing pages for a warmer feel

---

## 12. Best Practices

**Content length:**
- Keep each slide focused on ONE concept
- Body text should be 2-4 sentences maximum
- Users skim — use bullet points and bold text for key information

**Number of pages:**
- 4-6 total pages is the sweet spot
- Too few feels incomplete; too many causes fatigue and drop-off
- Use carousels sparingly — only when content is closely related (e.g., the different feed types)

**Tone:**
- Use warm, community-oriented language
- "Discover" not "Learn about"
- "Your neighbours" not "Other users"
- End on an encouraging note: "You're ready!" not "Setup complete"

**CTA buttons:**
- Use them sparingly — one or two per walkthrough at most
- Best for the most important features you want users to try first
- The button opens in the current window, so the walkthrough closes

**Testing changes:**
- After publishing changes, test the walkthrough by going to `/help-support` and clicking "Take the Tour"
- To test the full flow (including Phase 1), you'd need a user whose `Contact.Onboarding_Profile_Completed__c` is false

---

## Quick Reference: Field Cheat Sheet

```
Page Order    →  Which "screen" in the walkthrough (010, 020, 030...)
Slide Order   →  Position within a carousel page (010, 020, 030...)
                  Same Page Order + multiple Slide Orders = carousel
                  Same Page Order + single Slide Order = full page

Title         →  Big heading on the slide
Body          →  Rich text content below the heading
Hero Image    →  Large image above the heading
Page Title    →  Label above a carousel (only for multi-slide pages)
Button Label  →  CTA button text (leave blank = no button)
Button URL    →  Where the CTA goes (e.g., /library-list)
```

---

# FAQ Content Management

The Frequently Asked Questions on the Help & Support page are also CMS-driven. You can add, edit, reorder, and enrich FAQ answers with inline images — no code changes required.

## CMS Content Type: `fimby_faq_item`

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| **Question** | Yes | Text | The question displayed as the accordion heading (e.g., "How does the Library work?") |
| **Answer** | Yes | Rich Text | The answer content. Supports bold, italic, lists, links, and **inline images** for screenshots or step-by-step guides |
| **Sort Order** | Yes | Text | Zero-padded display order: `010`, `020`, `030`, etc. Use gaps of 10 for easy insertion |
| **Category** | No | Text | Optional grouping label (e.g., "Getting Started", "Library"). Reserved for future grouped display |

## Creating FAQ Items

1. In the CMS workspace, click **Create** → select **FIMBY FAQ Item**
2. Enter the **Question** (this is what users see in the accordion heading)
3. Write the **Answer** using the rich text editor:
   - Use **bold** for key terms
   - Use bullet lists for step-by-step instructions
   - Insert inline images for screenshots (click the image icon in the editor toolbar)
4. Set the **Sort Order** (e.g., `010` for the first FAQ, `020` for the second)
5. Optionally set a **Category** (not displayed yet, but useful for future grouping)
6. **Save** → **Publish**

## Example FAQ Content

| Sort Order | Question | Answer |
|------------|----------|--------|
| 010 | What is FIMBY? | FIMBY (Family In My Backyard) is a neighbourhood platform... |
| 020 | How do I update my profile? | Tap the menu icon... *(include screenshot)* |
| 030 | What are Asks & Offers? | Asks & Offers is a bulletin board... |
| 040 | How does the Library work? | The Library lets you share items... *(include screenshot of library page)* |
| 050 | Who can see my profile? | Your profile is visible to members in your neighbourhood... |
| 060 | How do I change notification settings? | Go to Settings... *(include annotated screenshot)* |

## Adding Inline Images to Answers

This is a key advantage of using CMS for FAQ content. To add screenshots or diagrams:

1. In the **Answer** rich text editor, click the **image** icon in the toolbar
2. Upload or select an image from the media library
3. The image appears inline within the answer text
4. You can add text before and after the image, creating a step-by-step guide with visual references

**Tips:**
- Annotate screenshots with arrows or highlights before uploading
- Keep images under 400px wide for best display in the accordion
- Use images sparingly — one per answer is usually enough

## Reordering FAQs

Change the **Sort Order** values and republish. The LWC sorts by this field automatically.

## Removing FAQs

**Unpublish** the content item to remove it from the page instantly, or delete it entirely.

## Fallback Behavior

If no CMS FAQ content is published (or the CMS wire fails), the page falls back to a set of 6 hardcoded FAQ items so the page is never empty. Once you publish your first `fimby_faq_item`, the CMS content takes over and the fallback is no longer used.

## Folder Organization (Recommended)

Create an **FAQ** folder in your CMS workspace and put all `fimby_faq_item` content items there. This keeps them organized alongside the **Onboarding** folder. The folder is purely organizational — the LWC filters by content type, not folder.
