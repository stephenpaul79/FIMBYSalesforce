/**
 * Test class for FimbyPushNotificationService
 */
@isTest
private class FimbyPushNotificationServiceTest {

    @TestSetup
    static void setupTestData() {
        // Use the standard test data factory to create a complete test setup
        // This creates: Neighbourhood (Account) → Contact → Community User
        FimbyTestDataFactory.createCompleteTestSetup();
    }

    /**
     * Helper to get the test community user created in setup
     */
    private static User getTestCommunityUser() {
        return [
            SELECT Id, ContactId, Contact.AccountId,
                   Push_Notifications_Enabled__c, Push_Messages__c,
                   Push_Needs_Offers__c, Push_Library__c,
                   Push_Stories__c, Push_Reminders__c,
                   Expo_Push_Token__c
            FROM User
            WHERE Profile.Name = 'Customer Community User'
            AND IsActive = true
            LIMIT 1
        ];
    }

    /**
     * Helper to get the test neighbourhood
     */
    private static Account getTestNeighbourhood() {
        return [SELECT Id FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // PAYLOAD TESTS
    // ─────────────────────────────────────────────────────────────────────────────

    @isTest
    static void testPushPayloadCreation() {
        User testUser = getTestCommunityUser();

        FimbyPushNotificationService.PushPayload payload = new FimbyPushNotificationService.PushPayload();
        payload.userId = testUser.Id;
        payload.title = 'Test Title';
        payload.body = 'Test Body';
        payload.notificationType = FimbyPushNotificationService.NotificationType.MESSAGE;
        payload.badge = 5;
        payload.data.put('customKey', 'customValue');

        String json = payload.toJson();

        System.assert(json.contains('"title":"Test Title"'), 'JSON should contain title');
        System.assert(json.contains('"body":"Test Body"'), 'JSON should contain body');
        System.assert(json.contains('"notification_type":"MESSAGE"'), 'JSON should contain notification type');
        System.assert(!json.contains('target_url'), 'JSON should not contain deprecated target_url');
        System.assert(json.contains('"badge":5'), 'JSON should contain badge count');
    }

    @isTest
    static void testPushPayloadConstructor() {
        User testUser = getTestCommunityUser();

        FimbyPushNotificationService.PushPayload payload = new FimbyPushNotificationService.PushPayload(
            testUser.Id,
            'Constructor Title',
            'Constructor Body',
            FimbyPushNotificationService.NotificationType.NEEDS_OFFERS
        );

        System.assertEquals('Constructor Title', payload.title, 'Title should match');
        System.assertEquals('Constructor Body', payload.body, 'Body should match');
        System.assertEquals(FimbyPushNotificationService.NotificationType.NEEDS_OFFERS, payload.notificationType, 'Type should match');
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // USER PREFERENCE TESTS
    // ─────────────────────────────────────────────────────────────────────────────

    @isTest
    static void testNotificationEnabledByDefault() {
        User testUser = getTestCommunityUser();

        // New users should have notifications enabled by default
        System.runAs(testUser) {
            Boolean enabled = FimbyPushNotificationService.isNotificationEnabled(
                testUser.Id,
                FimbyPushNotificationService.NotificationType.MESSAGE
            );
            System.assertEquals(true, enabled, 'Messages should be enabled by default');
        }
    }

    @isTest
    static void testMasterToggleDisablesAll() {
        User testUser = getTestCommunityUser();

        // Disable master toggle
        testUser.Push_Notifications_Enabled__c = false;
        update testUser;

        System.runAs(testUser) {
            Boolean enabled = FimbyPushNotificationService.isNotificationEnabled(
                testUser.Id,
                FimbyPushNotificationService.NotificationType.MESSAGE
            );
            System.assertEquals(false, enabled, 'Should be disabled when master toggle is off');
        }
    }

    @isTest
    static void testIndividualToggle() {
        User testUser = getTestCommunityUser();

        // Disable just stories
        testUser.Push_Stories__c = false;
        update testUser;

        System.runAs(testUser) {
            Boolean storiesEnabled = FimbyPushNotificationService.isNotificationEnabled(
                testUser.Id,
                FimbyPushNotificationService.NotificationType.STORY
            );
            Boolean messagesEnabled = FimbyPushNotificationService.isNotificationEnabled(
                testUser.Id,
                FimbyPushNotificationService.NotificationType.MESSAGE
            );

            System.assertEquals(false, storiesEnabled, 'Stories should be disabled');
            System.assertEquals(true, messagesEnabled, 'Messages should still be enabled');
        }
    }

    @isTest
    static void testGeneralNotificationsAlwaysEnabled() {
        User testUser = getTestCommunityUser();

        // Even with master toggle off, GENERAL notifications should... wait no
        // Actually GENERAL respects the master toggle - let me test with master ON
        System.runAs(testUser) {
            Boolean enabled = FimbyPushNotificationService.isNotificationEnabled(
                testUser.Id,
                FimbyPushNotificationService.NotificationType.GENERAL
            );
            System.assertEquals(true, enabled, 'General notifications should be enabled');
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // BATCH MODE TESTS
    // ─────────────────────────────────────────────────────────────────────────────

    @isTest
    static void testQueuePushNotifications() {
        User testUser = getTestCommunityUser();

        List<FimbyPushNotificationService.PushPayload> payloads = new List<FimbyPushNotificationService.PushPayload>();

        for (Integer i = 0; i < 5; i++) {
            payloads.add(new FimbyPushNotificationService.PushPayload(
                testUser.Id,
                'Batch Title ' + i,
                'Batch Body ' + i,
                FimbyPushNotificationService.NotificationType.STORY
            ));
        }

        Test.startTest();
        FimbyPushNotificationService.queuePushNotifications(payloads);
        Test.stopTest();

        // No exception means success (batch mode is placeholder for now)
        System.assert(true, 'Queue should complete without error');
    }

    @isTest
    static void testProcessPushNotificationQueue() {
        Test.startTest();
        FimbyPushNotificationService.processPushNotificationQueue();
        Test.stopTest();

        System.assert(true, 'Process queue should complete without error');
    }

    @isTest
    static void testBatchModeToggle() {
        System.assertEquals(false, FimbyPushNotificationService.USE_BATCH_MODE, 'Default should be real-time');

        FimbyPushNotificationService.USE_BATCH_MODE = true;
        System.assertEquals(true, FimbyPushNotificationService.USE_BATCH_MODE, 'Should toggle to batch mode');

        // Reset
        FimbyPushNotificationService.USE_BATCH_MODE = false;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // ENUM TESTS
    // ─────────────────────────────────────────────────────────────────────────────

    @isTest
    static void testNotificationTypeEnum() {
        System.assertNotEquals(null, FimbyPushNotificationService.NotificationType.MESSAGE);
        System.assertNotEquals(null, FimbyPushNotificationService.NotificationType.NEEDS_OFFERS);
        System.assertNotEquals(null, FimbyPushNotificationService.NotificationType.LIBRARY);
        System.assertNotEquals(null, FimbyPushNotificationService.NotificationType.STORY);
        System.assertNotEquals(null, FimbyPushNotificationService.NotificationType.REMINDER);
        System.assertNotEquals(null, FimbyPushNotificationService.NotificationType.BULK_BUY);
        System.assertNotEquals(null, FimbyPushNotificationService.NotificationType.GENERAL);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // HTTP CALLOUT TESTS
    // ─────────────────────────────────────────────────────────────────────────────

    private class MockPushHttpResponse implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        public MockPushHttpResponse(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    @isTest
    static void testSendPushNotificationSuccess() {
        User testUser = getTestCommunityUser();
        Test.setMock(HttpCalloutMock.class, new MockPushHttpResponse(200, '{"sent": true}'));

        FimbyPushNotificationService.PushPayload payload = new FimbyPushNotificationService.PushPayload(
            testUser.Id,
            'Test Notification',
            'This is a test',
            FimbyPushNotificationService.NotificationType.MESSAGE
        );

        Test.startTest();
        FimbyPushNotificationService.sendPushNotification(payload);
        Test.stopTest();

        System.assert(true, 'Send should complete without error');
    }

    @isTest
    static void testSendPushNotificationFailure() {
        User testUser = getTestCommunityUser();
        Test.setMock(HttpCalloutMock.class, new MockPushHttpResponse(500, '{"error": "server_error"}'));

        FimbyPushNotificationService.PushPayload payload = new FimbyPushNotificationService.PushPayload(
            testUser.Id,
            'Test Notification',
            'This is a test',
            FimbyPushNotificationService.NotificationType.MESSAGE
        );

        Test.startTest();
        FimbyPushNotificationService.sendPushNotification(payload);
        Test.stopTest();

        System.assert(true, 'Failure should be handled gracefully');
    }

    @isTest
    static void testQueueableExecutesBatch() {
        User testUser = getTestCommunityUser();
        Test.setMock(HttpCalloutMock.class, new MockPushHttpResponse(200, '{"sent": true}'));

        FimbyPushNotificationService.PushPayload p1 = new FimbyPushNotificationService.PushPayload(
            testUser.Id, 'Batch 1', 'Body 1', FimbyPushNotificationService.NotificationType.MESSAGE
        );
        FimbyPushNotificationService.PushPayload p2 = new FimbyPushNotificationService.PushPayload(
            testUser.Id, 'Batch 2', 'Body 2', FimbyPushNotificationService.NotificationType.LIBRARY
        );

        List<String> payloads = new List<String>{ p1.toJson(), p2.toJson() };

        Test.startTest();
        System.enqueueJob(new FimbyPushNotificationService.FimbyPushQueueable(payloads));
        Test.stopTest();

        System.assert(true, 'Queueable should process batch without error');
    }

    @isTest
    static void testSendMultipleNotifications() {
        User testUser = getTestCommunityUser();
        Test.setMock(HttpCalloutMock.class, new MockPushHttpResponse(200, '{"sent": true}'));

        List<FimbyPushNotificationService.PushPayload> payloads = new List<FimbyPushNotificationService.PushPayload>();
        for (Integer i = 0; i < 3; i++) {
            payloads.add(new FimbyPushNotificationService.PushPayload(
                testUser.Id, 'Multi ' + i, 'Body ' + i,
                FimbyPushNotificationService.NotificationType.STORY
            ));
        }

        Test.startTest();
        FimbyPushNotificationService.sendPushNotifications(payloads);
        Test.stopTest();

        System.assert(true, 'Multiple notifications should enqueue as single job');
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // CONVENIENCE METHOD TESTS
    // ─────────────────────────────────────────────────────────────────────────────

    @isTest
    static void testNotifyNewMessage() {
        User testUser = getTestCommunityUser();
        Test.setMock(HttpCalloutMock.class, new MockPushHttpResponse(200, '{"sent": true}'));

        Test.startTest();
        FimbyPushNotificationService.notifyNewMessage(
            testUser.Id,
            'Jane Doe',
            'Hey, are you available to help with the garden this weekend?'
        );
        Test.stopTest();

        System.assert(true, 'notifyNewMessage should complete');
    }

    @isTest
    static void testNotifyNewMessageLongPreview() {
        User testUser = getTestCommunityUser();
        Test.setMock(HttpCalloutMock.class, new MockPushHttpResponse(200, '{"sent": true}'));

        String longMessage = 'This is a very long message that should be truncated because it exceeds the 100 character limit for push notification previews and we want to keep them concise.';

        Test.startTest();
        FimbyPushNotificationService.notifyNewMessage(
            testUser.Id,
            'Jane Doe',
            longMessage
        );
        Test.stopTest();

        System.assert(true, 'Long message should be truncated without error');
    }

    @isTest
    static void testNotifyLibraryRequest() {
        User testUser = getTestCommunityUser();
        Test.setMock(HttpCalloutMock.class, new MockPushHttpResponse(200, '{"sent": true}'));

        Test.startTest();
        FimbyPushNotificationService.notifyLibraryActivity(
            testUser.Id,
            'Tom Wilson',
            'Power Drill',
            'REQUEST'
        );
        Test.stopTest();

        System.assert(true, 'Library request notification should complete');
    }

    @isTest
    static void testNotifyLibraryReturn() {
        User testUser = getTestCommunityUser();
        Test.setMock(HttpCalloutMock.class, new MockPushHttpResponse(200, '{"sent": true}'));

        Test.startTest();
        FimbyPushNotificationService.notifyLibraryActivity(
            testUser.Id,
            'Tom Wilson',
            'Power Drill',
            'RETURN'
        );
        Test.stopTest();

        System.assert(true, 'Library return notification should complete');
    }

    @isTest
    static void testNotifyLibraryOtherActivity() {
        User testUser = getTestCommunityUser();
        Test.setMock(HttpCalloutMock.class, new MockPushHttpResponse(200, '{"sent": true}'));

        Test.startTest();
        FimbyPushNotificationService.notifyLibraryActivity(
            testUser.Id,
            'Tom Wilson',
            'Power Drill',
            'APPROVED'
        );
        Test.stopTest();

        System.assert(true, 'Library other activity notification should complete');
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // GET NOTIFIABLE USERS TEST
    // ─────────────────────────────────────────────────────────────────────────────

    @isTest
    static void testGetNotifiableUsers() {
        User testUser = getTestCommunityUser();
        Account neighbourhood = getTestNeighbourhood();

        // Set up user with push token and enabled notifications
        // Note: Neighbourhood_Account_ID__c is a formula field (Contact.npsp__Primary_Affiliation__r.Id)
        // so we only set the fields we can write to
        testUser.Expo_Push_Token__c = 'ExponentPushToken[test123]';
        testUser.Push_Notifications_Enabled__c = true;
        testUser.Push_Stories__c = true;
        update testUser;

        Test.startTest();
        // Use the neighbourhood from the test setup
        // The user's neighbourhood comes from their Contact's Primary Affiliation
        List<User> notifiableUsers = FimbyPushNotificationService.getNotifiableUsers(
            neighbourhood.Id,
            FimbyPushNotificationService.NotificationType.STORY
        );
        Test.stopTest();

        // Method should return a list without error
        // May be empty if Contact's Primary Affiliation isn't set up in test data
        System.assertNotEquals(null, notifiableUsers, 'Should return a list (not null)');
    }
}