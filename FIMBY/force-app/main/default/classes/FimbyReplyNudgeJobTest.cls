@isTest
private class FimbyReplyNudgeJobTest {

    @TestSetup
    static void setup() {
        Account hood = FimbyTestDataFactory.createNeighbourhood(true);
        insert new List<Contact>{
            new Contact(FirstName = 'Paula', LastName = 'PosterRNJ', AccountId = hood.Id, Email = 'poster.rnj@fimby.test.com'),
            new Contact(FirstName = 'Ravi', LastName = 'OneRNJ', AccountId = hood.Id, Email = 'one.rnj@fimby.test.com'),
            new Contact(FirstName = 'Bea', LastName = 'TwoRNJ', AccountId = hood.Id, Email = 'two.rnj@fimby.test.com')
        };
    }

    private static Contact c(String lastName) {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = :lastName LIMIT 1];
    }

    private static Needs_Offers__c ask() {
        Contact poster = c('PosterRNJ');
        Needs_Offers__c p = FimbyTestDataFactory.createNeedsOffers(poster.AccountId, poster.Id, FimbyConstants.RT_NEED, 1, false)[0];
        p.Name = 'Help moving a couch';
        insert p;
        return p;
    }

    private static Response__c reply(Needs_Offers__c p, Contact responder, Integer hoursAgo) {
        Response__c r = new Response__c(Name = 'RNJ', Need_Offer_Responded_To__c = p.Id, Contact__c = responder.Id,
            On_Behalf_Of_Contact__c = responder.Id, Status__c = FimbyConstants.RESPONSE_NEW, Amount_Requested__c = 1);
        insert r;
        Test.setCreatedDate(r.Id, Datetime.now().addHours(-hoursAgo));
        return r;
    }

    @isTest
    static void singleWaitingReplyNudgesWithResponderAsActor() {
        Needs_Offers__c p = ask();
        Response__c r = reply(p, c('OneRNJ'), 72);

        Test.startTest();
        Database.executeBatch(new FimbyReplyNudgeJob(new Set<Id>{ p.Id }, Datetime.now()), 50);
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Contact__c, Title__c, Body__c, Actor_Name__c, Actor_Contact__c, Related_Record_Id__c
            FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_RESPONSE_REMINDER
        ];
        System.assertEquals(1, notifs.size());
        System.assertEquals(c('PosterRNJ').Id, notifs[0].Contact__c);
        System.assertEquals('is waiting to hear back about your ask', notifs[0].Title__c);
        System.assertEquals('Review their response to “Help moving a couch” when you’re ready.', notifs[0].Body__c);
        System.assertEquals('Ravi OneRNJ', notifs[0].Actor_Name__c);
        System.assertEquals(c('OneRNJ').Id, notifs[0].Actor_Contact__c);
        System.assertEquals(String.valueOf(r.Id), notifs[0].Related_Record_Id__c, 'Links to the thread');
        System.assertEquals(Date.today(), [SELECT Last_Reply_Nudge_Date__c FROM Needs_Offers__c WHERE Id = :p.Id].Last_Reply_Nudge_Date__c);
    }

    @isTest
    static void multipleWaitingRepliesUseFimbyActorAndCount() {
        Needs_Offers__c p = ask();
        reply(p, c('OneRNJ'), 72);
        reply(p, c('TwoRNJ'), 50);

        Test.startTest();
        Database.executeBatch(new FimbyReplyNudgeJob(new Set<Id>{ p.Id }, Datetime.now()), 50);
        Test.stopTest();

        Notification__c n = [SELECT Title__c, Body__c, Actor_Name__c, Related_Record_Id__c FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_RESPONSE_REMINDER];
        System.assertEquals('2 neighbours are waiting to hear back', n.Title__c);
        System.assertEquals('Review the responses to “Help moving a couch” when you’re ready.', n.Body__c);
        System.assertEquals('FIMBY', n.Actor_Name__c);
        System.assertEquals(String.valueOf(p.Id), n.Related_Record_Id__c, 'Links to the response list');
    }

    @isTest
    static void freshRepliesPosterMessagesAndPriorNudgesAreSkipped() {
        Needs_Offers__c fresh = ask();
        reply(fresh, c('OneRNJ'), 2);

        Needs_Offers__c answered = ask();
        Response__c r = reply(answered, c('OneRNJ'), 72);
        Contact poster = c('PosterRNJ');
        insert new Response_Message__c(Response__c = r.Id, Body__c = 'Thanks', Sender__c = poster.Id,
            Sent_By__c = poster.Id, Is_System_Message__c = false);

        Needs_Offers__c alreadyNudged = ask();
        reply(alreadyNudged, c('TwoRNJ'), 72);
        update new Needs_Offers__c(Id = alreadyNudged.Id, Last_Reply_Nudge_Date__c = Date.today().addDays(-5));

        Test.startTest();
        Database.executeBatch(new FimbyReplyNudgeJob(new Set<Id>{ fresh.Id, answered.Id, alreadyNudged.Id }, Datetime.now()), 50);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Notification__c WHERE Type__c = :FimbyConstants.NOTIF_RESPONSE_REMINDER]);
    }

    @isTest
    static void legacyChatterRepliesAreNotNudged() {
        Needs_Offers__c p = ask();
        Response__c r = reply(p, c('OneRNJ'), 72);
        update new Response__c(Id = r.Id, Last_Reply_Date__c = Date.today().addDays(-2));

        Test.startTest();
        Map<Id, List<Response__c>> eligible = FimbyReplyNudgeJob.eligibleResponsesByPost(
            [SELECT Id, Contact__c, Posted_By__c FROM Needs_Offers__c WHERE Id = :p.Id], Datetime.now());
        Test.stopTest();
        System.assert(eligible.isEmpty(), 'Ambiguous pre-cutover conversations wait for manual review');
    }

    @isTest
    static void scheduleEntryPointQueuesBatch() {
        Test.startTest();
        System.schedule('Reply nudge test', '0 15 9 * * ?', new FimbyReplyNudgeJob());
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name = 'Reply nudge test']);
    }
}
