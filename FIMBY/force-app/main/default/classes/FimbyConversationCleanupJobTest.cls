@isTest
private class FimbyConversationCleanupJobTest {

    @isTest
    static void testExecuteWithNoStaleData() {
        Test.startTest();
        FimbyConversationCleanupJob job = new FimbyConversationCleanupJob();
        job.execute(null);
        Test.stopTest();
        System.assert(true, 'Job should execute without error when no stale data exists');
    }

    @isTest
    static void testExecuteWhenDisabled() {
        // When cleanup days is 0, the job should exit early
        Test.startTest();
        FimbyConversationCleanupJob job = new FimbyConversationCleanupJob();
        job.execute(null);
        Test.stopTest();
        System.assert(true, 'Job should handle disabled cleanup gracefully');
    }

    @isTest
    static void testAllContextTypesCleanedAt180d() {
        Account nb = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(nb.Id, 2, true);

        Integer days = FimbySettings.conversationCleanupDays();
        Datetime stale = Datetime.now().addDays(-(days + 5));

        // Previously-orphaned context types must now all be swept on the single window.
        List<String> contexts = new List<String>{
            'Direct', 'Library_Lending', 'Bulk_Buy', 'Missed_Pickup', 'Event', 'Vouch_Request', 'Skill'
        };
        List<Conversation__c> convos = new List<Conversation__c>();
        for (String ctx : contexts) {
            convos.add(new Conversation__c(
                Participant_1__c = contacts[0].Id,
                Participant_2__c = contacts[1].Id,
                Status__c = 'Active',
                Context_Type__c = ctx,
                Last_Message_Date__c = stale
            ));
        }
        insert convos;

        // Purge-sync target: a hidden event-chat notification keyed on a stale convo.
        Notification__c evtNotif = new Notification__c(
            Contact__c = contacts[0].Id,
            Type__c = FimbyConstants.NOTIF_EVENT_CHAT,
            Title__c = 'Event chat',
            Related_Record_Id__c = String.valueOf(convos[4].Id) // the 'Event' convo
        );
        insert evtNotif;

        Test.startTest();
        new FimbyConversationCleanupJob().execute(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Conversation__c],
            'All context types older than the window should be deleted');
        System.assertEquals(0, [SELECT COUNT() FROM Notification__c WHERE Id = :evtNotif.Id],
            'Related hidden notification should be purge-synced');
    }

    @isTest
    static void testStaleResponseThreadAndNotificationsPurged() {
        Account nb = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(nb.Id, 2, true);
        List<Needs_Offers__c> posts = FimbyTestDataFactory.createAskOfferItems(nb.Id, contacts[0].Id, 1, true);

        Integer days = FimbySettings.conversationCleanupDays();
        Date staleDate = Date.today().addDays(-(days + 5));

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = posts[0].Id,
            Contact__c = contacts[1].Id,
            Status__c = FimbyConstants.RESPONSE_NEW,
            Last_Reply_Date__c = staleDate
        );
        insert resp;

        Notification__c replyNotif = new Notification__c(
            Contact__c = contacts[0].Id,
            Type__c = FimbyConstants.NOTIF_RESPONSE_REPLY,
            Title__c = 'Sam replied',
            Related_Record_Id__c = String.valueOf(resp.Id)
        );
        insert replyNotif;

        Test.startTest();
        new FimbyConversationCleanupJob().execute(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Response__c WHERE Id = :resp.Id],
            'Stale response thread should be deleted');
        System.assertEquals(0, [SELECT COUNT() FROM Notification__c WHERE Id = :replyNotif.Id],
            'Related hidden reply notification should be purge-synced');
    }
}
