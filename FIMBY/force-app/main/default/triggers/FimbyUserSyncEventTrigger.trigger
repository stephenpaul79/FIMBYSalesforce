/**
 * @description Subscribes to Fimby_User_Sync_Event__e and hands the batch off to
 * FimbyUserSyncEventHandler. Platform Event triggers run as the Automated Process
 * user (system-level access), so updating User.Email here is NOT a self-service
 * email change and is therefore not held pending email confirmation.
 */
trigger FimbyUserSyncEventTrigger on Fimby_User_Sync_Event__e (after insert) {
    FimbyUserSyncEventHandler.handle(Trigger.new);
}
