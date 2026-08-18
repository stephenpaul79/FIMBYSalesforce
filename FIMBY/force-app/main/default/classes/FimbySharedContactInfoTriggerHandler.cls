/**
 * @description Object-level guarantees for Shared_Contact_Info__c, so the rules hold
 *              no matter which path writes — LWC, Apex service, admin Flow, Data
 *              Loader, or the migration batch.
 *
 *              A share is a consent EPISODE:
 *              - The two parties are fixed at insert. An episode cannot be reassigned.
 *              - Active to Revoked is the only closing transition, and it is one-way.
 *                Revoked to Active is refused; re-sharing must insert a new row.
 *              - A revoked row's snapshot is frozen, so revoked history stays a
 *                trustworthy audit trail rather than something a later write can edit.
 *              - Operational neighbourhood restamps are still allowed on revoked
 *                history, because cells get split and merged long after a share closes.
 *              - Deletes stay allowed: right-to-be-forgotten must never be blocked.
 *
 *              Closing an episode also closes what it authorized. In after-update the
 *              handler locks every bound conversation and posts one explanatory system
 *              message. That DML is deliberately not swallowed: a privacy closure that
 *              silently half-applied would be worse than a failed save.
 */
public without sharing class FimbySharedContactInfoTriggerHandler {

    public static final String REVOKE_BODY = FimbySharedContactService.REVOKE_NOTICE_BODY;

    /**
     * @description Stamps derived security fields on new rows.
     * @param newRows The inserted rows.
     */
    public static void handleBeforeInsert(List<Shared_Contact_Info__c> newRows) {
        stampDerivedFields(newRows, null);
    }

    /**
     * @description Rejects forbidden transitions and keeps derived fields correct.
     * @param newRows The updated rows.
     * @param oldMap The prior state.
     */
    public static void handleBeforeUpdate(
        List<Shared_Contact_Info__c> newRows, Map<Id, Shared_Contact_Info__c> oldMap
    ) {
        for (Shared_Contact_Info__c row : newRows) {
            Shared_Contact_Info__c prior = oldMap.get(row.Id);
            if (prior == null) {
                continue;
            }

            if (row.Contact__c != prior.Contact__c || row.Shared_To__c != prior.Shared_To__c) {
                row.addError(
                    'A contact share belongs to the two people who created it and cannot be reassigned.'
                );
                continue;
            }

            Boolean wasOpen = isOpenStatus(prior.Status__c);
            Boolean isOpen = isOpenStatus(row.Status__c);

            if (!wasOpen && isOpen) {
                row.addError(
                    'Contact sharing that has been stopped cannot be switched back on. '
                    + 'Share again to start a new connection.'
                );
                continue;
            }

            if (!wasOpen && changesDisclosure(row, prior)) {
                row.addError(
                    'Contact sharing that has been stopped is kept as history and can no longer be edited.'
                );
                continue;
            }

            if (wasOpen && !isOpen && row.Consent_Closed_Date__c == null) {
                row.Consent_Closed_Date__c = System.now();
            }
        }

        stampDerivedFields(newRows, oldMap);
    }

    /**
     * @description Closes what a newly revoked episode authorized: every bound thread
     *              becomes read-only and receives one explanatory system message.
     * @param newRows The updated rows.
     * @param oldMap The prior state.
     */
    public static void handleAfterUpdate(
        List<Shared_Contact_Info__c> newRows, Map<Id, Shared_Contact_Info__c> oldMap
    ) {
        Set<Id> newlyRevoked = new Set<Id>();
        for (Shared_Contact_Info__c row : newRows) {
            Shared_Contact_Info__c prior = oldMap.get(row.Id);
            if (prior != null && isOpenStatus(prior.Status__c) && !isOpenStatus(row.Status__c)) {
                newlyRevoked.add(row.Id);
            }
        }
        if (newlyRevoked.isEmpty()) {
            return;
        }
        lockAuthorizedConversations(newlyRevoked);
    }

    /**
     * @description Locks bound threads and posts the read-only notice. Exposed so the
     *              migration batch closes threads through exactly the same path.
     * @param revokedSciIds The episodes that just closed.
     */
    public static void lockAuthorizedConversations(Set<Id> revokedSciIds) {
        if (revokedSciIds == null || revokedSciIds.isEmpty()) {
            return;
        }

        List<Conversation__c> bound = [
            SELECT Id, Locked__c
            FROM Conversation__c
            WHERE Authorizing_Shared_Contact_Info__c IN :revokedSciIds
            AND Locked__c = false
        ];
        if (bound.isEmpty()) {
            return;
        }

        Set<Id> conversationIds = new Map<Id, Conversation__c>(bound).keySet();

        // One notice per thread, even if a revoke is retried or replayed.
        Set<Id> alreadyExplained = new Set<Id>();
        for (Message__c existing : [
            SELECT Conversation__c
            FROM Message__c
            WHERE Conversation__c IN :conversationIds
            AND Is_System_Message__c = true
            AND System_Message_Type__c = 'Contact_Sharing_Revoked'
        ]) {
            alreadyExplained.add(existing.Conversation__c);
        }

        // An empty thread has nothing to explain and should not be resurfaced in the
        // inbox by a system message that is its only content.
        Set<Id> hasHistory = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Conversation__c cid
            FROM Message__c
            WHERE Conversation__c IN :conversationIds
            GROUP BY Conversation__c
        ]) {
            hasHistory.add((Id) ar.get('cid'));
        }

        List<Conversation__c> toLock = new List<Conversation__c>();
        List<Message__c> notices = new List<Message__c>();
        Datetime now = Datetime.now();

        for (Conversation__c conv : bound) {
            toLock.add(new Conversation__c(Id = conv.Id, Locked__c = true));
            if (!alreadyExplained.contains(conv.Id) && hasHistory.contains(conv.Id)) {
                notices.add(new Message__c(
                    Conversation__c = conv.Id,
                    Body__c = REVOKE_BODY,
                    Is_System_Message__c = true,
                    System_Message_Type__c = 'Contact_Sharing_Revoked',
                    Status__c = FimbyConstants.MESSAGE_SENT,
                    Sent_Date__c = now
                ));
            }
        }

        update toLock;
        if (!notices.isEmpty()) {
            insert notices;
        }
    }

    /**
     * @description Keeps Active_Pair_Key__c and the neighbourhood stamps consistent
     *              with the row's parties and status. The key is the concurrency guard
     *              that stops two Active episodes existing for one direction; it is
     *              cleared on revoke so history rows never collide.
     * @param rows The rows being saved.
     * @param oldMap Prior state on update, null on insert.
     */
    private static void stampDerivedFields(
        List<Shared_Contact_Info__c> rows, Map<Id, Shared_Contact_Info__c> oldMap
    ) {
        Set<Id> contactIds = new Set<Id>();
        for (Shared_Contact_Info__c row : rows) {
            if (row.Contact__c != null) contactIds.add(row.Contact__c);
            if (row.Shared_To__c != null) contactIds.add(row.Shared_To__c);
        }
        Map<Id, Id> neighbourhoods = FimbySharedContactService.neighbourhoodsFor(contactIds);

        for (Shared_Contact_Info__c row : rows) {
            if (row.Status__c == null) {
                row.Status__c = FimbyConstants.SHARED_CONTACT_ACTIVE;
            }
            Boolean isOpen = isOpenStatus(row.Status__c);

            row.Active_Pair_Key__c = isOpen
                ? FimbySharedContactService.buildPairKey(row.Contact__c, row.Shared_To__c)
                : null;

            if (isOpen && String.isBlank(row.Active_Pair_Key__c)) {
                row.addError('A contact share must record both the sharer and the recipient.');
                continue;
            }

            // Neighbourhood restamps are operational, not consent changes, so they are
            // applied to revoked history too and must be recalculated every save.
            if (row.Contact__c != null && neighbourhoods.containsKey(row.Contact__c)) {
                row.Contact_Neighbourhood__c = neighbourhoods.get(row.Contact__c);
            }
            if (row.Shared_To__c != null && neighbourhoods.containsKey(row.Shared_To__c)) {
                row.Shared_To_Neighbourhood__c = neighbourhoods.get(row.Shared_To__c);
            }
        }
    }

    /**
     * @description Whether a save alters what was actually disclosed, as opposed to
     *              operational bookkeeping like a neighbourhood restamp.
     * @param row The incoming row.
     * @param prior The stored row.
     * @return true when the snapshot or its context changed.
     */
    private static Boolean changesDisclosure(Shared_Contact_Info__c row, Shared_Contact_Info__c prior) {
        return row.Email__c != prior.Email__c
            || row.Phone__c != prior.Phone__c
            || row.First_Name__c != prior.First_Name__c
            || row.Last_Name__c != prior.Last_Name__c
            || row.Street__c != prior.Street__c
            || row.City__c != prior.City__c
            || row.Province_State__c != prior.Province_State__c
            || row.Postal_Code__c != prior.Postal_Code__c
            || row.Country__c != prior.Country__c
            || row.Additional_Info__c != prior.Additional_Info__c
            || row.Origin__c != prior.Origin__c
            || row.Response__c != prior.Response__c
            || row.Lending_Request__c != prior.Lending_Request__c;
    }

    private static Boolean isOpenStatus(String status) {
        return status == null || status == FimbyConstants.SHARED_CONTACT_ACTIVE;
    }
}
