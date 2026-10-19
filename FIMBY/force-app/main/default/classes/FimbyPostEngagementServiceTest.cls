@isTest
private class FimbyPostEngagementServiceTest {

    @TestSetup
    static void setup() {
        Account hood = FimbyTestDataFactory.createNeighbourhood(true);
        insert new List<Contact>{
            new Contact(FirstName = 'Paula', LastName = 'PosterPES', AccountId = hood.Id, Email = 'poster.pes@fimby.test.com'),
            new Contact(FirstName = 'Ana', LastName = 'OnePES', AccountId = hood.Id, Email = 'one.pes@fimby.test.com'),
            new Contact(FirstName = 'Ben', LastName = 'TwoPES', AccountId = hood.Id, Email = 'two.pes@fimby.test.com')
        };
    }

    private static Contact c(String lastName) {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = :lastName LIMIT 1];
    }

    private static Response__c reply(Id postId, Contact responder, String status, Decimal qty) {
        return new Response__c(Name = 'PES', Need_Offer_Responded_To__c = postId, Contact__c = responder.Id,
            On_Behalf_Of_Contact__c = responder.Id, Status__c = status, Amount_Requested__c = qty);
    }

    @isTest
    static void summarizesRepliesAcceptanceAndViewer() {
        Contact poster = c('PosterPES');
        Contact one = c('OnePES');
        Contact two = c('TwoPES');
        Needs_Offers__c ask = FimbyTestDataFactory.createNeedsOffers(poster.AccountId, poster.Id, FimbyConstants.RT_NEED, 1, true)[0];
        insert new List<Response__c>{
            reply(ask.Id, one, FimbyConstants.RESPONSE_ACCEPTED, 2),
            reply(ask.Id, two, FimbyConstants.RESPONSE_NEW, 1),
            reply(ask.Id, two, FimbyConstants.RESPONSE_DECLINED, 1)
        };

        Test.startTest();
        Map<Id, FimbyPostEngagementService.Summary> result =
            FimbyPostEngagementService.summarize(new Set<Id>{ ask.Id }, two.Id);
        Test.stopTest();

        FimbyPostEngagementService.Summary s = result.get(ask.Id);
        System.assertEquals(2, s.replyCount, 'Unique represented neighbours with an active reply');
        System.assertEquals(2, s.acceptedQuantity);
        System.assertEquals(true, s.hasAcceptedResponse);
        System.assertEquals(true, s.viewerHasActiveResponse);
        System.assertEquals(false, s.hasPosterConversation);
        System.assertEquals(true, s.isEngaged());
    }

    @isTest
    static void posterMessageCountsAsConversation() {
        Contact poster = c('PosterPES');
        Contact one = c('OnePES');
        Needs_Offers__c offer = FimbyTestDataFactory.createNeedsOffers(poster.AccountId, poster.Id, FimbyConstants.RT_OFFER, 1, true)[0];
        Response__c r = reply(offer.Id, one, FimbyConstants.RESPONSE_NEW, 1);
        insert r;
        insert new List<Response_Message__c>{
            new Response_Message__c(Response__c = r.Id, Body__c = 'System', Sender__c = poster.Id, Is_System_Message__c = true),
            new Response_Message__c(Response__c = r.Id, Body__c = 'Hi there', Sender__c = one.Id, Sent_By__c = one.Id, Is_System_Message__c = false)
        };
        System.assertEquals(false, FimbyPostEngagementService.summarize(new Set<Id>{ offer.Id }, null).get(offer.Id).isEngaged(),
            'A responder message alone is not engagement');

        insert new Response_Message__c(Response__c = r.Id, Body__c = 'Sure', Sender__c = poster.Id, Sent_By__c = poster.Id,
            Is_System_Message__c = false);
        Test.startTest();
        FimbyPostEngagementService.Summary s = FimbyPostEngagementService.summarize(new Set<Id>{ offer.Id }, null).get(offer.Id);
        Test.stopTest();
        System.assertEquals(true, s.hasPosterConversation);
        System.assertEquals(true, s.isEngaged());
        System.assertEquals(offer.Id, FimbyPostEngagementService.posterMessagedResponses(
            [SELECT Id, Contact__c, Posted_By__c FROM Needs_Offers__c WHERE Id = :offer.Id]).get(r.Id));
    }

    @isTest
    static void eventsAndBulkBuysClassifyByTheirOwnRules() {
        Contact poster = c('PosterPES');
        Contact one = c('OnePES');
        Needs_Offers__c evt = FimbyTestDataFactory.createNeedsOffers(poster.AccountId, poster.Id, FimbyConstants.RT_OFFER, 1, false)[0];
        evt.Type__c = 'Event';
        evt.Event_Type__c = 'Open_Event';
        evt.Start_Date__c = Date.today().addDays(2);
        evt.Location__c = 'Hall';
        Needs_Offers__c bb = FimbyTestDataFactory.createNeedsOffers(poster.AccountId, poster.Id, FimbyConstants.RT_BULK_BUY, 1, false)[0];
        bb.Status__c = FimbyConstants.NEEDS_OFFERS_AVAILABLE;
        bb.Total_Quantity__c = 10;
        bb.Total_Estimated_Cost__c = 150;
        bb.Allocation_Unit_Label__c = 'bags';
        insert new List<Needs_Offers__c>{ evt, bb };
        insert new List<Response__c>{
            reply(evt.Id, one, FimbyConstants.RESPONSE_NEW, 1),
            reply(bb.Id, one, FimbyConstants.RESPONSE_RESERVED, 1)
        };

        Test.startTest();
        Map<Id, FimbyPostEngagementService.Summary> result =
            FimbyPostEngagementService.summarize(new Set<Id>{ evt.Id, bb.Id }, one.Id);
        Test.stopTest();

        System.assertEquals(true, result.get(evt.Id).isEngaged(), 'Any active RSVP engages an event');
        System.assertEquals(false, result.get(bb.Id).isEngaged(), 'Bulk Buys never use this classification');
        System.assertEquals(true, result.get(bb.Id).viewerHasActiveResponse, 'Reserved counts for the viewer');
        System.assertEquals(0, result.get(bb.Id).replyCount);
    }

    @isTest
    static void helpers() {
        System.assertEquals(0, FimbyPostEngagementService.summarize(null, null).size());
        System.assertEquals(0, FimbyPostEngagementService.posterMessagedResponses(null).size());
        System.assertEquals(null, FimbyPostEngagementService.representedResponder(null));
        Id cid = Contact.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        System.assertEquals(cid, FimbyPostEngagementService.representedResponder(new Response__c(Contact__c = cid)));
        System.assertEquals(true, FimbyPostEngagementService.isMatched(2, 2));
        System.assertEquals(false, FimbyPostEngagementService.isMatched(null, 2));
        System.assertEquals(false, FimbyPostEngagementService.isMatched(0, 2));
        System.assertEquals(false, FimbyPostEngagementService.isMatched(3, 2));
    }
}
