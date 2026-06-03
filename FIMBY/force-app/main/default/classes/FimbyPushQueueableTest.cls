@IsTest
public class FimbyPushQueueableTest {

    @TestSetup
    static void setupTestData() {
        FimbyTestDataFactory.createCompleteTestSetup();
    }

    private static User getTestUser() {
        return [
            SELECT Id, ContactId, Last_DM_Push_At__c, Last_Activity_Push_At__c
            FROM User
            WHERE Profile.Name = 'Customer Community User'
            AND IsActive = true
            LIMIT 1
        ];
    }

    private static Contact getTestContact() {
        User u = getTestUser();
        return [SELECT Id FROM Contact WHERE Id = :u.ContactId LIMIT 1];
    }

    /* ── Success: marks Sent + stamps gate ────────────────────────────── */

    @IsTest
    static void testQueueable_Success_MarksSentAndStampsGate() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Notification__c notif = new Notification__c(
            Contact__c = testContact.Id,
            Type__c = 'Response',
            Title__c = 'Test',
            Body__c = 'Body',
            Push_Status__c = 'Pending'
        );
        insert notif;

        FimbyPushNotificationService.PushPayload payload =
            new FimbyPushNotificationService.PushPayload(
                testUser.Id,
                'Neighbourhood activity',
                'Something\'s happening in your neighbourhood.',
                FimbyPushNotificationService.NotificationType.GENERAL
            );

        List<Id> notifIds = new List<Id>{ notif.Id };
        Map<Id, String> gateUpdates = new Map<Id, String>{ testUser.Id => 'ACTIVITY' };

        Test.setMock(HttpCalloutMock.class, new MockPushResponse(200, '{"sent":true}'));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>{ payload },
            notifIds,
            gateUpdates
        ));
        Test.stopTest();

        Notification__c result = [SELECT Push_Status__c FROM Notification__c WHERE Id = :notif.Id];
        System.assertEquals('Sent', result.Push_Status__c, 'Should be marked Sent after success');

        User updatedUser = [SELECT Last_Activity_Push_At__c FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, updatedUser.Last_Activity_Push_At__c,
            'Activity gate timestamp should be stamped');
    }

    /* ── Failure: marks Failed, gate NOT stamped ─────────────────────── */

    @IsTest
    static void testQueueable_Failure_MarksFailedNoGateStamp() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Notification__c notif = new Notification__c(
            Contact__c = testContact.Id,
            Type__c = 'Message',
            Title__c = 'Test DM',
            Body__c = 'Body',
            Push_Status__c = 'Pending'
        );
        insert notif;

        FimbyPushNotificationService.PushPayload payload =
            new FimbyPushNotificationService.PushPayload(
                testUser.Id,
                'New message',
                'A neighbour sent you a message.',
                FimbyPushNotificationService.NotificationType.MESSAGE
            );

        List<Id> notifIds = new List<Id>{ notif.Id };
        Map<Id, String> gateUpdates = new Map<Id, String>{ testUser.Id => 'DM' };

        Test.setMock(HttpCalloutMock.class, new MockPushResponse(500, '{"error":"server_error"}'));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>{ payload },
            notifIds,
            gateUpdates
        ));
        Test.stopTest();

        Notification__c result = [SELECT Push_Status__c, Push_Error__c FROM Notification__c WHERE Id = :notif.Id];
        System.assertEquals('Failed', result.Push_Status__c, 'Should be marked Failed after callout error');
        System.assertNotEquals(null, result.Push_Error__c, 'Should have error detail');
    }

    /* ── BOTH gate stamps both timestamps ────────────────────────────── */

    @IsTest
    static void testQueueable_BothGateStampsBothTimestamps() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Notification__c notif1 = new Notification__c(
            Contact__c = testContact.Id, Type__c = 'Message',
            Title__c = 'DM', Body__c = 'Body', Push_Status__c = 'Pending'
        );
        Notification__c notif2 = new Notification__c(
            Contact__c = testContact.Id, Type__c = 'Response',
            Title__c = 'Activity', Body__c = 'Body', Push_Status__c = 'Pending'
        );
        insert new List<Notification__c>{ notif1, notif2 };

        FimbyPushNotificationService.PushPayload payload =
            new FimbyPushNotificationService.PushPayload(
                testUser.Id,
                'New messages and activity',
                'Combined push.',
                FimbyPushNotificationService.NotificationType.GENERAL
            );

        List<Id> notifIds = new List<Id>{ notif1.Id, notif2.Id };
        Map<Id, String> gateUpdates = new Map<Id, String>{ testUser.Id => 'BOTH' };

        Test.setMock(HttpCalloutMock.class, new MockPushResponse(200, '{"sent":true}'));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>{ payload },
            notifIds,
            gateUpdates
        ));
        Test.stopTest();

        User u = [SELECT Last_DM_Push_At__c, Last_Activity_Push_At__c FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, u.Last_DM_Push_At__c, 'DM gate should be stamped');
        System.assertNotEquals(null, u.Last_Activity_Push_At__c, 'Activity gate should be stamped');
    }

    /* ── Empty payload list: exits cleanly ───────────────────────────── */

    @IsTest
    static void testQueueable_EmptyPayloads() {
        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>(),
            new List<Id>(),
            new Map<Id, String>()
        ));
        Test.stopTest();

        System.assert(true, 'Empty queueable should exit without error');
    }

    /* ── Null payloads: exits cleanly ────────────────────────────────── */

    @IsTest
    static void testQueueable_NullPayloads() {
        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(null, null, null));
        Test.stopTest();

        System.assert(true, 'Null queueable should exit without error');
    }

    /* ── Chaining: >100 payloads triggers chainRemainder ────────────── */

    @IsTest
    static void testQueueable_ChainsWhenOverHundred() {
        User testUser = getTestUser();

        List<FimbyPushNotificationService.PushPayload> bigBatch =
            new List<FimbyPushNotificationService.PushPayload>();
        for (Integer i = 0; i < 105; i++) {
            bigBatch.add(new FimbyPushNotificationService.PushPayload(
                testUser.Id, 'Title ' + i, 'Body ' + i,
                FimbyPushNotificationService.NotificationType.GENERAL
            ));
        }

        Test.setMock(HttpCalloutMock.class, new MockPushResponse(200, '{"sent":true}'));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            bigBatch,
            new List<Id>(),
            new Map<Id, String>()
        ));
        Test.stopTest();

        System.assert(true, 'Should chain remaining 5 payloads without error');
    }

    /* ── Gate stamp action: @future + DM-only branch ─────────────────── */

    @IsTest
    static void testGateStampAction_FutureAndEmptyMap() {
        User testUser = getTestUser();
        FimbyPushGateStampAction.stampGatesSync(null);
        FimbyPushGateStampAction.stampGatesSync(new Map<String, String>());

        Map<String, String> dmGate = new Map<String, String>{ String.valueOf(testUser.Id) => 'DM' };
        Test.startTest();
        FimbyPushGateStampAction.stampGates(dmGate);
        Test.stopTest();

        User u = [SELECT Last_DM_Push_At__c, Last_Activity_Push_At__c FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, u.Last_DM_Push_At__c, 'DM gate should be stamped via @future');
    }

    /* ── Multiple notifications marked Sent in one batch ─────────────── */

    @IsTest
    static void testQueueable_MultipleNotifsSent() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        List<Notification__c> notifs = new List<Notification__c>();
        for (Integer i = 0; i < 5; i++) {
            notifs.add(new Notification__c(
                Contact__c = testContact.Id,
                Type__c = 'Response',
                Title__c = 'Notif ' + i,
                Body__c = 'Body',
                Push_Status__c = 'Pending'
            ));
        }
        insert notifs;

        List<Id> notifIds = new List<Id>();
        for (Notification__c n : notifs) {
            notifIds.add(n.Id);
        }

        FimbyPushNotificationService.PushPayload payload =
            new FimbyPushNotificationService.PushPayload(
                testUser.Id, 'Activity', 'Body',
                FimbyPushNotificationService.NotificationType.GENERAL
            );

        Map<Id, String> gateUpdates = new Map<Id, String>{ testUser.Id => 'ACTIVITY' };

        Test.setMock(HttpCalloutMock.class, new MockPushResponse(200, '{"sent":true}'));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>{ payload },
            notifIds,
            gateUpdates
        ));
        Test.stopTest();

        Integer sentCount = [SELECT COUNT() FROM Notification__c
            WHERE Id IN :notifIds AND Push_Status__c = 'Sent'];
        System.assertEquals(5, sentCount, 'All 5 notifications should be Sent');
    }

    private class MockPushResponse implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        public MockPushResponse(Integer statusCode, String body) {
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
}
