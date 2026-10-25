/**
 * @description Batchable that replaces the legacy Flow-based digest system. Iterates over
 * Neighbourhood Accounts, builds digest content once per neighbourhood, then enqueues
 * FimbyDigestEmailSendQueueable to send in recipient chunks. Content query + HTML build
 * happens once per neighbourhood.
 *
 * Daily cadence on Sun/Mon targets Include_Sundays users only; Sunday-rest users receive
 * a Monday catch-up batch (DailySundayRestCatchUp) covering Sat+Sun.
 *
 * Window: "since last send". Each neighbourhood's window runs from the previous run's
 * Digest_Email_Log__c.Window_End__c to this batch's start time, in the neighbourhood's
 * Time_Zone__c for the first-run midnight fallback (see resolveWindows).
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
    private Datetime runAt;

    public static final String CADENCE_DAILY = 'Daily';
    public static final String CADENCE_WEEKLY = 'Weekly';
    public static final String CADENCE_DAILY_SUNDAY_REST = 'DailySundayRestCatchUp';

    public static final String SKIP_REASON_NO_CONTENT = 'No feed-card content for this window';
    @TestVisible static final String SKIP_REASON_NO_RECIPIENTS = 'No eligible recipients (FIMBY_Summary_Emails__c)';

    private static final Integer DAILY_MAX_LOOKBACK_DAYS = 7;
    private static final Integer WEEKLY_MAX_LOOKBACK_DAYS = 14;
    private static final Integer CATCH_UP_MIN_ANCHOR_AGE_HOURS = 36;
    private static final Integer ANCHOR_QUERY_DAYS = 30;
    private static final Set<String> ADVANCING_STATUSES = new Set<String>{ 'Sent', 'Skipped', 'Partial' };

    @TestVisible
    private static FimbyDigestEmailSendQueueable lastDispatched;

    global FimbyDigestEmailBatch(String frequency) {
        this(frequency, Datetime.now());
    }

    @TestVisible
    private FimbyDigestEmailBatch(String frequency, Datetime runAt) {
        this.frequency = frequency;
        this.runAt = Datetime.newInstance(runAt.getTime() - Math.mod(runAt.getTime(), 60000L));
    }

    /**
     * @description The exact content window for one neighbourhood's run. endAt is exclusive
     * and becomes the next run's startAt. windowDate keeps the legacy label-date rule so
     * Window_Date__c, retention and the idempotency key read the same as before.
     */
    public class DigestWindow {
        public Datetime startAt;
        public Datetime endAt;
        public Date windowDate;
        public String baseKey;
    }

    global Database.QueryLocator start(Database.BatchableContext ctx) {
        Set<String> pilotIds = FimbySettings.emailPilotNeighbourhoodIds();
        if (!pilotIds.isEmpty()) {
            return Database.getQueryLocator([
            SELECT Id, Name, Time_Zone__c
            FROM Account
            WHERE RecordType.DeveloperName = 'Boundary_Account'
                  AND Id IN :pilotIds
            ]);
        }
        return Database.getQueryLocator([
            SELECT Id, Name, Time_Zone__c
            FROM Account
            WHERE RecordType.DeveloperName = 'Boundary_Account'
        ]);
    }

    global void execute(Database.BatchableContext ctx, List<Account> neighbourhoods) {
        List<Digest_Email_Log__c> skippedLogs = new List<Digest_Email_Log__c>();
        String builderCadence = resolveBuilderCadence(frequency);
        Map<Id, DigestWindow> windowByNeighbourhood = resolveWindows(neighbourhoods);

        for (Account nh : neighbourhoods) {
            try {
                DigestWindow window = windowByNeighbourhood.get(nh.Id);
                FimbyDigestEmailBuilder.DigestResult content =
                    FimbyDigestEmailBuilder.buildDigestContent(
                        nh.Id, nh.Name, builderCadence, window.startAt, window.endAt, new Set<Id>()
                    );

                if (content.isEmpty) {
                    skippedLogs.add(buildSkippedLog(nh.Id, window, content.itemCount, SKIP_REASON_NO_CONTENT));
                    continue;
                }

                List<User> recipients = queryEligibleRecipients(nh.Id);
                if (recipients.isEmpty()) {
                    skippedLogs.add(buildSkippedLog(nh.Id, window, content.itemCount, SKIP_REASON_NO_RECIPIENTS));
                    continue;
                }

                dispatchRecipients(nh, window, content, recipients);
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
        DigestWindow window,
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
            nh.Id, nh.Name, frequency, window.windowDate, window.startAt, window.endAt, cohorts
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
    DigestWindow resolveWindowForTest(Account nh) {
        return resolveWindows(new List<Account>{ nh }).get(nh.Id);
    }

    /**
     * @description Resolves each neighbourhood's window from one log query. Order of
     * preference: (1) a stored window under this run's own key, so a retry or resume covers
     * exactly the same content; (2) the end of the latest prior run of the same type that
     * advanced the checkpoint; (3) local midnight N days back (first v2 run, or after the
     * switchover from the calendar-day window). The start is clamped to the max lookback.
     */
    private Map<Id, DigestWindow> resolveWindows(List<Account> neighbourhoods) {
        Set<Id> nhIds = new Set<Id>();
        for (Account nh : neighbourhoods) {
            nhIds.add(nh.Id);
        }
        Map<Id, List<Digest_Email_Log__c>> logsByNeighbourhood = loadCheckpointLogs(nhIds);

        Map<Id, DigestWindow> windows = new Map<Id, DigestWindow>();
        for (Account nh : neighbourhoods) {
            List<Digest_Email_Log__c> logs = logsByNeighbourhood.get(nh.Id);
            windows.put(nh.Id, resolveWindow(
                nh.Id, resolveTimeZone(nh), logs != null ? logs : new List<Digest_Email_Log__c>()
            ));
        }
        return windows;
    }

    private Map<Id, List<Digest_Email_Log__c>> loadCheckpointLogs(Set<Id> nhIds) {
        Datetime lowerBound = runAt.addDays(-ANCHOR_QUERY_DAYS);
        Set<String> cadences = new Set<String>{ CADENCE_DAILY, CADENCE_WEEKLY };
        Map<Id, List<Digest_Email_Log__c>> logsByNeighbourhood = new Map<Id, List<Digest_Email_Log__c>>();
        for (Digest_Email_Log__c log : [
            SELECT Id, Neighbourhood__c, Idempotency_Key__c, Status__c,
                   Window_Start__c, Window_End__c
            FROM Digest_Email_Log__c
            WHERE Neighbourhood__c IN :nhIds
              AND Cadence__c IN :cadences
              AND Window_End__c != null
              AND Window_End__c >= :lowerBound
            ORDER BY Window_End__c DESC
            LIMIT 2000
        ]) {
            if (!logsByNeighbourhood.containsKey(log.Neighbourhood__c)) {
                logsByNeighbourhood.put(log.Neighbourhood__c, new List<Digest_Email_Log__c>());
            }
            logsByNeighbourhood.get(log.Neighbourhood__c).add(log);
        }
        return logsByNeighbourhood;
    }

    private DigestWindow resolveWindow(Id nhId, TimeZone tz, List<Digest_Email_Log__c> logs) {
        DigestWindow window = new DigestWindow();
        window.endAt = runAt;
        Date localEndDate = Date.valueOf(runAt.format('yyyy-MM-dd', tz.getID()));
        window.windowDate = localEndDate.addDays(-labelDaysBack(frequency));
        window.baseKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(nhId, frequency, window.windowDate);

        for (Digest_Email_Log__c log : logs) {
            if (log.Idempotency_Key__c != null && log.Idempotency_Key__c.startsWith(window.baseKey)
                && log.Window_Start__c != null) {
                if (log.Window_Start__c < log.Window_End__c) {
                    window.startAt = log.Window_Start__c;
                    window.endAt = log.Window_End__c;
                    return window;
                }
                FimbyLogger.error('FimbyDigestEmailBatch', 'resolveWindow',
                    new DigestWindowException('Stored window is invalid for ' + log.Idempotency_Key__c), nhId);
            }
        }

        Datetime anchor = findAnchor(nhId, window.baseKey, logs);
        Datetime startAt = anchor != null
            ? anchor
            : localMidnight(localEndDate.addDays(-labelDaysBack(frequency)), tz);

        Datetime floor = runAt.addDays(-maxLookbackDays(frequency));
        window.startAt = startAt < floor ? floor : startAt;
        return window;
    }

    /**
     * @description End of the latest prior run of this run type that advanced the checkpoint.
     * A run (one base key plus any block-variant keys) advances when any of its rows is not
     * Failed, so a failed variant never holds back the neighbourhood. An all-Failed run does
     * not advance, so the next run covers its content too.
     */
    private Datetime findAnchor(Id nhId, String currentBaseKey, List<Digest_Email_Log__c> logs) {
        String anchorType = frequency == CADENCE_WEEKLY ? CADENCE_WEEKLY : CADENCE_DAILY;
        Datetime latestAllowedEnd = frequency == CADENCE_DAILY_SUNDAY_REST
            ? runAt.addHours(-CATCH_UP_MIN_ANCHOR_AGE_HOURS)
            : runAt;

        Map<String, Datetime> endByRun = new Map<String, Datetime>();
        Set<String> advancingRuns = new Set<String>();
        for (Digest_Email_Log__c log : logs) {
            String runKey = baseKeyOf(log.Idempotency_Key__c);
            if (runKey == null || runKey == currentBaseKey || runTypeOf(runKey, nhId) != anchorType) {
                continue;
            }
            if (log.Window_End__c > runAt) {
                FimbyLogger.error('FimbyDigestEmailBatch', 'findAnchor',
                    new DigestWindowException('Checkpoint is later than this run for ' + log.Idempotency_Key__c), nhId);
                continue;
            }
            if (log.Window_End__c > latestAllowedEnd) {
                continue;
            }
            Datetime runEnd = endByRun.get(runKey);
            if (runEnd == null || log.Window_End__c > runEnd) {
                endByRun.put(runKey, log.Window_End__c);
            }
            if (ADVANCING_STATUSES.contains(log.Status__c)) {
                advancingRuns.add(runKey);
            }
        }

        Datetime anchor;
        for (String runKey : advancingRuns) {
            Datetime runEnd = endByRun.get(runKey);
            if (anchor == null || runEnd > anchor) {
                anchor = runEnd;
            }
        }
        return anchor;
    }

    /** v2 base key: {nhId}_{Type}_v2_{yyyy-MM-dd}; anything after is a variant suffix. */
    @TestVisible
    private static String baseKeyOf(String key) {
        if (String.isBlank(key)) {
            return null;
        }
        Integer marker = key.indexOf(FimbyDigestEmailSendQueueable.KEY_VERSION_MARKER);
        if (marker < 0) {
            return null;
        }
        Integer baseLength = marker + FimbyDigestEmailSendQueueable.KEY_VERSION_MARKER.length() + 10;
        return key.length() >= baseLength ? key.substring(0, baseLength) : null;
    }

    private static String runTypeOf(String baseKey, Id nhId) {
        String prefix = String.valueOf(nhId) + '_';
        Integer marker = baseKey.indexOf(FimbyDigestEmailSendQueueable.KEY_VERSION_MARKER);
        if (!baseKey.startsWith(prefix) || marker <= prefix.length()) {
            return null;
        }
        return baseKey.substring(prefix.length(), marker);
    }

    private static Integer labelDaysBack(String freq) {
        if (freq == CADENCE_WEEKLY) {
            return 7;
        }
        return freq == CADENCE_DAILY_SUNDAY_REST ? 2 : 1;
    }

    private static Integer maxLookbackDays(String freq) {
        return freq == CADENCE_WEEKLY ? WEEKLY_MAX_LOOKBACK_DAYS : DAILY_MAX_LOOKBACK_DAYS;
    }

    private static TimeZone resolveTimeZone(Account nh) {
        Object tzId = nh.getPopulatedFieldsAsMap().get('Time_Zone__c');
        if (tzId != null && String.isNotBlank(String.valueOf(tzId))) {
            return TimeZone.getTimeZone(String.valueOf(tzId));
        }
        return UserInfo.getTimeZone();
    }

    /**
     * @description UTC instant of local midnight on the given date. The offset is taken at
     * midnight itself (second pass), not at run time, because they differ on a DST change day.
     */
    @TestVisible
    private static Datetime localMidnight(Date localDate, TimeZone tz) {
        Datetime gmtMidnight = Datetime.newInstanceGmt(localDate, Time.newInstance(0, 0, 0, 0));
        Datetime guess = gmtMidnight.addSeconds(-tz.getOffset(gmtMidnight) / 1000);
        return gmtMidnight.addSeconds(-tz.getOffset(guess) / 1000);
    }

    public class DigestWindowException extends Exception {}

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
    private Digest_Email_Log__c buildSkippedLog(Id nhId, DigestWindow window, Integer itemCount, String reason) {
        return new Digest_Email_Log__c(
            Neighbourhood__c = nhId,
            Cadence__c = resolveLogCadence(frequency),
            Window_Date__c = window.windowDate,
            Window_Start__c = window.startAt,
            Window_End__c = window.endAt,
            Status__c = 'Skipped',
            Recipient_Count__c = 0,
            Content_Item_Count__c = itemCount,
            Template_Version__c = 'FimbyEmailHtmlBuilder',
            Error_Message__c = reason?.abbreviate(255),
            Idempotency_Key__c = window.baseKey
        );
    }
}
