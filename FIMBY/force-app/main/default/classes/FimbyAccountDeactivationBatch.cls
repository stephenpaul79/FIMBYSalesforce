/**
 * @description Scheduled batch job that processes account deactivation requests.
 * For each Contact with Deactivation_Requested__c = true:
 *   1. If the Contact has any active lending activity (open Lending_Request__c
 *      or unreturned Loaned_Item__c on either side), defers processing until a
 *      future run when all loans are resolved.
 *   2. Removes the Contact's support relationships, then cascades to any
 *      parent-managed child profile that just lost its last Approved guardian so
 *      the child is scrubbed in this same run rather than left an orphan. Where
 *      another guardian survives, the child's display parent is repaired instead.
 *   3. Hard-deletes content owned or authored by the Contact (posts, stories,
 *      library items, group-chat membership, authored messages, notifications,
 *      share-contact records).
 *   4. Anonymizes references on cross-user kept records (lending history,
 *      legacy 1:1 conversations, orphaned responses).
 *   5. Marks the Contact's Feedback__c rows for 90-day-deferred anonymization.
 *   6. Anonymizes the Contact itself ("A former neighbour") rather than
 *      deleting — keeps foreign-key references resolvable on retained records
 *      held by other neighbours (blocks, completed lending history, etc.).
 *   7. Lets the @future-style obfuscateUser scrub the User-record PII.
 *
 * Schedule via:
 *   System.schedule('FIMBY Account Deactivation', '0 0 0 * * ?', new FimbyAccountDeactivationBatch());
 */
global without sharing class FimbyAccountDeactivationBatch implements Database.Batchable<SObject>, Schedulable {

    private static final Set<String> ACTIVE_LENDING_REQUEST_STATUSES = new Set<String>{
        'Waitlisted', 'Requesting Confirmation', 'Pending Approval', 'Approved'
    };

    private static final Integer FEEDBACK_ANONYMIZATION_DELAY_DAYS = 90;

    /**
     * @description Schedulable execute; kicks off the batch with batch size 10.
     */
    global void execute(SchedulableContext sc) {
        Database.executeBatch(this, 10);
    }

    /**
     * @description Returns query locator for Contacts with Deactivation_Requested__c = true.
     * Belt-and-suspenders: also requires the in-app grace window to be absent or
     * elapsed. Without this guard a Contact in the middle of its 30-day grace
     * could be scrubbed if Deactivation_Requested__c were ever accidentally
     * co-flagged (e.g. via a Flow). FimbyGraceExpiryBatch is the only path that
     * should flip Deactivation_Requested__c for graceful deletes; it runs after
     * Grace_Started_At__c is more than Grace_Window_Days__c (default 30) old.
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        DateTime graceCutoff = System.now()
            .addDays(-FimbySettings.defaultGraceWindowDays());
        return Database.getQueryLocator([
            SELECT Id FROM Contact
            WHERE Deactivation_Requested__c = true
              AND (Grace_Started_At__c = NULL OR Grace_Started_At__c <= :graceCutoff)
        ]);
    }

    /**
     * @description Processes a batch of Contacts. Splits into "ready to deactivate"
     * vs "active loans, defer to next run" then runs each cleanup step.
     */
    global void execute(Database.BatchableContext bc, List<Contact> contacts) {
        Set<Id> allContactIds = new Set<Id>();
        for (Contact c : contacts) {
            allContactIds.add(c.Id);
        }

        Set<Id> heldContactIds = findContactsWithActiveLending(allContactIds);
        if (!heldContactIds.isEmpty()) {
            FimbyLogger.info('FimbyAccountDeactivationBatch', 'execute',
                'Deferring deactivation for ' + heldContactIds.size() +
                ' Contact(s) with active lending: ' + heldContactIds);
        }

        Set<Id> readyContactIds = new Set<Id>();
        for (Id id : allContactIds) {
            if (!heldContactIds.contains(id)) {
                readyContactIds.add(id);
            }
        }
        if (readyContactIds.isEmpty()) {
            return;
        }

        // Parent-managed children who just lost their last guardian join this same
        // transaction, so the adult and the child are scrubbed on one nightly run as
        // the published deletion policy promises.
        Set<Id> cleanupIds = new Set<Id>(readyContactIds);
        cleanupIds.addAll(cascadeManagedProfiles(readyContactIds));

        obfuscateUsers(cleanupIds);
        deleteOwnedContent(cleanupIds);
        anonymizeParticipationRefs(cleanupIds);
        markFeedbackForDelayedAnonymization(cleanupIds);
        anonymizeContacts(cleanupIds);
    }

    // ============================================================
    // Step 0b: No-orphan cascade for parent-managed profiles
    // ============================================================

    /**
     * Removes this chunk's support relationships and works out what that did to any
     * parent-managed children the departing adults looked after.
     *
     * The candidate capture has to happen before the mandates are deleted, because
     * afterwards there is nothing left to point at the child. Doing it in this order
     * also makes the result correct regardless of how Salesforce split the chunks: two
     * guardians of the same child may land in different chunks, and whichever chunk
     * removes the last mandate is the one that sees no survivors.
     *
     * Fails closed. If the cascade throws, the exception escapes execute() and
     * Salesforce rolls the whole chunk back, including the mandate deletion — a
     * guardian must never disappear while their child stays behind unflagged.
     *
     * @param readyContactIds Adults being scrubbed this run.
     * @return Orphaned children with no active loans, to scrub in this transaction.
     */
    private Set<Id> cascadeManagedProfiles(Set<Id> readyContactIds) {
        try {
            Set<Id> candidateChildIds =
                FimbyManagedProfileCascadeService.candidateChildrenOf(readyContactIds);

            cleanUpSupportRelationships(readyContactIds);

            FimbyManagedProfileCascadeService.CascadeResult cascade =
                FimbyManagedProfileCascadeService.resolveAfterGuardianRemoval(candidateChildIds);

            Set<Id> heldOrphanIds = findContactsWithActiveLending(cascade.orphanIds);
            Set<Id> unheldOrphanIds = new Set<Id>();
            for (Id orphanId : cascade.orphanIds) {
                if (!heldOrphanIds.contains(orphanId)) {
                    unheldOrphanIds.add(orphanId);
                }
            }

            // A held child keeps its remaining rows until the run that actually
            // scrubs it, so nothing is half-removed while a loan is still out.
            cleanUpSupportRelationships(unheldOrphanIds);

            FimbyLogger.info('FimbyAccountDeactivationBatch', 'cascadeManagedProfiles',
                'Managed-profile cascade: ' + candidateChildIds.size() + ' candidate(s), '
                + cascade.orphanIds.size() + ' orphaned, '
                + cascade.repairedChildIds.size() + ' display parent(s) repaired, '
                + heldOrphanIds.size() + ' deferred for active lending.');

            return unheldOrphanIds;
        } catch (Exception e) {
            // Logged here as well as rethrown: a repeating signature in Error_Log__c
            // is the only outward sign that a chunk is silently rolling back nightly.
            FimbyLogger.error('FimbyAccountDeactivationBatch', 'cascadeManagedProfiles', e);
            throw e;
        }
    }

    /**
     * Splits support-relationship cleanup into the two things it should always have
     * been. A row where the departing Contact is an actual party (helper or subject)
     * is theirs and goes. A row where they merely appear in an audit lookup belongs to
     * other people: nulling the lookup keeps the mandate intact.
     *
     * The old single-query delete took both, which meant a guardian leaving could
     * destroy the surviving co-guardian's mandate purely because they had been the one
     * to approve it — orphaning the child the cascade had just judged safe.
     *
     * All-or-none DML, so a failure rolls the chunk back rather than partially
     * dismantling someone's relationships.
     */
    private void cleanUpSupportRelationships(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return;
        }

        List<Support_Relationship__c> rows = [
            SELECT Id, Contact__c, Related_Contact__c, Approved_By__c, Ended_By__c
            FROM Support_Relationship__c
            WHERE Contact__c IN :contactIds
               OR Related_Contact__c IN :contactIds
               OR Approved_By__c IN :contactIds
               OR Ended_By__c IN :contactIds
        ];
        if (rows.isEmpty()) {
            return;
        }

        List<Support_Relationship__c> toDelete = new List<Support_Relationship__c>();
        List<Support_Relationship__c> toScrub = new List<Support_Relationship__c>();

        for (Support_Relationship__c rel : rows) {
            Boolean isParty = contactIds.contains(rel.Contact__c)
                || contactIds.contains(rel.Related_Contact__c);
            if (isParty) {
                toDelete.add(rel);
                continue;
            }
            if (contactIds.contains(rel.Approved_By__c)) {
                rel.Approved_By__c = null;
            }
            if (contactIds.contains(rel.Ended_By__c)) {
                rel.Ended_By__c = null;
            }
            toScrub.add(rel);
        }

        if (!toScrub.isEmpty()) {
            update toScrub;
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    /**
     * @description Batch finish callback; no post-processing required.
     */
    global void finish(Database.BatchableContext bc) {
    }

    // ============================================================
    // Step 0: Active-loan hold gate
    // ============================================================

    /**
     * @description Identifies Contacts that have at least one open lending
     * record on either side. Those Contacts are skipped this run; the next
     * scheduled run picks them up once loans are physically resolved.
     */
    private Set<Id> findContactsWithActiveLending(Set<Id> contactIds) {
        Set<Id> held = new Set<Id>();
        if (contactIds == null || contactIds.isEmpty()) {
            return held;
        }

        for (Lending_Request__c lr : [
            SELECT Requested_By__c, Item_Owner__c
            FROM Lending_Request__c
            WHERE Status__c IN :ACTIVE_LENDING_REQUEST_STATUSES
              AND (Requested_By__c IN :contactIds OR Item_Owner__c IN :contactIds)
        ]) {
            if (contactIds.contains(lr.Requested_By__c)) held.add(lr.Requested_By__c);
            if (contactIds.contains(lr.Item_Owner__c)) held.add(lr.Item_Owner__c);
        }

        for (Loaned_Item__c li : [
            SELECT Owned_By__c, Loaned_To__c
            FROM Loaned_Item__c
            WHERE Returned_Date__c = null
              AND (Owned_By__c IN :contactIds OR Loaned_To__c IN :contactIds)
        ]) {
            if (contactIds.contains(li.Owned_By__c)) held.add(li.Owned_By__c);
            if (contactIds.contains(li.Loaned_To__c)) held.add(li.Loaned_To__c);
        }

        return held;
    }

    // ============================================================
    // Step 1: Scrub the User record
    // ============================================================

    /**
     * Uses the standard Salesforce obfuscateUser API to deactivate the User
     * and wipe personal data. Falls back to plain IsActive=false in any
     * test/edge context where obfuscateUser is unavailable.
     */
    private void obfuscateUsers(Set<Id> contactIds) {
        List<User> users = [
            SELECT Id FROM User WHERE ContactId IN :contactIds
        ];
        for (User u : users) {
            try {
                System.UserManagement.obfuscateUser(u.Id);
            } catch (Exception e) {
                FimbyLogger.error('FimbyAccountDeactivationBatch', 'obfuscateUsers', e);
            }
        }

        List<User> stillActive = [
            SELECT Id FROM User WHERE ContactId IN :contactIds AND IsActive = true
        ];
        for (User u : stillActive) {
            u.IsActive = false;
        }
        if (!stillActive.isEmpty()) {
            update stillActive;
        }
    }

    // ============================================================
    // Step 2: Delete content owned or authored by the Contact
    // ============================================================

    /**
     * Hard-deletes records the Contact authored or owned. Filters check both
     * the post-owner and submitted-by fields wherever they differ (e.g.
     * Library_Item__c.Owner_Contact__c vs Listed_By__c) so content posted
     * while acting as a different identity is also cleaned up.
     */
    private void deleteOwnedContent(Set<Id> contactIds) {
        List<SObject> toDelete = new List<SObject>();

        toDelete.addAll([
            SELECT Id FROM Notification__c WHERE Contact__c IN :contactIds
        ]);

        toDelete.addAll([
            SELECT Id FROM Story__c
            WHERE Posted_By__c IN :contactIds OR Contact__c IN :contactIds
        ]);

        toDelete.addAll([
            SELECT Id FROM Needs_Offers__c
            WHERE Posted_By__c IN :contactIds OR Contact__c IN :contactIds
        ]);

        toDelete.addAll([
            SELECT Id FROM Library_Item__c
            WHERE Owner_Contact__c IN :contactIds OR Listed_By__c IN :contactIds
        ]);

        List<Shared_Contact_Info__c> episodes = [
            SELECT Id FROM Shared_Contact_Info__c
            WHERE Contact__c IN :contactIds OR Shared_To__c IN :contactIds
        ];
        // Conversation__c.Authorizing_Shared_Contact_Info__c is SetNull on
        // delete, so deleting these episodes would leave the other neighbour
        // looking at a thread that quietly stops working with no explanation.
        // Lock and explain them first, while the link still exists.
        lockThreadsAuthorizedBy(episodes);
        toDelete.addAll(episodes);

        toDelete.addAll([
            SELECT Id FROM Conversation_Member__c WHERE Contact__c IN :contactIds
        ]);

        toDelete.addAll([
            SELECT Id FROM Message__c
            WHERE Sender__c IN :contactIds OR Sent_By__c IN :contactIds
        ]);

        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }
    }

    /**
     * Reuses the revoke path so a departing neighbour's threads close the same
     * way a withdrawn share does — locked, with the standard notice — rather
     * than silently failing the lazy-bind check later.
     */
    private void lockThreadsAuthorizedBy(List<Shared_Contact_Info__c> episodes) {
        if (episodes == null || episodes.isEmpty()) {
            return;
        }
        Set<Id> sciIds = new Map<Id, Shared_Contact_Info__c>(episodes).keySet();
        try {
            FimbySharedContactInfoTriggerHandler.lockAuthorizedConversations(sciIds);
        } catch (Exception e) {
            // A thread that cannot be locked must not strand the whole scrub;
            // the fail-closed bind check still keeps it from being used.
            FimbyLogger.warn('FimbyAccountDeactivationBatch', 'lockThreadsAuthorizedBy',
                'Could not lock threads bound to deleted episodes: ' + e.getMessage());
        }
    }

    // ============================================================
    // Step 3: Anonymize cross-user kept records
    // ============================================================

    /**
     * Nulls Contact references on records that belong to other neighbours and
     * must be retained. Blocked_Contact__c is intentionally NOT nulled —
     * keeping the row preserves the bidirectional shield, and the
     * anonymized Contact stub still resolves the FK.
     */
    private void anonymizeParticipationRefs(Set<Id> contactIds) {
        List<Conversation__c> convos = [
            SELECT Id, Participant_1__c, Participant_2__c, Last_Message_Sender__c
            FROM Conversation__c
            WHERE Participant_1__c IN :contactIds
               OR Participant_2__c IN :contactIds
               OR Last_Message_Sender__c IN :contactIds
        ];
        for (Conversation__c cv : convos) {
            if (contactIds.contains(cv.Participant_1__c)) cv.Participant_1__c = null;
            if (contactIds.contains(cv.Participant_2__c)) cv.Participant_2__c = null;
            if (contactIds.contains(cv.Last_Message_Sender__c)) cv.Last_Message_Sender__c = null;
        }
        if (!convos.isEmpty()) update convos;

        // Response__c orphans: most cascade-delete with their parent
        // Needs_Offers__c. Surviving rows (e.g. response on a post that
        // wasn't authored by us) get their contact-side fields nulled.
        List<Response__c> responses = [
            SELECT Id, Contact__c, Reply_To_Contact__c, On_Behalf_Of_Contact__c,
                   Last_Reply_Contact_Lookup__c, Flagged_Responder__c, Reported_By__c
            FROM Response__c
            WHERE Contact__c IN :contactIds OR Reply_To_Contact__c IN :contactIds
               OR On_Behalf_Of_Contact__c IN :contactIds OR Last_Reply_Contact_Lookup__c IN :contactIds
               OR Flagged_Responder__c IN :contactIds OR Reported_By__c IN :contactIds
        ];
        for (Response__c r : responses) {
            if (contactIds.contains(r.Contact__c)) r.Contact__c = null;
            if (contactIds.contains(r.Reply_To_Contact__c)) r.Reply_To_Contact__c = null;
            if (contactIds.contains(r.On_Behalf_Of_Contact__c)) r.On_Behalf_Of_Contact__c = null;
            if (contactIds.contains(r.Last_Reply_Contact_Lookup__c)) r.Last_Reply_Contact_Lookup__c = null;
            if (contactIds.contains(r.Flagged_Responder__c)) r.Flagged_Responder__c = null;
            if (contactIds.contains(r.Reported_By__c)) r.Reported_By__c = null;
        }
        if (!responses.isEmpty()) update responses;

        List<Lending_History__c> history = [
            SELECT Id, Lent_By__c, Borrowed_By__c FROM Lending_History__c
            WHERE Lent_By__c IN :contactIds OR Borrowed_By__c IN :contactIds
        ];
        for (Lending_History__c lh : history) {
            if (contactIds.contains(lh.Lent_By__c)) lh.Lent_By__c = null;
            if (contactIds.contains(lh.Borrowed_By__c)) lh.Borrowed_By__c = null;
        }
        if (!history.isEmpty()) update history;
    }

    // ============================================================
    // Step 4: Defer Feedback anonymization 90 days
    // ============================================================

    /**
     * Operational records (abuse reports, complaints) need a holding period
     * after the submitter requests deletion so admins can investigate
     * connected reports. The Feedback Anonymization scheduled batch later
     * nulls the submitter references on rows whose Anonymize_After__c has
     * arrived.
     */
    private void markFeedbackForDelayedAnonymization(Set<Id> contactIds) {
        Date due = Date.today().addDays(FEEDBACK_ANONYMIZATION_DELAY_DAYS);

        List<Feedback__c> feedback = [
            SELECT Id, Anonymize_After__c FROM Feedback__c
            WHERE (Posted_By__c IN :contactIds
                OR Contact__c IN :contactIds
                OR Posted_For_Person__c IN :contactIds)
              AND Anonymize_After__c = null
        ];
        for (Feedback__c f : feedback) {
            f.Anonymize_After__c = due;
        }
        if (!feedback.isEmpty()) update feedback;
    }

    // ============================================================
    // Step 5: Anonymize the Contact (keep the row)
    // ============================================================

    /**
     * Replaces identifying data with a "former neighbour" stub. The Contact
     * row is intentionally retained so foreign-key references on records
     * held by other neighbours (Blocked_Contact, Lending_History, etc.)
     * still resolve and render as "A former neighbour".
     *
     * If the platform refuses the update (e.g. obfuscateUser already locked
     * the Contact for portal-cleanup), falls back to a plain delete.
     */
    private void anonymizeContacts(Set<Id> contactIds) {
        List<Contact> toAnonymize = new List<Contact>();
        for (Id id : contactIds) {
            toAnonymize.add(new Contact(
                Id = id,
                FirstName = 'A former',
                LastName = 'neighbour',
                Email = null,
                Phone = null,
                MobilePhone = null,
                MailingStreet = null,
                MailingCity = null,
                MailingState = null,
                MailingPostalCode = null,
                MailingCountry = null,
                Pronouns__c = null,
                Image_URL__c = null,
                Image_Ratio__c = null,
                Languages_Spoken__c = null,
                Accessibility_Notes__c = null,
                General_Availability__c = null,
                About_Neighbourhood_Tenure__c = null,
                About_What_Brought_You__c = null,
                About_Local_Place__c = null,
                About_Enjoys_Doing__c = null,
                About_Fun_Fact__c = null,
                Care_Welcome_Support__c = null,
                Care_Unhelpful_Things__c = null,
                Care_How_To_Ask__c = null,
                Care_Hard_Nos__c = null,
                Care_Standing_Visible__c = false,
                Care_Updated_Date__c = null,
                Logged_In_As_Contact__c = null,
                Logged_In_As_Neighbourhood__c = null,
                // A parent-managed profile carries a child's birthdate and the
                // adult who looked after it. Both are the whole point of the
                // erasure, so they go with the rest of the identifying data.
                Birthdate = null,
                Is_Parent_Proxied__c = false,
                Proxied_By_Contact__c = null,
                Deactivation_Requested__c = false,
                Grace_Started_At__c = null,
                Grace_Window_Days__c = null
            ));
        }

        List<Database.SaveResult> results = Database.update(toAnonymize, false);
        List<Id> failedIds = new List<Id>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                FimbyLogger.warn('FimbyAccountDeactivationBatch', 'anonymizeContacts',
                    'Anonymize failed for ' + toAnonymize[i].Id +
                    ' — falling back to delete. Error: ' + results[i].getErrors()[0].getMessage());
                failedIds.add(toAnonymize[i].Id);
            }
        }

        if (!failedIds.isEmpty()) {
            List<Contact> fallback = [SELECT Id FROM Contact WHERE Id IN :failedIds];
            if (!fallback.isEmpty()) {
                Database.delete(fallback, false);
            }
        }
    }
}
