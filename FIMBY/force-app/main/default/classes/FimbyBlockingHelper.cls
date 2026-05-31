/**
 * @description Shared helper for resolving the bidirectional set of Contact Ids
 *              that the given user has blocked OR has been blocked by.
 *              Used to suppress unwanted content / contact across messaging,
 *              vouching, and story comments.
 *
 *              Extracted from duplicate helpers in FimbyConversationController
 *              and FimbyVouchController so the single source of truth is here.
 *
 *              `without sharing` is intentional: callers must be able to see
 *              every Blocked_Contact__c row involving them, regardless of
 *              which party owns the record. The query is hard-scoped to the
 *              caller's own Contact id, so this cannot leak other people's
 *              blocks. Matches the behaviour of the original private helpers
 *              that lived inside `FimbyVouchController` (without sharing).
 */
public without sharing class FimbyBlockingHelper {

    /**
     * @description Returns the set of Contact Ids that should be hidden from
     *              the perspective of the given Contact: anyone the contact has
     *              blocked, plus anyone who has blocked the contact. The input
     *              Contact Id itself is excluded from the result.
     * @param contactId The viewer's Contact Id.
     * @return Set of Contact Ids representing the bidirectional block set.
     */
    public static Set<Id> getBidirectionalBlocks(Id contactId) {
        Set<Id> blocked = new Set<Id>();
        if (contactId == null) {
            return blocked;
        }
        for (Blocked_Contact__c bc : [
            SELECT Blocker__c, Blocked__c
            FROM Blocked_Contact__c
            WHERE Blocker__c = :contactId OR Blocked__c = :contactId
        ]) {
            if (bc.Blocker__c != null && bc.Blocker__c != contactId) {
                blocked.add(bc.Blocker__c);
            }
            if (bc.Blocked__c != null && bc.Blocked__c != contactId) {
                blocked.add(bc.Blocked__c);
            }
        }
        return blocked;
    }
}
