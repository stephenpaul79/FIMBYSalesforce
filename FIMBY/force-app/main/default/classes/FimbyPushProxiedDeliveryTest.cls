/**
 * @description Covers push delivery for inboxes whose Contact has no login of their own —
 * elder supportees, organization contacts, and parent-proxied children.
 *
 * Two properties matter most here and are asserted directly:
 *   1. The alert actually reaches the neighbour approved to act for that inbox.
 *   2. The card names WHOSE inbox it is. "Aisha messaged you" is wrong when Aisha
 *      messaged the user's child, and it hides which identity needs attention.
 */
@IsTest
private class FimbyPushProxiedDeliveryTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);

        Contact guardian = new Contact(
            FirstName = 'Sarah', LastName = 'Guardian', AccountId = nh.Id);
        Contact child = new Contact(
            FirstName = 'Maya', LastName = 'Proxied', AccountId = nh.Id);
        insert new List<Contact>{ guardian, child };

        FimbyTestDataFactory.createCommunityUser(guardian.Id, null, true);

        // The child deliberately gets NO User — that absence is what makes this a
        // proxied inbox and forces the fan-out path.
        insert new Support_Relationship__c(
            Contact__c = guardian.Id,
            Related_Contact__c = child.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id,
            Consent_Method__c = 'Written'
        );
    }

    /**
     * Approving a support relationship can itself notify the supporter, so each
     * batch test starts from a clean slate — otherwise setup rows would ride along
     * in the cycle and skew the payload counts and badge assertions.
     */
    private static void clearNotifications() {
        delete [SELECT Id FROM Notification__c];
    }

    private static Contact childContact() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Proxied' LIMIT 1];
    }

    private static User guardianUser() {
        Contact g = [SELECT Id FROM Contact WHERE LastName = 'Guardian' LIMIT 1];
        return [SELECT Id, ContactId FROM User WHERE ContactId = :g.Id LIMIT 1];
    }

    private static Map<String, Object> firstNotif(String body) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        List<Object> notifs = (List<Object>) parsed.get('notifications');
        return (Map<String, Object>) notifs[0];
    }

    private static List<Object> allNotifs(String body) {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
        return (List<Object>) parsed.get('notifications');
    }

    /* =================================================================
     * End-to-end fan-out
     * ================================================================= */

    /**
     * The whole point of the feature: an alert for a Contact who cannot log in
     * still reaches a real device, and it is addressed to the guardian's User.
     */
    @IsTest
    static void alertForALoginLessChildReachesTheGuardiansDevice() {
        clearNotifications();
        Contact child = childContact();
        User guardian = guardianUser();

        insert new Notification__c(
            Contact__c = child.Id,
            Type__c = FimbyConstants.NOTIF_MESSAGE,
            Title__c = 'sent a message',
            Body__c = 'Are you coming Saturday?',
            Actor_Name__c = 'Aisha Bello',
            Push_Status__c = 'Pending'
        );

        CapturingMock mock = new CapturingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assert(String.isNotBlank(mock.capturedBody),
            'A notification on a login-less contact must still produce a push');
        Map<String, Object> payload = firstNotif(mock.capturedBody);
        System.assertEquals(String.valueOf(guardian.Id), payload.get('user_id'),
            'The push must be addressed to the approved guardian, not the child');
    }

    /**
     * A single audible notification keeps its real copy and deep link, and the
     * Action_URL__c is passed through untouched — that is what carries ?actAs=
     * so the tap lands in the child's identity rather than the parent's.
     */
    @IsTest
    static void singleAlertPassesTheIdentityAwareDeepLinkThrough() {
        clearNotifications();
        Contact child = childContact();

        insert new Notification__c(
            Contact__c = child.Id,
            Type__c = FimbyConstants.NOTIF_MESSAGE,
            Title__c = 'sent a message',
            Body__c = 'Are you coming Saturday?',
            Actor_Name__c = 'Aisha Bello',
            Action_URL__c = '/conversation?id=abc&actAs=' + child.Id,
            Push_Status__c = 'Pending'
        );

        CapturingMock mock = new CapturingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        Map<String, Object> payload = firstNotif(mock.capturedBody);
        Map<String, Object> data = (Map<String, Object>) payload.get('data');
        System.assertEquals('/conversation?id=abc&actAs=' + child.Id, data.get('action_url'),
            'The acting identity must survive into the push payload');
    }

    /**
     * With several unread rows the card becomes an aggregate, and that is exactly
     * where second-person copy would lie. It must name the child instead.
     */
    @IsTest
    static void aggregateCardNamesTheChildRatherThanSayingYou() {
        clearNotifications();
        Contact child = childContact();

        insert new List<Notification__c>{
            new Notification__c(
                Contact__c = child.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'sent a message', Body__c = 'b',
                Actor_Name__c = 'Aisha Bello', Push_Status__c = 'Pending'),
            new Notification__c(
                Contact__c = child.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'sent a message', Body__c = 'b',
                Actor_Name__c = 'Aisha Bello', Push_Status__c = 'Pending')
        };

        CapturingMock mock = new CapturingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        String title = (String) firstNotif(mock.capturedBody).get('title');
        System.assertEquals('Aisha Bello messaged Maya', title,
            'A proxied aggregate must name the child, never "you"');
    }

    /**
     * One login, two inboxes. The badge is what the OS icon shows, so it has to
     * count everything the person is responsible for or the icon contradicts the
     * bell.
     */
    @IsTest
    static void badgeCountsEveryInboxTheGuardianServes() {
        clearNotifications();
        Contact child = childContact();
        User guardian = guardianUser();

        insert new List<Notification__c>{
            new Notification__c(
                Contact__c = child.Id, Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'sent a message', Body__c = 'b',
                Actor_Name__c = 'Aisha Bello', Push_Status__c = 'Pending'),
            new Notification__c(
                Contact__c = guardian.ContactId, Type__c = FimbyConstants.NOTIF_MESSAGE,
                Title__c = 'sent a message', Body__c = 'b',
                Actor_Name__c = 'Aisha Bello', Push_Status__c = 'Pending')
        };

        CapturingMock mock = new CapturingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        List<Object> notifs = allNotifs(mock.capturedBody);
        System.assertEquals(1, notifs.size(),
            'Two inboxes served by one login must collapse into a single buzz');

        Map<String, Object> payload = (Map<String, Object>) notifs[0];
        System.assertEquals(2, (Integer) payload.get('badge'),
            'The badge must sum unread across every inbox the guardian serves');
        System.assertEquals('New messages for you and Maya', (String) payload.get('title'),
            'A mixed cycle names both audiences instead of guessing one');
    }

    /* =================================================================
     * Ledger-driven retry
     * ================================================================= */

    /**
     * A guardian already marked Sent in the ledger must not be pushed again, even
     * though the row is still Pending overall for the other guardian's sake.
     */
    @IsTest
    static void aRecipientAlreadyDeliveredIsNotPushedAgain() {
        clearNotifications();
        Contact child = childContact();
        User guardian = guardianUser();

        FimbySupportedIdentityDelivery.Ledger ledger =
            new FimbySupportedIdentityDelivery.Ledger(child.Id);
        ledger.r.add(new FimbySupportedIdentityDelivery.Recipient(
            guardian.Id, FimbySupportedIdentityDelivery.SENT, null));

        // System mode: Delivery_State__c is internal delivery plumbing that no
        // profile is meant to edit, so the seed writes it the same way the
        // notification pipeline does rather than depending on admin FLS.
        Database.insert(new Notification__c(
            Contact__c = child.Id,
            Type__c = FimbyConstants.NOTIF_MESSAGE,
            Title__c = 'sent a message', Body__c = 'b',
            Actor_Name__c = 'Aisha Bello',
            Push_Status__c = 'Pending',
            Delivery_State__c = FimbySupportedIdentityDelivery.serializeLedger(ledger)
        ), AccessLevel.SYSTEM_MODE);

        CapturingMock mock = new CapturingMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        System.assert(String.isBlank(mock.capturedBody),
            'A recipient already recorded as Sent must not be pushed a second time');
    }

    /**
     * The queueable writes each recipient's outcome into the ledger and recomputes
     * the aggregate from the whole ledger, so a delivered guardian is never
     * flattened away by an undelivered one.
     */
    @IsTest
    static void deliveryOutcomeIsRecordedPerRecipient() {
        clearNotifications();
        Contact child = childContact();
        User guardian = guardianUser();

        FimbySupportedIdentityDelivery.Ledger ledger =
            new FimbySupportedIdentityDelivery.Ledger(child.Id);
        ledger.r.add(new FimbySupportedIdentityDelivery.Recipient(
            guardian.Id, FimbySupportedIdentityDelivery.PENDING, null));
        // A second recipient who is not part of this slice, standing in for the
        // other guardian whose delivery is still owed.
        ledger.r.add(new FimbySupportedIdentityDelivery.Recipient(
            UserInfo.getUserId(), FimbySupportedIdentityDelivery.PENDING, null));

        Notification__c notif = new Notification__c(
            Contact__c = child.Id,
            Type__c = FimbyConstants.NOTIF_MESSAGE,
            Title__c = 'sent a message', Body__c = 'b',
            Actor_Name__c = 'Aisha Bello',
            Push_Status__c = 'Pending',
            Delivery_State__c = FimbySupportedIdentityDelivery.serializeLedger(ledger)
        );
        Database.insert(notif, AccessLevel.SYSTEM_MODE);

        Test.setMock(HttpCalloutMock.class, new CapturingMock());

        Test.startTest();
        new FimbyPushBatchJob().execute(null);
        Test.stopTest();

        Notification__c after = [
            SELECT Push_Status__c, Delivery_State__c
            FROM Notification__c WHERE Id = :notif.Id
            WITH SYSTEM_MODE
        ];

        FimbySupportedIdentityDelivery.Ledger reloaded =
            FimbySupportedIdentityDelivery.parseLedger(after.Delivery_State__c);
        System.assertNotEquals(null, reloaded, 'The ledger must survive the delivery pass');
        System.assertEquals(FimbySupportedIdentityDelivery.SENT,
            reloaded.forUser(guardian.Id).p,
            'The guardian who was pushed must be recorded as delivered');
        System.assertEquals(FimbySupportedIdentityDelivery.PENDING,
            reloaded.forUser(UserInfo.getUserId()).p,
            'A recipient outside this slice must keep their outstanding claim');
        System.assertEquals('Pending', after.Push_Status__c,
            'The row stays queued while any recipient is still owed a delivery');
    }

    /* =================================================================
     * Copy rules
     * ================================================================= */

    @IsTest
    static void recipientLabelDescribesWhoTheCycleIsFor() {
        Id own = childContact().Id;
        Id childA = guardianUser().ContactId;
        Map<Id, String> names = new Map<Id, String>{ childA => 'Maya' };

        System.assertEquals(null,
            FimbyPushBatchJob.buildRecipientLabel(
                new Set<Id>{ own }, new Set<Id>(), names),
            'An ordinary single-identity cycle keeps the familiar "you" copy');

        System.assertEquals('Maya',
            FimbyPushBatchJob.buildRecipientLabel(
                new Set<Id>{ childA }, new Set<Id>{ childA }, names),
            'A cycle wholly about one child names that child');

        System.assertEquals('you and Maya',
            FimbyPushBatchJob.buildRecipientLabel(
                new Set<Id>{ own, childA }, new Set<Id>{ childA }, names),
            'A mixed cycle names both audiences');

        System.assertEquals('someone you help',
            FimbyPushBatchJob.buildRecipientLabel(
                new Set<Id>{ childA }, new Set<Id>{ childA }, new Map<Id, String>()),
            'A missing name degrades to a warm placeholder rather than a blank');
    }

    @IsTest
    static void aggregateTitlesStayGrammaticalAndHonest() {
        List<String> one = new List<String>{ 'Aisha' };
        List<String> two = new List<String>{ 'Aisha', 'Jordan' };

        System.assertEquals('Aisha messaged Maya',
            FimbyPushBatchJob.buildAggregateTitle(one, 'DM', 'Maya', true));
        System.assertEquals('Aisha and Jordan messaged Maya',
            FimbyPushBatchJob.buildAggregateTitle(two, 'DM', 'Maya', true));
        System.assertEquals('Aisha posted in Maya\'s neighbourhood',
            FimbyPushBatchJob.buildAggregateTitle(one, 'ACTIVITY', 'Maya', true));

        // No single actor sentence can honestly describe two different inboxes,
        // so a mixed cycle switches to audience-led phrasing.
        System.assertEquals('New messages for you and Maya',
            FimbyPushBatchJob.buildAggregateTitle(one, 'DM', 'you and Maya', false));
        System.assertEquals('Neighbourhood activity for you and Maya',
            FimbyPushBatchJob.buildAggregateTitle(one, 'ACTIVITY', 'you and Maya', false));
        System.assertEquals('Messages and activity for you and Maya',
            FimbyPushBatchJob.buildAggregateTitle(two, 'BOTH', 'you and Maya', false));
        System.assertEquals('New messages for Maya',
            FimbyPushBatchJob.buildAggregateTitle(new List<String>(), 'DM', 'Maya', true),
            'With no usable actor name the copy falls back to naming the audience');

        // The unproxied path must be untouched by any of the above.
        System.assertEquals('Aisha messaged you',
            FimbyPushBatchJob.buildAggregateTitle(one, 'DM'));
        System.assertEquals('Aisha posted in your neighbourhood',
            FimbyPushBatchJob.buildAggregateTitle(one, 'ACTIVITY'));
    }

    @IsTest
    static void pushStateFallsBackToTheChannelStatusWithoutALedger() {
        Notification__c plain = new Notification__c(Push_Status__c = 'Pending');
        System.assertEquals('Pending',
            FimbyPushBatchJob.pushStateFor(plain, UserInfo.getUserId()),
            'A row with no ledger uses the plain channel status');

        Notification__c garbage = new Notification__c(
            Push_Status__c = 'Pending', Delivery_State__c = 'not json');
        System.assertEquals('Pending',
            FimbyPushBatchJob.pushStateFor(garbage, UserInfo.getUserId()),
            'An unreadable ledger must not strand the row');

        FimbySupportedIdentityDelivery.Ledger ledger =
            new FimbySupportedIdentityDelivery.Ledger(null);
        ledger.r.add(new FimbySupportedIdentityDelivery.Recipient(
            UserInfo.getUserId(), FimbySupportedIdentityDelivery.SENT, null));
        Notification__c withLedger = new Notification__c(
            Push_Status__c = 'Pending',
            Delivery_State__c = FimbySupportedIdentityDelivery.serializeLedger(ledger));

        System.assertEquals(FimbySupportedIdentityDelivery.SENT,
            FimbyPushBatchJob.pushStateFor(withLedger, UserInfo.getUserId()),
            'A ledgered row reports that recipient\'s own state');
        System.assertEquals(null,
            FimbyPushBatchJob.pushStateFor(withLedger, guardianUser().Id),
            'A user absent from the ledger is not a recipient of that row');
    }

    /**
     * Stands in for a healthy bridge: captures what we sent and accepts every card,
     * echoing one result per entry keyed by user_id exactly as the real endpoint does.
     */
    private class CapturingMock implements HttpCalloutMock {
        public String capturedBody;

        public HTTPResponse respond(HTTPRequest req) {
            capturedBody = req.getBody();
            List<String> results = new List<String>();
            try {
                Map<String, Object> parsed =
                    (Map<String, Object>) JSON.deserializeUntyped(capturedBody);
                for (Object entry : (List<Object>) parsed.get('notifications')) {
                    Object uid = ((Map<String, Object>) entry).get('user_id');
                    if (uid != null) {
                        results.add('{"user_id":"' + uid + '","accepted":true}');
                    }
                }
            } catch (Exception ignored) {
                // A malformed body is the assertion's problem, not the mock's.
            }
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"sent":' + results.size() + ',"success":true,"results":['
                + String.join(results, ',') + ']}');
            return res;
        }
    }
}
