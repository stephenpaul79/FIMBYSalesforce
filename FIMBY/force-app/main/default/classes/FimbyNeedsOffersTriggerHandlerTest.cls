@isTest
private class FimbyNeedsOffersTriggerHandlerTest {

    private static Id rtId(String developerName) {
        return Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get(developerName).getRecordTypeId();
    }

    @isTest
    static void enteringTerminalStampsClosedDate() {
        Id fakeId = Needs_Offers__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';
        Needs_Offers__c old = new Needs_Offers__c(Id = fakeId, Status__c = FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED);
        Needs_Offers__c changed = new Needs_Offers__c(Id = fakeId, Status__c = FimbyConstants.NEEDS_OFFERS_COMPLETED,
            Closed_By__c = FimbyConstants.CLOSED_BY_POSTER);

        FimbyNeedsOffersTriggerHandler.beforeUpdate(new List<Needs_Offers__c>{ changed }, new Map<Id, Needs_Offers__c>{ fakeId => old });

        System.assertNotEquals(null, changed.Closed_Date__c);
        System.assertEquals(FimbyConstants.CLOSED_BY_POSTER, changed.Closed_By__c);
    }

    @isTest
    static void existingClosedDateIsKept() {
        Id fakeId = Needs_Offers__c.SObjectType.getDescribe().getKeyPrefix() + '000000000002';
        Datetime earlier = Datetime.now().addDays(-3);
        Needs_Offers__c old = new Needs_Offers__c(Id = fakeId, Status__c = FimbyConstants.NEEDS_OFFERS_POSTED);
        Needs_Offers__c changed = new Needs_Offers__c(Id = fakeId, Status__c = FimbyConstants.NEEDS_OFFERS_EXPIRED,
            Closed_Date__c = earlier);
        FimbyNeedsOffersTriggerHandler.beforeUpdate(new List<Needs_Offers__c>{ changed }, new Map<Id, Needs_Offers__c>{ fakeId => old });
        System.assertEquals(earlier, changed.Closed_Date__c, 'Reconciliation can set its own boundary date');
    }

    @isTest
    static void leavingTerminalClearsClosureFields() {
        Id fakeId = Needs_Offers__c.SObjectType.getDescribe().getKeyPrefix() + '000000000003';
        Needs_Offers__c old = new Needs_Offers__c(Id = fakeId, Status__c = FimbyConstants.NEEDS_OFFERS_EXPIRED);
        Needs_Offers__c changed = new Needs_Offers__c(Id = fakeId, Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            Closed_Date__c = Datetime.now(), Closed_By__c = FimbyConstants.CLOSED_BY_AUTO);
        FimbyNeedsOffersTriggerHandler.beforeUpdate(new List<Needs_Offers__c>{ changed }, new Map<Id, Needs_Offers__c>{ fakeId => old });
        System.assertEquals(null, changed.Closed_Date__c);
        System.assertEquals(null, changed.Closed_By__c);
    }

    @isTest
    static void autoAcceptPromotesReplyReceived() {
        Id fakeId = Needs_Offers__c.SObjectType.getDescribe().getKeyPrefix() + '000000000004';
        Needs_Offers__c old = new Needs_Offers__c(Id = fakeId, Status__c = FimbyConstants.NEEDS_OFFERS_POSTED);
        Needs_Offers__c changed = new Needs_Offers__c(Id = fakeId, Status__c = FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED,
            Auto_Accept_Responses__c = true);
        FimbyNeedsOffersTriggerHandler.beforeUpdate(new List<Needs_Offers__c>{ changed }, new Map<Id, Needs_Offers__c>{ fakeId => old });
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED, changed.Status__c);
    }

    @isTest
    static void afterUpdateHandsClosedAsksToLifecycleAndSkipsBulkBuys() {
        Account hood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact poster = FimbyTestDataFactory.createNeighbourhoodContact(hood.Id, true);
        Contact responder = FimbyTestDataFactory.createNeighbourhoodContact(hood.Id, true);
        Needs_Offers__c ask = FimbyTestDataFactory.createNeedsOffers(hood.Id, poster.Id, FimbyConstants.RT_NEED, 1, true)[0];
        Response__c resp = new Response__c(Name = 'NOTH', Need_Offer_Responded_To__c = ask.Id, Contact__c = responder.Id,
            On_Behalf_Of_Contact__c = responder.Id, Status__c = FimbyConstants.RESPONSE_ACCEPTED, Amount_Requested__c = 1);
        insert resp;

        Needs_Offers__c old = [SELECT Id, Status__c, RecordTypeId FROM Needs_Offers__c WHERE Id = :ask.Id];
        Test.startTest();
        update new Needs_Offers__c(Id = ask.Id, Status__c = FimbyConstants.NEEDS_OFFERS_COMPLETED,
            Closed_By__c = FimbyConstants.CLOSED_BY_POSTER);
        Needs_Offers__c changed = [SELECT Id, Status__c, RecordTypeId FROM Needs_Offers__c WHERE Id = :ask.Id];
        Needs_Offers__c bulkBuy = new Needs_Offers__c(Id = Needs_Offers__c.SObjectType.getDescribe().getKeyPrefix() + '000000000009',
            RecordTypeId = rtId(FimbyConstants.RT_BULK_BUY), Status__c = FimbyConstants.NEEDS_OFFERS_COMPLETED);
        Needs_Offers__c bulkBuyOld = new Needs_Offers__c(Id = bulkBuy.Id, RecordTypeId = bulkBuy.RecordTypeId,
            Status__c = FimbyConstants.NEEDS_OFFERS_AVAILABLE);
        FimbyNeedsOffersTriggerHandler.afterUpdate(
            new List<Needs_Offers__c>{ changed, bulkBuy },
            new Map<Id, Needs_Offers__c>{ ask.Id => old, bulkBuy.Id => bulkBuyOld });
        Test.stopTest();

        System.assertEquals(FimbyConstants.RESPONSE_COMPLETED, [SELECT Status__c FROM Response__c WHERE Id = :resp.Id].Status__c);
    }
}
