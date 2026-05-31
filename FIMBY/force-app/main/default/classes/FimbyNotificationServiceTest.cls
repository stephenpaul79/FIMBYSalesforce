@IsTest
public class FimbyNotificationServiceTest {

    @TestSetup
    static void setupTestData() {
        FimbyTestDataFactory.createCompleteTestSetup();
    }

    private static User getTestUser() {
        return [
            SELECT Id, ContactId
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

    /* ── New notification sets Push_Status = Pending when gate is open ──── */

    @IsTest
    static void testCreateNotification_GateOpen_SetsPending() {
        Contact testContact = getTestContact();

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id,
            'Response',
            'Sarah responded to your post',
            'I can help with your garden!',
            null,
            'Needs_Offers__c',
            '/asks-offers/test123',
            'Sarah Johnson'
        );
        Test.stopTest();

        Notification__c notif = [
            SELECT Id, Title__c, Type__c, Push_Status__c, Actor_Name__c, Read_Date__c
            FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        System.assertEquals('Response', notif.Type__c);
        System.assertEquals('Pending', notif.Push_Status__c, 'Gate is open (never pushed) so status should be Pending');
        System.assertEquals(null, notif.Read_Date__c, 'Should be unread');
    }

    /* ── Push disabled → null status ────────────────────────────────────── */

    @IsTest
    static void testCreateNotification_PushDisabled_SetsNull() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = testUser.Id, Push_Notifications_Enabled__c = false);
        }

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id,
            'Response',
            'Sarah responded',
            'Body',
            null,
            'Needs_Offers__c',
            '/test',
            'Sarah'
        );
        Test.stopTest();

        Notification__c notif = [
            SELECT Push_Status__c FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        System.assertEquals(null, notif.Push_Status__c, 'Push disabled → null status');
    }

    /* ── Type toggle off → null status ──────────────────────────────────── */

    @IsTest
    static void testCreateNotification_TypeToggleOff_SetsNull() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = testUser.Id, Push_Needs_Offers__c = false);
        }

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id,
            'Response',
            'Sarah responded',
            'Body',
            null,
            'Needs_Offers__c',
            '/test',
            'Sarah'
        );
        Test.stopTest();

        Notification__c notif = [
            SELECT Push_Status__c FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        System.assertEquals(null, notif.Push_Status__c, 'Type toggle off → null status');
    }

    /* ── Gate closed (already pushed today, no login since) → null ──────── */

    @IsTest
    static void testCreateNotification_GateClosed_SetsNull() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();

        Datetime recentPush = Datetime.now().addMinutes(-30);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(
                Id = testUser.Id,
                Last_Activity_Push_At__c = recentPush,
                Last_App_Open_At__c = recentPush.addHours(-1)
            );
        }

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id,
            'Response',
            'Sarah responded',
            'Body',
            null,
            'Needs_Offers__c',
            '/test',
            'Sarah'
        );
        Test.stopTest();

        Notification__c notif = [
            SELECT Push_Status__c FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        System.assertEquals(null, notif.Push_Status__c, 'Gate closed → null status');
    }

    /* ── A4: Events push category routes through Push_Events__c ──────────── */

    /**
     * Migration test: a user who silenced Asks & Offers (Push_Needs_Offers__c
     * = false) but kept Events on still receives event chat after the routing
     * change in PUSH_TYPE_MAP.
     */
    @IsTest
    static void testCreateNotification_EventChat_RoutesToPushEvents() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(
                Id = testUser.Id,
                Push_Notifications_Enabled__c = true,
                Push_Needs_Offers__c = false,
                Push_Events__c = true
            );
        }

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id,
            FimbyConstants.NOTIF_EVENT_CHAT,
            'Sarah replied in event chat',
            'See you Sunday!',
            null,
            'Needs_Offers__c',
            '/event/test',
            'Sarah'
        );
        Test.stopTest();

        Notification__c notif = [
            SELECT Push_Status__c FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        System.assertEquals('Pending', notif.Push_Status__c,
            'Event chat must respect Push_Events__c, not Push_Needs_Offers__c');
    }

    @IsTest
    static void testCreateNotification_EventChat_EventsToggleOff_SetsNull() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(
                Id = testUser.Id,
                Push_Notifications_Enabled__c = true,
                Push_Needs_Offers__c = true,
                Push_Events__c = false
            );
        }

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id,
            FimbyConstants.NOTIF_EVENT_CHAT,
            'Sarah replied in event chat',
            'See you Sunday!',
            null,
            'Needs_Offers__c',
            '/event/test',
            'Sarah'
        );
        Test.stopTest();

        Notification__c notif = [
            SELECT Push_Status__c FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        System.assertEquals(null, notif.Push_Status__c,
            'Push_Events__c off must suppress event chat');
    }

    /* ── A4: Security/safety bypass ──────────────────────────────────────── */

    /**
     * Forward-infrastructure test: SECURITY_BYPASS_PUSH_TYPES is EMPTY in
     * production (push always respects user preferences — urgent/safety
     * messaging rides email instead). This test registers a type via the
     * Test.isRunningTest()-gated hook to confirm the bypass code path still
     * works, so a future maintainer can rely on it without re-wiring. It must
     * NOT be read as evidence that any production type bypasses the toggle.
     */
    @IsTest
    static void testCreateNotification_SecurityBypass_OverridesAllToggles() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(
                Id = testUser.Id,
                Push_Notifications_Enabled__c = false,
                Push_Messages__c = false,
                Push_Needs_Offers__c = false,
                Push_Events__c = false,
                Push_Library__c = false,
                Push_Stories__c = false,
                Push_Reminders__c = false,
                Push_Bulk_Buy__c = false
            );
        }

        // Use a real Notification__c.Type__c picklist value so the insert
        // succeeds; the bypass-for-test method is gated on Test.isRunningTest()
        // so this can't accidentally leak into production behavior.
        String bypassType = FimbyConstants.NOTIF_RESPONSE;
        FimbyNotificationService.addSecurityBypassPushTypeForTest(bypassType);

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id,
            bypassType,
            'Suspicious login from new device',
            'If this was not you, please reset your password.',
            null,
            'Contact',
            '/settings',
            'FIMBY'
        );
        Test.stopTest();

        Notification__c notif = [
            SELECT Push_Status__c FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        System.assertEquals('Pending', notif.Push_Status__c,
            'Security bypass must push even when every toggle is off');
    }

    /* ── Guard: null recipient ───────────────────────────────────────────── */

    @IsTest
    static void testCreateNotificationNullRecipient() {
        Test.startTest();
        FimbyNotificationService.createNotification(
            null, 'Response', 'Test', 'Body', null, 'Test__c', '/test', 'Actor'
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Notification__c]);
    }

    /* ── Guard: blank title ──────────────────────────────────────────────── */

    @IsTest
    static void testCreateNotificationBlankTitle() {
        Contact testContact = getTestContact();

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id, 'Response', '', 'Body', null, 'Test__c', '/test', 'Actor'
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Notification__c]);
    }

    /* ── Bulk createNotifications sets Push_Status per recipient ────────── */

    @IsTest
    static void testCreateNotifications_SetsPushStatus() {
        Contact testContact = getTestContact();

        List<Notification__c> notifications = new List<Notification__c>{
            new Notification__c(
                Contact__c = testContact.Id,
                Type__c = 'Response',
                Title__c = 'Notification 1',
                Body__c = 'Body 1',
                Action_URL__c = '/test/1'
            ),
            new Notification__c(
                Contact__c = testContact.Id,
                Type__c = 'Comment',
                Title__c = 'Notification 2',
                Body__c = 'Body 2',
                Action_URL__c = '/test/2'
            )
        };

        Test.startTest();
        FimbyNotificationService.createNotifications(notifications);
        Test.stopTest();

        List<Notification__c> created = [
            SELECT Id, Push_Status__c FROM Notification__c WHERE Contact__c = :testContact.Id
        ];
        System.assertEquals(2, created.size());
        for (Notification__c n : created) {
            System.assertEquals('Pending', n.Push_Status__c, 'Gate open → Pending');
        }
    }

    /* ── Empty / null list guards ────────────────────────────────────────── */

    @IsTest
    static void testCreateNotificationsEmptyList() {
        Test.startTest();
        FimbyNotificationService.createNotifications(new List<Notification__c>());
        FimbyNotificationService.createNotifications(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Notification__c]);
    }

    /* ── All notification type mappings resolve without error ─────────────── */

    @IsTest
    static void testAllNotificationTypesMappedToPush() {
        Contact testContact = getTestContact();

        List<String> allTypes = new List<String>{
            'Response', 'Comment', 'Lending_Request', 'Loan_Approved',
            'Extension_Request', 'Extension_Approved', 'Overdue_Reminder',
            'Item_Returned', 'Bulk_Buy_Reservation', 'Bulk_Buy_Status',
            'Bulk_Buy_Pickup', 'Message', 'Event_Chat', 'Event_Reminder'
        };

        Test.startTest();
        for (String t : allTypes) {
            FimbyNotificationService.createNotification(
                testContact.Id, t, 'Title for ' + t, 'Body',
                null, 'Test__c', '/test', 'Actor'
            );
        }
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Notification__c WHERE Contact__c = :testContact.Id];
        System.assertEquals(allTypes.size(), count, 'All types should create notifications');
    }

    /* ── Same type + related record creates separate rows (no aggregation) ── */

    @IsTest
    static void testDuplicateTypeCreatesIndividualRows() {
        Contact testContact = getTestContact();
        Id fakeRelatedId = testContact.Id;

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id, 'Response', 'Alice responded to your need',
            'I can help!', fakeRelatedId, 'Needs_Offers__c', '/asks-offers/test', 'Alice'
        );
        FimbyNotificationService.createNotification(
            testContact.Id, 'Response', 'Bob responded to your need',
            'Me too!', fakeRelatedId, 'Needs_Offers__c', '/asks-offers/test', 'Bob'
        );
        Test.stopTest();

        List<Notification__c> results = [
            SELECT Title__c FROM Notification__c
            WHERE Contact__c = :testContact.Id AND Type__c = 'Response'
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(2, results.size(), 'Each event should create its own row');
        System.assert(results[0].Title__c.contains('Alice'));
        System.assert(results[1].Title__c.contains('Bob'));
    }

    /* ── Second notification after gate reopen gets its own Pending row ──── */

    @IsTest
    static void testSecondNotificationAfterGateReopen() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();
        Id fakeRelatedId = testContact.Id;

        Datetime oldPush = Datetime.now().addMinutes(-30);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(
                Id = testUser.Id,
                Last_Activity_Push_At__c = oldPush,
                Last_App_Open_At__c = oldPush.addHours(-1)
            );
        }

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id, 'Response', 'Alice responded',
            'Body', fakeRelatedId, 'Needs_Offers__c', '/test', 'Alice'
        );

        Notification__c first = [
            SELECT Push_Status__c FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        System.assertEquals(null, first.Push_Status__c, 'Gate closed → null');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = testUser.Id, Last_App_Open_At__c = Datetime.now());
        }

        FimbyNotificationService.createNotification(
            testContact.Id, 'Response', 'Bob responded',
            'Body', fakeRelatedId, 'Needs_Offers__c', '/test', 'Bob'
        );
        Test.stopTest();

        List<Notification__c> results = [
            SELECT Push_Status__c, Title__c FROM Notification__c
            WHERE Contact__c = :testContact.Id ORDER BY CreatedDate ASC
        ];
        System.assertEquals(2, results.size(), 'Two separate rows');
        System.assertEquals(null, results[0].Push_Status__c, 'First row stays null (gate was closed)');
        System.assertEquals('Pending', results[1].Push_Status__c, 'Second row is Pending (gate reopened)');
    }

    /* ── Fatigue dampener: gate stays closed if Last_App_Open too old ──── */

    @IsTest
    static void testFatigueDampener_GateStaysClosed() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(
                Id = testUser.Id,
                Last_Activity_Push_At__c = Datetime.now().addDays(-2),
                Last_App_Open_At__c = Datetime.now().addDays(-10)
            );
        }

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id, 'Response', 'Sarah responded', 'Body',
            null, 'Needs_Offers__c', '/test', 'Sarah'
        );
        Test.stopTest();

        Notification__c notif = [
            SELECT Push_Status__c FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        System.assertEquals(null, notif.Push_Status__c, 'Fatigue dampener → gate stays closed');
    }

    /* ── skipPush overload → null Push_Status regardless of gate ──────── */

    @IsTest
    static void testCreateNotification_SkipPush_SetsNull() {
        Contact testContact = getTestContact();

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id,
            'Response',
            'Someone withdrew from your event',
            'Body',
            null,
            'Needs_Offers__c',
            '/test',
            'Sarah',
            true
        );
        Test.stopTest();

        Notification__c notif = [
            SELECT Push_Status__c FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        System.assertEquals(null, notif.Push_Status__c,
            'skipPush = true → null Push_Status regardless of gate state');
    }

    /* ── NOTIF_EVENT_CHAT maps to Activity gate ────────────────────────── */

    @IsTest
    static void testEventChatType_MapsToActivityGate() {
        String gateType = FimbyNotificationService.GATE_TYPE_MAP.get(FimbyConstants.NOTIF_EVENT_CHAT);
        System.assertEquals('ACTIVITY', gateType,
            'NOTIF_EVENT_CHAT should map to ACTIVITY gate (not DM)');
    }

    /* ── Bulk from requests: creates individual rows ──────────────────── */

    @IsTest
    static void testBulkFromRequests_CreatesIndividualRows() {
        Contact testContact = getTestContact();
        Id fakeRelatedId = testContact.Id;

        List<FimbyNotificationService.NotificationRequest> requests =
            new List<FimbyNotificationService.NotificationRequest>{
                new FimbyNotificationService.NotificationRequest(
                    testContact.Id, 'Response', 'Bob responded', 'Me too!',
                    fakeRelatedId, 'Needs_Offers__c', '/asks-offers/test', 'Bob'
                ),
                new FimbyNotificationService.NotificationRequest(
                    testContact.Id, 'Response', 'Carol responded', 'Count me in!',
                    fakeRelatedId, 'Needs_Offers__c', '/asks-offers/test', 'Carol'
                )
            };

        Test.startTest();
        FimbyNotificationService.createNotificationsFromRequests(requests);
        Test.stopTest();

        List<Notification__c> results = [
            SELECT Title__c, Push_Status__c
            FROM Notification__c WHERE Contact__c = :testContact.Id AND Type__c = 'Response'
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(2, results.size(), 'Each request creates its own row');
        System.assert(results[0].Title__c.contains('Bob'));
        System.assert(results[1].Title__c.contains('Carol'));
    }

    /* ── Bulk from requests: applies push gate check ─────────────────── */

    @IsTest
    static void testBulkFromRequests_AppliesPushGate() {
        Contact testContact = getTestContact();

        List<FimbyNotificationService.NotificationRequest> requests =
            new List<FimbyNotificationService.NotificationRequest>{
                new FimbyNotificationService.NotificationRequest(
                    testContact.Id, 'Comment', 'Someone commented', 'Nice story!',
                    null, 'Story__c', '/stories/test', 'Dave'
                )
            };

        Test.startTest();
        FimbyNotificationService.createNotificationsFromRequests(requests);
        Test.stopTest();

        Notification__c notif = [
            SELECT Title__c, Push_Status__c
            FROM Notification__c WHERE Contact__c = :testContact.Id AND Type__c = 'Comment' LIMIT 1
        ];
        System.assertEquals('Pending', notif.Push_Status__c, 'Gate open → Pending');
    }

    /* ── Bulk from requests: empty/null guards ──────────────────────── */

    @IsTest
    static void testBulkFromRequests_EmptyList() {
        Test.startTest();
        FimbyNotificationService.createNotificationsFromRequests(
            new List<FimbyNotificationService.NotificationRequest>()
        );
        FimbyNotificationService.createNotificationsFromRequests(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Notification__c]);
    }

    /* ── DM gate independent from Activity gate ───────────────────────── */

    @IsTest
    static void testDMGateIndependent() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();

        Datetime recentPush = Datetime.now().addMinutes(-30);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(
                Id = testUser.Id,
                Last_Activity_Push_At__c = recentPush,
                Last_DM_Push_At__c = null,
                Last_App_Open_At__c = recentPush.addHours(-1)
            );
        }

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id, 'Response', 'Activity notif', 'Body',
            null, 'Needs_Offers__c', '/test', 'Actor'
        );
        FimbyNotificationService.createNotification(
            testContact.Id, 'Message', 'DM notif', 'Body',
            null, 'Conversation__c', '/messages', 'Actor'
        );
        Test.stopTest();

        Notification__c actNotif = [
            SELECT Push_Status__c FROM Notification__c
            WHERE Contact__c = :testContact.Id AND Type__c = 'Response' LIMIT 1
        ];
        Notification__c dmNotif = [
            SELECT Push_Status__c FROM Notification__c
            WHERE Contact__c = :testContact.Id AND Type__c = 'Message' LIMIT 1
        ];

        System.assertEquals(null, actNotif.Push_Status__c, 'Activity gate closed');
        System.assertEquals('Pending', dmNotif.Push_Status__c, 'DM gate open (never pushed)');
    }

    /* ── Actor + URL + body persist on the notification row ──────────────── */

    @IsTest
    static void testCreateNotification_PersistsActorUrlAndBody() {
        Contact testContact = getTestContact();
        String url = FimbySettings.getUrl('Library_List');
        System.assert(String.isNotBlank(url), 'Library_List URL CMDT should be deployed');

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id,
            FimbyConstants.NOTIF_VOUCH_APPROVED,
            'You have been welcomed in',
            'Sam vouched for you. The library is open.',
            null,
            'Vouch_Record__c',
            url,
            'Sam Rivera'
        );
        Test.stopTest();

        Notification__c n = [
            SELECT Title__c, Body__c, Action_URL__c, Actor_Name__c, Type__c
            FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        System.assertEquals('You have been welcomed in', n.Title__c, 'Title persists');
        System.assertEquals('Sam vouched for you. The library is open.', n.Body__c, 'Body persists');
        System.assertEquals(url, n.Action_URL__c, 'Action URL persists from FimbySettings.getUrl()');
        System.assertEquals('Sam Rivera', n.Actor_Name__c, 'Actor persists');
        System.assert(n.Action_URL__c.contains('/library-list'), 'Action URL resolves to the library list route');
    }

    /* ── Vouch_* types respect the push master toggle (no push bypass) ─────── */

    @IsTest
    static void testVouchTypes_RespectPushGate_WhenDisabled() {
        Contact testContact = getTestContact();
        User testUser = getTestUser();

        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(
                Id = testUser.Id,
                Push_Notifications_Enabled__c = false
            );
        }

        Test.startTest();
        FimbyNotificationService.createNotification(
            testContact.Id,
            FimbyConstants.NOTIF_VOUCH_APPROVED,
            'You have been welcomed in',
            'The library is open.',
            null,
            'Vouch_Record__c',
            FimbySettings.getUrl('Library_List'),
            'Sam Rivera'
        );
        Test.stopTest();

        Notification__c notif = [
            SELECT Push_Status__c, Type__c
            FROM Notification__c WHERE Contact__c = :testContact.Id LIMIT 1
        ];
        // Push never bypasses user preferences. The in-app notification is still
        // created; urgent vouch info reaches the user via the email lane (which
        // keeps its own SECURITY_BYPASS_TYPES).
        System.assertEquals(
            null,
            notif.Push_Status__c,
            'Vouch push must be suppressed when the master push toggle is off'
        );
    }
}
