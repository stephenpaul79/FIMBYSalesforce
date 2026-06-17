# FIMBY Notification Contract

Voice inherits from CLAUDE.md §5. Cross-refs: architecture (identity stamping, scoping, `NOTIF_*`), apex-best-practices (bulkification, no SOQL in loops).

## 1. Voice — neighbour, not platform
| Rule | Example |
|------|---------|
| Active voice, present tense | `Maya replied to your offer` not `A reply has been posted` |
| Lowercase first-person (`i`, `my`) | `i wanted to check in` |
| Recipient-aware second person | `Maya wants to borrow your drill` not `A neighbour requested an item` |
| Non-punitive | `Maya didn't respond yet` not `Maya failed to respond` |
| No exclamation marks | `Pickup is ready for Maple Co-op` |
| No em/en dashes | periods, commas, new sentences |
| No "Community Member / User / Member" labels | use names; fall back to `'A neighbour'` |

## 2. Title shape
```
"{actor display name} {verb} {object phrase}"   // actor-initiated
"{thing} {state change}"                         // state-initiated, no actor
"Your {thing} {state change}"                    // state change targeting recipient
```
`Title__c` ≤ **80 chars** (iOS lock-screen). Never duplicate `actorName` inside the title when `Actor_Name__c` is also set (LWC renders both → doubles).

## 3. Body shape
One sentence carrying the **deciding context** (date, quantity, location, deadline). `Body__c` ≤ **140 chars**. Empty string allowed when title is self-contained; **never `null`**.

## 4. Actor convention (mandatory)
`Actor_Name__c` is **always one of**:
1. A **human display name** from the **represented identity** (`Posted_By__c`/`On_Behalf_Of__c`/acting-as Contact per the dual-stamp table). Prefer full name; first-name-only when intimacy outweighs disambiguation (lending, bulk-buy).
2. A **team label**: `'Neighbourhood team'` (moderator actions, vouch revoke/pause, support relationship lifecycle) or `'FIMBY'` (system-initiated: auto-handoff, waitlist promotion, event reminders, bulk-buy broadcasts).
3. A documented **icon token** only when it replaces a person: `'care'` (support relationship lifecycle) or `'system'` (reserved). LWC renders the icon instead of initials.

`null` and `''` are **banned** (initials avatar renders blank / `'CA'`).

## 5. URL convention (mandatory — enables host swap)
Strict separation by destination; both surfaces are CMDT-backed (admins edit via Setup, no Apex deploy):

| Destination | Source CMDT | Apex helper |
|-------------|-------------|-------------|
| Experience Cloud site | `FIMBY_URL__mdt` (`Base_URL__c` + `Path__c`) | `FimbySettings.getUrl(devName, recordId?, querySuffix?)` |
| Public website (`fimby.com/...`) | `FIMBY_Public_Website_URL__mdt` (`Full_URL__c`) | `FimbyPublicWebsiteLinks.getUrl(devName)` |

Rules: every `Action_URL__c` and every Experience-Cloud email CTA → `FimbySettings.getUrl(...)` (never hardcoded/relative/public). Every public-website email link → `FimbyPublicWebsiteLinks.getUrl(...)` (never via `FimbySettings`, never a `FIMBY_URL__mdt` record). Every `FIMBY_URL__mdt` record shares the **same** `Base_URL__c`; if you'd want a different base, it belongs in `FIMBY_Public_Website_URL__mdt`. No hardcoded URL strings outside the two helper classes.

```apex
FimbySettings.getUrl(developerName)                          // page route
FimbySettings.getUrl(developerName, recordId)                // record detail
FimbySettings.getUrl(developerName, recordId, querySuffix)   // + query string
FimbyPublicWebsiteLinks.getUrl(developerName)                // Full_URL__c
```

**Double-prefix history:** `FimbyEmailHtmlBuilder.buildCtaUrl()` used to prepend `https://our.fimby.com` unconditionally → `https://our.fimby.com/https://our.fimby.com/...`. Fix: pass through unchanged when `Action_URL__c.startsWithIgnoreCase('http')`. New code must not depend on `buildCtaUrl()` host-stitching.

## 6. Push deep-link metadata (server-only, dormant)
`FimbyPushNotificationService.PushPayload.data` carries optional `action_url` (= `Notification__c.Action_URL__c`) and `notification_id` on single-notification pushes; batched pushes include `action_url` only when the batch covers exactly one notification. Mobile `resolvePushRoute()` currently routes by `channelId` only (→ `/messages` or `/notifications`); it does **not** read `action_url`. Single-notification pushes carry the real `Title__c`/`Body__c`. Multi-item pushes carry a **name-led aggregate** built in `FimbyPushBatchJob` (`buildAggregateTitle`/`buildAggregateBody`): lead with one real `Actor_Name__c`, fall back to `'A neighbour'` (then to today's generic strings when no name exists), team/icon tokens (`'FIMBY'`, `'Neighbourhood team'`, `'care'`, `'system'`) skipped, 80/140 caps truncated on a word boundary, body never `null`. `action_url`/`notification_id` ride only on single-notification pushes.

## 7. Coverage rules — what produces a notification
- **Content edits never notify** (author owns the artifact).
- **Content deletes don't notify when nothing is pending** (deleting a story with comments, a fulfilled post).
- **Content deletes DO notify when something is pending** (library item with active borrow requests, archiving a post with unresolved responders, cancelling an event with RSVPs).
- **Actions on behalf of the recipient always notify** (represented identity gets it).
- **System-driven state changes notify** when the recipient lost an option (waitlist promotion, request lapsed, capacity reached).

## 8. Vouching is system messaging (no opt-out)
All `Vouch_*` types are account-safety messages: no per-category toggle, bypass every gate (master push, per-category, doorbell fatigue, quiet hours). Types: `Vouch_Request_Received`, `Vouch_Request_Reminder`, `Vouch_Approved`, `Vouch_Declined`, `Vouch_Revoked`, `Voucher_Paused`. Push: `FimbyNotificationService.SECURITY_BYPASS_PUSH_TYPES`. Email: `FimbyEmailAlertService.SECURITY_BYPASS_EMAIL_TYPES`. Settings UI: static "Account & Safety" line, no toggle.

## 9. Dual-check ownership
Viewer can see / click through a notification when **either** `Notification__c.Contact__c == actingAsContactId` **OR** the related record's real-actor field matches `realContactId`. Resolve both via `FimbyIdentityRepository`.

## 10. Blocking
Notification list queries filter by `FimbyBlockingHelper.getBidirectionalBlocks(viewerContactId)` against both the represented-identity field and the real-actor field. Don't re-implement inline.
