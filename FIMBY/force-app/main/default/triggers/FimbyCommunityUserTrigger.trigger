/**
 * @description Insert/update on User. Before: mirrors Contact identity onto
 * community users so Experience Cloud welcome emails greet the neighbour, not the
 * admin who activated the account. After: queues a "New Signup" moderator welcome
 * task when a community user tied to a neighbourhood contact becomes active.
 */
trigger FimbyCommunityUserTrigger on User (before insert, before update, after insert, after update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        FimbyCommunityUserTriggerHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        FimbyCommunityUserTriggerHandler.handleBeforeUpdate(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        FimbyCommunityUserTriggerHandler.handleAfterInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        FimbyCommunityUserTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
