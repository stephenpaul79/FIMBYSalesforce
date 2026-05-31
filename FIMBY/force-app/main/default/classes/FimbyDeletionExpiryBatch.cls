/**
 * @description Daily housekeeping job for the account-deletion flow.
 * Runs three passes synchronously inside one Schedulable execute, which
 * fits the expected volume (low single-digit deletion Cases per day):
 *
 *   1. Expire stale Awaiting Confirmation Cases — Cases whose
 *      Confirmation_Sent_Date__c is older than 7 days. Marked Expired,
 *      cancellation email sent, Case closed.
 *   2. Process 24-hour safeguard — Cases in Confirmed with
 *      Safeguard_Enqueue_After__c at or before now. Invokes
 *      FimbyDeletionController.enqueue, which flags Contact, sends the
 *      completion email, and enqueues FimbyDeactivateUserQueueable.
 *   3. Rate-limit detection — backstop for FimbyDeletionIntakeService.
 *      Any ContactId with more than 3 deletion Cases in the last 24h gets
 *      Deletion_Rate_Limit_Flagged__c set on all of those Cases. The case
 *      owner reviews flagged Cases manually before allowing CONFIRM DELETE
 *      to be honoured.
 *
 * Implements Schedulable only — Batchable was unnecessary for the expected
 * volume. Refactor to Batchable if deletion Case volume ever exceeds the
 * synchronous SOQL/CPU limits.
 *
 * Schedule via:
 *   System.schedule('FIMBY Deletion Expiry', '0 0 1 * * ?',
 *                   new FimbyDeletionExpiryBatch());
 */
global without sharing class FimbyDeletionExpiryBatch implements Schedulable {

    private static final Integer EXPIRY_DAYS = 7;
    private static final Integer RATE_LIMIT_MAX_PER_24H = 3;
    private static final String DELETION_RT_DEVELOPER_NAME = 'Account_Deletion';

    /**
     * @description Schedulable entry point. Runs all three passes.
     */
    global void execute(SchedulableContext sc) {
        run();
    }

    /**
     * @description Public entry point so tests (and Anonymous Apex) can
     * invoke without scheduling.
     */
    public static void run() {
        Id deletionRtId = getDeletionRecordTypeId();
        if (deletionRtId == null) {
            FimbyLogger.warn('FimbyDeletionExpiryBatch', 'run',
                'Account_Deletion RecordType not deployed yet — skipping all passes');
            return;
        }
        try {
            processExpiry(deletionRtId);
        } catch (Exception e) {
            FimbyLogger.error('FimbyDeletionExpiryBatch', 'processExpiry', e);
        }
        try {
            processSafeguard(deletionRtId);
        } catch (Exception e) {
            FimbyLogger.error('FimbyDeletionExpiryBatch', 'processSafeguard', e);
        }
        try {
            processRateLimit(deletionRtId);
        } catch (Exception e) {
            FimbyLogger.error('FimbyDeletionExpiryBatch', 'processRateLimit', e);
        }
    }

    /**
     * @description Pass 1 — find Cases stuck in Awaiting Confirmation past
     * the 7-day deadline. Mark Expired, send the cancellation email, close.
     */
    private static void processExpiry(Id deletionRtId) {
        DateTime cutoff = System.now().addDays(-EXPIRY_DAYS);

        List<Case> stale = [
            SELECT Id, Contact_User_Id__c, ContactId, SuppliedEmail
            FROM Case
            WHERE RecordTypeId = :deletionRtId
              AND Deletion_Stage__c = 'Awaiting Confirmation'
              AND Confirmation_Sent_Date__c <= :cutoff
              AND Deletion_Rate_Limit_Flagged__c = false
            LIMIT 200
        ];
        if (stale.isEmpty()) return;

        for (Case c : stale) {
            c.Deletion_Stage__c = 'Expired';
            c.Status = 'Closed';
        }
        Database.update(stale, false);

        for (Case c : stale) {
            if (String.isNotBlank(c.Contact_User_Id__c)) {
                FimbyDeletionEmailService.sendCancellation(c.Id, (Id) c.Contact_User_Id__c);
            } else if (String.isNotBlank(c.SuppliedEmail)) {
                FimbyDeletionEmailService.sendNoActiveAccount(c.Id, c.SuppliedEmail);
            }
        }
    }

    /**
     * @description Pass 2 — find Confirmed Cases whose 24-hour safeguard has
     * elapsed. Hand them to FimbyDeletionController.enqueue.
     */
    private static void processSafeguard(Id deletionRtId) {
        DateTime nowUtc = System.now();

        List<Case> ready = [
            SELECT Id
            FROM Case
            WHERE RecordTypeId = :deletionRtId
              AND Deletion_Stage__c = 'Confirmed'
              AND Safeguard_Enqueue_After__c != null
              AND Safeguard_Enqueue_After__c <= :nowUtc
              AND Deletion_Rate_Limit_Flagged__c = false
            LIMIT 100
        ];
        if (ready.isEmpty()) return;

        List<Id> caseIds = new List<Id>();
        for (Case c : ready) caseIds.add(c.Id);

        FimbyDeletionController.enqueue(caseIds);
    }

    /**
     * @description Pass 3 — backstop the intake-time rate-limit. Any Contact
     * with more than 3 deletion Cases in the last 24h has all of those
     * Cases (regardless of stage) flagged for owner review. Confirmation
     * processing is paused for flagged Cases.
     */
    private static void processRateLimit(Id deletionRtId) {
        DateTime windowStart = System.now().addHours(-24);

        List<AggregateResult> aggs = [
            SELECT ContactId, COUNT(Id) cnt
            FROM Case
            WHERE RecordTypeId = :deletionRtId
              AND ContactId != null
              AND CreatedDate >= :windowStart
            GROUP BY ContactId
            HAVING COUNT(Id) > :RATE_LIMIT_MAX_PER_24H
        ];
        if (aggs.isEmpty()) return;

        Set<Id> abusedContacts = new Set<Id>();
        for (AggregateResult ar : aggs) {
            abusedContacts.add((Id) ar.get('ContactId'));
        }

        List<Case> toFlag = [
            SELECT Id, Deletion_Rate_Limit_Flagged__c
            FROM Case
            WHERE RecordTypeId = :deletionRtId
              AND ContactId IN :abusedContacts
              AND CreatedDate >= :windowStart
              AND Deletion_Rate_Limit_Flagged__c = false
            LIMIT 500
        ];
        if (toFlag.isEmpty()) return;

        for (Case c : toFlag) c.Deletion_Rate_Limit_Flagged__c = true;
        Database.update(toFlag, false);

        FimbyLogger.warn('FimbyDeletionExpiryBatch', 'processRateLimit',
            'Flagged ' + toFlag.size() + ' deletion Case(s) across '
            + abusedContacts.size() + ' Contact(s) for owner review');
    }

    private static Id getDeletionRecordTypeId() {
        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        Map<String, Schema.RecordTypeInfo> infos = d.getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo info = infos.get(DELETION_RT_DEVELOPER_NAME);
        return (info == null) ? null : info.getRecordTypeId();
    }
}
