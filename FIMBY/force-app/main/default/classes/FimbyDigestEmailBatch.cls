/**
 * @description Batchable that replaces the legacy Flow-based digest system. Iterates over
 * Neighbourhood Accounts, builds digest content once per neighbourhood, then enqueues
 * FimbyDigestEmailSendQueueable to send in recipient chunks. Content query + HTML build
 * happens once per neighbourhood.
 *
 * Daily cadence on Sun/Mon targets Include_Sundays users only; Sunday-rest users receive
 * a Monday catch-up batch (DailySundayRestCatchUp) covering Sat+Sun.
 *
 * Send gate: only enqueue the queueable when the builder produces feed-card content AND
 * there are eligible recipients. When neither is true, write a Skipped log row so ops can
 * confirm the batch ran (the presence of one row per active neighbourhood per cadence per
 * day is the proof of life).
 */
global without sharing class FimbyDigestEmailBatch implements Database.Batchable<SObject>, Database.Stateful {

    private String frequency;
    private Date windowStart;
    private Date windowEnd;

    public static final String CADENCE_DAILY = 'Daily';
    public static final String CADENCE_WEEKLY = 'Weekly';
    public static final String CADENCE_DAILY_SUNDAY_REST = 'DailySundayRestCatchUp';

    @TestVisible static final String SKIP_REASON_NO_CONTENT = 'No feed-card content for this window';
    @TestVisible static final String SKIP_REASON_NO_RECIPIENTS = 'No eligible recipients (FIMBY_Summary_Emails__c)';

    global FimbyDigestEmailBatch(String frequency) {
        this.frequency = frequency;
        this.windowEnd = Date.today().addDays(-1);
        if (frequency == CADENCE_WEEKLY) {
            this.windowStart = this.windowEnd.addDays(-6);
        } else if (frequency == CADENCE_DAILY_SUNDAY_REST) {
            this.windowStart = this.windowEnd.addDays(-1);
        } else {
            this.windowStart = this.windowEnd;
        }
    }

    global Database.QueryLocator start(Database.BatchableContext ctx) {
        Set<String> pilotIds = FimbySettings.emailPilotNeighbourhoodIds();
        if (!pilotIds.isEmpty()) {
            return Database.getQueryLocator([
                SELECT Id, Name
                FROM Account
                WHERE RecordType.DeveloperName = 'Boundary_Account'
                  AND Id IN :pilotIds
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id, Name
            FROM Account
            WHERE RecordType.DeveloperName = 'Boundary_Account'
        ]);
    }

    global void execute(Database.BatchableContext ctx, List<Account> neighbourhoods) {
        List<Digest_Email_Log__c> skippedLogs = new List<Digest_Email_Log__c>();
        String builderCadence = resolveBuilderCadence(frequency);

        for (Account nh : neighbourhoods) {
            try {
                FimbyDigestEmailBuilder.DigestResult content =
                    FimbyDigestEmailBuilder.buildDigestContent(
                        nh.Id, nh.Name, builderCadence, windowStart, windowEnd
                    );

                if (content.isEmpty) {
                    skippedLogs.add(buildSkippedLog(nh.Id, content.itemCount, SKIP_REASON_NO_CONTENT));
                    continue;
                }

                List<User> recipients = queryEligibleRecipients(nh.Id);
                if (recipients.isEmpty()) {
                    skippedLogs.add(buildSkippedLog(nh.Id, content.itemCount, SKIP_REASON_NO_RECIPIENTS));
                    continue;
                }

                List<Id> userIds = new List<Id>();
                for (User u : recipients) {
                    userIds.add(u.Id);
                }

                System.enqueueJob(new FimbyDigestEmailSendQueueable(
                    nh.Id, nh.Name, frequency, windowStart, windowEnd,
                    content.html, content.itemCount, userIds
                ));
            } catch (Exception e) {
                FimbyLogger.error('FimbyDigestEmailBatch', 'execute', e, nh.Id);
            }
        }

        if (!skippedLogs.isEmpty()) {
            try {
                Database.upsert(skippedLogs, Digest_Email_Log__c.Idempotency_Key__c, false);
            } catch (Exception e) {
                FimbyLogger.error('FimbyDigestEmailBatch', 'execute-upsert-skipped', e);
            }
        }
    }

    global void finish(Database.BatchableContext ctx) {
        FimbyLogger.info('FimbyDigestEmailBatch', 'finish',
            'Digest batch completed for frequency: ' + frequency);
    }

    @TestVisible
    Date getWindowStartForTest() {
        return windowStart;
    }

    @TestVisible
    Date getWindowEndForTest() {
        return windowEnd;
    }

    @TestVisible
    private List<User> queryEligibleRecipients(Id neighbourhoodId) {
        String summaryCadence = resolveSummaryEmailCadence(frequency);
        Boolean filterIncludeSundaysOnly = frequency == CADENCE_DAILY
            && (FimbyDigestEmailScheduler.isSundayNow() || FimbyDigestEmailScheduler.isMondayNow());
        Boolean filterExcludeSundays = frequency == CADENCE_DAILY_SUNDAY_REST;

        String soql = 'SELECT Id, ContactId, Email, Contact.HasOptedOutOfEmail, Include_Sundays__c, Contact.Account.Name '
            + 'FROM User WHERE Contact.AccountId = :neighbourhoodId '
            + 'AND IsActive = true AND Email != null AND Contact.HasOptedOutOfEmail = false '
            + 'AND FIMBY_Summary_Emails__c = :summaryCadence';
        if (filterIncludeSundaysOnly) {
            soql += ' AND Include_Sundays__c = true';
        } else if (filterExcludeSundays) {
            soql += ' AND Include_Sundays__c = false';
        }
        return Database.query(soql);
    }

    @TestVisible
    private static String resolveBuilderCadence(String freq) {
        if (freq == CADENCE_DAILY_SUNDAY_REST) {
            return CADENCE_DAILY;
        }
        return freq;
    }

    @TestVisible
    private static String resolveSummaryEmailCadence(String freq) {
        if (freq == CADENCE_DAILY_SUNDAY_REST) {
            return CADENCE_DAILY;
        }
        return freq;
    }

    public static String resolveLogCadence(String freq) {
        if (freq == CADENCE_DAILY_SUNDAY_REST) {
            return CADENCE_DAILY;
        }
        return freq;
    }

    private Digest_Email_Log__c buildSkippedLog(Id nhId, Integer itemCount, String reason) {
        return new Digest_Email_Log__c(
            Neighbourhood__c = nhId,
            Cadence__c = resolveLogCadence(frequency),
            Window_Date__c = windowStart,
            Status__c = 'Skipped',
            Recipient_Count__c = 0,
            Content_Item_Count__c = itemCount,
            Template_Version__c = 'FimbyEmailHtmlBuilder',
            Error_Message__c = reason?.abbreviate(255),
            Idempotency_Key__c = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
                nhId, frequency, windowStart, windowEnd
            )
        );
    }
}
