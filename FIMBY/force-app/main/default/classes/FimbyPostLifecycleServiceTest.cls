@isTest
private class FimbyPostLifecycleServiceTest {

    @TestSetup
    static void setup() {
        Account hood = FimbyTestDataFactory.createNeighbourhood(true);
        insert new List<Contact>{
            new Contact(FirstName = 'Paula', LastName = 'PosterPLS', AccountId = hood.Id, Email = 'poster.pls@fimby.test.com'),
            new Contact(FirstName = 'Ana', LastName = 'AcceptedPLS', AccountId = hood.Id, Email = 'accepted.pls@fimby.test.com'),
            new Contact(FirstName = 'Mo', LastName = 'MessagedPLS', AccountId = hood.Id, Email = 'messaged.pls@fimby.test.com'),
            new Contact(FirstName = 'Una', LastName = 'UnansweredPLS', AccountId = hood.Id, Email = 'unanswered.pls@fimby.test.com')
        };
    }

    private static Contact c(String lastName) {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = :lastName LIMIT 1];
    }

    private static Needs_Offers__c post(String rt, Boolean isEvent) {
        Contact poster = c('PosterPLS');
        Needs_Offers__c p = FimbyTestDataFactory.createNeedsOffers(poster.AccountId, poster.Id, rt, 1, false)[0];
        p.Name = 'Moving boxes';
        if (isEvent) {
            p.Type__c = 'Event';
            p.Event_Type__c = 'Gathering';
            p.Start_Date__c = Date.today().addDays(2);
            p.End_Date__c = Date.today().addDays(2);
            p.Location__c = 'Corner Park';
        }
        insert p;
        return p;
    }

    private static Response__c reply(Needs_Offers__c p, Contact responder, String status) {
        Response__c r = new Response__c(
            Name = 'PLS reply',
            Need_Offer_Responded_To__c = p.Id,
            Contact__c = responder.Id,
            On_Behalf_Of_Contact__c = responder.Id,
            Status__c = status,
            Amount_Requested__c = 1
        );
        insert r;
        return r;
    }

    private static void posterMessage(Response__c r) {
        Contact poster = c('PosterPLS');
        insert new Response_Message__c(Response__c = r.Id, Body__c = 'Still around?', Sender__c = poster.Id,
            Sent_By__c = poster.Id, Sent_Date__c = Datetime.now(), Is_System_Message__c = false);
    }

    private static void close(Needs_Offers__c p, String status, String closedBy) {
        update new Needs_Offers__c(Id = p.Id, Status__c = status, Closed_By__c = closedBy);
        FimbyPostLifecycleService.onPostsClosed(new List<Needs_Offers__c>{ new Needs_Offers__c(Id = p.Id) });
    }

    private static String statusOf(Response__c r) {
        return [SELECT Status__c FROM Response__c WHERE Id = :r.Id].Status__c;
    }

    private static List<Notification__c> lifecycleNotifs() {
        return [
            SELECT Contact__c, Title__c, Body__c, Actor_Name__c, Actor_Contact__c
            FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_POST_LIFECYCLE_CLOSED
        ];
    }

    @isTest
    static void posterCompleteAskResolvesResponsesAndThanksUnanswered() {
        Needs_Offers__c p = post(FimbyConstants.RT_NEED, false);
        Response__c accepted = reply(p, c('AcceptedPLS'), FimbyConstants.RESPONSE_ACCEPTED);
        Response__c messaged = reply(p, c('MessagedPLS'), FimbyConstants.RESPONSE_NEW);
        Response__c unanswered = reply(p, c('UnansweredPLS'), FimbyConstants.RESPONSE_NEW);
        posterMessage(messaged);

        Test.startTest();
        close(p, FimbyConstants.NEEDS_OFFERS_COMPLETED, FimbyConstants.CLOSED_BY_POSTER);
        Test.stopTest();

        System.assertEquals(FimbyConstants.RESPONSE_COMPLETED, statusOf(accepted));
        System.assertEquals(FimbyConstants.RESPONSE_COMPLETED, statusOf(messaged), 'A poster conversation counts as resolved');
        System.assertEquals(FimbyConstants.RESPONSE_DECLINED, statusOf(unanswered));

        List<Notification__c> notifs = lifecycleNotifs();
        System.assertEquals(1, notifs.size(), 'Only the unanswered responder hears about the close');
        System.assertEquals(c('UnansweredPLS').Id, notifs[0].Contact__c);
        System.assertEquals('closed their ask', notifs[0].Title__c);
        System.assertEquals(c('PosterPLS').Id, notifs[0].Actor_Contact__c, 'Represented poster is the actor');
        System.assert(notifs[0].Body__c.startsWith('The ask closed before you heard back.'));
        System.assert(notifs[0].Body__c.length() <= 140);
    }

    @isTest
    static void posterCancelNotifiesNewAndAccepted() {
        Needs_Offers__c p = post(FimbyConstants.RT_OFFER, false);
        Response__c accepted = reply(p, c('AcceptedPLS'), FimbyConstants.RESPONSE_ACCEPTED);
        Response__c fresh = reply(p, c('UnansweredPLS'), FimbyConstants.RESPONSE_NEW);

        Test.startTest();
        close(p, FimbyConstants.NEEDS_OFFERS_CANCELLED, FimbyConstants.CLOSED_BY_POSTER);
        Test.stopTest();

        System.assertEquals(FimbyConstants.RESPONSE_CANCELLED, statusOf(accepted));
        System.assertEquals(FimbyConstants.RESPONSE_CANCELLED, statusOf(fresh));
        List<Notification__c> notifs = lifecycleNotifs();
        System.assertEquals(2, notifs.size());
        for (Notification__c n : notifs) {
            System.assertEquals('withdrew their offer', n.Title__c);
            System.assertNotEquals(c('PosterPLS').Id, n.Contact__c, 'Poster is never told about their own action');
        }
    }

    @isTest
    static void autoCompleteTellsPosterAndUnresolvedResponders() {
        Needs_Offers__c p = post(FimbyConstants.RT_NEED, false);
        Response__c accepted = reply(p, c('AcceptedPLS'), FimbyConstants.RESPONSE_ACCEPTED);
        Response__c fresh = reply(p, c('UnansweredPLS'), FimbyConstants.RESPONSE_NEW);

        Test.startTest();
        close(p, FimbyConstants.NEEDS_OFFERS_COMPLETED, FimbyConstants.CLOSED_BY_AUTO);
        Test.stopTest();

        System.assertEquals(FimbyConstants.RESPONSE_COMPLETED, statusOf(accepted));
        System.assertEquals(FimbyConstants.RESPONSE_DECLINED, statusOf(fresh));
        Map<Id, Notification__c> byRecipient = new Map<Id, Notification__c>();
        for (Notification__c n : lifecycleNotifs()) {
            byRecipient.put(n.Contact__c, n);
        }
        System.assertEquals(2, byRecipient.size(), 'Poster plus the unresolved responder; nothing extra to the accepted one');
        Notification__c posterNote = byRecipient.get(c('PosterPLS').Id);
        System.assertEquals('Your ask closed as Answered', posterNote.Title__c);
        System.assertEquals('FIMBY', posterNote.Actor_Name__c);
        System.assertEquals(null, posterNote.Actor_Contact__c);
        System.assertEquals('An ask you replied to has closed', byRecipient.get(c('UnansweredPLS').Id).Title__c);
    }

    @isTest
    static void autoExpiryNotifiesOnlyUnansweredResponders() {
        Needs_Offers__c p = post(FimbyConstants.RT_OFFER, false);
        Response__c fresh = reply(p, c('UnansweredPLS'), FimbyConstants.RESPONSE_NEW);

        Test.startTest();
        close(p, FimbyConstants.NEEDS_OFFERS_EXPIRED, FimbyConstants.CLOSED_BY_AUTO);
        Test.stopTest();

        System.assertEquals(FimbyConstants.RESPONSE_EXPIRED, statusOf(fresh));
        List<Notification__c> notifs = lifecycleNotifs();
        System.assertEquals(1, notifs.size(), 'No poster alert on expiry');
        System.assertEquals(c('UnansweredPLS').Id, notifs[0].Contact__c);
        System.assertEquals('An offer you replied to has closed', notifs[0].Title__c);
    }

    @isTest
    static void suppressedReconciliationCascadesWithoutNotifying() {
        Needs_Offers__c p = post(FimbyConstants.RT_OFFER, false);
        Response__c fresh = reply(p, c('UnansweredPLS'), FimbyConstants.RESPONSE_NEW);

        Test.startTest();
        FimbyPostLifecycleService.suppressNotifications = true;
        close(p, FimbyConstants.NEEDS_OFFERS_EXPIRED, FimbyConstants.CLOSED_BY_AUTO);
        Test.stopTest();

        System.assertEquals(FimbyConstants.RESPONSE_EXPIRED, statusOf(fresh), 'Cascade still runs');
        System.assertEquals(0, lifecycleNotifs().size(), 'Reconciliation sends no retroactive notices');
    }

    @isTest
    static void completedEventExpiresUnacceptedRsvpsSilently() {
        Needs_Offers__c p = post(FimbyConstants.RT_OFFER, true);
        Response__c going = reply(p, c('AcceptedPLS'), FimbyConstants.RESPONSE_ACCEPTED);
        Response__c pending = reply(p, c('UnansweredPLS'), FimbyConstants.RESPONSE_NEW);

        Test.startTest();
        close(p, FimbyConstants.NEEDS_OFFERS_COMPLETED, FimbyConstants.CLOSED_BY_POSTER);
        Test.stopTest();

        System.assertEquals(FimbyConstants.RESPONSE_COMPLETED, statusOf(going));
        System.assertEquals(FimbyConstants.RESPONSE_EXPIRED, statusOf(pending));
        System.assertEquals(0, lifecycleNotifs().size(), 'Event RSVPers stay silent');
    }

    @isTest
    static void secondCallInSameTransactionIsIgnored() {
        Needs_Offers__c p = post(FimbyConstants.RT_NEED, false);
        reply(p, c('AcceptedPLS'), FimbyConstants.RESPONSE_ACCEPTED);
        Test.startTest();
        close(p, FimbyConstants.NEEDS_OFFERS_COMPLETED, FimbyConstants.CLOSED_BY_AUTO);
        FimbyPostLifecycleService.onPostsClosed(new List<Needs_Offers__c>{ new Needs_Offers__c(Id = p.Id) });
        Test.stopTest();
        System.assertEquals(1, lifecycleNotifs().size(), 'Poster auto-complete notice is sent once');
    }

    @isTest
    static void targetMatrixAndLabels() {
        Needs_Offers__c ask = new Needs_Offers__c(Status__c = FimbyConstants.NEEDS_OFFERS_COMPLETED, Type__c = 'Goods - Unperishable');
        Response__c fresh = new Response__c(Status__c = FimbyConstants.RESPONSE_NEW);
        Response__c accepted = new Response__c(Status__c = FimbyConstants.RESPONSE_ACCEPTED);
        Response__c declined = new Response__c(Status__c = FimbyConstants.RESPONSE_DECLINED);

        System.assertEquals(FimbyConstants.RESPONSE_DECLINED, FimbyPostLifecycleService.targetStatus(ask, fresh, false));
        System.assertEquals(FimbyConstants.RESPONSE_COMPLETED, FimbyPostLifecycleService.targetStatus(ask, fresh, true));
        System.assertEquals(FimbyConstants.RESPONSE_COMPLETED, FimbyPostLifecycleService.targetStatus(ask, accepted, false));
        System.assertEquals(null, FimbyPostLifecycleService.targetStatus(ask, declined, false));

        ask.Status__c = FimbyConstants.NEEDS_OFFERS_EXPIRED;
        System.assertEquals(FimbyConstants.RESPONSE_EXPIRED, FimbyPostLifecycleService.targetStatus(ask, fresh, false));
        System.assertEquals(FimbyConstants.RESPONSE_COMPLETED, FimbyPostLifecycleService.targetStatus(ask, accepted, false));

        ask.Status__c = FimbyConstants.NEEDS_OFFERS_CANCELLED;
        System.assertEquals(FimbyConstants.RESPONSE_CANCELLED, FimbyPostLifecycleService.targetStatus(ask, accepted, false));

        System.assertEquals(null, FimbyPostLifecycleService.outcomeLabel(null));
        System.assertEquals('Happened', FimbyPostLifecycleService.outcomeLabel(new Needs_Offers__c(Type__c = 'Event')));
        System.assertEquals('Received', FimbyPostLifecycleService.outcomeLabel(new Needs_Offers__c(Type__c = 'Goods - Unperishable')));
    }
}
