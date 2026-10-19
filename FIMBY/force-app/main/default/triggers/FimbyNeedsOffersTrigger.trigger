trigger FimbyNeedsOffersTrigger on Needs_Offers__c (before update, after update) {
    if (Trigger.isBefore) {
        FimbyNeedsOffersTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
    } else {
        FimbyNeedsOffersTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}
