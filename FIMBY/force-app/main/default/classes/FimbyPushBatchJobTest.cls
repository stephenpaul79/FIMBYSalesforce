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

        Test.setMock(HttpCalloutMock.class, new CapturingEchoMock(true));

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
                Actor_Name__c = 'Maya Chen',
                Push_Status__c = 'Pending'
            ),
            new Notification__c(
                Contact__c = testContact.Id,
                Type__c = 'Response',
                Title__c = 'Activity 2', Body__c = 'b',
                Actor_Name__c = 'Jordan Lee',
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
        Map<String, Object> parsed = firstNotif(mock.capturedBody);
        System.assertEquals('Maya Chen and Jordan Lee posted nearby', parsed.get('title'),
            'Two named activity notifications lead with both neighbour names');
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
                Actor_Name__c = 'Maya Chen',
                Push_Status__c = 'Pending'
            ),
            new Notification__c(
                Contact__c = testContact.Id,
                Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'DM 2', Body__c = 'b',
                Actor_Name__c = 'Jordan Lee',
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
        Map<String, Object> parsed = firstNotif(mock.capturedBody);
        System.assertEquals('Maya Chen and Jordan Lee messaged you', parsed.get('title'),
            'Two named DMs lead with both neighbour names');
    }

    /* ── Phase 1: collapseId bucketing ───────────────────────────────────── */

    // The queueable now POSTs a batch body { "notifications": [ {...} ] }.
    // Unwrap the first payload object so existing per-payload assertions hold.
    private static Map<String, Object> firstNotif(String capturedBody) {
        return (Map<String, Object>) allNotifs(capturedBody)[0];
    }

    private static List<Object> allNotifs(String capturedBody) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(capturedBody);
        return (List<Object>) parsed.get('notifications');
    }

    private static String capturedCollapseId(String capturedBody) {
        return (String) firstNotif(capturedBody).get('collapse_id');
    }

    @IsTest
    static void testCollapseId_DMBucket_ShapeMatches() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        insert new List<Notification__c>{
            new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'DM 1', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending'),
            new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'DM 2', Body__c = 'b', Actor_Name__c = 'Jordan', Push_Status__c = 'Pending')
        };

        CapturingMock mock = new CapturingMock(200, '{"sent":true}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assertEquals(testUser.Id + ':dm', capturedCollapseId(mock.capturedBody),
            'DM bucket collapse_id is "{userId}:dm"');
    }

    @IsTest
    static void testCollapseId_ActivityBucket_ShapeMatches() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        insert new List<Notification__c>{
            new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'A 1', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending'),
            new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'A 2', Body__c = 'b', Actor_Name__c = 'Jordan', Push_Status__c = 'Pending')
        };

        CapturingMock mock = new CapturingMock(200, '{"sent":true}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assertEquals(testUser.Id + ':activity', capturedCollapseId(mock.capturedBody),
            'Activity bucket collapse_id is "{userId}:activity"');
    }

    @IsTest
    static void testMixedCycle_EmitsTwoPings_PerGate_NeverMerged() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        // A DM and an activity notification in the same cycle. The two gates must
        // NOT merge into a single ping — each gets its own card so its deep link
        // routes to the right surface (/messages vs /notifications).
        insert new List<Notification__c>{
            new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'DM', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending'),
            new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'Activity', Body__c = 'b', Actor_Name__c = 'Jordan', Push_Status__c = 'Pending')
        };

        CapturingMock mock = new CapturingMock(200, '{"sent":true}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        List<Object> notifs = allNotifs(mock.capturedBody);
        System.assertEquals(2, notifs.size(),
            'A mixed DM + activity cycle must emit exactly two pings, one per gate');

        Map<String, Map<String, Object>> byCollapse = new Map<String, Map<String, Object>>();
        for (Object o : notifs) {
            Map<String, Object> n = (Map<String, Object>) o;
            byCollapse.put((String) n.get('collapse_id'), n);
        }

        System.assert(byCollapse.containsKey(testUser.Id + ':dm'),
            'A DM-gated ping with the :dm collapse key must be present');
        System.assert(byCollapse.containsKey(testUser.Id + ':activity'),
            'An activity-gated ping with the :activity collapse key must be present');
        System.assert(!byCollapse.containsKey(testUser.Id + ':both'),
            'The merged :both ping must no longer exist');

        // Each ping routes to its own surface via channelId.
        Map<String, Object> dmData = (Map<String, Object>) byCollapse.get(testUser.Id + ':dm').get('data');
        Map<String, Object> actData = (Map<String, Object>) byCollapse.get(testUser.Id + ':activity').get('data');
        System.assertEquals('messages', dmData.get('channelId'),
            'DM ping routes to the messages surface');
        System.assertEquals('activity', actData.get('channelId'),
            'Activity ping routes to the notifications surface');
    }

    @IsTest
    static void testMixedCycle_StampsBothDoorbells() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        insert new List<Notification__c>{
            new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'DM', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending'),
            new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'Activity', Body__c = 'b', Actor_Name__c = 'Jordan', Push_Status__c = 'Pending')
        };

        Test.setMock(HttpCalloutMock.class, new CapturingEchoMock(true));
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        // Two pings, but gate stamping stays per-user: both doorbells move.
        User u = [SELECT Last_DM_Push_At__c, Last_Activity_Push_At__c FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, u.Last_DM_Push_At__c, 'DM doorbell stamped');
        System.assertNotEquals(null, u.Last_Activity_Push_At__c, 'Activity doorbell stamped');
    }

    @IsTest
    static void testCollapseId_SinglePush_Present() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        insert new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
            Title__c = 'One DM', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending');

        CapturingMock mock = new CapturingMock(200, '{"sent":true}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assertEquals(testUser.Id + ':dm', capturedCollapseId(mock.capturedBody),
            'Single DM push still carries a collapse_id');
    }

    /* ── Phase 0: named aggregation builders ─────────────────────────────── */

    private static Notification__c notifWithActor(String actorName, String type) {
        return new Notification__c(Type__c = type, Actor_Name__c = actorName);
    }

    @IsTest
    static void testComposeSinglePush_BellVisibleType_PrependsActorName() {
        // Bell-visible de-actored title gets the real actor name prepended so the
        // lock-screen copy reads whole.
        Notification__c n = notifWithActor('Maya Chen', 'Lending_Request');
        n.Title__c = 'requested to borrow your drill';
        String title = FimbyPushBatchJob.composeSinglePushTitle(n);
        System.assertEquals('Maya Chen requested to borrow your drill', title,
            'Bell-visible single push leads with the actor name');
    }

    @IsTest
    static void testComposeSinglePush_TokenActor_PassesThrough() {
        Notification__c n = notifWithActor('FIMBY', 'Lending_Request');
        n.Title__c = 'The ladder is now on loan to you';
        String title = FimbyPushBatchJob.composeSinglePushTitle(n);
        System.assertEquals('The ladder is now on loan to you', title,
            'Token-actor titles are self-contained and pass through unchanged');
    }

    @IsTest
    static void testComposeSinglePush_MessageStyleType_PassesThrough() {
        // Message-style titles already carry the name; do not double it.
        Notification__c n = notifWithActor('Sam Rivera', FimbyConstants.NOTIF_MESSAGE);
        n.Title__c = 'Sam Rivera';
        String title = FimbyPushBatchJob.composeSinglePushTitle(n);
        System.assertEquals('Sam Rivera', title,
            'Message-style single push passes through without prepending the name again');
    }

    @IsTest
    static void testAggregate_TwoActivityActors_TitleNamesBoth() {
        List<Notification__c> bucket = new List<Notification__c>{
            notifWithActor('Maya Chen', 'Response'),
            notifWithActor('Jordan Lee', 'Response')
        };
        List<String> names = FimbyPushBatchJob.extractRealNames(bucket);
        String title = FimbyPushBatchJob.buildAggregateTitle(names, 'ACTIVITY');
        System.assert(title.contains('Maya Chen'), 'Title should name the first actor');
        System.assert(title.contains('Jordan Lee'), 'Title should name the second actor');
        System.assert(title.contains(' and '), 'Two actors join with "and"');
    }

    @IsTest
    static void testAggregate_ThreeDMActors_TitleNamesOnePlusCount() {
        List<Notification__c> bucket = new List<Notification__c>{
            notifWithActor('Maya Chen', FimbyConstants.NOTIF_MESSAGE),
            notifWithActor('Jordan Lee', FimbyConstants.NOTIF_MESSAGE),
            notifWithActor('Sam Rivera', FimbyConstants.NOTIF_MESSAGE)
        };
        List<String> names = FimbyPushBatchJob.extractRealNames(bucket);
        String title = FimbyPushBatchJob.buildAggregateTitle(names, 'DM');
        System.assertEquals('Maya Chen and 2 others messaged you', title,
            'Three DM actors lead with the first name + remainder count');
    }

    @IsTest
    static void testAggregate_TeamTokenActor_FallsBackToNeighbour() {
        List<Notification__c> bucket = new List<Notification__c>{
            notifWithActor('FIMBY', 'Response'),
            notifWithActor('Neighbourhood team', 'Response')
        };
        List<String> names = FimbyPushBatchJob.extractRealNames(bucket);
        System.assert(names.isEmpty(), 'Team/icon tokens are not real names');
        String title = FimbyPushBatchJob.buildAggregateTitle(names, 'ACTIVITY');
        System.assertEquals('Neighbourhood activity', title,
            'No real name falls back to the generic activity title');
        System.assert(!title.contains('FIMBY'), 'No team token leaks into the title');
        System.assert(!title.contains('Neighbourhood team'), 'No team token leaks into the title');
    }

    @IsTest
    static void testAggregate_TitleNeverExceeds80Chars() {
        String longName = 'Alexandria Bartholomew Christopherson';
        List<Notification__c> bucket = new List<Notification__c>{
            notifWithActor(longName, 'Response'),
            notifWithActor('Maximilian Featherstonehaugh', 'Response')
        };
        List<String> names = FimbyPushBatchJob.extractRealNames(bucket);
        String title = FimbyPushBatchJob.buildAggregateTitle(names, 'ACTIVITY');
        System.assert(title.length() <= 80, 'Title must not exceed 80 chars, was ' + title.length());
        System.assert(!title.endsWith(' '), 'Truncation should not leave trailing space');
    }

    @IsTest
    static void testAggregate_BodyNeverNull() {
        for (String gateKind : new List<String>{ 'DM', 'ACTIVITY', 'BOTH' }) {
            for (Integer count : new List<Integer>{ 0, 1, 2, 5 }) {
                String body = FimbyPushBatchJob.buildAggregateBody(count, gateKind);
                System.assertNotEquals(null, body,
                    'Body must never be null (gate=' + gateKind + ', count=' + count + ')');
            }
        }
        // Activity body counts the remainder, never "and 0 more".
        System.assert(!FimbyPushBatchJob.buildAggregateBody(1, 'ACTIVITY').contains('0 more'),
            'Single activity body should not read "and 0 more"');
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

        Map<String, Object> parsed = firstNotif(body);
        Map<String, Object> data = (Map<String, Object>) parsed.get('data');
        System.assertNotEquals(null, data, 'payload.data must be present for single-notification pushes');
        System.assertEquals(String.valueOf(notif.Id), data.get('notification_id'),
            'notification_id must let the mobile client mark the row read after tap');
        System.assertEquals(notif.Action_URL__c, data.get('action_url'),
            'action_url must carry the deep link so the device routes straight to the surface');
        System.assertEquals(FimbyConstants.NOTIF_LENDING_REQUEST, data.get('notification_type'),
            'notification_type lets the mobile client pick the right channel + icon');
    }

    /* ── Phase 2: passive quiet-upgrade ──────────────────────────────────── */

    // Neutralise the audible skip rules so audible/gate assertions are
    // deterministic regardless of the org clock.
    private static void disableSkipRules(Id userId) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = userId,
                Quiet_Hours_Preference__c = 'NONE',
                Include_Sundays__c = true);
        }
    }

    @IsTest
    static void testBatchJob_QuietOnly_PassiveDmPayload() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        insert new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
            Title__c = 'DM', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending_Quiet');

        CapturingEchoMock mock = new CapturingEchoMock(true);
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        Map<String, Object> n = firstNotif(mock.capturedBody);
        System.assertEquals('passive', n.get('interruption_level'),
            'A quiet-only cycle sends a passive push');
        Map<String, Object> data = (Map<String, Object>) n.get('data');
        System.assertEquals(true, data.get('quiet'), 'data.quiet flags the passive push for the mobile handler');
        System.assertEquals('messages_quiet', data.get('channelId'),
            'Quiet DM refresh routes to the low-importance channel');

        User u = [SELECT Last_DM_Push_At__c, Last_Quiet_Refresh_At__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals(null, u.Last_DM_Push_At__c, 'Quiet refresh must NOT move the DM doorbell');
        System.assertNotEquals(null, u.Last_Quiet_Refresh_At__c, 'Quiet refresh stamps observability timestamp');
    }

    @IsTest
    static void testBatchJob_Mixed_AudiblePushStampsDoorbell() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        insert new List<Notification__c>{
            new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'DM', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending'),
            new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'Activity', Body__c = 'b', Actor_Name__c = 'Jordan', Push_Status__c = 'Pending_Quiet')
        };

        CapturingEchoMock mock = new CapturingEchoMock(true);
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        Map<String, Object> n = firstNotif(mock.capturedBody);
        System.assertEquals(null, n.get('interruption_level'),
            'A cycle with any Pending row is audible, not passive');

        User u = [SELECT Last_DM_Push_At__c, Last_Activity_Push_At__c FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, u.Last_DM_Push_At__c, 'Mixed audible cycle stamps the DM doorbell');
        System.assertNotEquals(null, u.Last_Activity_Push_At__c, 'BOTH gate stamps the activity doorbell too');
    }

    @IsTest
    static void testBatchJob_ContentFromUnread_NamesEarlierActor() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        // Earlier actor: already Sent, still unread (Read_Date null).
        insert new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
            Title__c = 'Old DM', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Sent');
        // Newer actor: the new trigger row.
        insert new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
            Title__c = 'New DM', Body__c = 'b', Actor_Name__c = 'Jordan', Push_Status__c = 'Pending_Quiet');

        CapturingEchoMock mock = new CapturingEchoMock(true);
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        Map<String, Object> n = firstNotif(mock.capturedBody);
        String title = (String) n.get('title');
        System.assert(title.contains('Maya'),
            'Card content reads the whole unread set, so the earlier actor is still named: ' + title);
        System.assert(title.contains('Jordan'), 'The newer actor is named too: ' + title);
        System.assertEquals(2, n.get('badge'), 'Badge reflects total unread, not just this cycle');
    }

    @IsTest
    static void testBatchJob_QuietOnly_ActivityChannelUnchanged() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        insert new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
            Title__c = 'A', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending_Quiet');

        CapturingEchoMock mock = new CapturingEchoMock(true);
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        Map<String, Object> n = firstNotif(mock.capturedBody);
        Map<String, Object> data = (Map<String, Object>) n.get('data');
        System.assertEquals('activity', data.get('channelId'),
            'A quiet activity refresh keeps the DEFAULT-importance activity channel');
        System.assertEquals('passive', n.get('interruption_level'), 'Still a passive push');
    }

    /* ── Phase 3: true unread badge ──────────────────────────────────────── */

    private static Integer capturedBadge(String capturedBody) {
        return (Integer) firstNotif(capturedBody).get('badge');
    }

    @IsTest
    static void testBadge_EqualsUnreadCount() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        List<Notification__c> notifs = new List<Notification__c>();
        for (Integer i = 0; i < 3; i++) {
            notifs.add(new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'A' + i, Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending'));
        }
        insert notifs;

        CapturingEchoMock mock = new CapturingEchoMock(true);
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assertEquals(3, capturedBadge(mock.capturedBody), 'Badge equals total unread count');
    }

    @IsTest
    static void testBadge_IgnoresReadNotifications() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        // 2 unread + 2 already read.
        insert new List<Notification__c>{
            new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'U1', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending'),
            new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'U2', Body__c = 'b', Actor_Name__c = 'Jordan', Push_Status__c = 'Pending')
        };
        insert new List<Notification__c>{
            new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'R1', Body__c = 'b', Read_Date__c = Datetime.now(), Push_Status__c = 'Sent'),
            new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'R2', Body__c = 'b', Read_Date__c = Datetime.now(), Push_Status__c = 'Sent')
        };

        CapturingEchoMock mock = new CapturingEchoMock(true);
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assertEquals(2, capturedBadge(mock.capturedBody), 'Read notifications do not count toward the badge');
    }

    @IsTest
    static void testBadge_CountsSkipPushRows() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        // One pushed (Pending) + one in-app-only (skipPush → Push_Status null), both unread.
        insert new List<Notification__c>{
            new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'Pushed', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending'),
            new Notification__c(Contact__c = testContact.Id, Type__c = 'Response',
                Title__c = 'InAppOnly', Body__c = 'b', Actor_Name__c = 'Jordan', Push_Status__c = null)
        };

        CapturingEchoMock mock = new CapturingEchoMock(true);
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assertEquals(2, capturedBadge(mock.capturedBody),
            'Badge mirrors total in-app unread, including skipPush in-app-only rows');
    }

    /**
     * Captures the outbound batch body AND returns a per-entry results array
     * echoing the configured accepted verdict, so gate-stamp / Push_Status
     * assertions see a realistic bridge response.
     */
    private class CapturingEchoMock implements HttpCalloutMock {
        public String capturedBody;
        private Boolean accepted;

        public CapturingEchoMock(Boolean accepted) {
            this.accepted = accepted;
        }

        public HTTPResponse respond(HTTPRequest req) {
            if (capturedBody == null) {
                capturedBody = req.getBody();
            }
            List<Object> results = new List<Object>();
            try {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
                Object notifsRaw = parsed.get('notifications');
                if (notifsRaw instanceof List<Object>) {
                    for (Object o : (List<Object>) notifsRaw) {
                        Map<String, Object> nn = (Map<String, Object>) o;
                        results.add(new Map<String, Object>{
                            'user_id' => nn.get('user_id'), 'accepted' => accepted
                        });
                    }
                }
            } catch (Exception e) {
                // leave empty
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{ 'results' => results }));
            return res;
        }
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

    /* ── Gate-stamp regression: Thanks/Reply single audible stamps DM gate ── */

    @IsTest
    static void testSingleAudible_ThanksReceived_StampsDmGate() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        insert new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_THANKS_RECEIVED,
            Title__c = 'Thanks', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending');

        Test.setMock(HttpCalloutMock.class, new CapturingEchoMock(true));
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        User u = [SELECT Last_DM_Push_At__c, Last_Activity_Push_At__c FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, u.Last_DM_Push_At__c,
            'Thanks_Received is DM-gated at creation, so delivery must stamp the DM doorbell (regression)');
        System.assertEquals(null, u.Last_Activity_Push_At__c,
            'Thanks_Received must NOT stamp the activity doorbell');
    }

    @IsTest
    static void testSingleAudible_ResponseReply_StampsDmGate() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        insert new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_RESPONSE_REPLY,
            Title__c = 'Reply', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending');

        Test.setMock(HttpCalloutMock.class, new CapturingEchoMock(true));
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        User u = [SELECT Last_DM_Push_At__c FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, u.Last_DM_Push_At__c,
            'Response_Reply is DM-gated, so a single audible push stamps the DM doorbell');
    }

    @IsTest
    static void testSingleAudible_EventChat_RoutesMessagesChannel_StampsActivityGate() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        insert new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_EVENT_CHAT,
            Title__c = 'Event chat', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending');

        CapturingEchoMock mock = new CapturingEchoMock(true);
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        Map<String, Object> n = firstNotif(mock.capturedBody);
        Map<String, Object> data = (Map<String, Object>) n.get('data');
        System.assertEquals('messages', data.get('channelId'),
            'Event_Chat routes to the messages channel (content surface)');

        User u = [SELECT Last_DM_Push_At__c, Last_Activity_Push_At__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals(null, u.Last_DM_Push_At__c,
            'Event_Chat is the deliberate channel != gate case: messages channel but ACTIVITY gate');
        System.assertNotEquals(null, u.Last_Activity_Push_At__c,
            'Event_Chat stamps the ACTIVITY doorbell');
    }

    @IsTest
    static void testAggregatedMessageStyle_RoutesMessagesBucket() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        disableSkipRules(testUser.Id);
        delete [SELECT Id FROM Notification__c WHERE Contact__c = :testContact.Id];

        // Two message-style rows (reply + event chat) → aggregated DM/message bucket.
        insert new List<Notification__c>{
            new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_RESPONSE_REPLY,
                Title__c = 'r', Body__c = 'b', Actor_Name__c = 'Maya', Push_Status__c = 'Pending'),
            new Notification__c(Contact__c = testContact.Id, Type__c = FimbyConstants.NOTIF_EVENT_CHAT,
                Title__c = 'e', Body__c = 'b', Actor_Name__c = 'Jordan', Push_Status__c = 'Pending')
        };

        CapturingEchoMock mock = new CapturingEchoMock(true);
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        Map<String, Object> n = firstNotif(mock.capturedBody);
        Map<String, Object> data = (Map<String, Object>) n.get('data');
        String channelId = (String) data.get('channelId');
        System.assert(channelId != null && channelId.startsWith('messages'),
            'Aggregated message-style pushes land in the messages bucket, not activity: ' + channelId);
    }
}
