trigger FimbyDeletionEmailMessageTrigger on EmailMessage (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        FimbyDeletionConfirmationService.handleAfterInsert(Trigger.new);
    }
}
