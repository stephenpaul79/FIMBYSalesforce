@IsTest
public class FimbyNotificationCleanupJobTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        List<Notification__c> notifs = new List<Notification__c>();

        // Old read notification (31 days ago) — should be deleted
        notifs.add(new Notification__c(
            Contact__c = contact.Id,
            Type__c = 'Response',
            Title__c = 'Old read notification',
            Read_Date__c = Datetime.now().addDays(-31)
        ));

        // Recently read notification (5 days ago) — should be preserved
        notifs.add(new Notification__c(
            Contact__c = contact.Id,
            Type__c = 'Comment',
            Title__c = 'Recent read notification',
            Read_Date__c = Datetime.now().addDays(-5)
        ));

        // Unread notification — should be preserved
        notifs.add(new Notification__c(
            Contact__c = contact.Id,
            Type__c = 'Lending_Request',
            Title__c = 'Unread notification'
        ));

        // Recent Pending notification (1 day old) — should be preserved
        notifs.add(new Notification__c(
            Contact__c = contact.Id,
            Type__c = 'Response',
            Title__c = 'Recent pending notification',
            Push_Status__c = 'Pending'
        ));

        insert notifs;
    }

    @IsTest
    static void testCleanupDeletesOldReadNotifications() {
        List<Notification__c> allBefore = [SELECT Id FROM Notification__c];
        System.assertEquals(4, allBefore.size(), 'Should start with 4 notifications');

        Test.startTest();
        FimbyNotificationCleanupJob job = new FimbyNotificationCleanupJob();
        job.execute(null);
        Test.stopTest();

        List<Notification__c> allAfter = [SELECT Id, Title__c, Read_Date__c, Push_Status__c FROM Notification__c ORDER BY Title__c];
        System.assertEquals(3, allAfter.size(), 'Should have 3 remaining notifications after cleanup');

        Set<String> remainingTitles = new Set<String>();
        for (Notification__c n : allAfter) {
            remainingTitles.add(n.Title__c);
        }
        System.assert(!remainingTitles.contains('Old read notification'), 'Old read notification should have been deleted');
        System.assert(remainingTitles.contains('Recent read notification'), 'Recent read notification should be preserved');
        System.assert(remainingTitles.contains('Unread notification'), 'Unread notification should be preserved');
        System.assert(remainingTitles.contains('Recent pending notification'), 'Recent pending should be preserved');
    }

    @IsTest
    static void testHiddenTypesSurvive30DayReadPurge() {
        Account nb = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nb.Id, true);

        // Read long ago, but a hidden message-style type — must NOT be deleted
        // by the 30-day read-purge (it lives as long as its thread).
        Notification__c hiddenRead = new Notification__c(
            Contact__c = c.Id,
            Type__c = FimbyConstants.NOTIF_RESPONSE_REPLY,
            Title__c = 'Hidden read reply',
            Read_Date__c = Datetime.now().addDays(-45),
            Related_Record_Id__c = String.valueOf(c.Id)
        );
        insert hiddenRead;

        Test.startTest();
        new FimbyNotificationCleanupJob().execute(null);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Notification__c WHERE Id = :hiddenRead.Id],
            'Hidden type must survive the 30-day read-purge');
    }

    @IsTest
    static void testSchedulableExecution() {
        Test.startTest();
        String jobId = System.schedule(
            'Test FIMBY Notification Cleanup',
            '0 0 2 * * ?',
            new FimbyNotificationCleanupJob()
        );
        Test.stopTest();

        CronTrigger ct = [SELECT Id, State FROM CronTrigger WHERE Id = :jobId LIMIT 1];
        System.assertNotEquals(null, ct, 'Scheduled job should exist');
    }
}