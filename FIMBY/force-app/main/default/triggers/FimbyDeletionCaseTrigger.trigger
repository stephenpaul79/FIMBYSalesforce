trigger FimbyDeletionCaseTrigger on Case (before insert, after insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        FimbyDeletionIntakeService.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isAfter && Trigger.isInsert) {
        FimbyDeletionIntakeService.handleAfterInsert(Trigger.new);
    }
}
