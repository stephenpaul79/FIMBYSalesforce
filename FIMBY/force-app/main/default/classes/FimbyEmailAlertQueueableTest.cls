@IsTest
private class FimbyEmailAlertQueueableTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        FimbyTestDataFactory.createCommunityUser(c.Id, null, true);
    }

    static Contact getTestContact() {
        return [SELECT Id FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1];
    }

    static User getTestUser() {
        return [SELECT Id, ContactId, Email_Alerts_Enabled__c FROM User
                WHERE ContactId != null AND Profile.Name = 'Customer Community User - Mobile App'
                AND UserName LIKE '%@testorg.com' LIMIT 1];
    }

    private static void patchTestUser(User u) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update u;
        }
    }

    @IsTest
    static void execute_emptyMap_exitsCleanly() {
        Test.startTest();
        new FimbyEmailAlertQueueable(new Map<Id, List<Notification__c>>()).execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_nullMap_exitsCleanly() {
        Test.startTest();
        new FimbyEmailAlertQueueable(null).execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_sendsViaBrandedShell() {
        Contact c = getTestContact();
        User u = getTestUser();
        u.Email_Alerts_Enabled__c = true;
        patchTestUser(u);

        List<Notification__c> notifs = FimbyTestDataFactory.createNotifications(
            c.Id, 'Message', 'Processing', 2, true
        );

        FimbyEmailAlertQueueable.oweaCached = u.Id;

        Map<Id, List<Notification__c>> byContact = new Map<Id, List<Notification__c>>();
        byContact.put(c.Id, notifs);

        Test.startTest();
        new FimbyEmailAlertQueueable(byContact).execute(null);
        Test.stopTest();

        for (Notification__c n : [SELECT Email_Status__c FROM Notification__c WHERE Id IN :notifs]) {
            System.assertEquals('Sent', n.Email_Status__c, 'Should send via branded shell');
        }
    }

    @IsTest
    static void execute_eventReminder_rechecksEventsToggleWithoutQueryException() {
        Contact c = getTestContact();
        User u = getTestUser();
        u.Email_Alerts_Enabled__c = true;
        u.Email_Alert_Events__c = true;
        patchTestUser(u);

        List<Notification__c> notifs = FimbyTestDataFactory.createNotifications(
            c.Id, FimbyConstants.NOTIF_EVENT_REMINDER, 'Processing', 1, true
        );

        FimbyEmailAlertQueueable.oweaCached = u.Id;

        Map<Id, List<Notification__c>> byContact = new Map<Id, List<Notification__c>>();
        byContact.put(c.Id, notifs);

        Test.startTest();
        new FimbyEmailAlertQueueable(byContact).execute(null);
        Test.stopTest();

        Notification__c updated = [SELECT Email_Status__c FROM Notification__c WHERE Id = :notifs[0].Id];
        System.assertEquals('Sent', updated.Email_Status__c,
            'Event reminder send-time toggle check requires Email_Alert_Events__c on the User query');
    }

    @IsTest
    static void execute_singleMessage_sendsSingleSubject() {
        Contact c = getTestContact();
        User u = getTestUser();
        u.Email_Alerts_Enabled__c = true;
        patchTestUser(u);

        List<Notification__c> notifs = FimbyTestDataFactory.createNotifications(
            c.Id, 'Message', 'Processing', 1, true
        );

        FimbyEmailAlertQueueable.oweaCached = u.Id;

        Map<Id, List<Notification__c>> byContact = new Map<Id, List<Notification__c>>();
        byContact.put(c.Id, notifs);

        Test.startTest();
        new FimbyEmailAlertQueueable(byContact).execute(null);
        Test.stopTest();

        Notification__c updated = [SELECT Email_Status__c FROM Notification__c WHERE Id = :notifs[0].Id];
        System.assertEquals('Sent', updated.Email_Status__c,
            'Should be Sent with valid user and test HTML');
    }

    @IsTest
    static void execute_multipleMessages_usesGroupSubject() {
        Contact c = getTestContact();
        User u = getTestUser();
        u.Email_Alerts_Enabled__c = true;
        patchTestUser(u);

        List<Notification__c> notifs = FimbyTestDataFactory.createNotifications(
            c.Id, 'Message', 'Processing', 3, true
        );

        FimbyEmailAlertQueueable.oweaCached = u.Id;

        Map<Id, List<Notification__c>> byContact = new Map<Id, List<Notification__c>>();
        byContact.put(c.Id, notifs);

        Test.startTest();
        new FimbyEmailAlertQueueable(byContact).execute(null);
        Test.stopTest();

        for (Notification__c n : [SELECT Email_Status__c FROM Notification__c WHERE Id IN :notifs]) {
            System.assertEquals('Sent', n.Email_Status__c);
        }
    }

    @IsTest
    static void execute_mixedTypes_usesGenericSubject() {
        Contact c = getTestContact();
        User u = getTestUser();
        u.Email_Alerts_Enabled__c = true;
        patchTestUser(u);

        Notification__c n1 = FimbyTestDataFactory.createNotifications(c.Id, 'Message', 'Processing', 1, true)[0];
        Notification__c n2 = FimbyTestDataFactory.createNotifications(c.Id, 'Lending_Request', 'Processing', 1, true)[0];

        FimbyEmailAlertQueueable.oweaCached = u.Id;

        Map<Id, List<Notification__c>> byContact = new Map<Id, List<Notification__c>>();
        byContact.put(c.Id, new List<Notification__c>{ n1, n2 });

        Test.startTest();
        new FimbyEmailAlertQueueable(byContact).execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_responseAlert_sendsViaBrandedShell() {
        Contact c = getTestContact();
        User u = getTestUser();
        u.Email_Alerts_Enabled__c = true;
        patchTestUser(u);

        List<Notification__c> notifs = FimbyTestDataFactory.createNotifications(
            c.Id, 'Response', 'Processing', 1, true
        );

        FimbyEmailAlertQueueable.oweaCached = u.Id;

        Map<Id, List<Notification__c>> byContact = new Map<Id, List<Notification__c>>();
        byContact.put(c.Id, notifs);

        Test.startTest();
        new FimbyEmailAlertQueueable(byContact).execute(null);
        Test.stopTest();

        Notification__c updated = [SELECT Email_Status__c FROM Notification__c WHERE Id = :notifs[0].Id];
        System.assertEquals('Sent', updated.Email_Status__c, 'Should send via branded shell');
    }

    @IsTest
    static void enrichNotifications_nullList_returnsEmptyMap() {
        Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> result =
            FimbyEmailAlertQueueable.enrichNotifications(null);
        System.assertEquals(0, result.size(), 'Null input should return empty map');
    }

    @IsTest
    static void enrichNotifications_emptyList_returnsEmptyMap() {
        Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> result =
            FimbyEmailAlertQueueable.enrichNotifications(new List<Notification__c>());
        System.assertEquals(0, result.size(), 'Empty input should return empty map');
    }

    @IsTest
    static void enrichNotifications_noRelatedRecords_returnsEmptyMap() {
        Notification__c n = new Notification__c(
            Title__c = 'No related', Type__c = 'Message'
        );
        Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> result =
            FimbyEmailAlertQueueable.enrichNotifications(new List<Notification__c>{ n });
        System.assertEquals(0, result.size(), 'No related record IDs should return empty');
    }

    @IsTest
    static void enrichNotifications_withNeedsOffers_returnsEnrichment() {
        Account nh = [SELECT Id FROM Account LIMIT 1];
        Contact c = getTestContact();
        List<Needs_Offers__c> posts = FimbyTestDataFactory.createAskOfferItems(nh.Id, c.Id, 1, true);
        Needs_Offers__c post = posts[0];

        Notification__c n = new Notification__c(
            Title__c = 'Post notif', Type__c = 'Response',
            Related_Record_Id__c = String.valueOf(post.Id),
            Related_Record_Type__c = 'Needs_Offers__c'
        );
        Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> result =
            FimbyEmailAlertQueueable.enrichNotifications(new List<Notification__c>{ n });
        System.assert(result.containsKey(String.valueOf(post.Id)), 'Should have enrichment for post');
    }

    @IsTest
    static void enrichNotifications_withLibraryItem_returnsEnrichment() {
        Account nh = [SELECT Id FROM Account LIMIT 1];
        Contact c = getTestContact();
        List<Library_Item__c> items = FimbyTestDataFactory.createLibraryItems(nh.Id, c.Id, 1, true);

        Notification__c n = new Notification__c(
            Title__c = 'Library notif', Type__c = 'Lending_Request',
            Related_Record_Id__c = String.valueOf(items[0].Id),
            Related_Record_Type__c = 'Library_Item__c'
        );
        Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> result =
            FimbyEmailAlertQueueable.enrichNotifications(new List<Notification__c>{ n });
        System.assert(result.containsKey(String.valueOf(items[0].Id)), 'Should have enrichment for library item');
    }

    @IsTest
    static void enrichNotifications_withStory_returnsEnrichment() {
        Account nh = [SELECT Id FROM Account LIMIT 1];
        Contact c = getTestContact();
        List<Story__c> stories = FimbyTestDataFactory.createStories(nh.Id, c.Id, 1, true);

        Notification__c n = new Notification__c(
            Title__c = 'Story notif', Type__c = 'Comment',
            Related_Record_Id__c = String.valueOf(stories[0].Id),
            Related_Record_Type__c = 'Story__c'
        );
        Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> result =
            FimbyEmailAlertQueueable.enrichNotifications(new List<Notification__c>{ n });
        System.assert(result.containsKey(String.valueOf(stories[0].Id)), 'Should have enrichment for story');
    }

    @IsTest
    static void enrichNotifications_withResponse_returnsEnrichment() {
        Account nh = [SELECT Id FROM Account LIMIT 1];
        Contact c = getTestContact();
        List<Needs_Offers__c> posts = FimbyTestDataFactory.createAskOfferItems(nh.Id, c.Id, 1, true);
        Response__c resp = new Response__c(
            Name = 'Test Response',
            Contact__c = c.Id,
            Need_Offer_Responded_To__c = posts[0].Id,
            Neighbourhood__c = nh.Id
        );
        insert resp;

        Notification__c n = new Notification__c(
            Title__c = 'Resp notif', Type__c = 'Response',
            Related_Record_Id__c = String.valueOf(resp.Id),
            Related_Record_Type__c = 'Response__c'
        );
        Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> result =
            FimbyEmailAlertQueueable.enrichNotifications(new List<Notification__c>{ n });
        System.assert(result.containsKey(String.valueOf(resp.Id)), 'Should have enrichment for response');
    }

    @IsTest
    static void enrichNotifications_withConversation_returnsEnrichment() {
        Contact c = getTestContact();
        Conversation__c conv = new Conversation__c(
            Participant_1__c = c.Id,
            Participant_2__c = c.Id,
            Last_Message_Sender__c = c.Id
        );
        insert conv;

        Notification__c n = new Notification__c(
            Title__c = 'Conv notif', Type__c = 'Message',
            Related_Record_Id__c = String.valueOf(conv.Id),
            Related_Record_Type__c = 'Conversation__c'
        );
        Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> result =
            FimbyEmailAlertQueueable.enrichNotifications(new List<Notification__c>{ n });
        System.assert(result.containsKey(String.valueOf(conv.Id)), 'Should have enrichment for conversation');
    }

    @IsTest
    static void enrichNotifications_mixedTypes_enrichesAll() {
        Account nh = [SELECT Id FROM Account LIMIT 1];
        Contact c = getTestContact();
        List<Needs_Offers__c> posts = FimbyTestDataFactory.createAskOfferItems(nh.Id, c.Id, 1, true);
        List<Library_Item__c> items = FimbyTestDataFactory.createLibraryItems(nh.Id, c.Id, 1, true);

        List<Notification__c> notifs = new List<Notification__c>{
            new Notification__c(
                Title__c = 'Post notif', Type__c = 'Response',
                Related_Record_Id__c = String.valueOf(posts[0].Id),
                Related_Record_Type__c = 'Needs_Offers__c'
            ),
            new Notification__c(
                Title__c = 'Library notif', Type__c = 'Lending_Request',
                Related_Record_Id__c = String.valueOf(items[0].Id),
                Related_Record_Type__c = 'Library_Item__c'
            )
        };
        Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> result =
            FimbyEmailAlertQueueable.enrichNotifications(notifs);
        System.assertEquals(2, result.size(), 'Should enrich both record types');
    }

    // ── Subject matrix (Phase 1: Title__c drives single-alert subjects) ──────

    @IsTest
    static void buildSubject_singleAlert_usesTitle() {
        Notification__c n = new Notification__c(
            Type__c = FimbyConstants.NOTIF_LENDING_REQUEST,
            Title__c = 'Your borrow request was declined',
            Body__c = 'The owner wasn\'t able to lend this item right now.'
        );
        FimbyEmailAlertQueueable q = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>()
        );

        Test.startTest();
        String subject = q.buildSubject(new List<Notification__c>{ n });
        Test.stopTest();

        System.assertEquals('Your borrow request was declined', subject,
            'Single alert subject must come from Title__c, not the coarse type map');
    }

    @IsTest
    static void buildSubject_singleAlert_actorLedTitle_prependsActorName() {
        Notification__c n = new Notification__c(
            Type__c = FimbyConstants.NOTIF_VOUCH_REQUEST_RECEIVED,
            Title__c = 'would like you to vouch for them',
            Actor_Name__c = 'Emily D.',
            Actor_Contact__c = Contact.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
        );
        FimbyEmailAlertQueueable q = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>()
        );

        Test.startTest();
        String subject = q.buildSubject(new List<Notification__c>{ n });
        Test.stopTest();

        System.assertEquals('Emily D. would like you to vouch for them', subject,
            'Single-alert subject must prepend the actor name to a de-actored verb-phrase title');
    }

    @IsTest
    static void buildSubject_singleAlert_waitlistPromotion_usesTitle() {
        Notification__c n = new Notification__c(
            Type__c = FimbyConstants.NOTIF_LENDING_REQUEST,
            Title__c = 'My Cat is now available',
            Body__c = 'You\'re next on the waitlist.'
        );
        FimbyEmailAlertQueueable q = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>()
        );
        String subject = q.buildSubject(new List<Notification__c>{ n });
        System.assertEquals('My Cat is now available', subject,
            'Waitlist promotion subject must match the card headline');
    }

    @IsTest
    static void buildSubject_singleAlert_loanApproved_usesTitle() {
        Notification__c n = new Notification__c(
            Type__c = FimbyConstants.NOTIF_LOAN_APPROVED,
            Title__c = 'Your borrow request was approved',
            Body__c = 'Pickup date: 2026-05-30.'
        );
        FimbyEmailAlertQueueable q = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>()
        );
        String subject = q.buildSubject(new List<Notification__c>{ n });
        System.assertEquals('Your borrow request was approved', subject);
    }

    @IsTest
    static void buildSubject_singleAlert_messageType_keepsPrivacyGenericSubject() {
        Notification__c n = new Notification__c(
            Type__c = FimbyConstants.NOTIF_MESSAGE,
            Title__c = 'Sam: Hey, are you home tonight?',
            Body__c = 'Hey, are you home tonight?'
        );
        FimbyEmailAlertQueueable q = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>()
        );
        String subject = q.buildSubject(new List<Notification__c>{ n });
        System.assertEquals('New message from a neighbour', subject,
            'DM previews must never leak content into the email subject line');
    }

    @IsTest
    static void buildSubject_singleAlert_blankTitle_fallsBackToTypeSubject() {
        Notification__c n = new Notification__c(
            Type__c = FimbyConstants.NOTIF_LENDING_REQUEST,
            Title__c = null,
            Body__c = 'No title — legacy record.'
        );
        FimbyEmailAlertQueueable q = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>()
        );
        String subject = q.buildSubject(new List<Notification__c>{ n });
        System.assertEquals('Someone wants to borrow your item', subject,
            'Blank Title__c must fall back to the type-based subject');
    }

    @IsTest
    static void buildSubject_singleAlert_longTitle_isTruncated() {
        String longTitle = 'A very long title that exceeds the email subject ' +
            'maximum length and needs to be truncated cleanly with an ellipsis at the end';
        Notification__c n = new Notification__c(
            Type__c = FimbyConstants.NOTIF_LENDING_REQUEST,
            Title__c = longTitle
        );
        FimbyEmailAlertQueueable q = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>()
        );
        String subject = q.buildSubject(new List<Notification__c>{ n });
        System.assert(subject.length() <= 78,
            'Subject should be truncated to <= 78 chars, was ' + subject.length());
        System.assert(subject.endsWith('\u2026'),
            'Truncated subjects end with an ellipsis');
    }

    @IsTest
    static void buildSubject_multipleMessages_usesBatchSubject() {
        Notification__c n1 = new Notification__c(
            Type__c = FimbyConstants.NOTIF_MESSAGE, Title__c = 'Sam: Hi'
        );
        Notification__c n2 = new Notification__c(
            Type__c = FimbyConstants.NOTIF_MESSAGE, Title__c = 'Maya: Coffee?'
        );
        FimbyEmailAlertQueueable q = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>()
        );
        String subject = q.buildSubject(new List<Notification__c>{ n1, n2 });
        System.assertEquals('2 new messages', subject);
    }

    @IsTest
    static void buildSubject_mixedTypes_usesGenericBatchSubject() {
        Notification__c n1 = new Notification__c(
            Type__c = FimbyConstants.NOTIF_MESSAGE, Title__c = 'Sam: Hi'
        );
        Notification__c n2 = new Notification__c(
            Type__c = FimbyConstants.NOTIF_LENDING_REQUEST,
            Title__c = 'Return confirmed for Drill'
        );
        FimbyEmailAlertQueueable q = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>()
        );
        String subject = q.buildSubject(new List<Notification__c>{ n1, n2 });
        System.assertEquals('2 new updates in your neighbourhood', subject);
    }

    @IsTest
    static void execute_userAlertsDisabled_suppresses() {
        Contact c = getTestContact();
        User u = getTestUser();
        u.Email_Alerts_Enabled__c = false;
        patchTestUser(u);

        List<Notification__c> notifs = FimbyTestDataFactory.createNotifications(
            c.Id, 'Comment', 'Processing', 1, true
        );

        FimbyEmailAlertQueueable.oweaCached = u.Id;

        Map<Id, List<Notification__c>> byContact = new Map<Id, List<Notification__c>>();
        byContact.put(c.Id, notifs);

        Test.startTest();
        new FimbyEmailAlertQueueable(byContact).execute(null);
        Test.stopTest();

        Notification__c updated = [SELECT Email_Status__c FROM Notification__c WHERE Id = :notifs[0].Id];
        System.assertEquals('Suppressed', updated.Email_Status__c);
    }
}
