trigger BlockedContactModeratorTrigger on Blocked_Contact__c (after insert) {
    BlockedContactModeratorTriggerHandler.handleAfterInsert(Trigger.new);
}
