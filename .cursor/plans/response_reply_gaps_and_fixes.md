# Response/Reply Gaps Analysis & Proposed Fixes

**Status:** Key fixes implemented. See "Implemented" section below.

## Summary of Requirements
1. **Internal + external notifications** should lead to viewing the response and replying
2. **Need/Offer detail** should allow poster to drill into a specific response and reply
3. **Replies to responses** should only be made by the poster (Need/Offer owner)
4. **All response and reply functions** must use `Logged_In_As_ID__c` for acting-as contact

---

## Gap 1: Poster-Only Reply Not Enforced

**Current:** `getResponseForReply` and `submitResponseReply` allow BOTH poster AND responder to reply. The access check passes if `isPoster || isResponder`.

**Required:** Only the poster (Need/Offer owner / Posted_By) may reply.

**Fix:**
- In `FimbyResponseController.getResponseForReply`: Block access if `!isPoster` (remove the `isResponder` path that allows responder to reply)
- In `FimbyResponseController.submitResponseReply`: Add guard at start — if `!isPoster`, return error immediately
- Update `fimbyResponseReply` LWC: `getResponseForReply` will now return `notAuthorized` for responders; the component already handles `errorState === 'notAuthorized'`

**Also:** Poster check should consider `Posted_By__c` (Contact) for household support. Currently `isPoster` uses only `Need_Offer.OwnerId` (User). For full Logged_In_As support, poster should be: current User is Need_Offer Owner *OR* current user's acting-as Contact equals Posted_By__c.

---

## Gap 2: Internal Notification Lands on Wrong Page

**Current:** Internal notification `actionUrl` = `/response-detail/{responseId}`. When the poster taps the notification, they go to the Response Detail page. That page uses `fimbyResponsesList`, which:
- Uses **mock data** (no live API)
- **Ignores** `recordId` from the route — does not show the single response or allow reply

**Required:** Clicking the notification should open the specific response with ability to reply (as poster).

**Fix Options:**
- **Option A:** Change notification `actionUrl` to `/response-reply/{responseId}` so poster lands directly on the reply form
- **Option B:** Enhance `fimbyResponsesList` to accept `recordId`; when present, show single response and embed `fimbyResponseReply` (or navigate to response-reply)

**Recommendation:** Option A — use `/response-reply/{responseId}` as the notification link. Simpler and the Response Reply page is designed for this. Ensure the Response_Reply route supports recordId from the URL path (it should, as a record-based route).

---

## Gap 3: Need/Offer Detail — No Drill-Down to Reply

**Current:** `fimbyNeedOfferDetail` displays responses (responder name + status) but **no click handler**. Poster cannot drill into a response to reply.

**Required:** Poster (isAuthor) should be able to click a response row and open reply (modal or navigate to response-reply).

**Fix:**
- Add click handler on response rows when `isAuthor` is true
- Navigate to `/response-reply/{responseId}` or open `fimbyResponseReply` modal with `recordId`
- Make response rows visually clickable (cursor, hover) when poster

---

## Gap 4: External Email Notification Links

**Current:**
- `Response_Received` workflow (on new response) emails `Reply_To_Contact__c` (poster)
- `Reply_Response_Alert` workflow (on reply) emails `Last_Reply_Contact_Lookup__c` (recipient of reply)
- `emailReply` view (FIMBY_Family_In_My_Backyard_2_01) uses `Response_Reply` **Flow** with `recordId`
- Digital Experience site FIMBY1 has `Response_Reply` **page** with `fimbyResponseReply` at `/response-reply`

**Risk:** Email templates may link to Flow vs. the LWC page. Need to ensure the email contains a URL to the site’s response-reply page (e.g. `https://fimby.my.site.com/s/sitename/response-reply/{!Response__c.Id}`) so poster can reply from email.

**Fix:**
- Audit email templates `Response_Reply_1662411096019` and `Response_Received` for the link they use
- Ensure they point to the Digital Experience response-reply URL with `{!Response__c.Id}`

---

## Gap 5: Logged_In_As Usage — Verification

| Component / Method | Logged_In_As Usage | Status |
|--------------------|--------------------|--------|
| `createResponse` | Uses `FimbyContactController.getActingAsContact()` for realContactId, actingAsContactId → Contact__c, On_Behalf_Of_Contact__c | OK |
| `submitResponseReply` | Uses `getActingAsContact()` for replyingContactId | OK |
| `getResponseForReply` | No contact assignment; only access check | OK |
| `getResponseForStatusUpdate` / `updateResponseStatus` | No explicit Logged_In_As; uses User Id for access | Consider: status updates by poster — ensure poster check uses acting-as contact for household |
| `fimbyQuickResponse` | Uses `getActingAsContact()` (display + createResponse passes it) | OK |
| `fimbyResponseReply` | Uses `getActingAsContact()` for display | OK |
| Internal notification recipient | `Posted_By__c` — Contact who posted | OK (notifications filtered by acting-as contact) |

**Potential Gap:** `fimbyNeedOfferDetail.isAuthor` compares `currentUserId` to `OwnerId` and `Posted_By__c`. `Posted_By__c` is a Contact Id; `currentUserId` is a User Id — that comparison is invalid. For households, author should be: User owns the record *OR* acting-as Contact equals Posted_By__c.

**Fix:** Update `isAuthor` to use `FimbyContactController.getActingAsContact()` and compare `actingAsContactId` to `Posted_By__c` (in addition to User/Owner check). May require wire or async call to get acting-as contact; or add an Apex method `getIsAuthorForNeedOffer(needOfferId)` that does this server-side.

---

## Gap 6: Response Detail Page (fimbyResponsesList) Uses Mock Data

**Current:** `fimbyResponsesList` loads hardcoded mock responses. It never calls Apex for real responses.

**Impact:** Even if we fixed the notification URL, a “My Responses” list view (e.g. from My Stuff) would not show real data. Navigation to `response-detail` from fimbyResponsesList passes `recordId`, but the target page doesn’t use it.

**Fix:**
- Add Apex method to fetch responses for the current user (posted needs/offers) — e.g. `getResponsesForCurrentUser`
- Replace mock data in `fimbyResponsesList` with live data
- When `recordId` is provided (from page context), show single response with reply capability or redirect to response-reply

---

## Gap 7: Response_Status_Update — Poster-Only

**Current:** `getResponseForStatusUpdate` allows both Response owner and Need/Offer owner (`hasAccess`).

**Required:** Status updates (Accept, Decline, Complete) should be poster-only, matching reply semantics.

**Fix:** Restrict `getResponseForStatusUpdate` and `updateResponseStatus` to poster only (Need/Offer owner / Posted_By). Remove the “Response owner can update” path if that exists.

---

## Conversation Model (Updated)

- **Both poster and responder** can add replies to the thread — no strict ping-pong.
- **Exclusive thread** — only those 2 individuals (poster + responder) can participate. No 3rd party can chime in.
- **Logged_In_As** — poster detection uses Posted_By__c for household support.

## Implemented Fixes

- **Gap 1 (Exclusive 2-party thread):** `getResponseForReply` and `submitResponseReply` allow poster OR responder (no 3rd party). Added Logged_In_As for household support. Tests: `testGetResponseForReply_AsResponder_Success`, `testGetResponseForReply_ThirdParty_NotAuthorized`.
- **Gap 2 (Notification URL):** Changed internal notification `actionUrl` from `/response-detail/` to `/response-reply/` so poster lands directly on reply form.
- **Gap 3 (Need/Offer drill-down):** Added clickable response rows on `fimbyNeedOfferDetail` for poster (`isAuthor`) — navigates to `/response-reply/{responseId}`.
- **Gap 5 (isAuthor / Logged_In_As):** Updated `fimbyNeedOfferDetail` to use `getActingAsContact()` and compare `actingAsContactId` to `Posted_By__c` for household support.
- **fimbyResponseReply:** Added `extractRecordIdFromUrl()` so it works when navigated to via `/response-reply/{recordId}` even if recordId is not passed from page context.

## Implementation Priority (Remaining)

1. ~~**Poster-only reply**~~ — DONE
2. **Internal notification URL** — use `/response-reply/{responseId}` (Gap 2)
3. **Need/Offer drill-down** — clickable response rows → reply (Gap 3)
4. **isAuthor / Logged_In_As** — Fix `fimbyNeedOfferDetail` (Gap 5)
5. **fimbyResponsesList** — Replace mock with live data; support recordId (Gap 6)
6. **Status update** — Poster-only (Gap 7)
7. **Email templates** — Audit and fix links (Gap 4)

---

## Visibility of Replies to 3rd Parties (Open Question)

**Consideration:** Limit visibility of the reply thread when a 3rd party views the Need/Offer detail page.

**Potential approaches:**

| Approach | Pros | Cons |
|----------|------|------|
| **Hide reply content entirely** | Maximum privacy — conversation stays between poster & responder | Support/admin may need visibility; less transparency in the community |
| **Show “Private conversation” placeholder** | Signals that a thread exists without exposing content | Extra UI; may confuse some users |
| **Show responder names + status only** (current) | Light transparency — “Sarah responded, Accepted” | Reply content in Chatter/Last_Reply could still be accessible via sharing or other UI |
| **Keep full visibility** | Admins/support can help; community transparency | Poster/responder may expect privacy |

**Technical considerations:**
- Reply content lives in **Chatter (FeedItem)** on Response__c and in **Last_Reply__c**
- Hiding requires: sharing rules to restrict Response__c, and/or UI logic to not render reply content for 3rd parties
- Chatter visibility is controlled by sharing on the parent (Response__c) — if 3rd parties have read access, they may see feed items

**Recommendation:** Start with **responder names + status visible** (current), but **don’t expose reply text** (Chatter threads, Last_Reply__c) to 3rd parties. Add sharing/CRUD or UI checks to hide reply content for non-participants. Revisit if admins or support need access.
