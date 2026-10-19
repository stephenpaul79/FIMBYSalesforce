trigger FimbyResponseTrigger on Response__c (after insert, after update) {
    if (Trigger.isInsert) {
        FimbyResponseTriggerHandler.afterInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
        FimbyResponseTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
    }
}
