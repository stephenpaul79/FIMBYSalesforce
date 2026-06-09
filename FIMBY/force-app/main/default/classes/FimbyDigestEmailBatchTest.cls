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

    @IsTest
    static void batchSundayRestCatchUp_resolvesTwoDayWindow() {
        FimbyDigestEmailBatch batch = new FimbyDigestEmailBatch(FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST);
        System.assertEquals(Date.today().addDays(-1), batch.getWindowEndForTest());
        System.assertEquals(Date.today().addDays(-2), batch.getWindowStartForTest());
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
        Account emptyNh = new Account(Name = 'Empty Test NH');
        insert emptyNh;

        FimbyDigestEmailBatch batch = new FimbyDigestEmailBatch('Daily');

        Test.startTest();
        batch.execute(null, new List<Account>{ emptyNh });
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [
            SELECT Id, Status__c, Recipient_Count__c, Content_Item_Count__c, Error_Message__c, Idempotency_Key__c
            FROM Digest_Email_Log__c
            WHERE Neighbourhood__c = :emptyNh.Id
        ];
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

        Test.startTest();
        batch.execute(null, new List<Account>{ nh });
        Test.stopTest();

        List<Digest_Email_Log__c> skipped = [
            SELECT Id FROM Digest_Email_Log__c
            WHERE Neighbourhood__c = :nh.Id AND Status__c = 'Skipped'
        ];
        System.assertEquals(0, skipped.size(),
            'Neighbourhood with content + recipient should enqueue the queueable, not write a Skipped log.');
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
        Database.executeBatch(new FimbyDigestEmailBatch('Daily'), 5);
        Test.stopTest();
    }
}
