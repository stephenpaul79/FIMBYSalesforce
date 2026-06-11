@isTest
private class FimbyRefreshReminderJobTest {

    @isTest
    static void execute_sendsReminderNearExpiry() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact author = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Id needRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Reminder Need',
            Details__c = 'About to expire',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = needRt,
            Contact__c = author.Id,
            Posted_By__c = author.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(1),
            Posted_Date__c = Datetime.now().addDays(-8),
            Refresh_Count__c = 0
        );
        insert post;
        Test.setCreatedDate(post.Id, Datetime.now().addDays(-8));

        FimbyRefreshReminderJob.testMaxRows = 50;

        Test.startTest();
        new FimbyRefreshReminderJob().execute(null);
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Notification__c
             WHERE Contact__c = :author.Id AND Type__c = :FimbyConstants.NOTIF_REFRESH_REMINDER],
            'Author should receive a refresh reminder'
        );
        post = [SELECT Last_Refresh_Reminder_Date__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals(Date.today(), post.Last_Refresh_Reminder_Date__c);
    }

    @isTest
    static void execute_skipsWhenNotYetDue() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact author = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Id needRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Future Reminder Need',
            Details__c = 'Too new',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = needRt,
            Contact__c = author.Id,
            Posted_By__c = author.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(14),
            Refresh_Count__c = 0
        );
        insert post;

        FimbyRefreshReminderJob.testMaxRows = 50;

        Test.startTest();
        new FimbyRefreshReminderJob().execute(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_REFRESH_REMINDER]);
    }

    @isTest
    static void execute_skipsWhenAtRefreshCap() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact author = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Id needRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Capped Need',
            Details__c = 'At cap',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = needRt,
            Contact__c = author.Id,
            Posted_By__c = author.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(1),
            Posted_Date__c = Datetime.now().addDays(-8),
            Refresh_Count__c = FimbySettings.refreshMaxCount()
        );
        insert post;

        FimbyRefreshReminderJob.testMaxRows = 50;

        Test.startTest();
        new FimbyRefreshReminderJob().execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_REFRESH_REMINDER]
        );
    }

    @isTest
    static void execute_skipsAlreadyNudgedThisCycle() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact author = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Id needRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Already Nudged',
            Details__c = 'No repeat',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = needRt,
            Contact__c = author.Id,
            Posted_By__c = author.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(1),
            Posted_Date__c = Datetime.now().addDays(-8),
            Refresh_Count__c = 0,
            Last_Refresh_Reminder_Date__c = Date.today(),
            Last_Refreshed_Date__c = null
        );
        insert post;
        Test.setCreatedDate(post.Id, Datetime.now().addDays(-8));

        FimbyRefreshReminderJob.testMaxRows = 50;

        Test.startTest();
        new FimbyRefreshReminderJob().execute(null);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_REFRESH_REMINDER]
        );
    }

    @isTest
    static void execute_sendsOfferReminderCopy() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact author = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Id offerRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Reminder Offer',
            Details__c = 'Still around?',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = offerRt,
            Contact__c = author.Id,
            Posted_By__c = author.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(1),
            Refresh_Count__c = 0
        );
        insert post;
        Test.setCreatedDate(post.Id, Datetime.now().addDays(-8));

        FimbyRefreshReminderJob.testMaxRows = 50;

        Test.startTest();
        new FimbyRefreshReminderJob().execute(null);
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Body__c FROM Notification__c
            WHERE Contact__c = :author.Id AND Type__c = :FimbyConstants.NOTIF_REFRESH_REMINDER
        ];
        System.assertEquals(1, notifs.size());
        System.assert(notifs[0].Body__c.contains('still available'), notifs[0].Body__c);
    }

    @isTest
    static void reminderHelpers_computeDueAndCycle() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact author = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Id needRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Helper Need',
            Details__c = 'Helper',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = needRt,
            Contact__c = author.Id,
            Posted_By__c = author.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(1),
            Last_Refresh_Reminder_Date__c = Date.today().addDays(-3),
            Last_Refreshed_Date__c = Date.today().addDays(-1)
        );
        insert post;
        Test.setCreatedDate(post.Id, Datetime.now().addDays(-10));
        post = [
            SELECT CreatedDate, End_Date__c, Last_Refresh_Reminder_Date__c, Last_Refreshed_Date__c
            FROM Needs_Offers__c WHERE Id = :post.Id
        ];

        System.assertEquals(true, FimbyRefreshReminderJob.isReminderDue(post, Date.today(), 7, 1));
        System.assertEquals(true, FimbyRefreshReminderJob.isEligibleForReminderCycle(post));

        post.Last_Refresh_Reminder_Date__c = Date.today();
        System.assertEquals(false, FimbyRefreshReminderJob.isEligibleForReminderCycle(post));
    }
}
