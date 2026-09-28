@IsTest
private class FimbyMonthlyDirectoryBatchTest {

    private static User makeRecipient(Id contactId) {
        User u;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            u = FimbyTestDataFactory.createCommunityUser(contactId, 'Customer Community User', false);
            u.Email_Alerts_Enabled__c = true;
            u.Email_Alert_Library__c = true;
            insert u;
        }
        return u;
    }

    private static Digest_Email_Log__c logFor(Id nhId) {
        return [
            SELECT Status__c, Cadence__c, Window_Date__c, Error_Message__c, Content_Item_Count__c
            FROM Digest_Email_Log__c WHERE Neighbourhood__c = :nhId LIMIT 1
        ];
    }

    @IsTest
    static void constructor_usesFirstDayOfMonthAndMonthlyKey() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        FimbyMonthlyDirectoryBatch batch = new FimbyMonthlyDirectoryBatch();
        Date monthStart = Date.today().toStartOfMonth();
        System.assertEquals(monthStart, batch.getWindowDateForTest());
        System.assertEquals(String.valueOf(nh.Id) + '_Monthly_' + String.valueOf(monthStart),
            FimbyMonthlyDirectoryBatch.buildIdempotencyKey(nh.Id, monthStart));
    }

    @IsTest
    static void execute_noContent_writesSkippedMonthlyLog() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);

        Test.startTest();
        new FimbyMonthlyDirectoryBatch().execute(null, new List<Account>{ nh });
        Test.stopTest();

        Digest_Email_Log__c log = logFor(nh.Id);
        System.assertEquals('Skipped', log.Status__c);
        System.assertEquals('Monthly', log.Cadence__c);
        System.assertEquals(Date.today().toStartOfMonth(), log.Window_Date__c);
        System.assertEquals(FimbyMonthlyDirectoryBatch.SKIP_REASON_NO_CONTENT, log.Error_Message__c);
    }

    @IsTest
    static void execute_contentWithoutRecipients_writesSkippedLog() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        FimbyTestDataFactory.createLibraryItems(nh.Id, c.Id, 2, true);

        Test.startTest();
        new FimbyMonthlyDirectoryBatch().execute(null, new List<Account>{ nh });
        Test.stopTest();

        Digest_Email_Log__c log = logFor(nh.Id);
        System.assertEquals('Skipped', log.Status__c);
        System.assertEquals(FimbyMonthlyDirectoryBatch.SKIP_REASON_NO_RECIPIENTS, log.Error_Message__c);
        System.assertEquals(2, log.Content_Item_Count__c);
    }

    @IsTest
    static void execute_contentAndRecipient_enqueuesExactlyOneSender() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Contact c2 = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        FimbyTestDataFactory.createLibraryItems(nh.Id, c.Id, 2, true);
        makeRecipient(c.Id);
        makeRecipient(c2.Id);
        FimbyMonthlyDirectoryBatch.enforceLastLoginDate = false;
        FimbyMonthlyDirectorySendQueueable.testOweaUnavailable = true;

        Test.startTest();
        new FimbyMonthlyDirectoryBatch().execute(null, new List<Account>{ nh });
        Integer enqueued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(1, enqueued, 'One neighbourhood enqueues exactly one sender');
        System.assertEquals(2, FimbyMonthlyDirectoryBatch.lastDispatched.userIdsForTest().size());
        System.assertEquals(0, [
            SELECT COUNT() FROM Digest_Email_Log__c WHERE Neighbourhood__c = :nh.Id AND Status__c = 'Skipped'
        ]);
    }

    @IsTest
    static void queryEligibleRecipients_respectsLibraryEmailToggle() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact optedIn = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Contact optedOut = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        User inUser = makeRecipient(optedIn.Id);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User outUser = FimbyTestDataFactory.createCommunityUser(optedOut.Id, 'Customer Community User', false);
            outUser.Email_Alert_Library__c = false;
            insert outUser;
        }
        FimbyMonthlyDirectoryBatch.enforceLastLoginDate = false;

        Test.startTest();
        List<User> recipients = new FimbyMonthlyDirectoryBatch().queryEligibleRecipients(nh.Id);
        FimbyMonthlyDirectoryBatch.enforceLastLoginDate = true;
        List<User> loggedInOnly = new FimbyMonthlyDirectoryBatch().queryEligibleRecipients(nh.Id);
        Test.stopTest();

        System.assertEquals(1, recipients.size());
        System.assertEquals(inUser.Id, recipients[0].Id);
        System.assertEquals(0, loggedInOnly.size(), 'Users who never logged in are skipped');
    }

    @IsTest
    static void execute_alreadySentThisMonth_doesNotDispatch() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        FimbyTestDataFactory.createLibraryItems(nh.Id, c.Id, 1, true);
        makeRecipient(c.Id);
        FimbyMonthlyDirectoryBatch.enforceLastLoginDate = false;
        Date monthStart = Date.today().toStartOfMonth();
        insert new Digest_Email_Log__c(
            Neighbourhood__c = nh.Id, Cadence__c = 'Monthly', Window_Date__c = monthStart,
            Status__c = 'Sent', Recipient_Count__c = 1,
            Idempotency_Key__c = FimbyMonthlyDirectoryBatch.buildIdempotencyKey(nh.Id, monthStart)
        );

        Test.startTest();
        new FimbyMonthlyDirectoryBatch().execute(null, new List<Account>{ nh });
        Integer enqueued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(0, enqueued, 'A Sent month never resends');
        System.assertEquals(null, FimbyMonthlyDirectoryBatch.lastDispatched);
    }

    @IsTest
    static void start_withAndWithoutPilot_returnsLocator() {
        FimbySettings.setMock(new FIMBY_App_Settings__mdt(Email_Pilot_Neighbourhood_Ids__c = ''));
        System.assertNotEquals(null, new FimbyMonthlyDirectoryBatch().start(null));
        FimbySettings.setMock(new FIMBY_App_Settings__mdt(Email_Pilot_Neighbourhood_Ids__c = '001000000000001'));
        System.assertNotEquals(null, new FimbyMonthlyDirectoryBatch().start(null));
    }

    @IsTest
    static void fullBatch_runsAndFinishes() {
        FimbySettings.setMock(new FIMBY_App_Settings__mdt(Email_Pilot_Neighbourhood_Ids__c = ''));
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);

        Test.startTest();
        Database.executeBatch(new FimbyMonthlyDirectoryBatch(), 1);
        Test.stopTest();

        System.assertEquals('Skipped', logFor(nh.Id).Status__c);
    }
}
