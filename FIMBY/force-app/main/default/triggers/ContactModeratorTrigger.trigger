trigger ContactModeratorTrigger on Contact (after update) {
    ContactModeratorTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
}
