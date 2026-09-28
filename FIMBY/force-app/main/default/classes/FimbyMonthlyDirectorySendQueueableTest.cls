@IsTest
private class FimbyMonthlyDirectorySendQueueableTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 3, true);
        insert new List<Library_Item__c>{
            new Library_Item__c(Name = 'Cordless Drill', Category__c = 'Tools', Status__c = 'Available',
                Neighbourhood__c = nh.Id, Owner_Contact__c = contacts[0].Id, Listed_By__c = contacts[0].Id),
            new Library_Item__c(Name = 'Stand Mixer', Category__c = 'Kitchen Supplies', Status__c = 'Available',
                Neighbourhood__c = nh.Id, Owner_Contact__c = contacts[2].Id, Listed_By__c = contacts[2].Id)
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<User> users = new List<User>();
            for (Integer i = 0; i < 2; i++) {
                users.add(FimbyTestDataFactory.createCommunityUser(contacts[i].Id, 'Customer Community User', false));
            }
            insert users;
        }
    }

    private static Account nh() {
        return [SELECT Id, Name FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
    }

    private static List<User> recipients() {
        return [
            SELECT Id, ContactId FROM User WHERE Contact.AccountId = :nh().Id
            ORDER BY Contact.CreatedDate ASC, ContactId ASC
        ];
    }

    private static List<Id> repeatedRecipient(Integer count) {
        Id userId = recipients()[0].Id;
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < count; i++) {
            ids.add(userId);
        }
        return ids;
    }

    private static Digest_Email_Log__c monthlyLog() {
        return [
            SELECT Status__c, Cadence__c, Window_Date__c, Email_Body_Preview__c, Failed_Recipients__c
            FROM Digest_Email_Log__c WHERE Cadence__c = 'Monthly' LIMIT 1
        ];
    }

    @IsTest
    static void processStep_rendersSendsAndLogsMonthlyRow() {
        FimbyMonthlyDirectorySendQueueable.oweaCached = UserInfo.getUserId();
        Account a = nh();
        List<Id> ids = new List<Id>();
        for (User u : recipients()) {
            ids.add(u.Id);
        }
        Date monthStart = Date.today().toStartOfMonth();

        Test.startTest();
        FimbyMonthlyDirectorySendQueueable next =
            new FimbyMonthlyDirectorySendQueueable(a.Id, a.Name, monthStart, ids).processStep();
        Test.stopTest();

        System.assertEquals(null, next, 'Two recipients fit in one chunk');
        Digest_Email_Log__c log = monthlyLog();
        System.assertEquals(monthStart, log.Window_Date__c);
        System.assert(log.Email_Body_Preview__c.contains('Cordless Drill'),
            'Preview stores the full representative email');
        System.assert(log.Email_Body_Preview__c.contains('your monthly library update'));
    }

    @IsTest
    static void renderForUsers_blocksShapeEachRecipientsEmail() {
        List<User> users = recipients();
        Contact mixerOwner = [
            SELECT Id FROM Contact WHERE AccountId = :nh().Id ORDER BY CreatedDate ASC, Id ASC
        ][2];
        insert new Blocked_Contact__c(Blocker__c = mixerOwner.Id, Blocked__c = users[0].ContactId);
        List<User> withNames = [SELECT Id, FirstName, LastName, ContactId FROM User WHERE Id IN :users];

        Test.startTest();
        FimbyMonthlyDirectoryEmailBuilder.Directory directory =
            FimbyMonthlyDirectoryEmailBuilder.loadDirectory(nh().Id);
        Map<Id, FimbyMonthlyDirectorySendQueueable.RenderedEmail> rendered =
            FimbyMonthlyDirectorySendQueueable.renderForUsers(directory, nh().Name, withNames);
        Test.stopTest();

        String blockedView = rendered.get(users[0].Id).html;
        String cleanView = rendered.get(users[1].Id).html;
        System.assert(!blockedView.contains('Stand Mixer'),
            'Being blocked by an owner hides their items (bidirectional)');
        System.assert(cleanView.contains('Stand Mixer'));
        System.assert(rendered.get(users[0].Id).totalBytes <= FimbyMonthlyDirectorySendQueueable.EMAIL_BYTE_CAP);
        System.assert(cleanView.contains('Email preferences'), 'Footer preferences link is kept');
        System.assert(!cleanView.contains('BellActive.png'), 'Header action icons are hidden');
    }

    @IsTest
    static void previewForRecipient_returnsWrappedEmailWithinCap() {
        User u = recipients()[0];

        Test.startTest();
        FimbyMonthlyDirectorySendQueueable.RenderedEmail preview =
            FimbyMonthlyDirectorySendQueueable.previewForRecipient(nh().Id, nh().Name, u.Id);
        Test.stopTest();

        System.assert(preview.html.contains('Items To Borrow'));
        System.assert(preview.totalBytes <= FimbyMonthlyDirectorySendQueueable.EMAIL_BYTE_CAP);
        System.assertEquals(2, preview.result.itemsShown);
        System.assertEquals(0, [SELECT COUNT() FROM Digest_Email_Log__c], 'Preview writes nothing');
    }

    @IsTest
    static void processStep_moreThanOneChunk_staysPartialUntilFinal() {
        FimbyMonthlyDirectorySendQueueable.testOweaUnavailable = true;
        Account a = nh();
        List<Id> ids = repeatedRecipient(51);

        Test.startTest();
        FimbyMonthlyDirectorySendQueueable second = new FimbyMonthlyDirectorySendQueueable(
            a.Id, a.Name, Date.today().toStartOfMonth(), ids
        ).processStep();
        System.assertNotEquals(null, second, '51 recipients need a second chunk');
        Integer remaining = second.userIdsForTest().size();
        String midStatus = monthlyLog().Status__c;
        FimbyMonthlyDirectorySendQueueable third = second.processStep();
        Test.stopTest();

        System.assertEquals(1, remaining);
        System.assertEquals('Partial', midStatus, 'Mid-run row is never Sent');
        System.assertEquals(null, third);
        System.assertEquals('Failed', monthlyLog().Status__c);
    }

    @IsTest
    static void execute_withRemainingRecipients_enqueuesOneSuccessor() {
        FimbyMonthlyDirectorySendQueueable.testOweaUnavailable = true;
        Account a = nh();
        List<Id> ids = repeatedRecipient(51);

        Test.startTest();
        new FimbyMonthlyDirectorySendQueueable(a.Id, a.Name, Date.today().toStartOfMonth(), ids).execute(null);
        Integer enqueued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(1, enqueued, 'A step chains at most one successor');
    }

    @IsTest
    static void processStep_alreadySent_stopsChain() {
        Account a = nh();
        Date monthStart = Date.today().toStartOfMonth();
        insert new Digest_Email_Log__c(
            Neighbourhood__c = a.Id, Cadence__c = 'Monthly', Window_Date__c = monthStart,
            Status__c = 'Sent', Recipient_Count__c = 2,
            Idempotency_Key__c = FimbyMonthlyDirectoryBatch.buildIdempotencyKey(a.Id, monthStart)
        );

        Test.startTest();
        FimbyMonthlyDirectorySendQueueable next = new FimbyMonthlyDirectorySendQueueable(
            a.Id, a.Name, monthStart, new List<Id>{ recipients()[0].Id }
        ).processStep();
        Test.stopTest();

        System.assertEquals(null, next);
        System.assertEquals('Sent', monthlyLog().Status__c);
    }

    @IsTest
    static void dispatch_inlineDrainsChain() {
        FimbyMonthlyDirectorySendQueueable.testOweaUnavailable = true;
        FimbyMonthlyDirectorySendQueueable.runInlineForTest = true;
        Account a = nh();
        List<Id> ids = repeatedRecipient(51);

        Test.startTest();
        FimbyMonthlyDirectorySendQueueable.dispatch(
            new FimbyMonthlyDirectorySendQueueable(a.Id, a.Name, Date.today().toStartOfMonth(), ids)
        );
        FimbyMonthlyDirectorySendQueueable.dispatch(null);
        Test.stopTest();

        System.assertEquals('Failed', monthlyLog().Status__c, 'Both chunks ran and the final one resolved');
    }

    @IsTest
    static void computeStatus_onlyFinalChunkResolvesSent() {
        Digest_Email_Log__c ok = new Digest_Email_Log__c(Recipients__c = 'A - 005');
        Digest_Email_Log__c mixed = new Digest_Email_Log__c(Recipients__c = 'A - 005', Failed_Recipients__c = 'B - 005');
        System.assertEquals('Partial', FimbyMonthlyDirectorySendQueueable.computeStatus(ok, false, null));
        System.assertEquals('Sent', FimbyMonthlyDirectorySendQueueable.computeStatus(ok, true, null));
        System.assertEquals('Partial', FimbyMonthlyDirectorySendQueueable.computeStatus(mixed, true, null));
        System.assertEquals('Failed', FimbyMonthlyDirectorySendQueueable.computeStatus(
            new Digest_Email_Log__c(), true, 'OWEA not found'));
    }
}
