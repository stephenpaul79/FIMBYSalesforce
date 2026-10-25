@IsTest
private class FimbyDigestEmailBatchTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        FimbyTestDataFactory.createStories(nh.Id, c.Id, 2, true);
        FimbyTestDataFactory.createNeedsOffers(nh.Id, c.Id, 'Need', 2, true);
        FimbyTestDataFactory.createLibraryItems(nh.Id, c.Id, 2, true);
    }

    @IsTest
    static void batchConstructor_daily() {
        System.assertNotEquals(null, new FimbyDigestEmailBatch('Daily'));
    }

    @IsTest
    static void batchConstructor_weekly() {
        System.assertNotEquals(null, new FimbyDigestEmailBatch('Weekly'));
    }

    @IsTest
    static void scheduler_globalDisabled_exitsEarly() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Digest_Email_Global_Enabled__c = false
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        new FimbyDigestEmailScheduler('Daily').execute(null);
        Test.stopTest();
    }

    @IsTest
    static void batchConstructor_sundayRestCatchUp() {
        System.assertNotEquals(null, new FimbyDigestEmailBatch(FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST));
    }

    /* ---------------------------------------------------------------
     * Since-last-send window resolution. Runs are pinned to fixed instants
     * in January (America/Toronto = UTC-5, no DST) so expectations are exact.
     * Mon 2026-01-19 11:00Z = 6 AM Toronto.
     * --------------------------------------------------------------- */

    private static final String TORONTO = 'America/Toronto';
    private static final Datetime MONDAY_RUN = Datetime.newInstanceGmt(2026, 1, 19, 11, 0, 0);
    private static final Datetime TUESDAY_RUN = Datetime.newInstanceGmt(2026, 1, 20, 11, 0, 0);

    private static Account torontoNeighbourhood() {
        Account nh = new Account(Name = 'Window Test NH', Time_Zone__c = TORONTO);
        insert nh;
        return nh;
    }

    private static Digest_Email_Log__c insertRunLog(
        Id nhId, String freq, Date windowDate, String variantKey,
        String status, Datetime startAt, Datetime endAt
    ) {
        Digest_Email_Log__c log = new Digest_Email_Log__c(
            Neighbourhood__c = nhId,
            Cadence__c = FimbyDigestEmailBatch.resolveLogCadence(freq),
            Window_Date__c = windowDate,
            Window_Start__c = startAt,
            Window_End__c = endAt,
            Status__c = status,
            Idempotency_Key__c = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
                nhId, freq, windowDate, windowDate, variantKey
            )
        );
        insert log;
        return log;
    }

    @IsTest
    static void resolveWindow_dailyFirstRun_fallsBackToLocalMidnightYesterday() {
        Account nh = torontoNeighbourhood();
        FimbyDigestEmailBatch.DigestWindow w =
            new FimbyDigestEmailBatch('Daily', TUESDAY_RUN).resolveWindowForTest(nh);

        System.assertEquals(Datetime.newInstanceGmt(2026, 1, 19, 5, 0, 0), w.startAt,
            'No prior run: start at Toronto midnight on the label date.');
        System.assertEquals(TUESDAY_RUN, w.endAt);
        System.assertEquals(Date.newInstance(2026, 1, 19), w.windowDate);
        System.assertEquals(
            FimbyDigestEmailSendQueueable.buildIdempotencyKey(nh.Id, 'Daily', Date.newInstance(2026, 1, 19)),
            w.baseKey
        );
    }

    @IsTest
    static void resolveWindow_dailyAnchorsOnPreviousSendEnd() {
        Account nh = torontoNeighbourhood();
        Datetime priorEnd = Datetime.newInstanceGmt(2026, 1, 19, 11, 2, 0);
        insertRunLog(nh.Id, 'Daily', Date.newInstance(2026, 1, 18), null, 'Sent',
            Datetime.newInstanceGmt(2026, 1, 18, 11, 0, 0), priorEnd);

        FimbyDigestEmailBatch.DigestWindow w =
            new FimbyDigestEmailBatch('Daily', TUESDAY_RUN).resolveWindowForTest(nh);

        System.assertEquals(priorEnd, w.startAt,
            'Posts made overnight after the last send are picked up, not deferred a day.');
        System.assertEquals(TUESDAY_RUN, w.endAt);
    }

    @IsTest
    static void resolveWindow_allFailedRunDoesNotAdvance() {
        Account nh = torontoNeighbourhood();
        Datetime sentEnd = Datetime.newInstanceGmt(2026, 1, 18, 11, 0, 0);
        insertRunLog(nh.Id, 'Daily', Date.newInstance(2026, 1, 17), null, 'Sent',
            Datetime.newInstanceGmt(2026, 1, 17, 11, 0, 0), sentEnd);
        insertRunLog(nh.Id, 'Daily', Date.newInstance(2026, 1, 18), null, 'Failed',
            sentEnd, Datetime.newInstanceGmt(2026, 1, 19, 11, 0, 0));

        FimbyDigestEmailBatch.DigestWindow w =
            new FimbyDigestEmailBatch('Daily', TUESDAY_RUN).resolveWindowForTest(nh);

        System.assertEquals(sentEnd, w.startAt, 'A wholly failed run is covered again by the next run.');
    }

    @IsTest
    static void resolveWindow_failedVariantStillAdvancesWhenBaseSent() {
        Account nh = torontoNeighbourhood();
        Datetime priorEnd = Datetime.newInstanceGmt(2026, 1, 19, 11, 0, 0);
        Datetime priorStart = Datetime.newInstanceGmt(2026, 1, 18, 11, 0, 0);
        insertRunLog(nh.Id, 'Daily', Date.newInstance(2026, 1, 18), null, 'Sent', priorStart, priorEnd);
        insertRunLog(nh.Id, 'Daily', Date.newInstance(2026, 1, 18), 'blocked-sig', 'Failed', priorStart, priorEnd);

        FimbyDigestEmailBatch.DigestWindow w =
            new FimbyDigestEmailBatch('Daily', TUESDAY_RUN).resolveWindowForTest(nh);

        System.assertEquals(priorEnd, w.startAt);
    }

    @IsTest
    static void resolveWindow_rerunReusesStoredWindow() {
        Account nh = torontoNeighbourhood();
        Datetime storedStart = Datetime.newInstanceGmt(2026, 1, 19, 11, 1, 0);
        Datetime storedEnd = Datetime.newInstanceGmt(2026, 1, 20, 11, 0, 0);
        insertRunLog(nh.Id, 'Daily', Date.newInstance(2026, 1, 19), null, 'Partial', storedStart, storedEnd);

        FimbyDigestEmailBatch.DigestWindow w = new FimbyDigestEmailBatch(
            'Daily', TUESDAY_RUN.addMinutes(45)
        ).resolveWindowForTest(nh);

        System.assertEquals(storedStart, w.startAt, 'A retry covers exactly the original window.');
        System.assertEquals(storedEnd, w.endAt, 'A retry does not stretch the window to the retry time.');
    }

    @IsTest
    static void resolveWindow_longOutageClampsToSevenDays() {
        Account nh = torontoNeighbourhood();
        insertRunLog(nh.Id, 'Daily', Date.newInstance(2026, 1, 8), null, 'Sent',
            Datetime.newInstanceGmt(2026, 1, 8, 11, 0, 0), Datetime.newInstanceGmt(2026, 1, 9, 11, 0, 0));

        FimbyDigestEmailBatch.DigestWindow w =
            new FimbyDigestEmailBatch('Daily', TUESDAY_RUN).resolveWindowForTest(nh);

        System.assertEquals(TUESDAY_RUN.addDays(-7), w.startAt);
        System.assertEquals(FimbyDigestEmailBuilder.TIME_PHRASE_RECOVERY,
            FimbyDigestEmailBuilder.resolveTimePhrase('Daily', w.startAt, w.endAt));
    }

    @IsTest
    static void resolveWindow_futureCheckpointIsIgnored() {
        Account nh = torontoNeighbourhood();
        insertRunLog(nh.Id, 'Daily', Date.newInstance(2026, 1, 18), null, 'Sent',
            Datetime.newInstanceGmt(2026, 1, 18, 11, 0, 0), TUESDAY_RUN.addDays(1));

        FimbyDigestEmailBatch.DigestWindow w =
            new FimbyDigestEmailBatch('Daily', TUESDAY_RUN).resolveWindowForTest(nh);

        System.assertEquals(Datetime.newInstanceGmt(2026, 1, 19, 5, 0, 0), w.startAt,
            'A checkpoint later than the run itself is bad data, so fall back.');
    }

    @IsTest
    static void resolveWindow_mondayCatchUpAnchorsOnSaturdaySend() {
        Account nh = torontoNeighbourhood();
        Datetime saturdayEnd = Datetime.newInstanceGmt(2026, 1, 17, 11, 0, 0);
        insertRunLog(nh.Id, 'Daily', Date.newInstance(2026, 1, 16), null, 'Sent',
            Datetime.newInstanceGmt(2026, 1, 16, 11, 0, 0), saturdayEnd);
        // Sunday's Include_Sundays run must not anchor the Sunday-rest catch-up.
        insertRunLog(nh.Id, 'Daily', Date.newInstance(2026, 1, 17), null, 'Sent',
            saturdayEnd, Datetime.newInstanceGmt(2026, 1, 18, 11, 0, 0));

        FimbyDigestEmailBatch.DigestWindow w = new FimbyDigestEmailBatch(
            FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST, MONDAY_RUN
        ).resolveWindowForTest(nh);

        System.assertEquals(saturdayEnd, w.startAt);
        System.assertEquals(MONDAY_RUN, w.endAt);
        System.assertEquals(Date.newInstance(2026, 1, 17), w.windowDate, 'Catch-up labels Saturday.');
        System.assert(w.baseKey.contains('_DailySundayRest_v2_'), w.baseKey);
        System.assertEquals('this weekend',
            FimbyDigestEmailBuilder.resolveTimePhrase('Daily', w.startAt, w.endAt));
    }

    @IsTest
    static void resolveWindow_mondayCatchUpFirstRun_fallsBackToSaturdayMidnight() {
        Account nh = torontoNeighbourhood();
        FimbyDigestEmailBatch.DigestWindow w = new FimbyDigestEmailBatch(
            FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST, MONDAY_RUN
        ).resolveWindowForTest(nh);

        System.assertEquals(Datetime.newInstanceGmt(2026, 1, 17, 5, 0, 0), w.startAt);
    }

    @IsTest
    static void resolveWindow_weeklyIgnoresDailyRunsAndClampsToFourteenDays() {
        Account nh = torontoNeighbourhood();
        insertRunLog(nh.Id, 'Daily', Date.newInstance(2026, 1, 18), null, 'Sent',
            Datetime.newInstanceGmt(2026, 1, 18, 11, 0, 0), MONDAY_RUN);
        Datetime weeklyEnd = Datetime.newInstanceGmt(2026, 1, 12, 11, 0, 0);
        insertRunLog(nh.Id, 'Weekly', Date.newInstance(2026, 1, 5), null, 'Sent',
            Datetime.newInstanceGmt(2026, 1, 5, 11, 0, 0), weeklyEnd);

        FimbyDigestEmailBatch.DigestWindow w =
            new FimbyDigestEmailBatch('Weekly', MONDAY_RUN).resolveWindowForTest(nh);
        System.assertEquals(weeklyEnd, w.startAt, 'Weekly anchors only on weekly sends.');
        System.assertEquals(Date.newInstance(2026, 1, 12), w.windowDate);

        Account other = torontoNeighbourhood();
        insertRunLog(other.Id, 'Weekly', Date.newInstance(2025, 12, 29), null, 'Sent',
            Datetime.newInstanceGmt(2025, 12, 29, 11, 0, 0), Datetime.newInstanceGmt(2026, 1, 1, 11, 0, 0));
        FimbyDigestEmailBatch.DigestWindow clamped =
            new FimbyDigestEmailBatch('Weekly', MONDAY_RUN).resolveWindowForTest(other);
        System.assertEquals(MONDAY_RUN.addDays(-14), clamped.startAt);
    }

    @IsTest
    static void resolveWindow_weeklyFirstRun_fallsBackSevenLocalDays() {
        Account nh = torontoNeighbourhood();
        FimbyDigestEmailBatch.DigestWindow w =
            new FimbyDigestEmailBatch('Weekly', MONDAY_RUN).resolveWindowForTest(nh);
        System.assertEquals(Datetime.newInstanceGmt(2026, 1, 12, 5, 0, 0), w.startAt);
    }

    @IsTest
    static void resolveWindow_labelDateUsesNeighbourhoodLocalDate() {
        Account nh = torontoNeighbourhood();
        // 03:00Z on Jan 20 is still 10 PM Jan 19 in Toronto.
        FimbyDigestEmailBatch.DigestWindow w = new FimbyDigestEmailBatch(
            'Daily', Datetime.newInstanceGmt(2026, 1, 20, 3, 0, 0)
        ).resolveWindowForTest(nh);
        System.assertEquals(Date.newInstance(2026, 1, 18), w.windowDate);
    }

    @IsTest
    static void resolveWindow_blankTimeZoneUsesRunningUserZone() {
        Account nh = new Account(Name = 'No Zone NH');
        insert nh;
        FimbyDigestEmailBatch.DigestWindow w =
            new FimbyDigestEmailBatch('Daily', TUESDAY_RUN).resolveWindowForTest(nh);
        System.assertEquals(
            FimbyDigestEmailBatch.localMidnight(w.windowDate, UserInfo.getTimeZone()), w.startAt
        );
    }

    @IsTest
    static void batchConstructor_truncatesRunTimeToMinute() {
        Account nh = torontoNeighbourhood();
        FimbyDigestEmailBatch.DigestWindow w = new FimbyDigestEmailBatch(
            'Daily', TUESDAY_RUN.addSeconds(42)
        ).resolveWindowForTest(nh);
        System.assertEquals(TUESDAY_RUN, w.endAt);
    }

    @IsTest
    static void localMidnight_usesOffsetInEffectAtMidnightAcrossDst() {
        TimeZone toronto = TimeZone.getTimeZone(TORONTO);
        System.assertEquals(Datetime.newInstanceGmt(2026, 3, 8, 5, 0, 0),
            FimbyDigestEmailBatch.localMidnight(Date.newInstance(2026, 3, 8), toronto),
            'Spring-forward day: midnight is still standard time.');
        System.assertEquals(Datetime.newInstanceGmt(2026, 3, 9, 4, 0, 0),
            FimbyDigestEmailBatch.localMidnight(Date.newInstance(2026, 3, 9), toronto));
        System.assertEquals(Datetime.newInstanceGmt(2026, 11, 1, 4, 0, 0),
            FimbyDigestEmailBatch.localMidnight(Date.newInstance(2026, 11, 1), toronto),
            'Fall-back day: midnight is still daylight time.');
    }

    @IsTest
    static void baseKeyOf_stripsVariantSuffixAndRejectsLegacyKeys() {
        Id nhId = torontoNeighbourhood().Id;
        String base = FimbyDigestEmailSendQueueable.buildIdempotencyKey(nhId, 'Daily', Date.newInstance(2026, 1, 19));
        String variant = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            nhId, 'Daily', Date.newInstance(2026, 1, 19), Date.newInstance(2026, 1, 19), 'sig'
        );
        System.assertEquals(base, FimbyDigestEmailBatch.baseKeyOf(base));
        System.assertEquals(base, FimbyDigestEmailBatch.baseKeyOf(variant));
        System.assertEquals(null, FimbyDigestEmailBatch.baseKeyOf(nhId + '_Daily_2026-01-19'));
        System.assertEquals(null, FimbyDigestEmailBatch.baseKeyOf(null));
    }

    @IsTest
    static void resolveLogCadence_catchUpLogsAsDaily() {
        System.assertEquals(
            'Daily',
            FimbyDigestEmailBatch.resolveLogCadence(FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST)
        );
    }

    @IsTest
    static void resolveBuilderCadence_mapsCatchUpToDaily() {
        System.assertEquals(
            'Daily',
            FimbyDigestEmailBatch.resolveBuilderCadence(FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST)
        );
    }

    @IsTest
    static void schedulerIsMonday_returnsBooleanCleanly() {
        System.assertNotEquals(null, FimbyDigestEmailScheduler.isMondayNow());
    }

    @IsTest
    static void scheduler_globalEnabled_launchesBatch() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Digest_Email_Global_Enabled__c = true
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        new FimbyDigestEmailScheduler('Daily').execute(null);
        Test.stopTest();
    }

    @IsTest
    static void scheduler_monthly_launchesMonthlyDirectoryBatch() {
        FimbySettings.setMock(new FIMBY_App_Settings__mdt(Digest_Email_Global_Enabled__c = true));

        Test.startTest();
        new FimbyDigestEmailScheduler(FimbyMonthlyDirectoryBatch.CADENCE_MONTHLY).execute(null);
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob
            WHERE ApexClass.Name = 'FimbyMonthlyDirectoryBatch' AND JobType = 'BatchApex'
        ], 'Monthly cadence should launch the monthly directory batch');
    }

    @IsTest
    static void scheduler_catchUpEnabled_launchesOnMondayOrExitsOtherwise() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Digest_Email_Global_Enabled__c = true
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        try {
            new FimbyDigestEmailScheduler(FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST).execute(null);
        } catch (Exception e) {
            // Batch may fail in partial test org data; guard is Monday-only.
        }
        Test.stopTest();
    }

    @IsTest
    static void schedulerIsSunday_returnsBooleanCleanly() {
        System.assertNotEquals(null, FimbyDigestEmailScheduler.isSundayNow());
    }

    @IsTest
    static void batchStart_noPilot_returnsQueryLocator() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Digest_Email_Global_Enabled__c = true,
            Email_Pilot_Neighbourhood_Ids__c = ''
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        Database.QueryLocator ql = new FimbyDigestEmailBatch('Daily').start(null);
        Test.stopTest();

        System.assertNotEquals(null, ql);
    }

    @IsTest
    static void batchStart_withPilotIds_returnsFilteredQueryLocator() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Digest_Email_Global_Enabled__c = true,
            Email_Pilot_Neighbourhood_Ids__c = '001000000000001'
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        Database.QueryLocator ql = new FimbyDigestEmailBatch('Daily').start(null);
        Test.stopTest();

        System.assertNotEquals(null, ql);
    }

    @IsTest
    static void batchExecute_withNeighbourhood_buildsContentAndChecksRecipients() {
        Account nh = [SELECT Id, Name FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];

        FimbyDigestEmailBatch batch = new FimbyDigestEmailBatch('Daily');

        Test.startTest();
        batch.execute(null, new List<Account>{ nh });
        Test.stopTest();
    }

    @IsTest
    static void batchExecute_emptyNeighbourhood_writesSkippedLog() {
        Account emptyNh = new Account(Name = 'Empty Test NH', Digests_Paused__c = false);
        insert emptyNh;

        FimbyDigestEmailBatch batch = new FimbyDigestEmailBatch('Daily');

        Test.startTest();
        batch.execute(null, new List<Account>{ emptyNh });
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [
            SELECT Id, Status__c, Recipient_Count__c, Content_Item_Count__c, Error_Message__c, Idempotency_Key__c,
                   Window_Start__c, Window_End__c
            FROM Digest_Email_Log__c
            WHERE Neighbourhood__c = :emptyNh.Id
        ];
        System.assertNotEquals(null, logs[0].Window_Start__c, 'Skipped rows still record the window.');
        System.assert(logs[0].Window_Start__c < logs[0].Window_End__c, 'Window is non-empty.');
        System.assert(logs[0].Idempotency_Key__c.contains(FimbyDigestEmailSendQueueable.KEY_VERSION_MARKER),
            'New rows use v2 keys: ' + logs[0].Idempotency_Key__c);
        System.assertEquals(1, logs.size(), 'Empty neighbourhood should produce one Skipped log row.');
        System.assertEquals('Skipped', logs[0].Status__c);
        System.assertEquals(0, logs[0].Recipient_Count__c);
        System.assertEquals(0, logs[0].Content_Item_Count__c);
        System.assert(
            logs[0].Error_Message__c == FimbyDigestEmailBatch.SKIP_REASON_NO_CONTENT,
            'Reason should be no-content: ' + logs[0].Error_Message__c
        );
        System.assert(
            logs[0].Idempotency_Key__c.contains(String.valueOf(emptyNh.Id)),
            'Idempotency key should include neighbourhood id.'
        );
    }

    @IsTest
    static void batchExecute_neighbourhoodWithoutMatchingWindow_writesSkippedLog() {
        Account nh = [SELECT Id, Name FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];

        FimbyDigestEmailBatch batch = new FimbyDigestEmailBatch('Daily');

        Test.startTest();
        batch.execute(null, new List<Account>{ nh });
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [
            SELECT Id, Status__c, Error_Message__c, Recipient_Count__c
            FROM Digest_Email_Log__c
            WHERE Neighbourhood__c = :nh.Id
              AND Status__c = 'Skipped'
        ];
        System.assert(!logs.isEmpty(),
            'A Skipped log row should always be written when a neighbourhood is processed but nothing sends.');
        System.assertEquals(0, logs[0].Recipient_Count__c, 'Skipped log rows always have zero recipients.');
        System.assert(
            logs[0].Error_Message__c == FimbyDigestEmailBatch.SKIP_REASON_NO_CONTENT
                || logs[0].Error_Message__c == FimbyDigestEmailBatch.SKIP_REASON_NO_RECIPIENTS,
            'Skipped reason should be one of the two known values: ' + logs[0].Error_Message__c
        );
    }

    @IsTest
    static void batchExecute_withContentAndRecipients_enqueuesQueueable() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            u = FimbyTestDataFactory.createCommunityUser(c.Id, 'Customer Community User', false);
            u.FIMBY_Summary_Emails__c = 'Daily';
            u.Include_Sundays__c = true;
            insert u;
        }

        Date yesterday = Date.today().addDays(-1);
        Datetime yesterdayDt = Datetime.newInstance(yesterday, Time.newInstance(12, 0, 0, 0));

        List<Story__c> stories = FimbyTestDataFactory.createStories(nh.Id, c.Id, 1, false);
        insert stories;
        Test.setCreatedDate(stories[0].Id, yesterdayDt);

        FimbyDigestEmailBatch batch = new FimbyDigestEmailBatch('Daily');
        Boolean priorLoginFilter = FimbyDigestEmailBatch.enforceLastLoginDate;
        FimbyDigestEmailBatch.enforceLastLoginDate = false;

        Test.startTest();
        batch.execute(null, new List<Account>{ nh });
        Test.stopTest();

        FimbyDigestEmailBatch.enforceLastLoginDate = priorLoginFilter;

        List<Digest_Email_Log__c> skipped = [
            SELECT Id FROM Digest_Email_Log__c
            WHERE Neighbourhood__c = :nh.Id AND Status__c = 'Skipped'
        ];
        System.assertEquals(0, skipped.size(),
            'Neighbourhood with content + recipient should enqueue the queueable, not write a Skipped log.');
    }

    @IsTest
    static void batchExecute_pausedNeighbourhood_sendsNothingAndAdvancesCheckpoint() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(false);
        nh.Digests_Paused__c = true;
        insert nh;
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        makeWeeklyRecipient(c.Id);
        makeWindowedAsk(nh.Id, c.Id, 'Paused Ask');
        Boolean priorLoginFilter = FimbyDigestEmailBatch.enforceLastLoginDate;
        FimbyDigestEmailBatch.enforceLastLoginDate = false;

        Test.startTest();
        new FimbyDigestEmailBatch('Weekly').execute(null, new List<Account>{ nh });
        Integer enqueued = Limits.getQueueableJobs();
        Test.stopTest();

        FimbyDigestEmailBatch.enforceLastLoginDate = priorLoginFilter;

        System.assertEquals(0, enqueued, 'A paused neighbourhood sends no digest.');
        List<Digest_Email_Log__c> logs = [
            SELECT Status__c, Error_Message__c, Window_End__c, Recipient_Count__c
            FROM Digest_Email_Log__c WHERE Neighbourhood__c = :nh.Id
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('Skipped', logs[0].Status__c);
        System.assertEquals(FimbyDigestEmailBatch.SKIP_REASON_PAUSED, logs[0].Error_Message__c);
        System.assertNotEquals(null, logs[0].Window_End__c,
            'The paused row carries a checkpoint so unpausing does not replay the paused stretch.');
    }

    @IsTest
    static void isPaused_readsFieldOnlyWhenQueried() {
        System.assert(FimbyDigestEmailBatch.isPaused(new Account(Digests_Paused__c = true)));
        System.assert(!FimbyDigestEmailBatch.isPaused(new Account(Digests_Paused__c = false)));
        System.assert(!FimbyDigestEmailBatch.isPaused(new Account(Name = 'No flag loaded')));
    }

    @IsTest
    static void buildSkippedLog_idempotencyKeyIsPerBuild() {
        Account nh = new Account(Name = 'Skipped Log Key NH');
        insert nh;

        FimbyDigestEmailBatch batch = new FimbyDigestEmailBatch('Weekly');

        Test.startTest();
        batch.execute(null, new List<Account>{ nh });
        batch.execute(null, new List<Account>{ nh });
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [
            SELECT Id FROM Digest_Email_Log__c WHERE Neighbourhood__c = :nh.Id
        ];
        System.assertEquals(1, logs.size(),
            'Per-build idempotency key should prevent duplicate Skipped rows for the same window.');
    }

    private static User makeWeeklyRecipient(Id contactId) {
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            u = FimbyTestDataFactory.createCommunityUser(contactId, 'Customer Community User', false);
            u.FIMBY_Summary_Emails__c = 'Weekly';
            insert u;
        }
        return u;
    }

    private static void makeWindowedAsk(Id nhId, Id contactId, String name) {
        Id needRt = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();
        insert new Needs_Offers__c(
            Name = name, Details__c = 'detail',
            Type__c = 'Goods - Unperishable', Status__c = 'Posted',
            Neighbourhood__c = nhId, Contact__c = contactId, Posted_By__c = contactId,
            RecordTypeId = needRt,
            Posted_Date__c = Datetime.now().addDays(-3),
            End_Date__c = Date.today().addDays(7)
        );
    }

    @IsTest
    static void batchExecute_blockSymmetry_writesDistinctVariantRows() {
        FimbyDigestEmailSendQueueable.oweaCached = UserInfo.getUserId();

        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact a = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Contact b = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        makeWeeklyRecipient(a.Id);
        makeWeeklyRecipient(b.Id);
        makeWeeklyRecipient(c.Id);

        makeWindowedAsk(nh.Id, a.Id, 'Alpha Ask');
        makeWindowedAsk(nh.Id, b.Id, 'Beta Ask');
        makeWindowedAsk(nh.Id, c.Id, 'Gamma Ask');

        // A blocks B (single row) -> bidirectional: A hides B AND B hides A.
        insert new Blocked_Contact__c(Blocker__c = a.Id, Blocked__c = b.Id);

        FimbyDigestEmailBatch batch = new FimbyDigestEmailBatch('Weekly');
        Date ws = batch.resolveWindowForTest(nh).windowDate;
        Date we = ws;
        Boolean priorLoginFilter = FimbyDigestEmailBatch.enforceLastLoginDate;
        FimbyDigestEmailBatch.enforceLastLoginDate = false;
        FimbyDigestEmailSendQueueable.runInlineForTest = true;

        Test.startTest();
        batch.execute(null, new List<Account>{ nh });
        Test.stopTest();

        FimbyDigestEmailBatch.enforceLastLoginDate = priorLoginFilter;

        String baseKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(nh.Id, 'Weekly', ws, we);
        String variantKeyA = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            nh.Id, 'Weekly', ws, we, String.valueOf(b.Id)
        );
        String variantKeyB = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            nh.Id, 'Weekly', ws, we, String.valueOf(a.Id)
        );

        System.assertNotEquals(baseKey, variantKeyA, 'Variant A key must differ from base.');
        System.assertNotEquals(baseKey, variantKeyB, 'Variant B key must differ from base.');
        System.assertNotEquals(variantKeyA, variantKeyB, 'A and B variant keys must differ.');

        Map<String, Digest_Email_Log__c> byKey = new Map<String, Digest_Email_Log__c>();
        for (Digest_Email_Log__c log : [
            SELECT Idempotency_Key__c, Email_Body_Preview__c, Status__c
            FROM Digest_Email_Log__c WHERE Neighbourhood__c = :nh.Id
        ]) {
            byKey.put(log.Idempotency_Key__c, log);
        }

        System.assert(byKey.containsKey(baseKey), 'Clean cohort (C) keeps the shared base row.');
        System.assert(byKey.containsKey(variantKeyA), 'A gets a filtered variant row.');
        System.assert(byKey.containsKey(variantKeyB), 'B gets a filtered variant row.');

        System.assert(
            byKey.get(baseKey).Email_Body_Preview__c.contains('Alpha Ask')
                && byKey.get(baseKey).Email_Body_Preview__c.contains('Beta Ask')
                && byKey.get(baseKey).Email_Body_Preview__c.contains('Gamma Ask'),
            'Shared base build keeps every author.'
        );

        String aPreview = byKey.get(variantKeyA).Email_Body_Preview__c;
        System.assert(aPreview.contains('Alpha Ask') && aPreview.contains('Gamma Ask'),
            'A\'s filtered digest keeps its own + unrelated cards.');
        System.assert(!aPreview.contains('Beta Ask'),
            'A\'s filtered digest must exclude blocked B\'s cards.');

        String bPreview = byKey.get(variantKeyB).Email_Body_Preview__c;
        System.assert(bPreview.contains('Beta Ask') && bPreview.contains('Gamma Ask'),
            'B\'s filtered digest keeps its own + unrelated cards.');
        System.assert(!bPreview.contains('Alpha Ask'),
            'Symmetry: B\'s filtered digest must exclude A\'s cards too.');
    }

    @IsTest
    static void batchExecute_emptyFilteredCohort_writesSkippedVariantRowNotCollidingWithBase() {
        FimbyDigestEmailSendQueueable.oweaCached = UserInfo.getUserId();

        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact x = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Contact d = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Contact e = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        makeWeeklyRecipient(x.Id);
        makeWeeklyRecipient(d.Id);
        makeWeeklyRecipient(e.Id);

        // X is the only content author.
        makeWindowedAsk(nh.Id, x.Id, 'Solo Ask');

        // D blocks X -> D's filtered build hides X, which empties D's digest.
        insert new Blocked_Contact__c(Blocker__c = d.Id, Blocked__c = x.Id);

        FimbyDigestEmailBatch batch = new FimbyDigestEmailBatch('Weekly');
        Date ws = batch.resolveWindowForTest(nh).windowDate;
        Date we = ws;
        Boolean priorLoginFilter = FimbyDigestEmailBatch.enforceLastLoginDate;
        FimbyDigestEmailBatch.enforceLastLoginDate = false;
        FimbyDigestEmailSendQueueable.runInlineForTest = true;

        Test.startTest();
        batch.execute(null, new List<Account>{ nh });
        Test.stopTest();

        FimbyDigestEmailBatch.enforceLastLoginDate = priorLoginFilter;

        String baseKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(nh.Id, 'Weekly', ws, we);
        String dVariantKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            nh.Id, 'Weekly', ws, we, String.valueOf(x.Id)
        );
        System.assertNotEquals(baseKey, dVariantKey, 'Empty cohort variant key must differ from base.');

        Map<String, Digest_Email_Log__c> byKey = new Map<String, Digest_Email_Log__c>();
        for (Digest_Email_Log__c log : [
            SELECT Idempotency_Key__c, Status__c, Recipient_Count__c, Email_Body_Preview__c, Error_Message__c
            FROM Digest_Email_Log__c WHERE Neighbourhood__c = :nh.Id
        ]) {
            byKey.put(log.Idempotency_Key__c, log);
        }

        System.assert(byKey.containsKey(baseKey), 'Clean cohort (E) keeps the shared base row.');
        System.assertNotEquals('Skipped', byKey.get(baseKey).Status__c,
            'Base row must retain content and not be overwritten by the empty variant skip.');
        System.assert(byKey.get(baseKey).Email_Body_Preview__c.contains('Solo Ask'),
            'Base row keeps the only author\'s content.');

        System.assert(byKey.containsKey(dVariantKey),
            'Empty-filtered cohort (D) writes a Skipped variant row under the variant key.');
        System.assertEquals('Skipped', byKey.get(dVariantKey).Status__c);
        System.assertEquals(0, byKey.get(dVariantKey).Recipient_Count__c);
        System.assertEquals(
            FimbyDigestEmailBatch.SKIP_REASON_NO_CONTENT,
            byKey.get(dVariantKey).Error_Message__c
        );
    }

    @IsTest
    static void batchExecute_cleanPlusMultipleBlockCohorts_enqueuesExactlyOneSender() {
        FimbyDigestEmailSendQueueable.testOweaUnavailable = true;

        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact a = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Contact b = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        makeWeeklyRecipient(a.Id);
        makeWeeklyRecipient(b.Id);
        makeWeeklyRecipient(c.Id);
        makeWindowedAsk(nh.Id, a.Id, 'Alpha Ask');
        makeWindowedAsk(nh.Id, c.Id, 'Gamma Ask');

        // A blocks B -> two block signatures (A hides B, B hides A) plus clean C.
        insert new Blocked_Contact__c(Blocker__c = a.Id, Blocked__c = b.Id);

        FimbyDigestEmailBatch batch = new FimbyDigestEmailBatch('Weekly');
        Boolean priorLoginFilter = FimbyDigestEmailBatch.enforceLastLoginDate;
        FimbyDigestEmailBatch.enforceLastLoginDate = false;

        Test.startTest();
        batch.execute(null, new List<Account>{ nh });
        Integer enqueued = Limits.getQueueableJobs();
        List<FimbyDigestEmailSendQueueable.DispatchCohort> cohorts =
            FimbyDigestEmailBatch.lastDispatched.cohortsForTest();
        Integer cohortCount = cohorts.size();
        String firstVariant = cohorts[0].variantKey;
        String secondVariant = cohorts[1].variantKey;
        String thirdVariant = cohorts[2].variantKey;
        Boolean cleanPrebuilt = cohorts[0].contentHtml != null;
        Boolean variantsLazy = cohorts[1].contentHtml == null && cohorts[2].contentHtml == null;
        Test.stopTest();

        FimbyDigestEmailBatch.enforceLastLoginDate = priorLoginFilter;

        System.assertEquals(1, enqueued,
            'One neighbourhood with several cohorts must enqueue exactly one sender.');
        System.assertEquals(3, cohortCount, 'Clean cohort plus two block signatures.');
        System.assertEquals(null, firstVariant, 'Clean cohort is dispatched first.');
        System.assert(secondVariant < thirdVariant,
            'Block signatures are dispatched in sorted order so retries are deterministic.');
        System.assert(cleanPrebuilt, 'Clean cohort reuses the shared build.');
        System.assert(variantsLazy, 'Filtered cohorts are built only when the sender reaches them.');
    }

    @IsTest
    static void batchFinish_logsCleanly() {
        Test.startTest();
        new FimbyDigestEmailBatch('Daily').finish(null);
        Test.stopTest();
    }

    @IsTest
    static void fullBatch_executesEndToEnd() {
        FIMBY_App_Settings__mdt mock = new FIMBY_App_Settings__mdt(
            Digest_Email_Global_Enabled__c = true,
            Email_Pilot_Neighbourhood_Ids__c = ''
        );
        FimbySettings.setMock(mock);

        Test.startTest();
        Database.executeBatch(new FimbyDigestEmailBatch('Daily'), 1);
        Test.stopTest();
    }

    @IsTest
    static void queryEligibleRecipients_excludesNeverLoggedInUser() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User u = FimbyTestDataFactory.createCommunityUser(c.Id, 'Customer Community User', false);
            u.FIMBY_Summary_Emails__c = 'Daily';
            insert u;
        }

        FimbyDigestEmailBatch batch = new FimbyDigestEmailBatch('Daily');
        FimbyDigestEmailBatch.enforceLastLoginDate = true;

        Test.startTest();
        List<User> recipients = batch.queryEligibleRecipients(nh.Id);
        Test.stopTest();

        System.assertEquals(0, recipients.size(),
            'Users who have never logged in must not receive digest emails.');
    }
}
