@isTest
private class FimbyPostEndOfLifeJobTest {

    @TestSetup
    static void setup() {
        Account hood = FimbyTestDataFactory.createNeighbourhood(true);
        insert new List<Contact>{
            new Contact(FirstName = 'Paula', LastName = 'PosterEOL', AccountId = hood.Id, Email = 'poster.eol@fimby.test.com'),
            new Contact(FirstName = 'Ravi', LastName = 'ResponderEOL', AccountId = hood.Id, Email = 'responder.eol@fimby.test.com')
        };
    }

    private static Contact c(String lastName) {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = :lastName LIMIT 1];
    }

    private static Needs_Offers__c post(String rt, Date endDate) {
        Contact poster = c('PosterEOL');
        Needs_Offers__c p = FimbyTestDataFactory.createNeedsOffers(poster.AccountId, poster.Id, rt, 1, false)[0];
        p.End_Date__c = endDate;
        insert p;
        return p;
    }

    private static Response__c reply(Needs_Offers__c p, String status) {
        Contact responder = c('ResponderEOL');
        Response__c r = new Response__c(Name = 'EOL', Need_Offer_Responded_To__c = p.Id, Contact__c = responder.Id,
            On_Behalf_Of_Contact__c = responder.Id, Status__c = status, Amount_Requested__c = 1);
        insert r;
        return r;
    }

    private static Needs_Offers__c reload(Needs_Offers__c p) {
        return [SELECT Status__c, Closed_By__c, Closed_Date__c FROM Needs_Offers__c WHERE Id = :p.Id];
    }

    @isTest
    static void engagedAskCompletesAndUnengagedOfferExpires() {
        Needs_Offers__c engaged = post(FimbyConstants.RT_NEED, Date.today().addDays(-1));
        reply(engaged, FimbyConstants.RESPONSE_ACCEPTED);
        Needs_Offers__c quiet = post(FimbyConstants.RT_OFFER, Date.today().addDays(-1));
        Needs_Offers__c stillLive = post(FimbyConstants.RT_OFFER, Date.today());

        Test.startTest();
        Database.executeBatch(new FimbyPostEndOfLifeJob(new Set<Id>{ engaged.Id, quiet.Id, stillLive.Id }, Date.today()), 50);
        Test.stopTest();

        Needs_Offers__c e = reload(engaged);
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_COMPLETED, e.Status__c);
        System.assertEquals(FimbyConstants.CLOSED_BY_AUTO, e.Closed_By__c);
        System.assertNotEquals(null, e.Closed_Date__c);
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_EXPIRED, reload(quiet).Status__c);
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_POSTED, reload(stillLive).Status__c, 'The end date itself is still live');

        List<Notification__c> notifs = [SELECT Contact__c, Title__c FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_POST_LIFECYCLE_CLOSED];
        System.assertEquals(1, notifs.size(), 'Only the engaged poster hears about auto-completion');
        System.assertEquals('Your ask closed as Answered', notifs[0].Title__c);
    }

    @isTest
    static void rerunIsIdempotent() {
        Needs_Offers__c engaged = post(FimbyConstants.RT_NEED, Date.today().addDays(-2));
        reply(engaged, FimbyConstants.RESPONSE_ACCEPTED);
        FimbyPostEndOfLifeJob first = new FimbyPostEndOfLifeJob(new Set<Id>{ engaged.Id }, Date.today());
        Test.startTest();
        first.processPosts(new Set<Id>{ engaged.Id });
        new FimbyPostEndOfLifeJob(new Set<Id>{ engaged.Id }, Date.today()).processPosts(new Set<Id>{ engaged.Id });
        Test.stopTest();
        System.assertEquals(1, first.completedCount);
        System.assertEquals(1, [SELECT COUNT() FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_POST_LIFECYCLE_CLOSED]);
    }

    @isTest
    static void legacyChatterReplyHoldsPostForReview() {
        Needs_Offers__c p = post(FimbyConstants.RT_OFFER, Date.today().addDays(-1));
        Response__c r = reply(p, FimbyConstants.RESPONSE_NEW);
        update new Response__c(Id = r.Id, Last_Reply_Date__c = Date.today().addDays(-3));
        FimbyPostEndOfLifeJob job = new FimbyPostEndOfLifeJob(new Set<Id>{ p.Id }, Date.today());

        Test.startTest();
        job.processPosts(new Set<Id>{ p.Id });
        job.finish(null);
        Test.stopTest();

        System.assertNotEquals(FimbyConstants.NEEDS_OFFERS_EXPIRED, reload(p).Status__c, 'Left active for manual review');
        System.assertEquals(1, job.skippedLegacyPostIds.size());
    }

    @isTest
    static void effectiveEndDateRules() {
        Datetime posted = Datetime.newInstance(2026, 10, 1, 9, 0, 0);
        Needs_Offers__c withEnd = new Needs_Offers__c(End_Date__c = Date.newInstance(2026, 10, 5));
        System.assertEquals(Date.newInstance(2026, 10, 5), FimbyPostEndOfLifeJob.effectiveEndDate(withEnd));

        Needs_Offers__c event = new Needs_Offers__c(Type__c = 'Event', Start_Date__c = Date.newInstance(2026, 10, 9), Posted_Date__c = posted);
        System.assertEquals(Date.newInstance(2026, 10, 9), FimbyPostEndOfLifeJob.effectiveEndDate(event));
        System.assertEquals(null, FimbyPostEndOfLifeJob.effectiveEndDate(new Needs_Offers__c(Type__c = 'Event', Posted_Date__c = posted)),
            'Events never end from posting age');

        Needs_Offers__c offer = new Needs_Offers__c(Posted_Date__c = posted, Type__c = 'Goods - Unperishable');
        System.assertEquals(posted.date().addDays(FimbySettings.offerDefaultEndDays()), FimbyPostEndOfLifeJob.effectiveEndDate(offer));
        System.assertEquals(null, FimbyPostEndOfLifeJob.effectiveEndDate(new Needs_Offers__c(Type__c = 'Goods - Unperishable')));
    }

    @isTest
    static void scheduleEntryPointQueuesBatch() {
        Test.startTest();
        System.schedule('EOL test', '0 15 0 * * ?', new FimbyPostEndOfLifeJob());
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = 'EOL test']);
    }
}
