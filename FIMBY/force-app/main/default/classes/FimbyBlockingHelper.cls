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

    /**
     * @description Single-check convenience over a resolved block set.
     * @param blocked The bidirectional block set (typically from getBidirectionalBlocks).
     * @param candidateId The Contact Id to test.
     * @return true when candidateId is non-null and present in the block set.
     */
    public static Boolean isBlocked(Set<Id> blocked, Id candidateId) {
        return blocked != null && candidateId != null && blocked.contains(candidateId);
    }

    /**
     * @description Pairwise block check between two contacts. Targeted COUNT() query
     *              for surfaces that only need to know about a single relationship and
     *              should not pay for the full bidirectional set. Centralizes the inline
     *              Blocked_Contact__c query that previously lived in FimbyResponseController.
     * @param contactA First Contact Id.
     * @param contactB Second Contact Id.
     * @return true when a block exists in EITHER direction between the two contacts.
     */
    public static Boolean areBlocked(Id contactA, Id contactB) {
        if (contactA == null || contactB == null) {
            return false;
        }
        Integer blockCount = [
            SELECT COUNT()
            FROM Blocked_Contact__c
            WHERE (Blocker__c = :contactA AND Blocked__c = :contactB)
               OR (Blocker__c = :contactB AND Blocked__c = :contactA)
        ];
        return blockCount > 0;
    }

    /**
     * @description Per-item predicate for feed-card DTOs: a card is hidden when either its
     *              represented owner (ownerContactId) or its real author (realAuthorContactId)
     *              is in the block set. Lifted verbatim from the duplicate private copies that
     *              lived in FimbyHomeController and FimbyProfileActivityController.
     * @param item The feed card DTO.
     * @param blocked The bidirectional block set.
     * @return true when the card's author is blocked.
     */
    public static Boolean isBlockedFeedAuthor(FimbyFeedItem item, Set<Id> blocked) {
        if (item == null || blocked == null || blocked.isEmpty()) {
            return false;
        }
        if (item.ownerContactId != null && blocked.contains(item.ownerContactId)) {
            return true;
        }
        if (item.realAuthorContactId != null && blocked.contains(item.realAuthorContactId)) {
            return true;
        }
        return false;
    }

    /**
     * @description Returns the feed cards whose authors are not blocked, preserving order.
     *              Returns the input unchanged when there is nothing to filter.
     * @param items The feed cards.
     * @param blocked The bidirectional block set.
     * @return The visible subset.
     */
    public static List<FimbyFeedItem> filterVisibleFeedItems(List<FimbyFeedItem> items, Set<Id> blocked) {
        if (items == null || items.isEmpty() || blocked == null || blocked.isEmpty()) {
            return items;
        }
        List<FimbyFeedItem> visible = new List<FimbyFeedItem>();
        for (FimbyFeedItem item : items) {
            if (!isBlockedFeedAuthor(item, blocked)) {
                visible.add(item);
            }
        }
        return visible;
    }

    /**
     * @description SObject-agnostic block filter for raw record lists. A record is hidden
     *              when ANY of the listed author lookup fields holds a Contact Id in the
     *              block set. Reads field values via SObject.get so any object that exposes
     *              author lookups (e.g. Story_Comment__c, Skill_Offer__c) can reuse it.
     *              Returns the input unchanged when there is nothing to filter.
     * @param records The records to filter.
     * @param blocked The bidirectional block set.
     * @param authorFieldApiNames The lookup field API names that hold author Contact Ids.
     * @return The visible subset, preserving order.
     */
    public static List<SObject> filterVisible(
        List<SObject> records,
        Set<Id> blocked,
        List<String> authorFieldApiNames
    ) {
        if (records == null || records.isEmpty() || blocked == null || blocked.isEmpty()
                || authorFieldApiNames == null || authorFieldApiNames.isEmpty()) {
            return records;
        }
        List<SObject> visible = new List<SObject>();
        for (SObject record : records) {
            Boolean hidden = false;
            for (String fieldApiName : authorFieldApiNames) {
                Object value = record.get(fieldApiName);
                if (value != null && blocked.contains((Id) value)) {
                    hidden = true;
                    break;
                }
            }
            if (!hidden) {
                visible.add(record);
            }
        }
        return visible;
    }
}
