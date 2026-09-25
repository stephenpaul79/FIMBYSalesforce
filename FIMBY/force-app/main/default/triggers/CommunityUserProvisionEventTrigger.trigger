/**
 * @description Subscribes to Community_User_Provision_Event__e (published by the
 * FIMBY_Sign_Up_Private guest flow) and hands the batch to
 * FimbyCommunityUserProvisionHandler. Runs as the admin configured in
 * CommunityUserProvisionEventTriggerConfig so it can insert Users.
 */
trigger CommunityUserProvisionEventTrigger on Community_User_Provision_Event__e (after insert) {
    FimbyCommunityUserProvisionHandler.handle(Trigger.New);
}
