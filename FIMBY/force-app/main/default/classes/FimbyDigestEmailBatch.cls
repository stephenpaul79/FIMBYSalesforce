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
 *
 * Run with scope 1. An async batch execute may enqueue only one queueable, so each
 * neighbourhood hands all of its recipient cohorts to a single sender that works through
 * them serially.
 */
global without sharing class FimbyDigestEmailBatch implements Database.Batchable<SObject>, Database.Stateful {

    @TestVisible
    private static Boolean enforceLastLoginDate = true;

    private String frequency;
    private Date windowStart;
    private Date windowEnd;

    public static final String CADENCE_DAILY = 'Daily';
    public static final String CADENCE_WEEKLY = 'Weekly';
    public static final String CADENCE_DAILY_SUNDAY_REST = 'DailySundayRestCatchUp';

    public static final String SKIP_REASON_NO_CONTENT = 'No feed-card content for this window';
    @TestVisible static final String SKIP_REASON_NO_RECIPIENTS = 'No eligible recipients (FIMBY_Summary_Emails__c)';

    @TestVisible
    private static FimbyDigestEmailSendQueueable lastDispatched;

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

                dispatchRecipients(nh, content, recipients);
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

    /**
     * @description Partitions a neighbourhood's recipients into a clean cohort (no active
     * blocks — reuses the shared HTML + base idempotency key) and one or more blocker cohorts.
     * Recipients on either side of a block get a per-cohort filtered build that hides the
     * blocked author's cards. Cohorts with identical exclusion sets share one filtered build
     * (de-duped by a sorted-Id signature), and that signature is the variant key threaded
     * into the sender so variant rows never collide with the base row.
     *
     * Every cohort goes to one sender (clean first, then signatures in sorted order); the
     * sender builds each filtered cohort's HTML only when it reaches that cohort.
     */
    private void dispatchRecipients(
        Account nh,
        FimbyDigestEmailBuilder.DigestResult sharedContent,
        List<User> recipients
    ) {
        Map<Id, Set<Id>> exclusionByContact = buildBidirectionalExclusionMap(recipients);

        List<Id> cleanUserIds = new List<Id>();
        Map<String, List<Id>> userIdsBySignature = new Map<String, List<Id>>();
        Map<String, Set<Id>> exclusionBySignature = new Map<String, Set<Id>>();

        for (User u : recipients) {
            Set<Id> excl = u.ContactId != null ? exclusionByContact.get(u.ContactId) : null;
            if (excl == null || excl.isEmpty()) {
                cleanUserIds.add(u.Id);
                continue;
            }
            String signature = buildExclusionSignature(excl);
            if (!userIdsBySignature.containsKey(signature)) {
                userIdsBySignature.put(signature, new List<Id>());
                exclusionBySignature.put(signature, excl);
            }
            userIdsBySignature.get(signature).add(u.Id);
        }

        List<FimbyDigestEmailSendQueueable.DispatchCohort> cohorts =
            new List<FimbyDigestEmailSendQueueable.DispatchCohort>();

        if (!cleanUserIds.isEmpty()) {
            cleanUserIds.sort();
            cohorts.add(new FimbyDigestEmailSendQueueable.DispatchCohort(
                cleanUserIds, null, null, sharedContent.html, sharedContent.itemCount
            ));
        }

        List<String> signatures = new List<String>(userIdsBySignature.keySet());
        signatures.sort();
        for (String signature : signatures) {
            List<Id> cohortUserIds = userIdsBySignature.get(signature);
            cohortUserIds.sort();
            cohorts.add(new FimbyDigestEmailSendQueueable.DispatchCohort(
                cohortUserIds, exclusionBySignature.get(signature), signature, null, null
            ));
        }

        if (cohorts.isEmpty()) {
            return;
        }

        FimbyDigestEmailSendQueueable sender = new FimbyDigestEmailSendQueueable(
            nh.Id, nh.Name, frequency, windowStart, windowEnd, cohorts
        );
        lastDispatched = sender;
        FimbyDigestEmailSendQueueable.dispatch(sender);
    }

    /**
     * @description Batched form of FimbyBlockingHelper.getBidirectionalBlocks: one query
     * resolves, per recipient Contact, the set of Contact Ids to hide. If A blocks B then
     * A's set contains B AND B's set contains A (symmetry). Recipients with no blocks are
     * absent from the map.
     */
    @TestVisible
    private Map<Id, Set<Id>> buildBidirectionalExclusionMap(List<User> recipients) {
        Set<Id> recipientContactIds = new Set<Id>();
        for (User u : recipients) {
            if (u.ContactId != null) {
                recipientContactIds.add(u.ContactId);
            }
        }

        Map<Id, Set<Id>> exclusionByContact = new Map<Id, Set<Id>>();
        if (recipientContactIds.isEmpty()) {
            return exclusionByContact;
        }

        for (Blocked_Contact__c bc : [
            SELECT Blocker__c, Blocked__c
            FROM Blocked_Contact__c
            WHERE Blocker__c IN :recipientContactIds OR Blocked__c IN :recipientContactIds
        ]) {
            if (bc.Blocker__c != null && bc.Blocked__c != null) {
                if (recipientContactIds.contains(bc.Blocker__c)) {
                    addExclusion(exclusionByContact, bc.Blocker__c, bc.Blocked__c);
                }
                if (recipientContactIds.contains(bc.Blocked__c)) {
                    addExclusion(exclusionByContact, bc.Blocked__c, bc.Blocker__c);
                }
            }
        }
        return exclusionByContact;
    }

    private static void addExclusion(Map<Id, Set<Id>> exclusionByContact, Id viewer, Id hidden) {
        if (!exclusionByContact.containsKey(viewer)) {
            exclusionByContact.put(viewer, new Set<Id>());
        }
        exclusionByContact.get(viewer).add(hidden);
    }

    @TestVisible
    private static String buildExclusionSignature(Set<Id> excluded) {
        List<String> ids = new List<String>();
        for (Id excludedId : excluded) {
            ids.add(String.valueOf(excludedId));
        }
        ids.sort();
        return String.join(ids, ',');
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
        if (enforceLastLoginDate) {
            soql += ' AND LastLoginDate != null';
        }
        if (filterIncludeSundaysOnly) {
            soql += ' AND Include_Sundays__c = true';
        } else if (filterExcludeSundays) {
            soql += ' AND Include_Sundays__c = false';
        }
        return Database.query(soql);
    }

    public static String resolveBuilderCadence(String freq) {
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

    /**
     * @description Base Skipped log row for a neighbourhood with no content or no recipients.
     * Empty-filtered variant cohorts are logged by the sender under their variant key.
     */
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
