@isTest
private class FimbyResponseStatusServiceTest {

    @TestSetup
    static void setup() {
        Account hood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact poster = new Contact(FirstName = 'Paula', LastName = 'PosterRSS', AccountId = hood.Id,
            Email = 'poster.rss@fimby.test.com');
        Contact responder = new Contact(FirstName = 'Ravi', LastName = 'ResponderRSS', AccountId = hood.Id,
            Email = 'responder.rss@fimby.test.com');
        Contact stranger = new Contact(FirstName = 'Sam', LastName = 'StrangerRSS', AccountId = hood.Id,
            Email = 'stranger.rss@fimby.test.com');
        insert new List<Contact>{ poster, responder, stranger };
        FimbyTestDataFactory.createCommunityUser(poster.Id, null, true);
        FimbyTestDataFactory.createCommunityUser(responder.Id, null, true);
        FimbyTestDataFactory.createCommunityUser(stranger.Id, null, true);
    }

    private static Contact contactByLastName(String lastName) {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = :lastName LIMIT 1];
    }

    private static User userFor(Contact c) {
        return [SELECT Id FROM User WHERE ContactId = :c.Id LIMIT 1];
    }

    private static Needs_Offers__c createPost(Contact poster, String rt, String type) {
        Needs_Offers__c post = FimbyTestDataFactory.createNeedsOffers(poster.AccountId, poster.Id, rt, 1, false)[0];
        post.Name = 'Ladder for the weekend';
        if (type != null) {
            post.Type__c = type;
        }
        insert post;
        return post;
    }

    private static Response__c createResponse(Needs_Offers__c post, Contact responder, String status) {
        Response__c resp = new Response__c(
            Name = 'RSS response',
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = responder.Id,
            On_Behalf_Of_Contact__c = responder.Id,
            Status__c = status,
            Amount_Requested__c = 1
        );
        insert resp;
        return resp;
    }

    @isTest
    static void posterAcceptsNewResponse() {
        Contact poster = contactByLastName('PosterRSS');
        Contact responder = contactByLastName('ResponderRSS');
        Needs_Offers__c post = createPost(poster, FimbyConstants.RT_OFFER, null);
        Response__c resp = createResponse(post, responder, FimbyConstants.RESPONSE_NEW);

        FimbyResponseStatusService.Outcome outcome;
        Test.startTest();
        System.runAs(userFor(poster)) {
            outcome = FimbyResponseStatusService.changeStatus(
                resp.Id, FimbyConstants.RESPONSE_ACCEPTED, FimbyResponseStatusService.Source.POSTER);
        }
        Test.stopTest();

        System.assertEquals(true, outcome.success, 'Poster can accept a New response: ' + outcome.message);
        Response__c after = [SELECT Status__c, Responder_Unread_Count__c FROM Response__c WHERE Id = :resp.Id];
        System.assertEquals(FimbyConstants.RESPONSE_ACCEPTED, after.Status__c);
        System.assertEquals(1, after.Responder_Unread_Count__c, 'Responder sees one unread update');

        List<Response_Message__c> sys = [
            SELECT Body__c FROM Response_Message__c
            WHERE Response__c = :resp.Id AND Is_System_Message__c = true AND System_Message_Type__c = 'Status_Change'
        ];
        System.assertEquals(1, sys.size(), 'One status system message');

        List<Notification__c> notifs = [
            SELECT Contact__c, Title__c, Actor_Contact__c FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_RESPONSE
        ];
        System.assertEquals(1, notifs.size(), 'Responder gets one acceptance notification');
        System.assertEquals(responder.Id, notifs[0].Contact__c);
        System.assertEquals('accepted your response', notifs[0].Title__c);

        Contact counters = [SELECT Offer_Responses_For_Self__c FROM Contact WHERE Id = :responder.Id];
        System.assert(counters.Offer_Responses_For_Self__c >= 1, 'Acceptance counts as help given');
    }

    @isTest
    static void responderWithdrawsAcceptedResponseReversesCounters() {
        Contact poster = contactByLastName('PosterRSS');
        Contact responder = contactByLastName('ResponderRSS');
        Needs_Offers__c post = createPost(poster, FimbyConstants.RT_NEED, null);
        Response__c resp = createResponse(post, responder, FimbyConstants.RESPONSE_ACCEPTED);
        update new Contact(Id = responder.Id, Need_Responses_For_Self__c = 3, Responses_Posted__c = 4);

        FimbyResponseStatusService.Outcome outcome;
        Test.startTest();
        System.runAs(userFor(responder)) {
            outcome = FimbyResponseStatusService.changeStatus(
                resp.Id, FimbyConstants.RESPONSE_CANCELLED, FimbyResponseStatusService.Source.RESPONDER);
        }
        Test.stopTest();

        System.assertEquals(true, outcome.success, outcome.message);
        Contact c = [SELECT Need_Responses_For_Self__c, Responses_Posted__c FROM Contact WHERE Id = :responder.Id];
        System.assertEquals(2, c.Need_Responses_For_Self__c, 'Leaving Accepted takes back the help counter');
        System.assertEquals(3, c.Responses_Posted__c, 'Responder withdrawal takes back the submission');
        List<Notification__c> notifs = [SELECT Contact__c, Title__c FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_RESPONSE];
        System.assertEquals(1, notifs.size());
        System.assertEquals(poster.Id, notifs[0].Contact__c, 'Poster hears about the withdrawal');
        System.assertEquals('withdrew their response', notifs[0].Title__c);
    }

    @isTest
    static void invalidTransitionAndAuthorizationAreRejected() {
        Contact poster = contactByLastName('PosterRSS');
        Contact responder = contactByLastName('ResponderRSS');
        Contact stranger = contactByLastName('StrangerRSS');
        Needs_Offers__c post = createPost(poster, FimbyConstants.RT_OFFER, null);
        Response__c accepted = createResponse(post, responder, FimbyConstants.RESPONSE_ACCEPTED);

        FimbyResponseStatusService.Outcome declineAccepted;
        FimbyResponseStatusService.Outcome strangerAccept;
        Test.startTest();
        System.runAs(userFor(poster)) {
            declineAccepted = FimbyResponseStatusService.changeStatus(
                accepted.Id, FimbyConstants.RESPONSE_DECLINED, FimbyResponseStatusService.Source.POSTER);
        }
        FimbyIdentityRepository.clearCache();
        System.runAs(userFor(stranger)) {
            strangerAccept = FimbyResponseStatusService.changeStatus(
                accepted.Id, FimbyConstants.RESPONSE_COMPLETED, FimbyResponseStatusService.Source.POSTER);
        }
        Test.stopTest();

        System.assertEquals(false, declineAccepted.success);
        System.assertEquals('invalidTransition', declineAccepted.error);
        System.assertEquals(false, strangerAccept.success);
        System.assertEquals('notAuthorized', strangerAccept.error);
        System.assertEquals(FimbyConstants.RESPONSE_ACCEPTED,
            [SELECT Status__c FROM Response__c WHERE Id = :accepted.Id].Status__c);
    }

    @isTest
    static void acceptOnClosedPostIsRejected() {
        Contact poster = contactByLastName('PosterRSS');
        Contact responder = contactByLastName('ResponderRSS');
        Needs_Offers__c post = createPost(poster, FimbyConstants.RT_OFFER, null);
        Response__c resp = createResponse(post, responder, FimbyConstants.RESPONSE_NEW);
        Test.startTest();
        update new Needs_Offers__c(Id = post.Id, Status__c = FimbyConstants.NEEDS_OFFERS_EXPIRED,
            Closed_By__c = FimbyConstants.CLOSED_BY_AUTO);
        update new Response__c(Id = resp.Id, Status__c = FimbyConstants.RESPONSE_NEW);

        FimbyResponseStatusService.Outcome outcome;
        System.runAs(userFor(poster)) {
            outcome = FimbyResponseStatusService.changeStatus(
                resp.Id, FimbyConstants.RESPONSE_ACCEPTED, FimbyResponseStatusService.Source.POSTER);
        }
        Test.stopTest();
        System.assertEquals(false, outcome.success);
        System.assertEquals('postClosed', outcome.error);
    }

    @isTest
    static void sendMessageAndAcceptIsOneTransactionOneNotification() {
        Contact poster = contactByLastName('PosterRSS');
        Contact responder = contactByLastName('ResponderRSS');
        Needs_Offers__c post = createPost(poster, FimbyConstants.RT_NEED, null);
        Response__c resp = createResponse(post, responder, FimbyConstants.RESPONSE_NEW);

        FimbyResponseStatusService.Outcome outcome;
        Test.startTest();
        System.runAs(userFor(poster)) {
            outcome = FimbyResponseStatusService.sendMessageAndAccept(resp.Id, 'Saturday at 10 works for me');
        }
        Test.stopTest();

        System.assertEquals(true, outcome.success, outcome.message);
        Response__c after = [SELECT Status__c, Responder_Unread_Count__c, Last_Reply__c FROM Response__c WHERE Id = :resp.Id];
        System.assertEquals(FimbyConstants.RESPONSE_ACCEPTED, after.Status__c);
        System.assertEquals(2, after.Responder_Unread_Count__c, 'Message plus acceptance are both unread');
        System.assertEquals('Saturday at 10 works for me', after.Last_Reply__c);

        System.assertEquals(1, [SELECT COUNT() FROM Response_Message__c WHERE Response__c = :resp.Id AND Is_System_Message__c = false]);
        List<Notification__c> notifs = [SELECT Title__c, Body__c, Type__c FROM Notification__c WHERE Contact__c = :responder.Id];
        System.assertEquals(1, notifs.size(), 'One combined notification, not reply + acceptance');
        System.assertEquals('accepted your response', notifs[0].Title__c);
        System.assert(notifs[0].Body__c.contains('Saturday at 10'), 'Body carries the message snippet');
        System.assert(notifs[0].Body__c.length() <= 140);
    }

    @isTest
    static void sendMessageAndAcceptRequiresBody() {
        Contact poster = contactByLastName('PosterRSS');
        Contact responder = contactByLastName('ResponderRSS');
        Needs_Offers__c post = createPost(poster, FimbyConstants.RT_NEED, null);
        Response__c resp = createResponse(post, responder, FimbyConstants.RESPONSE_NEW);
        FimbyResponseStatusService.Outcome outcome;
        System.runAs(userFor(poster)) {
            outcome = FimbyResponseStatusService.sendMessageAndAccept(resp.Id, '  ');
        }
        System.assertEquals(false, outcome.success);
        System.assertEquals('invalidInput', outcome.error);
    }

    @isTest
    static void bulkBuyReservationsAreNotManagedHere() {
        Contact poster = contactByLastName('PosterRSS');
        Contact responder = contactByLastName('ResponderRSS');
        Needs_Offers__c post = FimbyTestDataFactory.createNeedsOffers(poster.AccountId, poster.Id, FimbyConstants.RT_BULK_BUY, 1, false)[0];
        post.Status__c = FimbyConstants.NEEDS_OFFERS_AVAILABLE;
        post.Total_Quantity__c = 10;
        post.Total_Estimated_Cost__c = 150;
        post.Allocation_Unit_Label__c = 'bags';
        insert post;
        Response__c resp = createResponse(post, responder, FimbyConstants.RESPONSE_NEW);
        FimbyResponseStatusService.Outcome outcome;
        System.runAs(userFor(poster)) {
            outcome = FimbyResponseStatusService.changeStatus(
                resp.Id, FimbyConstants.RESPONSE_ACCEPTED, FimbyResponseStatusService.Source.POSTER);
        }
        System.assertEquals(false, outcome.success);
        System.assertEquals('invalidTransition', outcome.error);
    }

    @isTest
    static void cascadeUpdatesInBulkWithoutNotifications() {
        Contact poster = contactByLastName('PosterRSS');
        Contact responder = contactByLastName('ResponderRSS');
        Needs_Offers__c post = createPost(poster, FimbyConstants.RT_OFFER, null);
        Response__c accepted = createResponse(post, responder, FimbyConstants.RESPONSE_ACCEPTED);
        Response__c fresh = createResponse(post, responder, FimbyConstants.RESPONSE_NEW);
        List<Response__c> scope = [
            SELECT Id, Status__c, Contact__c, On_Behalf_Of_Contact__c,
                   Need_Offer_Responded_To__r.RecordType.DeveloperName
            FROM Response__c WHERE Id IN (:accepted.Id, :fresh.Id)
        ];

        Map<Id, String> previous;
        Test.startTest();
        previous = FimbyResponseStatusService.applyCascade(scope, new Map<Id, String>{
            accepted.Id => FimbyConstants.RESPONSE_COMPLETED,
            fresh.Id => FimbyConstants.RESPONSE_DECLINED
        }, FimbyResponseStatusService.Source.PARENT_CASCADE);
        Test.stopTest();

        System.assertEquals(2, previous.size());
        Response__c done = [SELECT Status__c, Completed_Date__c FROM Response__c WHERE Id = :accepted.Id];
        System.assertEquals(FimbyConstants.RESPONSE_COMPLETED, done.Status__c);
        System.assertNotEquals(null, done.Completed_Date__c, 'Every path into Completed stamps the date');
        System.assertEquals(FimbyConstants.RESPONSE_DECLINED, [SELECT Status__c FROM Response__c WHERE Id = :fresh.Id].Status__c);
        System.assertEquals(0, [SELECT COUNT() FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_RESPONSE]);
    }

    @isTest
    static void quietWithdrawalCancelsAndReverses() {
        Contact poster = contactByLastName('PosterRSS');
        Contact responder = contactByLastName('ResponderRSS');
        Needs_Offers__c post = createPost(poster, FimbyConstants.RT_OFFER, null);
        Response__c resp = createResponse(post, responder, FimbyConstants.RESPONSE_ACCEPTED);
        update new Contact(Id = responder.Id, Offer_Responses_For_Self__c = 1, Responses_Posted__c = 1);
        Response__c locked = [SELECT Id, Status__c, Contact__c, On_Behalf_Of_Contact__c FROM Response__c WHERE Id = :resp.Id];

        Test.startTest();
        FimbyResponseStatusService.applyQuietResponderWithdrawal(locked, FimbyConstants.RT_OFFER);
        Test.stopTest();

        System.assertEquals(FimbyConstants.RESPONSE_CANCELLED, [SELECT Status__c FROM Response__c WHERE Id = :resp.Id].Status__c);
        Contact c = [SELECT Offer_Responses_For_Self__c, Responses_Posted__c FROM Contact WHERE Id = :responder.Id];
        System.assertEquals(0, c.Offer_Responses_For_Self__c);
        System.assertEquals(0, c.Responses_Posted__c);
    }

    @isTest
    static void bodyHelpersStayWithinLimits() {
        String longTitle = 'A'.repeat(200);
        String body = FimbyResponseStatusService.abbreviateTitleInBody('On “', longTitle, '”.');
        System.assert(body.length() <= 140, 'Body capped at 140');
        System.assert(body.endsWith('”.'), 'Sentence frame survives');
        System.assertEquals('Response accepted', FimbyResponseStatusService.systemMessageBody(FimbyConstants.RESPONSE_ACCEPTED, 'X'));
        System.assertEquals('Response declined', FimbyResponseStatusService.systemMessageBody(FimbyConstants.RESPONSE_DECLINED, 'X'));
        System.assertEquals('Ravi cancelled their response', FimbyResponseStatusService.systemMessageBody(FimbyConstants.RESPONSE_CANCELLED, 'Ravi'));
        System.assertEquals('Response marked as complete', FimbyResponseStatusService.systemMessageBody(FimbyConstants.RESPONSE_COMPLETED, 'X'));
        System.assertEquals('Status changed to Expired', FimbyResponseStatusService.systemMessageBody(FimbyConstants.RESPONSE_EXPIRED, 'X'));
    }
}
