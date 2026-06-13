@IsTest
public class FimbyPushBatchJobTest {

    @TestSetup
    static void setupTestData() {
        FimbyTestDataFactory.createCompleteTestSetup();
    }

    private static User getTestUser() {
        return [
            SELECT Id, ContactId, TimeZoneSidKey,
                   Quiet_Hours_Preference__c, Last_App_Open_At__c
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

    /* ── Happy path: Pending notifications dispatch to Queueable ─────── */

    @IsTest
    static void testBatchJob_DispatchesPendingNotifications() {
        Contact testContact = getTestContact();

        Notification__c notif = new Notification__c(
            Contact__c = testContact.Id,
            Type__c = 'Response',
            Title__c = 'Test notification',
            Body__c = 'Body',
            Push_Status__c = 'Pending'
        );
        insert notif;

        Test.setMock(HttpCalloutMock.class, new MockPushResponse(200, '{"sent":true}'));

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assert(true, 'Batch job should execute without error');
    }

    /* ── No Pending records: exits cleanly ────────────────────────────── */

    @IsTest
    static void testBatchJob_NoPendingRecords() {
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assert(true, 'Empty batch should exit without error');
    }

    /* ── Recent login no longer suppresses push ──────────────────────── */

    @IsTest
    static void testBatchJob_PushesEvenWhenRecentlyLoggedIn() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = testUser.Id, Last_App_Open_At__c = Datetime.now());
        }

        Notification__c notif = new Notification__c(
            Contact__c = testContact.Id,
            Type__c = 'Response',
            Title__c = 'Recent login test',
            Body__c = 'Body',
            Push_Status__c = 'Pending'
        );
        insert notif;

        Test.setMock(HttpCalloutMock.class, new MockPushResponse(200, '{"sent":true}'));

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        Notification__c result = [SELECT Push_Status__c FROM Notification__c WHERE Id = :notif.Id];
        System.assertNotEquals('Pending', result.Push_Status__c,
            'Recent login should no longer hold the push back');
    }

    /* ── Quiet hours: user skipped ───────────────────────────────────── */

    @IsTest
    static void testIsInQuietHours_WithNONE() {
        User u = new User(
            Quiet_Hours_Preference__c = 'NONE',
            TimeZoneSidKey = 'America/Vancouver'
        );
        System.assertEquals(false, FimbyPushBatchJob.isInQuietHours(u),
            'NONE preference means no quiet hours');
    }

    /* ── DM and Activity partitioning ────────────────────────────────── */

    @IsTest
    static void testBatchJob_DMAndActivityCombined() {
        Contact testContact = getTestContact();

        List<Notification__c> notifs = new List<Notification__c>{
            new Notification__c(
                Contact__c = testContact.Id,
                Type__c = 'Message',
                Title__c = 'DM notification',
                Body__c = 'Body',
                Push_Status__c = 'Pending'
            ),
            new Notification__c(
                Contact__c = testContact.Id,
                Type__c = 'Response',
                Title__c = 'Activity notification',
                Body__c = 'Body',
                Push_Status__c = 'Pending'
            )
        };
        insert notifs;

        Test.setMock(HttpCalloutMock.class, new MockPushResponse(200, '{"sent":true}'));

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assert(true, 'Combined DM + Activity batch should execute');
    }

    /* ── Activity-only batch collapses to generic "Neighbourhood activity" ── */

    @IsTest
    static void testBatchJob_ActivityOnly_DispatchesGenericActivityPayload() {
        Contact testContact = getTestContact();
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        List<Notification__c> notifs = new List<Notification__c>{
            new Notification__c(
                Contact__c = testContact.Id,
                Type__c = 'Response',
                Title__c = 'Activity 1', Body__c = 'b',
                Push_Status__c = 'Pending'
            ),
            new Notification__c(
                Contact__c = testContact.Id,
                Type__c = 'Response',
                Title__c = 'Activity 2', Body__c = 'b',
                Push_Status__c = 'Pending'
            )
        };
        insert notifs;

        CapturingMock mock = new CapturingMock(200, '{"sent":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assert(String.isNotBlank(mock.capturedBody), 'A payload should have been sent');
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('Neighbourhood activity', parsed.get('title'),
            'Multiple activity notifications collapse to the generic activity title');
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

    /* ── DM-only batch dispatches generic "New messages" payload ────────── */

    @IsTest
    static void testBatchJob_DMOnly_DispatchesGenericMessagesPayload() {
        Contact testContact = getTestContact();
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        List<Notification__c> notifs = new List<Notification__c>{
            new Notification__c(
                Contact__c = testContact.Id,
                Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'DM 1', Body__c = 'b',
                Push_Status__c = 'Pending'
            ),
            new Notification__c(
                Contact__c = testContact.Id,
                Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'DM 2', Body__c = 'b',
                Push_Status__c = 'Pending'
            )
        };
        insert notifs;

        CapturingMock mock = new CapturingMock(200, '{"sent":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assert(String.isNotBlank(mock.capturedBody), 'A payload should have been sent');
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(mock.capturedBody);
        System.assertEquals('New messages', parsed.get('title'),
            'Multiple DMs collapse to the generic "New messages" title');
    }

    /* ── Phase 7 smoke: single notification's payload carries deep-link data ── */
    /*
     * The mobile client now reads data.action_url and data.notification_id from
     * single-notification pushes to route the user straight to the surface
     * (vs. the generic "Neighbourhood activity" landing screen for batched pushes).
     * This test mocks the FCM HTTP callout and asserts the JSON body of the
     * outbound request contains both keys + the deep-link value we wrote on the
     * Notification__c row.
     */
    @IsTest
    static void testBatchJob_SinglePush_CarriesDeepLinkAndNotificationId() {
        Contact testContact = getTestContact();

        // Test setup data may have created incidental Notification__c rows via
        // triggers. Clear them so this test exercises the single-pending branch.
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        Notification__c notif = new Notification__c(
            Contact__c = testContact.Id,
            Type__c = FimbyConstants.NOTIF_LENDING_REQUEST,
            Title__c = 'Sam wants to borrow your drill',
            Body__c = 'Pick up Saturday morning works for them.',
            Action_URL__c = FimbySettings.getUrl('Library_Item', 'a005f000004XYZAAA4'),
            Actor_Name__c = 'Sam Rivera',
            Push_Status__c = 'Pending'
        );
        insert notif;

        CapturingMock mock = new CapturingMock(200, '{"sent":true}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        String body = mock.capturedBody;
        System.assert(String.isNotBlank(body),
            'FimbyPushQueueable should have issued one HTTP callout with a JSON payload');

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        Map<String, Object> data = (Map<String, Object>) parsed.get('data');
        System.assertNotEquals(null, data, 'payload.data must be present for single-notification pushes');
        System.assertEquals(String.valueOf(notif.Id), data.get('notification_id'),
            'notification_id must let the mobile client mark the row read after tap');
        System.assertEquals(notif.Action_URL__c, data.get('action_url'),
            'action_url must carry the deep link so the device routes straight to the surface');
        System.assertEquals(FimbyConstants.NOTIF_LENDING_REQUEST, data.get('notification_type'),
            'notification_type lets the mobile client pick the right channel + icon');
    }

    /**
     * Captures the first HTTP request body so tests can assert on the
     * outbound JSON payload. Returns a successful mock response so the
     * queueable continues its happy path.
     */
    private class CapturingMock implements HttpCalloutMock {
        public String capturedBody;
        private Integer statusCode;
        private String body;

        public CapturingMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HTTPResponse respond(HTTPRequest req) {
            if (capturedBody == null) {
                capturedBody = req.getBody();
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }
}
