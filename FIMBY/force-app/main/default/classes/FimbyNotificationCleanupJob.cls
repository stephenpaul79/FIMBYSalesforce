/**
 * @description Scheduled Apex job that runs daily to purge read notifications older than retention days
 * and stale Pending push records older than 7 days (edge cases from repeated quiet hours or active sessions).
 * Schedule example: System.schedule('FIMBY Notification Cleanup', '0 0 2 * * ?', new FimbyNotificationCleanupJob());
 */
global without sharing class FimbyNotificationCleanupJob implements Schedulable {

    @TestVisible
    private static final Integer STALE_PENDING_DAYS = 7;

    global void execute(SchedulableContext ctx) {
        try {
            Integer batchSize = FimbySettings.notificationCleanupBatchSize();

            Datetime readCutoff = Datetime.now().addDays(-FimbySettings.notificationRetentionDays());
            List<Notification__c> staleRead = [
                SELECT Id FROM Notification__c
                WHERE Read_Date__c != null AND Read_Date__c < :readCutoff
                LIMIT :batchSize
            ];
            if (!staleRead.isEmpty()) {
                Database.delete(staleRead, false);
            }

            Datetime pendingCutoff = Datetime.now().addDays(-STALE_PENDING_DAYS);
            List<Notification__c> stalePushPending = [
                SELECT Id FROM Notification__c
                WHERE Push_Status__c = 'Pending' AND CreatedDate < :pendingCutoff
                LIMIT :batchSize
            ];
            if (!stalePushPending.isEmpty()) {
                Database.delete(stalePushPending, false);
            }

            // Stale email Pending: delete notifications stuck as email Pending older than 7 days
            List<Notification__c> staleEmailPending = [
                SELECT Id FROM Notification__c
                WHERE Email_Status__c = 'Pending' AND CreatedDate < :pendingCutoff
                LIMIT :batchSize
            ];
            if (!staleEmailPending.isEmpty()) {
                Database.delete(staleEmailPending, false);
            }

            // Stale email Processing: reset to Pending if older than 1 hour (crashed queueables)
            Datetime processingCutoff = Datetime.now().addHours(-1);
            List<Notification__c> staleProcessing = [
                SELECT Id FROM Notification__c
                WHERE Email_Status__c = 'Processing' AND LastModifiedDate < :processingCutoff
                LIMIT :batchSize
            ];
            if (!staleProcessing.isEmpty()) {
                for (Notification__c n : staleProcessing) {
                    n.Email_Status__c = 'Pending';
                }
                Database.update(staleProcessing, false);
            }

            // Auto-retry: reset Failed emails with retries < 3 and age between 1h and 24h
            Datetime retryOldCutoff = Datetime.now().addHours(-24);
            List<Notification__c> retryable = [
                SELECT Id, Email_Retry_Count__c FROM Notification__c
                WHERE Email_Status__c = 'Failed'
                  AND Email_Retry_Count__c < 3
                  AND LastModifiedDate < :processingCutoff
                  AND LastModifiedDate > :retryOldCutoff
                LIMIT :batchSize
            ];
            if (!retryable.isEmpty()) {
                for (Notification__c n : retryable) {
                    n.Email_Status__c = 'Pending';
                }
                Database.update(retryable, false);
            }

            // Digest log retention: delete records older than 30 days
            Date digestCutoff = Date.today().addDays(-30);
            List<Digest_Email_Log__c> oldDigestLogs = [
                SELECT Id FROM Digest_Email_Log__c
                WHERE Window_Date__c < :digestCutoff
                LIMIT :batchSize
            ];
            if (!oldDigestLogs.isEmpty()) {
                Database.delete(oldDigestLogs, false);
            }
        } catch (Exception e) {
            FimbyLogger.error('FimbyNotificationCleanupJob', 'execute', e);
        }
    }
}