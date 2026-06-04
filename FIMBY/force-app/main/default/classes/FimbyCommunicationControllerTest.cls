@IsTest
public class FimbyCommunicationControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(neighbourhood.Id, 3, true);
        User communityUser = FimbyTestDataFactory.createCommunityUser(
            contacts[0].Id, 'Customer Community User - Mobile App', true
        );

        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = contacts[0].Id,
            Shared_To__c = contacts[1].Id,
            Email__c = 'shared@test.com',
            Phone__c = '0400000000'
        );
        insert sci;

        Shared_Contact_Info__c sci2 = new Shared_Contact_Info__c(
            Contact__c = contacts[2].Id,
            Shared_To__c = contacts[0].Id,
            Email__c = 'shared2@test.com'
        );
        insert sci2;
    }

    private static User getTestUser() {
        return [
            SELECT Id, ContactId
            FROM User
            WHERE Profile.Name = 'Customer Community User - Mobile App'
              AND IsActive = true
            ORDER BY CreatedDate DESC LIMIT 1
        ];
    }

    private static List<Contact> getOtherContacts() {
        User u = getTestUser();
        Contact myContact = [SELECT Id, AccountId FROM Contact WHERE Id = :u.ContactId];
        return [SELECT Id, Name FROM Contact WHERE Id != :myContact.Id AND AccountId = :myContact.AccountId ORDER BY Id];
    }

    // ================================================================
    // getThreads tests
    // ================================================================

    @IsTest
    static void testGetThreadsEmpty() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'all', null);

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertEquals(0, result.totalCount, 'Should have no threads');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsWithDmConversation() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        System.runAs(testUser) {
            FimbyConversationController.getOrCreateConversation(others[0].Id);
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'all', null);

            System.assertEquals(1, result.totalCount, 'Should have 1 thread');
            System.assertEquals('direct', result.threads[0].threadType, 'Should be a direct thread');
            System.assertNotEquals(null, result.threads[0].participantName, 'Should have participant name');
            System.assertNotEquals(null, result.threads[0].actionUrl, 'Should have action URL');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsHidesBlockedContact() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Contact viewer = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];

        System.runAs(testUser) {
            FimbyConversationController.getOrCreateConversation(others[0].Id);
        }

        insert new Blocked_Contact__c(
            Blocker__c = viewer.Id,
            Blocked__c = others[0].Id,
            Reason__c = 'QA block filter test'
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'all', null);
            System.assertEquals(0, result.totalCount,
                'DM thread with blocked contact should be hidden from inbox');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsDirectFilter() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        System.runAs(testUser) {
            FimbyConversationController.getOrCreateConversation(others[0].Id);
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult directResult =
                FimbyCommunicationController.getThreads(20, 0, 'direct', null);
            System.assertEquals(1, directResult.totalCount, 'Should have 1 direct thread');

            FimbyCommunicationController.ThreadListResult responseResult =
                FimbyCommunicationController.getThreads(20, 0, 'responses', null);
            System.assertEquals(0, responseResult.totalCount, 'Should have 0 response threads');

            FimbyCommunicationController.ThreadListResult libraryResult =
                FimbyCommunicationController.getThreads(20, 0, 'library', null);
            System.assertEquals(0, libraryResult.totalCount, 'Should have 0 library threads');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsWithResponse() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Test Need',
            Details__c = 'Test details',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id
        );
        insert post;

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Response__c resp = new Response__c(
            Name = 'Test Response',
            Response__c = 'I can help with that',
            Contact__c = myContact.Id,
            On_Behalf_Of_Contact__c = myContact.Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Last_Reply__c = 'Thanks for responding',
            Last_Reply_Date__c = Date.today(),
            Last_Reply_Contact_Lookup__c = others[0].Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult allResult =
                FimbyCommunicationController.getThreads(20, 0, 'all', null);
            System.assert(allResult.totalCount >= 1, 'Should have at least 1 thread');

            Boolean foundResponse = false;
            for (FimbyCommunicationController.CommunicationThread t : allResult.threads) {
                if (t.threadType == 'response') {
                    foundResponse = true;
                    System.assertNotEquals(null, t.contextLabel, 'Response should have context label');
                    System.assertEquals('New', t.statusBadge, 'Status badge should be New');
                }
            }
            System.assert(foundResponse, 'Should find a response thread');

            FimbyCommunicationController.ThreadListResult responseOnly =
                FimbyCommunicationController.getThreads(20, 0, 'responses', null);
            System.assertEquals(1, responseOnly.totalCount, 'Should have 1 response thread');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsExcludesCommunityEventWithoutMessages() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Needs_Offers__c eventPost = new Needs_Offers__c(
            Name = 'Community Festival',
            Details__c = 'A festival in the park',
            Type__c = 'Event',
            Event_Type__c = 'Community_Event',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id
        );
        insert eventPost;

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Response__c resp = new Response__c(
            Name = 'Community Festival',
            Response__c = 'Quick event response',
            Contact__c = myContact.Id,
            On_Behalf_Of_Contact__c = myContact.Id,
            Need_Offer_Responded_To__c = eventPost.Id,
            Status__c = 'Accepted',
            Neighbourhood__c = neighbourhood.Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'responses', null);
            System.assertEquals(0, result.totalCount,
                'Community Event response with no messages should not appear in threads');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsIncludesCommunityEventWithMessages() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Needs_Offers__c eventPost = new Needs_Offers__c(
            Name = 'Community Festival',
            Details__c = 'A festival in the park',
            Type__c = 'Event',
            Event_Type__c = 'Community_Event',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id
        );
        insert eventPost;

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Response__c resp = new Response__c(
            Name = 'Community Festival',
            Response__c = 'Quick event response',
            Contact__c = myContact.Id,
            On_Behalf_Of_Contact__c = myContact.Id,
            Need_Offer_Responded_To__c = eventPost.Id,
            Status__c = 'Accepted',
            Neighbourhood__c = neighbourhood.Id,
            Last_Reply__c = 'Hi, do you know if parking is free?',
            Last_Reply_Date__c = Date.today(),
            Last_Reply_Contact_Lookup__c = myContact.Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'responses', null);
            System.assertEquals(1, result.totalCount,
                'Community Event response with messages should appear in threads');
            System.assertEquals('community-event', result.threads[0].badgeType);
            System.assertEquals('response', result.threads[0].threadType);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsGatheringResponseBadge() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Needs_Offers__c gatheringPost = new Needs_Offers__c(
            Name = 'Block Party',
            Details__c = 'Neighbourhood potluck',
            Type__c = 'Event',
            Event_Type__c = 'Gathering',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id
        );
        insert gatheringPost;

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        insert new Response__c(
            Name = 'Block Party',
            Response__c = 'Count us in',
            Contact__c = myContact.Id,
            On_Behalf_Of_Contact__c = myContact.Id,
            Need_Offer_Responded_To__c = gatheringPost.Id,
            Status__c = 'Accepted',
            Neighbourhood__c = neighbourhood.Id,
            Last_Reply__c = 'See you there',
            Last_Reply_Date__c = Date.today(),
            Last_Reply_Contact_Lookup__c = others[0].Id
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'responses', null);
            System.assertEquals(1, result.totalCount);
            System.assertEquals('gathering', result.threads[0].badgeType);
            System.assertEquals('response', result.threads[0].threadType);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsWithLibraryConversation() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        Conversation__c libraryConvo = new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = others[0].Id,
            Status__c = 'Active',
            Context_Type__c = 'Library_Lending',
            Participant_1_Unread_Count__c = 0,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false,
            Last_Message_Date__c = Datetime.now(),
            Last_Message_Preview__c = 'Pickup at 3pm'
        );
        insert libraryConvo;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult libraryResult =
                FimbyCommunicationController.getThreads(20, 0, 'library', null);
            System.assertEquals(1, libraryResult.totalCount, 'Should have 1 library thread');
            System.assertEquals('library', libraryResult.threads[0].threadType, 'Should be library type');

            FimbyCommunicationController.ThreadListResult directResult =
                FimbyCommunicationController.getThreads(20, 0, 'direct', null);
            System.assertEquals(0, directResult.totalCount, 'Library convo should not appear in direct filter');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsWithSearch() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        System.runAs(testUser) {
            FimbyConversationController.getOrCreateConversation(others[0].Id);
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult found =
                FimbyCommunicationController.getThreads(20, 0, 'all', 'Resident');
            System.assertNotEquals(null, found, 'Search result should not be null');

            FimbyCommunicationController.ThreadListResult notFound =
                FimbyCommunicationController.getThreads(20, 0, 'all', 'ZZZNOMATCH');
            System.assertEquals(0, notFound.totalCount, 'Should find no threads for non-matching search');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsPagination() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        System.runAs(testUser) {
            FimbyConversationController.getOrCreateConversation(others[0].Id);
            FimbyConversationController.getOrCreateConversation(others[1].Id);
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult page1 =
                FimbyCommunicationController.getThreads(1, 0, 'all', null);
            System.assertEquals(2, page1.totalCount, 'Total should be 2');
            System.assertEquals(1, page1.threads.size(), 'Page should have 1 item');

            FimbyCommunicationController.ThreadListResult page2 =
                FimbyCommunicationController.getThreads(1, 1, 'all', null);
            System.assertEquals(1, page2.threads.size(), 'Page 2 should have 1 item');
        }
        Test.stopTest();
    }

    // ================================================================
    // getUnifiedUnreadCount tests
    // ================================================================

    @IsTest
    static void testGetUnifiedUnreadCountZero() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Integer count = FimbyCommunicationController.getUnifiedUnreadCount();
            System.assertEquals(0, count, 'Should have 0 unread');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetUnifiedUnreadCountWithDmUnread() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = others[0].Id,
            Status__c = 'Active',
            Participant_1_Unread_Count__c = 3,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false
        );
        insert conv;

        Test.startTest();
        System.runAs(testUser) {
            Integer count = FimbyCommunicationController.getUnifiedUnreadCount();
            System.assertEquals(1, count, 'Should count 1 unread conversation, not individual messages');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetUnifiedUnreadCountWithResponseUnread() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Test Offer',
            Details__c = 'Offering help',
            Type__c = 'Services - Free',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id
        );
        insert post;

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Response__c resp = new Response__c(
            Name = 'My Response',
            Response__c = 'I need this',
            Contact__c = myContact.Id,
            On_Behalf_Of_Contact__c = myContact.Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Last_Reply__c = 'Great, let me know',
            Last_Reply_Date__c = Date.today(),
            Last_Reply_Contact_Lookup__c = others[0].Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            Integer count = FimbyCommunicationController.getUnifiedUnreadCount();
            System.assert(count >= 1, 'Should have at least 1 unread from response');
        }
        Test.stopTest();
    }

    // ================================================================
    // markResponseViewed tests
    // ================================================================

    @IsTest
    static void testMarkResponseViewedAsPoster() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'My Post',
            Details__c = 'My post details',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = myContact.Id,
            Contact__c = myContact.Id
        );
        insert post;

        Response__c resp = new Response__c(
            Name = 'Someone Responded',
            Response__c = 'I can help',
            Contact__c = others[0].Id,
            On_Behalf_Of_Contact__c = others[0].Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markResponseViewed(resp.Id);
        }
        Test.stopTest();

        Response__c updated = [
            SELECT Poster_Last_Viewed__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertNotEquals(null, updated.Poster_Last_Viewed__c, 'Poster_Last_Viewed__c should be set');
    }

    @IsTest
    static void testMarkResponseViewedAsResponder() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Other Post',
            Details__c = 'Someone elses post',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id
        );
        insert post;

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Response__c resp = new Response__c(
            Name = 'My Response',
            Response__c = 'I can help',
            Contact__c = myContact.Id,
            On_Behalf_Of_Contact__c = myContact.Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markResponseViewed(resp.Id);
        }
        Test.stopTest();

        Response__c updated = [
            SELECT Responder_Last_Viewed__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertNotEquals(null, updated.Responder_Last_Viewed__c, 'Responder_Last_Viewed__c should be set');
    }

    @IsTest
    static void testMarkResponseViewedNullId() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markResponseViewed(null);
        }
        Test.stopTest();
    }

    // ================================================================
    // markThreadUnread tests
    // ================================================================

    @IsTest
    static void testMarkThreadUnreadDirect() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Id convId;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> convResult = FimbyConversationController.getOrCreateConversation(others[0].Id);
            convId = (Id) convResult.get('conversationId');

            FimbyCommunicationController.markThreadUnread('direct', convId);

            Conversation__c updated = [
                SELECT Participant_1_Unread_Count__c FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(1, updated.Participant_1_Unread_Count__c, 'Should set unread count to 1');
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkThreadUnreadResponse() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'My Post',
            Details__c = 'My post details',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = myContact.Id,
            Contact__c = myContact.Id
        );
        insert post;

        Response__c resp = new Response__c(
            Name = 'Someone Responded',
            Response__c = 'I can help',
            Contact__c = others[0].Id,
            On_Behalf_Of_Contact__c = others[0].Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Poster_Last_Viewed__c = Datetime.now()
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markThreadUnread('response', resp.Id);
        }
        Test.stopTest();

        Response__c updated = [
            SELECT Poster_Last_Viewed__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertEquals(null, updated.Poster_Last_Viewed__c, 'Poster_Last_Viewed__c should be cleared');
    }

    @IsTest
    static void testArchiveThreadResponse() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'My Post',
            Details__c = 'My post details',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = myContact.Id,
            Contact__c = myContact.Id
        );
        insert post;

        Response__c resp = new Response__c(
            Name = 'Someone Responded',
            Response__c = 'I can help',
            Contact__c = others[0].Id,
            On_Behalf_Of_Contact__c = others[0].Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.archiveThread('response', resp.Id);
        }
        Test.stopTest();

        Response__c updated = [
            SELECT Poster_Archived__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertEquals(true, updated.Poster_Archived__c, 'Poster_Archived__c should be set');
    }

    @IsTest
    static void testArchiveThreadDirect() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Id convId;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> convResult = FimbyConversationController.getOrCreateConversation(others[0].Id);
            convId = (Id) convResult.get('conversationId');

            FimbyCommunicationController.archiveThread('direct', convId);

            Conversation__c updated = [
                SELECT Participant_1_Archived__c FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(true, updated.Participant_1_Archived__c, 'Should be archived');
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkThreadUnreadLibrary() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Id convId;

        Test.startTest();
        System.runAs(testUser) {
            Conversation__c conv = new Conversation__c(
                Participant_1__c = testUser.ContactId,
                Participant_2__c = others[0].Id,
                Status__c = 'Active',
                Context_Type__c = 'Library_Lending',
                Participant_1_Unread_Count__c = 0,
                Participant_2_Unread_Count__c = 0,
                Participant_1_Archived__c = false,
                Participant_2_Archived__c = false
            );
            insert conv;
            convId = conv.Id;

            FimbyCommunicationController.markThreadUnread('library', convId);

            Conversation__c updated = [
                SELECT Participant_1_Unread_Count__c FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(1, updated.Participant_1_Unread_Count__c, 'Should set unread count to 1');
        }
        Test.stopTest();
    }

    @IsTest
    static void testArchiveThreadLibrary() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Id convId;

        Test.startTest();
        System.runAs(testUser) {
            Conversation__c conv = new Conversation__c(
                Participant_1__c = testUser.ContactId,
                Participant_2__c = others[0].Id,
                Status__c = 'Active',
                Context_Type__c = 'Library_Lending',
                Participant_1_Unread_Count__c = 0,
                Participant_2_Unread_Count__c = 0,
                Participant_1_Archived__c = false,
                Participant_2_Archived__c = false
            );
            insert conv;
            convId = conv.Id;

            FimbyCommunicationController.archiveThread('library', convId);

            Conversation__c updated = [
                SELECT Participant_1_Archived__c FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(true, updated.Participant_1_Archived__c, 'Should be archived');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetRetentionDaysForDisclaimer() {
        Test.startTest();
        Map<String, Integer> result = FimbyCommunicationController.getRetentionDaysForDisclaimer();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('dmDays'), 'Should have dmDays');
        System.assert(result.containsKey('responseDays'), 'Should have responseDays');
        System.assert(result.containsKey('libraryDays'), 'Should have libraryDays');
        System.assert(result.get('dmDays') != null, 'dmDays should have value');
        System.assert(result.get('responseDays') != null, 'responseDays should have value');
        System.assert(result.get('libraryDays') != null, 'libraryDays should have value');
    }

    @IsTest
    static void testGetThreadsExcludesArchivedResponse() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'My Post',
            Details__c = 'My post details',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = myContact.Id,
            Contact__c = myContact.Id
        );
        insert post;

        Response__c resp = new Response__c(
            Name = 'Archived Response',
            Response__c = 'I can help',
            Contact__c = others[0].Id,
            On_Behalf_Of_Contact__c = others[0].Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Poster_Archived__c = true
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'responses', null);
            System.assertEquals(0, result.totalCount, 'Archived response should not appear in threads');
        }
        Test.stopTest();
    }

    @IsTest
    static void testArchiveThreadAsResponder() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Other Post',
            Details__c = 'Someone elses post',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id
        );
        insert post;

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Response__c resp = new Response__c(
            Name = 'My Response',
            Response__c = 'I can help',
            Contact__c = myContact.Id,
            On_Behalf_Of_Contact__c = myContact.Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.archiveThread('response', resp.Id);
        }
        Test.stopTest();

        Response__c updated = [
            SELECT Responder_Archived__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertEquals(true, updated.Responder_Archived__c, 'Responder_Archived__c should be set');
    }

    @IsTest
    static void testMarkThreadUnreadResponseAsResponder() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Other Post',
            Details__c = 'Someone elses post',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id
        );
        insert post;

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Response__c resp = new Response__c(
            Name = 'My Response',
            Response__c = 'I can help',
            Contact__c = myContact.Id,
            On_Behalf_Of_Contact__c = myContact.Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Responder_Last_Viewed__c = Datetime.now()
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markThreadUnread('response', resp.Id);
        }
        Test.stopTest();

        Response__c updated = [
            SELECT Responder_Last_Viewed__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertEquals(null, updated.Responder_Last_Viewed__c, 'Responder_Last_Viewed__c should be cleared');
    }

    @IsTest
    static void testMarkThreadUnreadInvalidParams() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markThreadUnread(null, null);
            FimbyCommunicationController.markThreadUnread('', null);
        }
        Test.stopTest();
    }

    // ================================================================
    // markThreadRead tests
    // ================================================================

    @IsTest
    static void testMarkThreadReadDirect() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Id convId;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> convResult = FimbyConversationController.getOrCreateConversation(others[0].Id);
            convId = (Id) convResult.get('conversationId');

            FimbyCommunicationController.markThreadUnread('direct', convId);

            Conversation__c before = [
                SELECT Participant_1_Unread_Count__c FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(1, before.Participant_1_Unread_Count__c, 'Should be unread first');

            FimbyCommunicationController.markThreadRead('direct', convId);

            Conversation__c updated = [
                SELECT Participant_1_Unread_Count__c FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(0, updated.Participant_1_Unread_Count__c, 'Should set unread count to 0');
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkThreadReadResponse() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'My Post',
            Details__c = 'My post details',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = myContact.Id,
            Contact__c = myContact.Id
        );
        insert post;

        Response__c resp = new Response__c(
            Name = 'Someone Responded',
            Response__c = 'I can help',
            Contact__c = others[0].Id,
            On_Behalf_Of_Contact__c = others[0].Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Poster_Last_Viewed__c = null
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markThreadRead('response', resp.Id);
        }
        Test.stopTest();

        Response__c updated = [
            SELECT Poster_Last_Viewed__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertNotEquals(null, updated.Poster_Last_Viewed__c, 'Poster_Last_Viewed__c should be set');
    }

    @IsTest
    static void testMarkThreadReadResponseAsResponder() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Other Post',
            Details__c = 'Someone elses post',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id
        );
        insert post;

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Response__c resp = new Response__c(
            Name = 'My Response',
            Response__c = 'I can help',
            Contact__c = myContact.Id,
            On_Behalf_Of_Contact__c = myContact.Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Responder_Last_Viewed__c = null
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markThreadRead('response', resp.Id);
        }
        Test.stopTest();

        Response__c updated = [
            SELECT Responder_Last_Viewed__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertNotEquals(null, updated.Responder_Last_Viewed__c, 'Responder_Last_Viewed__c should be set');
    }

    @IsTest
    static void testMarkThreadReadLibrary() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Id convId;

        Test.startTest();
        System.runAs(testUser) {
            Conversation__c conv = new Conversation__c(
                Participant_1__c = testUser.ContactId,
                Participant_2__c = others[0].Id,
                Status__c = 'Active',
                Context_Type__c = 'Library_Lending',
                Participant_1_Unread_Count__c = 3,
                Participant_2_Unread_Count__c = 0,
                Participant_1_Archived__c = false,
                Participant_2_Archived__c = false
            );
            insert conv;
            convId = conv.Id;

            FimbyCommunicationController.markThreadRead('library', convId);

            Conversation__c updated = [
                SELECT Participant_1_Unread_Count__c FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(0, updated.Participant_1_Unread_Count__c, 'Should set unread count to 0');
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkThreadReadInvalidParams() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markThreadRead(null, null);
            FimbyCommunicationController.markThreadRead('', null);
        }
        Test.stopTest();
    }

    // ================================================================
    // getBadgeCounts tests
    // ================================================================

    @IsTest
    static void testGetBadgeCountsZero() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Integer> counts = FimbyCommunicationController.getBadgeCounts();
            System.assertNotEquals(null, counts, 'Result should not be null');
            System.assertEquals(0, counts.get('notifications'), 'Should have 0 notifications');
            System.assertEquals(0, counts.get('messages'), 'Should have 0 messages');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreads_OrgContactDmThread() {
        User testUser = getTestUser();
        Contact myContact = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId];

        Account orgAccount = new Account(Name = 'Community Garden Club', Logo_URL__c = 'https://example.com/garden.jpg');
        try {
            orgAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();
        } catch (Exception e) { /* RT may not exist */ }
        insert orgAccount;

        Contact orgContact = new Contact(
            FirstName = 'Org', LastName = 'GardenClub',
            AccountId = myContact.AccountId,
            Is_Organization_Contact__c = true,
            Organization_Account__c = orgAccount.Id
        );
        insert orgContact;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = myContact.Id,
            Participant_2__c = orgContact.Id,
            Status__c = 'Active',
            Participant_1_Unread_Count__c = 0,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false,
            Last_Message_Date__c = Datetime.now(),
            Last_Message_Preview__c = 'Hello from org'
        );
        insert conv;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'direct', null);

            Boolean foundOrgThread = false;
            for (FimbyCommunicationController.CommunicationThread t : result.threads) {
                if (t.threadId == conv.Id) {
                    foundOrgThread = true;
                    System.assertEquals(true, t.isOrgContact, 'Thread should have isOrgContact=true');
                    System.assertEquals('Community Garden Club', t.participantName, 'Should use org account name');
                    System.assertEquals('https://example.com/garden.jpg', t.participantImageUrl, 'Should use org logo URL');
                }
            }
            System.assert(foundOrgThread, 'Should find the org contact DM thread');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreads_OrgContactResponseThread() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Contact myContact = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId];
        Account neighbourhood = [SELECT Id FROM Account WHERE Id = :myContact.AccountId];

        Account orgAccount = new Account(Name = 'Community Garden Club', Logo_URL__c = 'https://example.com/garden.jpg');
        try {
            orgAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();
        } catch (Exception e) { /* RT may not exist */ }
        insert orgAccount;

        Contact orgContact = new Contact(
            FirstName = 'Org', LastName = 'GardenClub',
            AccountId = neighbourhood.Id,
            Is_Organization_Contact__c = true,
            Organization_Account__c = orgAccount.Id
        );
        insert orgContact;

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Org Need',
            Details__c = 'Org contact posted this',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = orgContact.Id,
            Contact__c = orgContact.Id
        );
        insert post;

        Response__c resp = new Response__c(
            Name = 'My Response',
            Response__c = 'I can help the org',
            Contact__c = myContact.Id,
            On_Behalf_Of_Contact__c = myContact.Id,
            Need_Offer_Responded_To__c = post.Id,
            Reply_To_Contact__c = orgContact.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Last_Reply__c = 'Thanks for helping',
            Last_Reply_Date__c = Date.today(),
            Last_Reply_Contact_Lookup__c = orgContact.Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'responses', null);

            Boolean foundOrgThread = false;
            for (FimbyCommunicationController.CommunicationThread t : result.threads) {
                if (t.threadId == resp.Id) {
                    foundOrgThread = true;
                    System.assertEquals(true, t.isOrgContact, 'Response thread should have isOrgContact=true');
                    System.assertEquals('Community Garden Club', t.participantName,
                        'Participant name should be org account name');
                    System.assertEquals('https://example.com/garden.jpg', t.participantImageUrl,
                        'Participant image should be org logo');
                }
            }
            System.assert(foundOrgThread, 'Should find the org contact response thread');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetBadgeCountsWithUnread() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = others[0].Id,
            Status__c = 'Active',
            Participant_1_Unread_Count__c = 2,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false
        );
        insert conv;

        Notification__c notif = new Notification__c(
            Contact__c = testUser.ContactId,
            Title__c = 'Test',
            Body__c = 'Test notification',
            Type__c = 'Response'
        );
        insert notif;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Integer> counts = FimbyCommunicationController.getBadgeCounts();
            System.assertEquals(1, counts.get('notifications'), 'Should have 1 notification');
            System.assertEquals(1, counts.get('messages'), 'Should count 1 unread conversation');
        }
        Test.stopTest();
    }

    // ================================================================
    // Unread filter tests
    // ================================================================

    @IsTest
    static void testGetThreadsUnreadFilter() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        Conversation__c readConv = new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = others[0].Id,
            Status__c = 'Active',
            Participant_1_Unread_Count__c = 0,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false,
            Last_Message_Date__c = Datetime.now().addHours(-1),
            Last_Message_Preview__c = 'Read message'
        );
        insert readConv;

        Conversation__c unreadConv = new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = others[1].Id,
            Status__c = 'Active',
            Participant_1_Unread_Count__c = 2,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false,
            Last_Message_Date__c = Datetime.now(),
            Last_Message_Preview__c = 'Unread message'
        );
        insert unreadConv;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult allResult =
                FimbyCommunicationController.getThreads(20, 0, 'all', null);
            System.assertEquals(2, allResult.totalCount, 'All filter should return both threads');

            FimbyCommunicationController.ThreadListResult unreadResult =
                FimbyCommunicationController.getThreads(20, 0, 'unread', null);
            System.assertEquals(1, unreadResult.totalCount, 'Unread filter should return only unread thread');
            System.assertEquals(true, unreadResult.threads[0].isUnread, 'Thread should be unread');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsUnreadFilterExcludesArchived() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        Conversation__c archivedUnread = new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = others[0].Id,
            Status__c = 'Active',
            Participant_1_Unread_Count__c = 5,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = true,
            Participant_2_Archived__c = false,
            Last_Message_Date__c = Datetime.now(),
            Last_Message_Preview__c = 'Archived unread'
        );
        insert archivedUnread;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult unreadResult =
                FimbyCommunicationController.getThreads(20, 0, 'unread', null);
            System.assertEquals(0, unreadResult.totalCount,
                'Unread filter should exclude archived threads');
        }
        Test.stopTest();
    }

    // ================================================================
    // Archived filter tests
    // ================================================================

    @IsTest
    static void testGetThreadsArchivedFilterDm() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        Conversation__c activeConv = new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = others[0].Id,
            Status__c = 'Active',
            Participant_1_Unread_Count__c = 0,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false,
            Last_Message_Date__c = Datetime.now(),
            Last_Message_Preview__c = 'Active message'
        );
        insert activeConv;

        Conversation__c archivedConv = new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = others[1].Id,
            Status__c = 'Active',
            Participant_1_Unread_Count__c = 0,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = true,
            Participant_2_Archived__c = false,
            Last_Message_Date__c = Datetime.now().addHours(-1),
            Last_Message_Preview__c = 'Archived message'
        );
        insert archivedConv;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult archivedResult =
                FimbyCommunicationController.getThreads(20, 0, 'archived', null);
            System.assertEquals(1, archivedResult.totalCount, 'Archived filter should return 1 thread');
            System.assertEquals(archivedConv.Id, archivedResult.threads[0].threadId,
                'Should return the archived conversation');

            FimbyCommunicationController.ThreadListResult allResult =
                FimbyCommunicationController.getThreads(20, 0, 'all', null);
            Boolean foundArchived = false;
            for (FimbyCommunicationController.CommunicationThread t : allResult.threads) {
                if (t.threadId == archivedConv.Id) foundArchived = true;
            }
            System.assertEquals(false, foundArchived, 'All filter should exclude archived conversation');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsArchivedFilterResponse() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'My Post',
            Details__c = 'My post details',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = myContact.Id,
            Contact__c = myContact.Id
        );
        insert post;

        Response__c resp = new Response__c(
            Name = 'Archived Response',
            Response__c = 'I can help',
            Contact__c = others[0].Id,
            On_Behalf_Of_Contact__c = others[0].Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Poster_Archived__c = true,
            Last_Reply__c = 'Thanks',
            Last_Reply_Date__c = Date.today(),
            Last_Reply_Contact_Lookup__c = others[0].Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult archivedResult =
                FimbyCommunicationController.getThreads(20, 0, 'archived', null);

            Boolean foundArchived = false;
            for (FimbyCommunicationController.CommunicationThread t : archivedResult.threads) {
                if (t.threadId == resp.Id) foundArchived = true;
            }
            System.assert(foundArchived, 'Archived filter should return archived response thread');

            FimbyCommunicationController.ThreadListResult allResult =
                FimbyCommunicationController.getThreads(20, 0, 'all', null);
            Boolean foundInAll = false;
            for (FimbyCommunicationController.CommunicationThread t : allResult.threads) {
                if (t.threadId == resp.Id) foundInAll = true;
            }
            System.assertEquals(false, foundInAll, 'All filter should exclude archived response thread');
        }
        Test.stopTest();
    }

    // ================================================================
    // unarchiveThread tests
    // ================================================================

    @IsTest
    static void testUnarchiveThreadDirect() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Id convId;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> convResult = FimbyConversationController.getOrCreateConversation(others[0].Id);
            convId = (Id) convResult.get('conversationId');

            FimbyCommunicationController.archiveThread('direct', convId);
            Conversation__c archived = [
                SELECT Participant_1_Archived__c FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(true, archived.Participant_1_Archived__c, 'Should be archived first');

            FimbyCommunicationController.unarchiveThread('direct', convId);
            Conversation__c updated = [
                SELECT Participant_1_Archived__c FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(false, updated.Participant_1_Archived__c, 'Should be unarchived');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUnarchiveThreadResponse() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'My Post',
            Details__c = 'My post details',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = myContact.Id,
            Contact__c = myContact.Id
        );
        insert post;

        Response__c resp = new Response__c(
            Name = 'Archived Response',
            Response__c = 'I can help',
            Contact__c = others[0].Id,
            On_Behalf_Of_Contact__c = others[0].Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Poster_Archived__c = true
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.unarchiveThread('response', resp.Id);
        }
        Test.stopTest();

        Response__c updated = [
            SELECT Poster_Archived__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertEquals(false, updated.Poster_Archived__c, 'Poster_Archived__c should be cleared');
    }

    @IsTest
    static void testUnarchiveThreadLibrary() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Id convId;

        Test.startTest();
        System.runAs(testUser) {
            Conversation__c conv = new Conversation__c(
                Participant_1__c = testUser.ContactId,
                Participant_2__c = others[0].Id,
                Status__c = 'Active',
                Context_Type__c = 'Library_Lending',
                Participant_1_Unread_Count__c = 0,
                Participant_2_Unread_Count__c = 0,
                Participant_1_Archived__c = false,
                Participant_2_Archived__c = false,
                Last_Message_Date__c = Datetime.now(),
                Last_Message_Preview__c = 'Library message'
            );
            insert conv;
            convId = conv.Id;

            FimbyCommunicationController.archiveThread('library', convId);
            Conversation__c archived = [
                SELECT Participant_1_Archived__c FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(true, archived.Participant_1_Archived__c, 'Should be archived first');

            FimbyCommunicationController.unarchiveThread('library', convId);
            Conversation__c updated = [
                SELECT Participant_1_Archived__c FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(false, updated.Participant_1_Archived__c, 'Should be unarchived');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUnarchiveThreadResponseAsResponder() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Other Post',
            Details__c = 'Someone elses post',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id
        );
        insert post;

        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        Response__c resp = new Response__c(
            Name = 'My Response',
            Response__c = 'I can help',
            Contact__c = myContact.Id,
            On_Behalf_Of_Contact__c = myContact.Id,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Responder_Archived__c = true
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.unarchiveThread('response', resp.Id);
        }
        Test.stopTest();

        Response__c updated = [
            SELECT Responder_Archived__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertEquals(false, updated.Responder_Archived__c, 'Responder_Archived__c should be cleared');
    }

    // ================================================================
    // Badge type + unified inbox (group threads)
    // ================================================================

    @IsTest
    static void testGetThreadsMissedPickupBadge() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        insert new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = others[0].Id,
            Status__c = 'Active',
            Context_Type__c = 'Missed_Pickup',
            Participant_1_Unread_Count__c = 1,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false,
            Last_Message_Date__c = Datetime.now(),
            Last_Message_Preview__c = 'Check in'
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'all', null);
            System.assertEquals(1, result.totalCount);
            System.assertEquals('checkin', result.threads[0].badgeType);
            System.assertEquals('checkin', result.threads[0].threadType);
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkThreadReadMissedPickupConversation() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = others[0].Id,
            Status__c = 'Active',
            Context_Type__c = 'Missed_Pickup',
            Participant_1_Unread_Count__c = 2,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false
        );
        insert conv;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markThreadRead('checkin', conv.Id);
        }
        Test.stopTest();

        Conversation__c updated = [
            SELECT Participant_1_Unread_Count__c FROM Conversation__c WHERE Id = :conv.Id
        ];
        System.assertEquals(0, updated.Participant_1_Unread_Count__c.intValue());
    }

    @IsTest
    static void testGetThreadsBulkBuyResponseBadge() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Id bbRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName()
            .get('Bulk_Buy').getRecordTypeId();
        Needs_Offers__c post = new Needs_Offers__c(
            RecordTypeId = bbRt,
            Name = 'Bulk Buy Post',
            Details__c = 'Details',
            Full_Details__c = 'Full',
            Status__c = 'Available',
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id,
            Neighbourhood__c = neighbourhood.Id,
            Giver_Recipient_Type__c = 'Self',
            Total_Quantity__c = 10,
            Allocation_Unit_Label__c = 'shares',
            Availability_Rule__c = 'Open_Until_Full_Or_Closed',
            Auto_Accept_Responses__c = true,
            Auto_Lock_Days__c = '7'
        );
        insert post;

        Response__c resp = new Response__c(
            Name = 'Reservation',
            Response__c = '2 shares',
            Contact__c = testUser.ContactId,
            On_Behalf_Of_Contact__c = testUser.ContactId,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Last_Reply__c = 'Thanks',
            Last_Reply_Date__c = Date.today(),
            Last_Reply_Contact_Lookup__c = others[0].Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'responses', null);
            System.assertEquals(1, result.totalCount);
            System.assertEquals('bulkbuy', result.threads[0].badgeType);
            System.assertEquals('response', result.threads[0].threadType);
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkThreadReadBulkBuyResponseRoutesToResponse() {
        User testUser = getTestUser();
        List<Contact> others = getOtherContacts();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'BB Post',
            Details__c = 'D',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = others[0].Id,
            Contact__c = others[0].Id
        );
        insert post;

        Response__c resp = new Response__c(
            Name = 'R',
            Response__c = 'Help',
            Contact__c = testUser.ContactId,
            On_Behalf_Of_Contact__c = testUser.ContactId,
            Need_Offer_Responded_To__c = post.Id,
            Status__c = 'New',
            Neighbourhood__c = neighbourhood.Id,
            Last_Reply_Date__c = Date.today(),
            Last_Reply_Contact_Lookup__c = others[0].Id
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markThreadRead('response', resp.Id);
        }
        Test.stopTest();

        Response__c updated = [
            SELECT Responder_Last_Viewed__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertNotEquals(null, updated.Responder_Last_Viewed__c);
    }

    @IsTest
    static void testGetThreadsWithGroupConversation() {
        User testUser = getTestUser();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Id bbRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName()
            .get('Bulk_Buy').getRecordTypeId();
        Needs_Offers__c post = new Needs_Offers__c(
            RecordTypeId = bbRt,
            Name = 'Group Bulk Buy',
            Details__c = 'Details',
            Full_Details__c = 'Full',
            Status__c = 'Available',
            Posted_By__c = testUser.ContactId,
            Contact__c = testUser.ContactId,
            Neighbourhood__c = neighbourhood.Id,
            Giver_Recipient_Type__c = 'Self',
            Total_Quantity__c = 10,
            Allocation_Unit_Label__c = 'shares',
            Availability_Rule__c = 'Open_Until_Full_Or_Closed',
            Auto_Accept_Responses__c = true,
            Auto_Lock_Days__c = '7',
            Image_1_URL__c = 'https://example.com/post.jpg'
        );
        insert post;

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true,
            Group_Name__c = 'Group Bulk Buy',
            Context_Type__c = 'Bulk_Buy',
            Related_Record_Id__c = post.Id,
            Status__c = 'Active',
            Last_Message_Date__c = Datetime.now(),
            Last_Message_Preview__c = 'Hello group'
        );
        insert conv;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id,
            Contact__c = testUser.ContactId,
            Role__c = 'Owner',
            Status__c = 'Active',
            Joined_Date__c = System.now(),
            Unread_Count__c = 1,
            Archived__c = false
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'all', null);
            System.assertEquals(1, result.totalCount);
            System.assertEquals('group', result.threads[0].threadType);
            System.assertEquals('bulkbuy', result.threads[0].badgeType);
            System.assertEquals(true, result.threads[0].isGroup);
            System.assertEquals('Group Bulk Buy', result.threads[0].participantName);
            System.assertEquals('https://example.com/post.jpg', result.threads[0].participantImageUrl);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetThreadsGroupEventBadge() {
        User testUser = getTestUser();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact myContact = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];

        Needs_Offers__c openEventPost = new Needs_Offers__c(
            Name = 'Park Meetup',
            Details__c = 'Open event',
            Type__c = 'Event',
            Event_Type__c = 'Open_Event',
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhood.Id,
            Posted_By__c = myContact.Id,
            Contact__c = myContact.Id
        );
        insert openEventPost;

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true,
            Group_Name__c = 'Open Event Chat',
            Context_Type__c = 'Event',
            Related_Record_Id__c = String.valueOf(openEventPost.Id),
            Status__c = 'Active',
            Last_Message_Date__c = Datetime.now()
        );
        insert conv;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id,
            Contact__c = testUser.ContactId,
            Role__c = 'Member',
            Status__c = 'Active',
            Joined_Date__c = System.now(),
            Unread_Count__c = 0,
            Archived__c = false
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.ThreadListResult result =
                FimbyCommunicationController.getThreads(20, 0, 'all', null);
            System.assertEquals(1, result.totalCount);
            System.assertEquals('event', result.threads[0].badgeType);
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkThreadReadGroupMember() {
        User testUser = getTestUser();

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true,
            Group_Name__c = 'Read Test Group',
            Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id,
            Contact__c = testUser.ContactId,
            Role__c = 'Member',
            Status__c = 'Active',
            Joined_Date__c = System.now(),
            Unread_Count__c = 3,
            Archived__c = false
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.markThreadRead('group', conv.Id);
        }
        Test.stopTest();

        Conversation_Member__c member = [
            SELECT Unread_Count__c, Last_Read_Date__c
            FROM Conversation_Member__c
            WHERE Conversation__c = :conv.Id AND Contact__c = :testUser.ContactId
            LIMIT 1
        ];
        System.assertEquals(0, member.Unread_Count__c.intValue());
        System.assertNotEquals(null, member.Last_Read_Date__c);
    }

    @IsTest
    static void testArchiveThreadGroupMember() {
        User testUser = getTestUser();

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true,
            Group_Name__c = 'Archive Test Group',
            Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active',
            Last_Message_Date__c = Datetime.now()
        );
        insert conv;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id,
            Contact__c = testUser.ContactId,
            Role__c = 'Member',
            Status__c = 'Active',
            Joined_Date__c = System.now(),
            Unread_Count__c = 0,
            Archived__c = false
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbyCommunicationController.archiveThread('group', conv.Id);
            FimbyCommunicationController.ThreadListResult active =
                FimbyCommunicationController.getThreads(20, 0, 'all', null);
            System.assertEquals(0, active.totalCount, 'Archived group should not appear in all');

            FimbyCommunicationController.ThreadListResult archived =
                FimbyCommunicationController.getThreads(20, 0, 'archived', null);
            System.assertEquals(1, archived.totalCount);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetUnifiedUnreadCountIncludesGroup() {
        User testUser = getTestUser();

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true,
            Group_Name__c = 'Unread Group',
            Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id,
            Contact__c = testUser.ContactId,
            Role__c = 'Member',
            Status__c = 'Active',
            Joined_Date__c = System.now(),
            Unread_Count__c = 2,
            Archived__c = false
        );

        Test.startTest();
        System.runAs(testUser) {
            Integer count = FimbyCommunicationController.getUnifiedUnreadCount();
            System.assert(count >= 1, 'Group unread should count toward unified badge');
        }
        Test.stopTest();
    }
}
