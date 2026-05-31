/**
 * @description After-update trigger for Support_Relationship__c. Hands off to
 * the handler so all paper-form lifecycle automation (TOS stamping on
 * approval, supporter notifications, activation-letter task creation) lives
 * in plain Apex.
 */
trigger FimbySupportRelationshipTrigger on Support_Relationship__c (
    before insert, after insert, after update
) {
    if (Trigger.isBefore && Trigger.isInsert) {
        FimbySupportRelationshipTriggerHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        FimbySupportRelationshipTriggerHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        FimbySupportRelationshipTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
