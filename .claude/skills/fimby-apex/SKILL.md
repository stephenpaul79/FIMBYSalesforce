---
name: fimby-apex
description: FIMBY Apex/trigger conventions — identity framework, support relationships, dual-stamp authorization, humane push notifications, rate limits, data-retention jobs, test-data lookup, and Salesforce Apex best practices. Load before editing any **/*.cls or **/*.trigger in the FIMBY repo, and consult the notification-contract reference when touching notification, email, or push classes.
---

# FIMBY Apex Patterns

Read this before writing or changing Apex. Architecture-level identity/dual-stamp/scoping rules live in `CLAUDE.md` §4 — this skill covers the Apex implementation detail. Two reference files extend it:

- **[apex-best-practices.md](apex-best-practices.md)** — general Salesforce Apex standards (bulkification, governor limits, security, testing, design patterns). Apply to all Apex.
- **[notification-contract.md](notification-contract.md)** — the notification/email/push contract. Load whenever you touch `Fimby*Notification*`, `Fimby*Controller`, `FimbyEmailAlert*`, `FimbyTransactionalEmailService`, `FimbyEmailHtmlBuilder`, `FimbyDigestEmailBuilder`, `FimbyPush*`, `FimbySettings`, `FimbyPublicWebsiteLinks`, `Fimby*ReminderJob`, or the related notification/settings LWCs and `FIMBY_URL`/`FIMBY_Public_Website_URL`/`FIMBY_Email_Template` CMDT.

## Identity Framework

`FimbyIdentityRepository` resolves identity per transaction: if `Logged_In_As_Contact__c` is set + an Approved `Support_Relationship__c` exists → use that Contact + its neighbourhood; otherwise → the user's own Contact + `AccountId`. Both `Logged_In_As_*` fields have Field History Tracking. Cache cleared via `FimbyIdentityRepository.clearCache()` + `sessionStorage` on switch.

Always resolve **both** `realContactId` and `actingAsContactId` server-side from `FimbyIdentityRepository` — never trust a single client ID. Authorization checks accept access via **either** path (see CLAUDE.md §4 dual-check). The same dual-check shape applies to lending lifecycle records:
```
req.Requested_By__c == actingAsContactId  OR  req.Requested_By_Real_Contact__c == realContactId
loan.Loaned_To__c   == actingAsContactId  OR  loan.Loaned_To_Real_Contact__c   == realContactId
```
Stamp the audit fields (`Requested_By_Real_Contact__c`, `Loaned_To_Real_Contact__c`) every time you create a `Lending_Request__c` / `Loaned_Item__c`.

### Support Relationships (`Support_Relationship__c`)
Master-detail → Contact (helper). Key fields: `Contact__c` (helper, MD), `Supported_Contact__c`, `Organization__c` (Lookup → Account, Organization RT), `Neighbourhood__c` (required scope), `Relationship_Type__c` (`Support_Person` / `Community_Group_Rep`), `Status__c` (`Pending → Approved → Inactive/Revoked`), `Consent_Method__c`, `Authorization_Image_URL__c`. Push prefs: `Push_Posts__c`, `Push_Messages__c`, `Push_Library__c`.

Lifecycle: Pending → admin approves → Approved; deactivation → Inactive; revocation → Revoked + clears `Logged_In_As_*` via `FimbySupportRelationshipQueueable`. No reactivation — create a new request. Before-insert trigger prevents duplicate Pending/Approved for the same Contact + target + Neighbourhood + Type.

### Community Groups
`Organization` Account RT with `Type='Community Group'`. Key fields: `Is_Approved_Community_Group__c`, `Organization_Contact__c`, `Logo_URL__c`. `Community_Group_Neighbourhood__c` links org ↔ neighbourhoods; `Is_Primary__c` designates primary. Organization Contact's `AccountId` = primary neighbourhood.

### Vouching guard
All vouch actions require the user act as their **own** identity. `FimbyVouchController.enforceOwnIdentityForVouching()` throws an `AuraHandledException` (friendly "switch back to yourself") when `actingAsContactId != realContactId`. Call it as the **first** statement of every public vouch `@AuraEnabled` method. Never bypass.

## Story Comments (`Story_Comment__c`)
FIMBY-native object (not Chatter `FeedItem`) → full dual stamping, scoping, moderation, blocking. MD → `Story__c` (`reparentableMasterDetail=false`, cascade delete, `ControlledByParent`). Dual stamp: `Posted_By__c` = represented identity, `Contact__c` = real author. `Status__c ∈ {Active, Hidden_By_Author, Hidden_By_Moderator}`. Edits always open: each edit captures prior body (255 chars) in `Body_Snapshot__c`, increments `Edit_Count__c`, stamps `Edited_Date__c`. `Mention_Contact_Ids__c` (JSON array) drives one `Notification__c` per mentioned contact + one to story owner. `Story__c.Comment_Count__c` is a roll-up (Active, non-moderator-hidden) — read it, don't aggregate. Blocking via `FimbyBlockingHelper.getBidirectionalBlocks(viewerContactId)` against both stamp fields.

### `FimbyBlockingHelper`
Centralized bidirectional block lookup `getBidirectionalBlocks(Id contactId)`, declared `without sharing` so callers see every block involving them. Used by conversation, vouch, story-comment controllers. **Do not re-implement inline.**

### Thanks
No longer posts to Chatter. Creates one `Response_Message__c` (`Is_System_Message__c=true`, `System_Message_Type__c='Thanks_Sent'`), stamps `Response__c.Poster_Thanked__c`/`Responder_Thanked__c`, sends one `Notification__c` (`Type__c='Thanks_Received'`), optionally emails. Rendered as a terracotta celebration card in `fimbyResponseThread`.

## Humane Push Notification System
Batched **two-gate doorbell** model. Gate check at creation time; batch dispatch every 15 min (`FimbyPushBatchJob`, zero DML; `FimbyPushQueueable` does post-delivery DML).

- **DM gate** (`Push_Messages__c`) — 1:1 DMs, response thread replies.
- **Activity gate** (`Push_Needs_Offers__c`) — RSVPs, event chat, bulk buy, library, stories, reminders.

A gate is **open** when: never pushed, OR user logged in since last push, OR new calendar day (unless fatigue dampener active). Closes when push delivered (stamps `Last_DM_Push_At__c`/`Last_Activity_Push_At__c`). Max one push per user per batch cycle.

### Adding a new notification type — ALL FOUR required (missing any = silent failure)
1. `FimbyConstants.cls` — add `NOTIF_YOUR_TYPE` constant.
2. `Notification__c Type__c` picklist — add the value (restricted).
3. `FimbyNotificationService.PUSH_TYPE_MAP` — map constant → `NotificationType` enum (`MESSAGE` → DM gate; anything else → Activity gate).
4. `FimbyNotificationService.ACTION_VERB_MAP` — add aggregation text (e.g. `'responded to your event'`).

### APIs
- `skipPush=true` (9-param `createNotification()` overload) — in-app-only, never pushes; `Push_Status__c` stays `null`.
- `createNotifications(List<Notification__c>)` — bulk; 1 SOQL total vs 2 SOQL/recipient for single. Always use bulk for multi-recipient (group chat, reminders).

## Rate Limiting
| Protection | Mechanism |
|-----------|-----------|
| Conversations | Max 5/day (`FIMBY_App_Settings__mdt`) |
| Profile updates | Field allowlists (`ALLOWED_CONTACT_FIELDS`, `ALLOWED_USER_*_FIELDS`) — unlisted fields throw |
| Sort params | Safe-sort whitelist (SOQL-injection prevention) |
| Search input | `String.escapeSingleQuotes()` |
| Query caps | search 200, messageable 200, story comments 50 |
| Bulk ops | mark-all-read 1K, delete-all-notifications 2K, push batch 100 |

## Data Retention Jobs
`FimbyNotificationCleanupJob` (daily, 30d read), `FimbyConversationCleanupJob` (daily, 90d DM / 180d threads), `FimbyBulkBuyExpiryJob` (hourly), `FimbyFollowUpExpiryJob` (weekly, 180d), `FimbyFollowUpAutoFinalizeJob` (48h), `FimbyAccountDeactivationBatch` (daily midnight). All TTLs from `FIMBY_App_Settings__mdt` with fallback defaults.

## Controller & Service Conventions
- **Controllers** (`Fimby*Controller`): `@AuraEnabled` for LWC; most use a `private without sharing` inner helper for elevated DML (`IdentityHelper`, `RelationshipHelper`, `NotificationHelper`).
- **Triggers**: one-trigger-per-object handler pattern (`FimbySupportRelationshipTrigger` → `...TriggerHandler`; before insert: duplicate guard; after update: status-change notifications + identity cleanup).
- **Queueables**: cross-object DML separated from trigger context.
- **Services**: `FimbyNotificationService` (in-app + push, creation-time gate), `FimbyPushNotificationService` (HTTP → auth bridge → Expo), `FimbyPushBatchJob` (15-min dispatcher), `FimbyPushQueueable`, `FimbyCacheService`, `FimbyVCardService`.
- **Utilities**: `FimbySettings`, `FimbyConstants`, `FimbyIdentityRepository`, `FimbyLogger` (publishes `Error_Log_Event__e`).
- **Test data**: `FimbyTestDataFactory`.

## Test data lookup — never query Users by email
`FimbyTestDataFactory.createCommunityUser()` generates **dynamic** emails/usernames (`DateTime.now()`, random suffix, static counter). `Email LIKE '%@testorg.com'` is unreliable (zero rows / wrong user / flaky deploys). Tie the User to the Contact created in the same class's `@TestSetup`:

```apex
private static User getTestUser() {
    Contact testContact = getTestContact();
    List<User> users = [SELECT Id, ContactId FROM User
                        WHERE ContactId = :testContact.Id AND IsActive = true LIMIT 1];
    System.assert(!users.isEmpty(), 'TestSetup must create a community User for the test Contact.');
    return users[0];
}
```
`getTestContact()` may use the stable factory domain (`%@fimby.test.com`) **only** when `@TestSetup` creates exactly one neighbourhood Contact. For extra personas, keep a reference to their `ContactId`/`User` — don't invent email patterns. When fixing tests, grep for `@testorg.com` in `*Test.cls` and replace with ContactId-based lookup.
