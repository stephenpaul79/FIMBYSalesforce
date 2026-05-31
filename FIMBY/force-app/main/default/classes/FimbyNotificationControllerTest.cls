@IsTest
public class FimbyNotificationControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User communityUser = FimbyTestDataFactory.createCommunityUser(contact.Id, 'Customer Community User - Mobile App', true);

        // Create test notifications in system context (MD to Contact)
        List<Notification__c> notifs = new List<Notification__c>();
        notifs.add(new Notification__c(
            Contact__c = contact.Id,
            Type__c = 'Response',
            Title__c = 'Someone responded to your post',
            Body__c = 'I can help with that!',
            Action_URL__c = '/asks-offers/test1',
            Actor_Name__c = 'Sarah Johnson'
        ));
        notifs.add(new Notification__c(
            Contact__c = contact.Id,
            Type__c = 'Comment',
            Title__c = 'New comment on your story',
            Body__c = 'Great story!',
            Action_URL__c = '/story/test2',
            Actor_Name__c = 'Mike Chen'
        ));
        notifs.add(new Notification__c(
            Contact__c = contact.Id,
            Type__c = 'Lending_Request',
            Title__c = 'Someone wants to borrow your item',
            Body__c = 'Can I borrow the drill?',
            Action_URL__c = '/library-item/test3?action=reviewRequest&requestId=fakeReq3',
            Actor_Name__c = 'Alex Kim',
            Read_Date__c = Datetime.now().addDays(-1)
        ));
        insert notifs;
    }

    private static User getTestUser() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        return [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];
    }

    @IsTest
    static void testGetNotifications() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyNotificationController.NotificationResult result = FimbyNotificationController.getNotifications(20, 0, null);

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertEquals(3, result.totalCount, 'Should have 3 total notifications');
            System.assertEquals(3, result.items.size(), 'Should return 3 items');

            Boolean foundUnread = false;
            Boolean foundRead = false;
            for (FimbyNotificationController.NotificationWrapper w : result.items) {
                if (w.isUnread) foundUnread = true;
                if (!w.isUnread) foundRead = true;
            }
            System.assert(foundUnread, 'Should have at least one unread notification');
            System.assert(foundRead, 'Should have at least one read notification');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetNotificationsPagination() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyNotificationController.NotificationResult page1 = FimbyNotificationController.getNotifications(2, 0, null);
            System.assertEquals(2, page1.items.size(), 'Page 1 should return 2 items');
            System.assertEquals(3, page1.totalCount, 'Total count should still be 3');

            FimbyNotificationController.NotificationResult page2 = FimbyNotificationController.getNotifications(2, 2, null);
            System.assertEquals(1, page2.items.size(), 'Page 2 should return 1 item');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetUnreadCount() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Integer count = FimbyNotificationController.getUnreadCount();
            System.assertEquals(2, count, 'Should have 2 unread notifications');
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkAsRead() {
        User testUser = getTestUser();
        Notification__c unreadNotif = [SELECT Id FROM Notification__c WHERE Read_Date__c = null LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            FimbyNotificationController.markAsRead(unreadNotif.Id);
        }
        Test.stopTest();

        Notification__c updated = [SELECT Id, Read_Date__c FROM Notification__c WHERE Id = :unreadNotif.Id];
        System.assertNotEquals(null, updated.Read_Date__c, 'Read_Date__c should be set after marking as read');
    }

    @IsTest
    static void testMarkAsReadAlreadyRead() {
        User testUser = getTestUser();
        Notification__c readNotif = [SELECT Id, Read_Date__c FROM Notification__c WHERE Read_Date__c != null LIMIT 1];
        Datetime originalReadDate = readNotif.Read_Date__c;

        Test.startTest();
        System.runAs(testUser) {
            FimbyNotificationController.markAsRead(readNotif.Id);
        }
        Test.stopTest();

        Notification__c updated = [SELECT Id, Read_Date__c FROM Notification__c WHERE Id = :readNotif.Id];
        System.assertEquals(originalReadDate, updated.Read_Date__c, 'Read_Date__c should not change if already read');
    }

    @IsTest
    static void testMarkAllAsRead() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Integer beforeCount = FimbyNotificationController.getUnreadCount();
            System.assertEquals(2, beforeCount, 'Should start with 2 unread');

            FimbyNotificationController.markAllAsRead();

            Integer afterCount = FimbyNotificationController.getUnreadCount();
            System.assertEquals(0, afterCount, 'Should have 0 unread after marking all');
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkAsReadNullId() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyNotificationController.markAsRead(null);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetNotificationsWithTypeFilter() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyNotificationController.NotificationResult responses =
                FimbyNotificationController.getNotifications(20, 0, 'Responses');
            System.assertEquals(1, responses.totalCount, 'Should have 1 Response notification');
            System.assertEquals(1, responses.items.size(), 'Should return 1 item');
            System.assertEquals('Response', responses.items[0].type, 'Item should be Response type');

            FimbyNotificationController.NotificationResult library =
                FimbyNotificationController.getNotifications(20, 0, 'Library');
            System.assertEquals(1, library.totalCount, 'Should have 1 Library notification');
            System.assertEquals('Lending_Request', library.items[0].type, 'Item should be Lending_Request type');

            FimbyNotificationController.NotificationResult all =
                FimbyNotificationController.getNotifications(20, 0, 'All');
            System.assertEquals(3, all.totalCount, 'All filter should return all notifications');
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkAsUnread() {
        User testUser = getTestUser();
        Notification__c readNotif = [SELECT Id, Read_Date__c FROM Notification__c WHERE Read_Date__c != null LIMIT 1];
        System.assertNotEquals(null, readNotif.Read_Date__c, 'Notification should start as read');

        Test.startTest();
        System.runAs(testUser) {
            FimbyNotificationController.markAsUnread(readNotif.Id);
        }
        Test.stopTest();

        Notification__c updated = [SELECT Id, Read_Date__c FROM Notification__c WHERE Id = :readNotif.Id];
        System.assertEquals(null, updated.Read_Date__c, 'Read_Date__c should be null after marking as unread');
    }

    @IsTest
    static void testDeleteNotification() {
        User testUser = getTestUser();
        Notification__c toDelete = [SELECT Id FROM Notification__c WHERE Type__c = 'Comment' LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            FimbyNotificationController.deleteNotification(toDelete.Id);
        }
        Test.stopTest();

        List<Notification__c> remaining = [SELECT Id FROM Notification__c WHERE Id = :toDelete.Id];
        System.assertEquals(0, remaining.size(), 'Notification should be deleted');
    }

    @IsTest
    static void testDeleteAllNotifications() {
        User testUser = getTestUser();
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            FimbyNotificationController.deleteAllNotifications();
        }
        Test.stopTest();

        Integer remaining = [SELECT COUNT() FROM Notification__c WHERE Contact__c = :testContact.Id];
        System.assertEquals(0, remaining, 'All notifications should be deleted');
    }

    @IsTest
    static void testGetNotificationsHidesBlockedActors() {
        User testUser = getTestUser();
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        Contact blockedActor = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, true);

        Needs_Offers__c post = FimbyTestDataFactory.createAskOfferItems(
            testNeighbourhood.Id, viewer.Id, 1, true
        )[0];
        post.Contact__c = blockedActor.Id;
        post.Posted_By__c = blockedActor.Id;
        update post;

        insert new Blocked_Contact__c(
            Blocker__c = viewer.Id,
            Blocked__c = blockedActor.Id,
            Reason__c = 'QA block filter test'
        );

        insert new Notification__c(
            Contact__c = viewer.Id,
            Type__c = 'Response',
            Title__c = 'Blocked actor responded',
            Body__c = 'Should be hidden',
            Related_Record_Id__c = String.valueOf(post.Id),
            Related_Record_Type__c = 'Needs_Offers__c',
            Action_URL__c = '/asks-offers/test-blocked',
            Actor_Name__c = 'Blocked Person'
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbyNotificationController.NotificationResult result =
                FimbyNotificationController.getNotifications(20, 0, null);
            System.assertEquals(3, result.totalCount,
                'Notification from blocked actor should be hidden from list');

            Integer unreadCount = FimbyNotificationController.getUnreadCount();
            System.assertEquals(2, unreadCount,
                'Unread count should exclude notifications from blocked actors');
        }
        Test.stopTest();
    }
}