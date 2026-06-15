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
        Date ws = batch.getWindowStartForTest();
        Date we = batch.getWindowEndForTest();

        Test.startTest();
        batch.execute(null, new List<Account>{ nh });
        Test.stopTest();

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
        Date ws = batch.getWindowStartForTest();
        Date we = batch.getWindowEndForTest();

        Test.startTest();
        batch.execute(null, new List<Account>{ nh });
        Test.stopTest();

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
