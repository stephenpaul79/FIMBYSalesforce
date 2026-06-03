/**
 * @description Before insert/update on User — mirrors Contact identity onto
 * community users so Experience Cloud welcome emails greet the neighbour, not
 * the admin who activated the account.
 */
trigger FimbyCommunityUserTrigger on User (before insert, before update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        FimbyCommunityUserTriggerHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        FimbyCommunityUserTriggerHandler.handleBeforeUpdate(Trigger.new);
    }
}
