@isTest
private class FimbyResponseTriggerHandlerTest {

    @TestSetup
    static void setup() {
        Account hood = FimbyTestDataFactory.createNeighbourhood(true);
        insert new List<Contact>{
            new Contact(FirstName = 'Paula', LastName = 'PosterRTH', AccountId = hood.Id, Email = 'poster.rth@fimby.test.com'),
            new Contact(FirstName = 'Ravi', LastName = 'ResponderRTH', AccountId = hood.Id, Email = 'responder.rth@fimby.test.com')
        };
    }

    private static Contact c(String lastName) {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = :lastName LIMIT 1];
    }

    private static Needs_Offers__c post(String rt, Boolean autoAccept) {
        Contact poster = c('PosterRTH');
        Needs_Offers__c p = FimbyTestDataFactory.createNeedsOffers(poster.AccountId, poster.Id, rt, 1, false)[0];
        p.Auto_Accept_Responses__c = autoAccept;
        insert p;
        return p;
    }

    private static Response__c reply(Needs_Offers__c p, String status) {
        Contact responder = c('ResponderRTH');
        Response__c r = new Response__c(Name = 'RTH', Need_Offer_Responded_To__c = p.Id, Contact__c = responder.Id,
            On_Behalf_Of_Contact__c = responder.Id, Status__c = status, Amount_Requested__c = 1);
        insert r;
        return r;
    }

    private static String parentStatus(Needs_Offers__c p) {
        return [SELECT Status__c FROM Needs_Offers__c WHERE Id = :p.Id].Status__c;
    }

    @isTest
    static void newReplyMovesPostedToReplyReceived() {
        Needs_Offers__c p = post(FimbyConstants.RT_NEED, false);
        Test.startTest();
        Response__c r = reply(p, FimbyConstants.RESPONSE_NEW);
        FimbyResponseTriggerHandler.afterInsert(new List<Response__c>{ r });
        Test.stopTest();
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED, parentStatus(p));
    }

    @isTest
    static void acceptedReplyMovesToReplyAccepted() {
        Needs_Offers__c p = post(FimbyConstants.RT_OFFER, false);
        Response__c r = reply(p, FimbyConstants.RESPONSE_NEW);
        Test.startTest();
        Response__c old = r.clone(true, true, true, true);
        r.Status__c = FimbyConstants.RESPONSE_ACCEPTED;
        update r;
        FimbyResponseTriggerHandler.afterUpdate(new List<Response__c>{ r }, new Map<Id, Response__c>{ r.Id => old });
        Test.stopTest();
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED, parentStatus(p));
    }

    @isTest
    static void terminalParentIsNeverReopened() {
        Needs_Offers__c p = post(FimbyConstants.RT_NEED, false);
        update new Needs_Offers__c(Id = p.Id, Status__c = FimbyConstants.NEEDS_OFFERS_EXPIRED,
            Closed_By__c = FimbyConstants.CLOSED_BY_AUTO);
        Test.startTest();
        Response__c r = reply(p, FimbyConstants.RESPONSE_NEW);
        FimbyResponseTriggerHandler.afterInsert(new List<Response__c>{ r });
        Test.stopTest();
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_EXPIRED, parentStatus(p));
    }

    @isTest
    static void ignoredStatusesDoNotAdvance() {
        Needs_Offers__c p = post(FimbyConstants.RT_NEED, false);
        Response__c r = new Response__c(Need_Offer_Responded_To__c = p.Id, Status__c = FimbyConstants.RESPONSE_DECLINED);
        Response__c noParent = new Response__c(Status__c = FimbyConstants.RESPONSE_NEW);
        Test.startTest();
        FimbyResponseTriggerHandler.afterInsert(new List<Response__c>{ r, noParent });
        Test.stopTest();
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_POSTED, parentStatus(p));
    }

    @isTest
    static void nextStatusRules() {
        Needs_Offers__c posted = new Needs_Offers__c(Status__c = FimbyConstants.NEEDS_OFFERS_POSTED);
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED, FimbyResponseTriggerHandler.nextStatus(posted, false));
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED, FimbyResponseTriggerHandler.nextStatus(posted, true));

        Needs_Offers__c legacy = new Needs_Offers__c(Status__c = FimbyConstants.NEEDS_OFFERS_SUBMITTED, Auto_Accept_Responses__c = true);
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED, FimbyResponseTriggerHandler.nextStatus(legacy, false));

        Needs_Offers__c received = new Needs_Offers__c(Status__c = FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED);
        System.assertEquals(null, FimbyResponseTriggerHandler.nextStatus(received, false));
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED, FimbyResponseTriggerHandler.nextStatus(received, true));

        Needs_Offers__c accepted = new Needs_Offers__c(Status__c = FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED);
        System.assertEquals(null, FimbyResponseTriggerHandler.nextStatus(accepted, true));
    }
}
