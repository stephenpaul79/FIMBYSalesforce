/**
 * @description Moves an active Ask/Offer/Event parent forward when replies arrive or are
 * accepted. Replaces the Update_Need_Offer_Status and auto-accept record-triggered Flows.
 *
 *   Posted / Submitted  -> Reply Received  (any eligible reply)
 *   Posted / Submitted  -> Reply Accepted  (auto-accept on, or an eligible reply is Accepted)
 *   Reply Received      -> Reply Accepted  (an eligible reply becomes Accepted)
 *
 * Reads child statuses directly rather than DLRS rollups, so the result does not depend on
 * trigger order. Never reopens a terminal parent and never touches Bulk Buys.
 */
public without sharing class FimbyResponseTriggerHandler {

    private static final Set<String> ELIGIBLE_RESPONSE_STATUSES = new Set<String>{
        FimbyConstants.RESPONSE_NEW,
        FimbyConstants.RESPONSE_ACCEPTED,
        FimbyConstants.RESPONSE_COMPLETED
    };

    private static final Set<String> ACCEPTED_RESPONSE_STATUSES = new Set<String>{
        FimbyConstants.RESPONSE_ACCEPTED,
        FimbyConstants.RESPONSE_COMPLETED
    };

    private static final Set<String> PRE_REPLY_PARENT_STATUSES = new Set<String>{
        FimbyConstants.NEEDS_OFFERS_POSTED,
        FimbyConstants.NEEDS_OFFERS_SUBMITTED
    };

    private static final Set<String> ADVANCEABLE_PARENT_STATUSES = new Set<String>{
        FimbyConstants.NEEDS_OFFERS_POSTED,
        FimbyConstants.NEEDS_OFFERS_SUBMITTED,
        FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED
    };

    public static void afterInsert(List<Response__c> newRows) {
        advanceParents(collectParents(newRows, null));
    }

    public static void afterUpdate(List<Response__c> newRows, Map<Id, Response__c> oldMap) {
        advanceParents(collectParents(newRows, oldMap));
    }

    private static Set<Id> collectParents(List<Response__c> newRows, Map<Id, Response__c> oldMap) {
        Set<Id> parentIds = new Set<Id>();
        for (Response__c resp : newRows) {
            if (resp.Need_Offer_Responded_To__c == null
                || !ELIGIBLE_RESPONSE_STATUSES.contains(resp.Status__c)) {
                continue;
            }
            Response__c old = oldMap == null ? null : oldMap.get(resp.Id);
            if (old != null && old.Status__c == resp.Status__c
                && old.Need_Offer_Responded_To__c == resp.Need_Offer_Responded_To__c) {
                continue;
            }
            parentIds.add(resp.Need_Offer_Responded_To__c);
        }
        return parentIds;
    }

    @TestVisible
    private static void advanceParents(Set<Id> parentIds) {
        if (parentIds.isEmpty()) {
            return;
        }
        List<Needs_Offers__c> parents = [
            SELECT Id, Status__c, Auto_Accept_Responses__c
            FROM Needs_Offers__c
            WHERE Id IN :parentIds
              AND RecordType.DeveloperName != :FimbyConstants.RT_BULK_BUY
              AND Status__c IN :ADVANCEABLE_PARENT_STATUSES
            FOR UPDATE
        ];
        if (parents.isEmpty()) {
            return;
        }

        Map<Id, Set<String>> statusesByParent = new Map<Id, Set<String>>();
        for (Response__c resp : [
            SELECT Need_Offer_Responded_To__c, Status__c
            FROM Response__c
            WHERE Need_Offer_Responded_To__c IN :new Map<Id, Needs_Offers__c>(parents).keySet()
              AND Status__c IN :ELIGIBLE_RESPONSE_STATUSES
        ]) {
            if (!statusesByParent.containsKey(resp.Need_Offer_Responded_To__c)) {
                statusesByParent.put(resp.Need_Offer_Responded_To__c, new Set<String>());
            }
            statusesByParent.get(resp.Need_Offer_Responded_To__c).add(resp.Status__c);
        }

        List<Needs_Offers__c> updates = new List<Needs_Offers__c>();
        for (Needs_Offers__c parent : parents) {
            Set<String> statuses = statusesByParent.get(parent.Id);
            if (statuses == null || statuses.isEmpty()) {
                continue;
            }
            Boolean anyAccepted = false;
            for (String s : statuses) {
                if (ACCEPTED_RESPONSE_STATUSES.contains(s)) {
                    anyAccepted = true;
                    break;
                }
            }
            String target = nextStatus(parent, anyAccepted);
            if (target != null && target != parent.Status__c) {
                updates.add(new Needs_Offers__c(Id = parent.Id, Status__c = target));
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    @TestVisible
    private static String nextStatus(Needs_Offers__c parent, Boolean anyAccepted) {
        Boolean goAccepted = anyAccepted || parent.Auto_Accept_Responses__c == true;
        if (PRE_REPLY_PARENT_STATUSES.contains(parent.Status__c)) {
            return goAccepted ? FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED : FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED;
        }
        if (parent.Status__c == FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED && goAccepted) {
            return FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED;
        }
        return null;
    }
}
