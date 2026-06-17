@IsTest
public class FimbyPushQueueableTest {

    @TestSetup
    static void setupTestData() {
        FimbyTestDataFactory.createCompleteTestSetup();
    }

    private static User getTestUser() {
        return [
            SELECT Id, ContactId, Last_DM_Push_At__c, Last_Activity_Push_At__c,
                   Last_Quiet_Refresh_At__c
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

    private static Map<Id, List<Id>> markMap(Id userId, List<Id> notifIds) {
        return new Map<Id, List<Id>>{ userId => notifIds };
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

        Test.setMock(HttpCalloutMock.class, new EchoMock(true));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>{ payload },
            markMap(testUser.Id, new List<Id>{ notif.Id }),
            new Map<Id, String>{ testUser.Id => 'ACTIVITY' }
        ));
        Test.stopTest();

        Notification__c result = [SELECT Push_Status__c FROM Notification__c WHERE Id = :notif.Id];
        System.assertEquals('Sent', result.Push_Status__c, 'Should be marked Sent after success');

        User updatedUser = [SELECT Last_Activity_Push_At__c FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, updatedUser.Last_Activity_Push_At__c,
            'Activity gate timestamp should be stamped');
    }

    /* ── Failure (HTTP 500): marks Failed, gate NOT stamped ──────────── */

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

        Test.setMock(HttpCalloutMock.class, new MockPushResponse(500, '{"error":"server_error"}'));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>{ payload },
            markMap(testUser.Id, new List<Id>{ notif.Id }),
            new Map<Id, String>{ testUser.Id => 'DM' }
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

        Test.setMock(HttpCalloutMock.class, new EchoMock(true));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>{ payload },
            markMap(testUser.Id, new List<Id>{ notif1.Id, notif2.Id }),
            new Map<Id, String>{ testUser.Id => 'BOTH' }
        ));
        Test.stopTest();

        User u = [SELECT Last_DM_Push_At__c, Last_Activity_Push_At__c FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, u.Last_DM_Push_At__c, 'DM gate should be stamped');
        System.assertNotEquals(null, u.Last_Activity_Push_At__c, 'Activity gate should be stamped');
    }

    /* ── Batch POST carries { notifications: [...] } ─────────────────── */

    @IsTest
    static void testQueueable_BatchBodyShape() {
        User testUser = getTestUser();

        FimbyPushNotificationService.PushPayload payload =
            new FimbyPushNotificationService.PushPayload(
                testUser.Id, 'T', 'B', FimbyPushNotificationService.NotificationType.GENERAL
            );

        EchoMock mock = new EchoMock(true);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>{ payload },
            new Map<Id, List<Id>>(),
            new Map<Id, String>()
        ));
        Test.stopTest();

        System.assert(mock.capturedBody.contains('"notifications"'),
            'Batch POST must wrap payloads in a notifications array');
    }

    /* ── Per-entry result: not-accepted Pending_Quiet stays Pending_Quiet ── */

    @IsTest
    static void testQueueable_QuietNotAccepted_StaysPendingQuiet() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Notification__c notif = new Notification__c(
            Contact__c = testContact.Id, Type__c = 'Response',
            Title__c = 'Quiet', Body__c = 'Body', Push_Status__c = 'Pending_Quiet'
        );
        insert notif;

        FimbyPushNotificationService.PushPayload payload =
            new FimbyPushNotificationService.PushPayload(
                testUser.Id, 'Activity', 'Body',
                FimbyPushNotificationService.NotificationType.GENERAL
            );
        payload.quiet = true;

        Test.setMock(HttpCalloutMock.class, new EchoMock(false));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>{ payload },
            markMap(testUser.Id, new List<Id>{ notif.Id }),
            new Map<Id, String>{ testUser.Id => 'QUIET' }
        ));
        Test.stopTest();

        Notification__c result = [SELECT Push_Status__c FROM Notification__c WHERE Id = :notif.Id];
        System.assertEquals('Pending_Quiet', result.Push_Status__c,
            'A not-accepted quiet row stays Pending_Quiet (retried next cycle), never Failed');

        User u = [SELECT Last_Quiet_Refresh_At__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals(null, u.Last_Quiet_Refresh_At__c,
            'Not-accepted quiet push does not stamp the quiet-refresh timestamp');
    }

    /* ── Per-entry result: not-accepted Pending → Failed ─────────────── */

    @IsTest
    static void testQueueable_AudibleNotAccepted_MarksFailed() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Notification__c notif = new Notification__c(
            Contact__c = testContact.Id, Type__c = 'Response',
            Title__c = 'Audible', Body__c = 'Body', Push_Status__c = 'Pending'
        );
        insert notif;

        FimbyPushNotificationService.PushPayload payload =
            new FimbyPushNotificationService.PushPayload(
                testUser.Id, 'Activity', 'Body',
                FimbyPushNotificationService.NotificationType.GENERAL
            );

        Test.setMock(HttpCalloutMock.class, new EchoMock(false));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>{ payload },
            markMap(testUser.Id, new List<Id>{ notif.Id }),
            new Map<Id, String>{ testUser.Id => 'ACTIVITY' }
        ));
        Test.stopTest();

        Notification__c result = [SELECT Push_Status__c FROM Notification__c WHERE Id = :notif.Id];
        System.assertEquals('Failed', result.Push_Status__c,
            'A not-accepted audible row is marked Failed');
    }

    /* ── Empty payload list: exits cleanly ───────────────────────────── */

    @IsTest
    static void testQueueable_EmptyPayloads() {
        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>(),
            new Map<Id, List<Id>>(),
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

        Test.setMock(HttpCalloutMock.class, new EchoMock(true));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            bigBatch,
            new Map<Id, List<Id>>(),
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

        Test.setMock(HttpCalloutMock.class, new EchoMock(true));

        Test.startTest();
        System.enqueueJob(new FimbyPushQueueable(
            new List<FimbyPushNotificationService.PushPayload>{ payload },
            markMap(testUser.Id, notifIds),
            new Map<Id, String>{ testUser.Id => 'ACTIVITY' }
        ));
        Test.stopTest();

        Integer sentCount = [SELECT COUNT() FROM Notification__c
            WHERE Id IN :notifIds AND Push_Status__c = 'Sent'];
        System.assertEquals(5, sentCount, 'All 5 notifications should be Sent');
    }

    /* Static-status mock for explicit-body / HTTP-failure tests. */
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

    /**
     * Parses the outbound batch body and returns a per-entry results array
     * echoing the configured accepted verdict for each user_id — mirrors the
     * bridge's { results: [{ user_id, accepted }] } contract.
     */
    private class EchoMock implements HttpCalloutMock {
        private Boolean accepted;
        public String capturedBody;

        public EchoMock(Boolean accepted) {
            this.accepted = accepted;
        }

        public HTTPResponse respond(HTTPRequest req) {
            capturedBody = req.getBody();
            List<Object> results = new List<Object>();
            try {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(capturedBody);
                Object notifsRaw = parsed.get('notifications');
                if (notifsRaw instanceof List<Object>) {
                    for (Object o : (List<Object>) notifsRaw) {
                        Map<String, Object> n = (Map<String, Object>) o;
                        results.add(new Map<String, Object>{
                            'user_id' => n.get('user_id'),
                            'accepted' => accepted
                        });
                    }
                }
            } catch (Exception e) {
                // leave results empty
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{ 'results' => results }));
            return res;
        }
    }
}
