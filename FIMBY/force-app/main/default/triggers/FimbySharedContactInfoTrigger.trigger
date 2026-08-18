/**
 * @description Enforces the consent-episode invariant on Shared_Contact_Info__c and
 * makes revocation atomic with locking the threads it authorized. All logic lives in
 * the handler so the admin Flow paths and the migration batch obey the same rules as
 * the LWC paths.
 */
trigger FimbySharedContactInfoTrigger on Shared_Contact_Info__c (
    before insert, before update, after update
) {
    if (FimbySharedContactService.skipTrigger) {
        return;
    }
    if (Trigger.isBefore && Trigger.isInsert) {
        FimbySharedContactInfoTriggerHandler.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        FimbySharedContactInfoTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        FimbySharedContactInfoTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
