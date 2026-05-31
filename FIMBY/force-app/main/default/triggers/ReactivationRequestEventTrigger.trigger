/**
 * @description Subscribes to Reactivation_Request_Event__e and hands the batch
 * off to FimbyReactivationRequestEventHandler. Platform Event triggers run as
 * the Automated Process user (system-level access), which is exactly what we
 * need - the publisher is the unauthenticated guest user, who can't read
 * User/Contact, mint tokens, or send email on its own.
 */
trigger ReactivationRequestEventTrigger on Reactivation_Request_Event__e (after insert) {
    FimbyReactivationRequestEventHandler.handle(Trigger.New);
}
