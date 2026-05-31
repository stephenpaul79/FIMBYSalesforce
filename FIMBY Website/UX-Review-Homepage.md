# UX Review: FIMBY Homepage — "Family In My Backyard"

## Summary
The messaging is strong and the content fits the mission. From a UX perspective, the page would benefit from clearer hierarchy, one-at-a-time section reveals, image placeholders to break up text, and a calmer CTA structure so the viewer isn’t overwhelmed.

---

## 1. **Information hierarchy & first impression**
- **Issue:** The main message lives inside a blockquote, so it doesn’t read as a clear “hero” or primary headline. The eye doesn’t get one obvious starting point.
- **Suggestion:** Use a dedicated hero section: one main headline, one supporting line, and a single primary CTA (e.g. “How it works” or “Join FIMBY”). Move the rest of the intro into the first scroll section.

## 2. **Too many equal CTAs**
- **Issue:** Six buttons in one row (How It Works, FAQ, Mission Vision, Signup, Login, Contact) compete for attention. There’s no clear primary vs secondary action.
- **Suggestion:** One primary CTA above the fold (e.g. Sign up or How it works). Group secondary actions (FAQ, Mission/Vision, Contact) as text links or a small link list. Keep Login visible but secondary.

## 3. **Sections feel samey**
- **Issue:** Every section uses the same two-column pattern (heading left, text right) and similar length. The page feels like one long essay instead of distinct “chapters.”
- **Suggestion:** Vary layout by section: hero → feature cards → quote block → short list → values. Add clear section titles and optional short intros so each block has a clear role and can “reveal” one by one on scroll.

## 4. **No scroll-driven narrative**
- **Issue:** Everything is visible in one flow. There’s no sense of progression or “one section at a time” as you scroll.
- **Suggestion:** Define clear sections (e.g. with a shared class like `fimby-scroll-section`). Use CSS (e.g. opacity/transform) or a small script so sections animate or “come into view” as they enter the viewport. Keeps the same content but improves pacing and focus.

## 5. **Missing imagery**
- **Issue:** One small image (FIMBY logo) in a long page. No photos of people, neighbourhoods, or shared life to support the “neighbourhood” and “belonging” message.
- **Suggestion:** Add explicit image placeholders per section (e.g. “Hero: neighbourhood or diverse neighbours,” “How it works: someone lending/helping,” “Care: people talking,” “Abundance: sharing items,” “Vision: community gathering”). Replace with real photos later.

## 6. **Geographic note (V6A)**
- **Issue:** The note “FIMBY is currently available to those who live, work or worship in the V6A of Vancouver, BC” is in small cite text at the bottom of the hero and is easy to miss.
- **Suggestion:** Give it its own small line or badge near the primary CTA (e.g. “Currently in Vancouver’s V6A”) or in the footer so eligibility is clear without cluttering the hero.

## 7. **Social links**
- **Issue:** Facebook and Instagram appear at the very end with no context.
- **Suggestion:** Move to a footer block with a short line like “Connect with us” and optional icons. Keeps the main content about the product and mission.

## 8. **Vibe and tone**
- **Content vibe:** Warm, neighbourly, grounded, “belonging not rescuing.” The copy already supports this.
- **Design vibe to aim for:** Warm but clean: soft backgrounds, ample whitespace, one focal point per section. Use the existing teal (#67bbd2) as an accent (buttons, highlights), not everywhere. Consider a warm off-white or very light warm grey for section backgrounds to differentiate from pure white.

---

## POC approach (what the redesign does)
- **Hero:** One headline, one subline, one primary CTA, location note, and an image placeholder.
- **Sections:** Each idea in its own block with a class for scroll-in-view (e.g. `fimby-scroll-section`). Varied layouts: feature cards, quote, list, values.
- **Image placeholders:** One per section with a short note on what photo to use.
- **CTAs:** Primary = Sign up / How it works; secondary = FAQ, Mission/Vision, Contact, Login in a compact footer strip.
- **Footer:** Location (V6A), secondary links, social with “Connect with us.”

This keeps your existing content and improves structure, hierarchy, and readiness for scroll behaviour and imagery.
