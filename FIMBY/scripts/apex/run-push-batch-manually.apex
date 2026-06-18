// ============================================================================
// RUN PUSH BATCH MANUALLY
// ============================================================================
// Fires the push-notification dispatcher immediately instead of waiting for
// the 15-minute scheduled run. Runs the EXACT same logic as the scheduled job:
// honours quiet hours, Sunday direct-only, the two-gate doorbell, and the
// one-push-per-user-per-cycle cap. It will NOT force a push to someone the
// normal humane-push rules would skip. Capped at FimbySettings.pushBatchCap().
//
// Run via: Salesforce Developer Console → Debug → Open Execute Anonymous
//          window, OR  `sf apex run --file scripts/apex/run-push-batch-manually.apex`
// ============================================================================

Integer pendingBefore = [
    SELECT COUNT()
    FROM Notification__c
    WHERE Push_Status__c IN ('Pending', 'Pending_Quiet')
];
System.debug('Pending push notifications before dispatch: ' + pendingBefore);

if (pendingBefore == 0) {
    System.debug('Nothing to dispatch. No notifications in Pending / Pending_Quiet.');
} else {
    new FimbyPushBatchJob().execute(null);
    System.debug('Push batch dispatched. FimbyPushQueueable enqueued for any eligible users.');
    System.debug('Re-run this script (or check Push_Status__c) shortly to confirm rows moved to Sent.');
}
