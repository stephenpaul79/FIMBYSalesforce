/**
 * @description Stamps closure fields and hands closed Asks/Offers/Events to the lifecycle
 * service. Replaces the Set_Need_Offer_Status_to_Accepted_for_Auto_Accept Flow.
 *
 * Before update:
 *   - entering Completed/Cancelled/Expired stamps Closed_Date__c (if blank); callers set Closed_By__c
 *   - leaving a terminal status (a future supported reopen) clears both fields
 *   - Reply Received with auto-accept on becomes Reply Accepted
 * After update:
 *   - non-Bulk-Buy posts that entered a terminal status go to FimbyPostLifecycleService once
 */
public without sharing class FimbyNeedsOffersTriggerHandler {

    private static Set<Id> lifecycleHandled = new Set<Id>();

    public static void beforeUpdate(List<Needs_Offers__c> newRows, Map<Id, Needs_Offers__c> oldMap) {
        Datetime now = Datetime.now();
        for (Needs_Offers__c post : newRows) {
            Needs_Offers__c old = oldMap.get(post.Id);
            Boolean wasTerminal = FimbyPostLifecycleService.TERMINAL_POST_STATUSES.contains(old.Status__c);
            Boolean isTerminal = FimbyPostLifecycleService.TERMINAL_POST_STATUSES.contains(post.Status__c);

            if (isTerminal && !wasTerminal && post.Closed_Date__c == null) {
                post.Closed_Date__c = now;
            } else if (!isTerminal && wasTerminal) {
                post.Closed_Date__c = null;
                post.Closed_By__c = null;
            }

            if (post.Status__c == FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED
                && post.Auto_Accept_Responses__c == true) {
                post.Status__c = FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED;
            }
        }
    }

    public static void afterUpdate(List<Needs_Offers__c> newRows, Map<Id, Needs_Offers__c> oldMap) {
        Set<Id> bulkBuyRtIds = bulkBuyRecordTypeIds();
        List<Needs_Offers__c> closed = new List<Needs_Offers__c>();
        for (Needs_Offers__c post : newRows) {
            Needs_Offers__c old = oldMap.get(post.Id);
            if (bulkBuyRtIds.contains(post.RecordTypeId) || lifecycleHandled.contains(post.Id)) {
                continue;
            }
            Boolean wasTerminal = FimbyPostLifecycleService.TERMINAL_POST_STATUSES.contains(old.Status__c);
            Boolean isTerminal = FimbyPostLifecycleService.TERMINAL_POST_STATUSES.contains(post.Status__c);
            if (isTerminal && !wasTerminal) {
                closed.add(post);
                lifecycleHandled.add(post.Id);
            }
        }
        if (!closed.isEmpty()) {
            FimbyPostLifecycleService.onPostsClosed(closed);
        }
    }

    private static Set<Id> bulkBuyRecordTypeIds() {
        Set<Id> ids = new Set<Id>();
        Schema.RecordTypeInfo info = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get(FimbyConstants.RT_BULK_BUY);
        if (info != null) {
            ids.add(info.getRecordTypeId());
        }
        return ids;
    }
}
