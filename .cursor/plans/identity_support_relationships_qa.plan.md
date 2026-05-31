# Identity & Support Relationships QA Plan

## Scope

- Covers the full "Logged In As" framework: identity switching, support-person relationships, community-group representation, manage-identities page, relationship setup flow, acting-as display across the app, organization profiles, actor stamping on content, and relationship lifecycle notifications.

## Priority 1

- Identity switching works end-to-end (AC: select identity from kebab menu, `Logged_In_As_Contact__c` and `Logged_In_As_Neighbourhood__c` update on Contact, feed/cache clears, page reloads into correct neighbourhood context).
- Switch-back to self works (AC: "Switch to myself" clears both fields, feed returns to personal neighbourhood).
- Feed renders correctly under switched identity (AC: neighbourhood-scoped content matches the target identity's neighbourhood, not the user's home neighbourhood).
- Relationship setup flow works for Support Person type (AC: type selection → contact search → consent method → authorization image upload → notes → review → submit creates Pending `Support_Relationship__c`).
- Relationship setup flow works for Community Group Rep type (AC: type selection → org search → consent method → authorization image upload → notes → review → submit creates Pending `Support_Relationship__c` with `Related_Organization__c`).
- Admin approval of relationship works (AC: status change to Approved triggers `Relationship_Approved` notification to helper, relationship appears as switchable identity in kebab).
- Revocation clears identity (AC: revoking an Approved relationship triggers `FimbySupportRelationshipQueueable` to clear helper's `Logged_In_As_*` fields if currently acting as revoked identity, sends `Relationship_Revoked` notification).
- Duplicate guard prevents duplicate active relationships (AC: submitting a second Pending/Approved relationship for the same Contact + target + Neighbourhood + Type combination is blocked by before-insert trigger).
- Content created while acting-as stamps both identities (AC: Story, Message, Response Message, Library Item records have real author in `Contact__c`/`Sender__c` and represented identity in `Posted_By__c`/`On_Behalf_Of__c`/`Listed_By__c`).
- Acting-as chip displays in universal header when not acting as self (AC: translucent pill shows target identity name, disappears when switched back to self).
- Organization contacts are excluded from user-facing contact searches (AC: `Is_Organization_Contact__c = true` records do not appear in messaging recipient search, neighbour search, etc.).

## Priority 2

- Manage Identities page loads three sections correctly (AC: "People I Support", "People Who Support Me", "Community Groups I Represent" each show correct relationship records with status, responsive table/card layout).
- Manage Identities "Access" button switches identity and redirects to home (AC: same behavior as kebab switch).
- Deactivation by helper works (AC: helper deactivates own relationship → status changes to Inactive, `Relationship_Deactivated` notification sent to supported person).
- Dismiss action hides relationship from helper's view without affecting the other party (AC: `Dismissed_By_Helper__c` / `Dismissed_By_Subject__c` fields work independently).
- Kebab menu shows max 3 identities with "Manage identities" link (AC: most recent/relevant identities shown, overflow handled by management page).
- Relationship notifications are always-on and cannot be silenced (AC: `Relationship_Approved`, `Relationship_Revoked`, `Relationship_Request`, `Relationship_Deactivated` bypass push notification preferences and quiet hours).
- Feed cards display organization name/logo (not rep's personal name) when content was posted as an org (AC: `isOrgContact` flag drives avatar and name rendering on `fimbyCard` and home feed).
- Detail pages show both real poster and represented identity when content was posted on behalf (AC: "Posted by {realName} for {orgName}" or equivalent).
- Organization profile page loads correctly (AC: name, type, logo, approval badge, associated neighbourhood, representatives list).
- Validation on identity switch: stale/revoked relationships are lazily cleared (AC: if `Logged_In_As_Contact__c` points to a Contact with no Approved relationship, `getActingAsContactId()` clears the override and falls back to self).

## Priority 3

- Inactive/Revoked relationships display at the bottom of manage-identities tables below Pending and Approved records.
- "Why can't I switch?" states are clear (AC: Pending shows "Awaiting approval", Inactive/Revoked explain status).
- Acting-as label appears on create/edit forms with context-specific wording ("Posting as:", "Responding as:", "Messaging as:", "Requesting as:").
- Organization default avatar (`NoOrgPhoto.png`) renders when org has no logo.
- Celebration fires on first relationship approval (`First_Relationship_Celebrated__c` flag on Contact).
- Icons from `Impact_Icons` static resource render correctly (CommunityReps, care, switch, trust, shield).
- Desktop/mobile layout parity for manage-identities page (table on desktop, cards on mobile).
- Field History Tracking captures identity switch audit trail on `Logged_In_As_Contact__c` and `Logged_In_As_Neighbourhood__c`.

## Tech Map (Consolidated)

- Routes/views: `manage-identities` (new Experience Cloud page needed), `organization-profile` (new Experience Cloud page needed, accepts `recordId`).
- Primary LWCs: `fimbyManageIdentities`, `fimbyRelationshipSetupModal`, `fimbyOrganizationProfile`, `fimbyUniversalHeader` (identity switcher + acting-as chip), `fimbyHomeFeed` (org contact display).
- Key child LWCs: `fimbyResponsiveList`, `fimbyImageUploader`, `fimbyCard`, `fimbyInfiniteScroll`.
- Key Apex: `FimbySupportRelationshipController` (switch identity, get identities, submit/confirm/revoke/deactivate/dismiss relationships), `FimbyIdentityRepository` (identity resolution, cache, neighbourhood override), `FimbyContactController` (getActingAsContact), `FimbyHomeController` (unified feed with org contact fields).
- Key Apex (lifecycle): `FimbySupportRelationshipTrigger` + `FimbySupportRelationshipTriggerHandler` (duplicate guard, status-change notifications), `FimbySupportRelationshipQueueable` (clear identity on revocation).
- Key Apex (modified): `FimbySearchController`, `FimbyLibraryController`, `FimbyQuickPostController`, `FimbyFeedbackController`, `FimbyMyStuffController`, `FimbyContactsController`, `FimbyAskOfferController` (all updated for `Logged_In_As_Contact__c` and `Is_Organization_Contact__c` filtering).
- Custom Objects: `Support_Relationship__c`, `Community_Group_Neighbourhood__c`.
- Key Contact fields: `Logged_In_As_Contact__c`, `Logged_In_As_Neighbourhood__c`, `Is_Organization_Contact__c`, `Organization_Account__c`, `First_Relationship_Celebrated__c`.
- Key Account fields: `Is_Approved_Community_Group__c`, `Organization_Contact__c`, `Logo_URL__c`.
- Notification types: `Relationship_Approved`, `Relationship_Revoked`, `Relationship_Request`, `Relationship_Deactivated`.
