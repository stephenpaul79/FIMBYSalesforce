/**
 * @description Monthly Library email (Items To Borrow + Skills On Offer). Runs the first
 * Tuesday of each month via FimbyDigestEmailScheduler('Monthly'), one neighbourhood per
 * execute (scope 1), because an async batch execute may enqueue only one queueable. Each
 * neighbourhood hands its sorted recipient list to one FimbyMonthlyDirectorySendQueueable.
 *
 * Recipients: active users in the neighbourhood with an email, not opted out of email, who
 * have logged in at least once, with the master email-alert toggle and the Library email
 * toggle on (Settings > Library > Email).
 *
 * Idempotency is per neighbourhood per calendar month (first day of the month), so a rerun
 * later in the month resumes a Partial send or exits after a Sent one.
 */
global without sharing class FimbyMonthlyDirectoryBatch implements Database.Batchable<SObject> {

    public static final String CADENCE_MONTHLY = 'Monthly';
    @TestVisible static final String SKIP_REASON_NO_CONTENT = 'No library items or skills to list';
    @TestVisible static final String SKIP_REASON_NO_RECIPIENTS = 'No eligible recipients (Email_Alert_Library__c)';

    @TestVisible
    private static Boolean enforceLastLoginDate = true;
    @TestVisible
    private static FimbyMonthlyDirectorySendQueueable lastDispatched;

    private Date windowDate;

    global FimbyMonthlyDirectoryBatch() {
        this.windowDate = Date.today().toStartOfMonth();
    }

    global Database.QueryLocator start(Database.BatchableContext ctx) {
        Set<String> pilotIds = FimbySettings.emailPilotNeighbourhoodIds();
        if (!pilotIds.isEmpty()) {
            return Database.getQueryLocator([
                SELECT Id, Name FROM Account
                WHERE RecordType.DeveloperName = 'Boundary_Account' AND Id IN :pilotIds
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id, Name FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account'
        ]);
    }

    global void execute(Database.BatchableContext ctx, List<Account> neighbourhoods) {
        for (Account nh : neighbourhoods) {
            try {
                processNeighbourhood(nh);
            } catch (Exception e) {
                FimbyLogger.error('FimbyMonthlyDirectoryBatch', 'execute', e, nh.Id);
            }
        }
    }

    private void processNeighbourhood(Account nh) {
        String key = buildIdempotencyKey(nh.Id, windowDate);
        List<Digest_Email_Log__c> existing = [
            SELECT Id, Status__c FROM Digest_Email_Log__c WHERE Idempotency_Key__c = :key LIMIT 1
        ];
        String existingStatus = existing.isEmpty() ? null : existing[0].Status__c;
        if (existingStatus == 'Sent') {
            return;
        }

        FimbyMonthlyDirectoryEmailBuilder.Directory directory =
            FimbyMonthlyDirectoryEmailBuilder.loadDirectory(nh.Id);
        if (directory.isEmpty()) {
            writeSkippedLog(nh.Id, key, existingStatus, 0, SKIP_REASON_NO_CONTENT);
            return;
        }

        List<Id> recipientIds = new List<Id>();
        for (User u : queryEligibleRecipients(nh.Id)) {
            recipientIds.add(u.Id);
        }
        if (recipientIds.isEmpty()) {
            writeSkippedLog(nh.Id, key, existingStatus, directory.totalCount(), SKIP_REASON_NO_RECIPIENTS);
            return;
        }
        recipientIds.sort();

        FimbyMonthlyDirectorySendQueueable sender =
            new FimbyMonthlyDirectorySendQueueable(nh.Id, nh.Name, windowDate, recipientIds);
        lastDispatched = sender;
        FimbyMonthlyDirectorySendQueueable.dispatch(sender);
    }

    /**
     * @description Proof-of-life row for a neighbourhood that had nothing to send. Never
     * overwrites a row that already recorded sends.
     */
    private void writeSkippedLog(Id nhId, String key, String existingStatus, Integer itemCount, String reason) {
        if (existingStatus != null && existingStatus != 'Skipped') {
            return;
        }
        Database.upsert(new Digest_Email_Log__c(
            Neighbourhood__c = nhId,
            Cadence__c = CADENCE_MONTHLY,
            Window_Date__c = windowDate,
            Status__c = 'Skipped',
            Recipient_Count__c = 0,
            Content_Item_Count__c = itemCount,
            Template_Version__c = 'FimbyMonthlyDirectoryEmailBuilder',
            Error_Message__c = reason.abbreviate(255),
            Idempotency_Key__c = key
        ), Digest_Email_Log__c.Idempotency_Key__c, false);
    }

    @TestVisible
    private List<User> queryEligibleRecipients(Id neighbourhoodId) {
        String soql = 'SELECT Id FROM User WHERE Contact.AccountId = :neighbourhoodId '
            + 'AND IsActive = true AND Email != null AND Contact.HasOptedOutOfEmail = false '
            + 'AND Email_Alerts_Enabled__c = true AND Email_Alert_Library__c = true';
        if (enforceLastLoginDate) {
            soql += ' AND LastLoginDate != null';
        }
        return Database.query(soql);
    }

    global void finish(Database.BatchableContext ctx) {
        FimbyLogger.info('FimbyMonthlyDirectoryBatch', 'finish',
            'Monthly Library email batch completed for ' + String.valueOf(windowDate));
    }

    public static String buildIdempotencyKey(Id nhId, Date windowDate) {
        return String.valueOf(nhId) + '_' + CADENCE_MONTHLY + '_' + String.valueOf(windowDate);
    }

    @TestVisible
    private Date getWindowDateForTest() {
        return windowDate;
    }
}
