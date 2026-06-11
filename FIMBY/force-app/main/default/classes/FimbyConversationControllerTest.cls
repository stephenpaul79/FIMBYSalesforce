@IsTest
public class FimbyConversationControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(neighbourhood.Id, 3, true);
        User communityUser = FimbyTestDataFactory.createCommunityUser(contacts[0].Id, 'Customer Community User - Mobile App', true);

        // Create shared contact info between contact[0] and contact[1]
        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = contacts[0].Id,
            Shared_To__c = contacts[1].Id,
            Email__c = 'shared@test.com',
            Phone__c = '0400000000'
        );
        insert sci;

        // Create shared contact info between contact[0] and contact[2]
        Shared_Contact_Info__c sci2 = new Shared_Contact_Info__c(
            Contact__c = contacts[2].Id,
            Shared_To__c = contacts[0].Id,
            Email__c = 'shared2@test.com'
        );
        insert sci2;
    }

    private static User getTestUser() {
        return [SELECT Id, ContactId FROM User WHERE Profile.Name = 'Customer Community User - Mobile App' AND IsActive = true ORDER BY CreatedDate DESC LIMIT 1];
    }

    private static Contact getOtherContact() {
        User u = getTestUser();
        Contact myContact = [SELECT Id, AccountId FROM Contact WHERE Id = :u.ContactId];
        Id neighbourhoodId = myContact.AccountId;
        return [SELECT Id FROM Contact WHERE Id != :myContact.Id AND AccountId = :neighbourhoodId LIMIT 1];
    }

    @IsTest
    static void testGetConversationsEmpty() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyConversationController.ConversationListResult result =
                FimbyConversationController.getConversations(20, 0, 'all', null);

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertEquals(0, result.totalCount, 'Should have no conversations');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetOrCreateConversation() {
        User testUser = getTestUser();
        Contact other = getOtherContact();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyConversationController.getOrCreateConversation(other.Id);

            System.assertEquals(true, result.get('success'), 'Should succeed');
            System.assertEquals(true, result.get('isNew'), 'Should be a new conversation');
            System.assertNotEquals(null, result.get('conversationId'), 'Should have conversation ID');

            // Call again — should find existing
            Map<String, Object> result2 = FimbyConversationController.getOrCreateConversation(other.Id);
            System.assertEquals(false, result2.get('isNew'), 'Should find existing conversation');
            System.assertEquals(result.get('conversationId'), result2.get('conversationId'), 'Should be same conversation');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetOrCreateConversationNoSharedContact() {
        User testUser = getTestUser();

        // Create a contact with NO shared contact info
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact stranger = new Contact(FirstName = 'Stranger', LastName = 'Person', AccountId = neighbourhood.Id);
        insert stranger;

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyConversationController.getOrCreateConversation(stranger.Id);
                System.assert(false, 'Should have thrown exception for non-shared contact');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e.getMessage(), 'Should have an error message');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetConversationsWithData() {
        User testUser = getTestUser();
        Contact other = getOtherContact();

        Test.startTest();
        System.runAs(testUser) {
            FimbyConversationController.getOrCreateConversation(other.Id);

            FimbyConversationController.ConversationListResult result =
                FimbyConversationController.getConversations(20, 0, 'all', null);

            System.assertEquals(1, result.conversations.size(), 'Should have 1 conversation');
            System.assertNotEquals(null, result.conversations[0].participantName, 'Should have participant name');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetConversationsUnreadFilter() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyConversationController.ConversationListResult result =
                FimbyConversationController.getConversations(20, 0, 'unread', null);

            System.assertNotEquals(null, result, 'Result should not be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void testArchiveUnarchiveConversation() {
        User testUser = getTestUser();
        Contact other = getOtherContact();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> conv = FimbyConversationController.getOrCreateConversation(other.Id);
            Id convId = (Id) conv.get('conversationId');

            FimbyConversationController.archiveConversation(convId);

            // Should appear in archived filter
            FimbyConversationController.ConversationListResult archived =
                FimbyConversationController.getConversations(20, 0, 'archived', null);
            System.assertEquals(1, archived.conversations.size(), 'Should have 1 archived conversation');

            // Unarchive
            FimbyConversationController.unarchiveConversation(convId);

            FimbyConversationController.ConversationListResult allConvs =
                FimbyConversationController.getConversations(20, 0, 'all', null);
            System.assertEquals(1, allConvs.conversations.size(), 'Should have 1 conversation in all');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetUnreadMessageCount() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Integer count = FimbyConversationController.getUnreadMessageCount();
            System.assertEquals(0, count, 'Should have 0 unread messages');
        }
        Test.stopTest();
    }

    @IsTest
    static void testBlockAndUnblockContact() {
        User testUser = getTestUser();
        Contact other = getOtherContact();

        Test.startTest();
        System.runAs(testUser) {
            // Create conversation first
            FimbyConversationController.getOrCreateConversation(other.Id);

            // Block
            Map<String, Object> blockResult = FimbyConversationController.blockContact(
                other.Id, 'Spam', true, 'Sending spam messages'
            );
            System.assertEquals(true, blockResult.get('success'), 'Block should succeed');
            System.assertEquals(false, blockResult.get('alreadyBlocked'), 'Should not already be blocked');

            // Block again — should report already blocked
            Map<String, Object> blockResult2 = FimbyConversationController.blockContact(
                other.Id, 'Spam', false, null
            );
            System.assertEquals(true, blockResult2.get('alreadyBlocked'), 'Should be already blocked');

            // Get blocked contacts
            List<FimbyConversationController.BlockedContactWrapper> blocked =
                FimbyConversationController.getBlockedContacts();
            System.assertEquals(1, blocked.size(), 'Should have 1 blocked contact');

            // Unblock
            FimbyConversationController.unblockContact(other.Id);

            List<FimbyConversationController.BlockedContactWrapper> afterUnblock =
                FimbyConversationController.getBlockedContacts();
            System.assertEquals(0, afterUnblock.size(), 'Should have 0 blocked contacts');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchNeighboursForBlock() {
        User testUser = getTestUser();
        Contact other = getOtherContact();

        Test.startTest();
        System.runAs(testUser) {
            List<Map<String, Object>> results =
                FimbyConversationController.searchNeighboursForBlock('Resident');
            System.assert(results.size() >= 1, 'Should find unblocked neighbourhood contacts');

            FimbyConversationController.blockContact(other.Id, 'Test', false, null);

            List<Map<String, Object>> afterBlock =
                FimbyConversationController.searchNeighboursForBlock('Resident');
            for (Map<String, Object> row : afterBlock) {
                System.assertNotEquals(
                    other.Id,
                    row.get('contactId'),
                    'Already blocked contact should not appear in search'
                );
            }

            System.assertEquals(
                0,
                FimbyConversationController.searchNeighboursForBlock('a').size(),
                'Search under 2 chars returns empty'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMessageableContacts() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            List<Map<String, Object>> contacts =
                FimbyConversationController.getMessageableContacts(null);

            System.assert(contacts.size() >= 1, 'Should have at least 1 messageable contact');

            // Test with search
            List<Map<String, Object>> searched =
                FimbyConversationController.getMessageableContacts('Resident');
            System.assertNotEquals(null, searched, 'Search result should not be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetConversationsWithSearch() {
        User testUser = getTestUser();
        Contact other = getOtherContact();

        Test.startTest();
        System.runAs(testUser) {
            FimbyConversationController.getOrCreateConversation(other.Id);

            FimbyConversationController.ConversationListResult result =
                FimbyConversationController.getConversations(20, 0, 'all', 'Resident');

            System.assertNotEquals(null, result, 'Search result should not be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void testIsConversationRevokedFalse() {
        User testUser = getTestUser();
        Contact other = getOtherContact();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> conv = FimbyConversationController.getOrCreateConversation(other.Id);
            Id convId = (Id) conv.get('conversationId');

            Boolean revoked = FimbyConversationController.isConversationRevoked(convId);
            System.assertEquals(false, revoked, 'Should not be revoked with active SCI');
        }
        Test.stopTest();
    }

    @IsTest
    static void testIsConversationRevokedTrue() {
        User testUser = getTestUser();
        Contact other = getOtherContact();

        // First create a conversation
        Id convId;
        System.runAs(testUser) {
            Map<String, Object> conv = FimbyConversationController.getOrCreateConversation(other.Id);
            convId = (Id) conv.get('conversationId');
        }

        // Revoke all SCI records between the two contacts
        List<Shared_Contact_Info__c> scis = [
            SELECT Id FROM Shared_Contact_Info__c
            WHERE (Contact__c = :testUser.ContactId AND Shared_To__c = :other.Id)
               OR (Contact__c = :other.Id AND Shared_To__c = :testUser.ContactId)
        ];
        for (Shared_Contact_Info__c s : scis) {
            s.Status__c = 'Revoked';
        }
        update scis;

        Test.startTest();
        System.runAs(testUser) {
            Boolean revokedNow = FimbyConversationController.isConversationRevoked(convId);
            System.assertEquals(true, revokedNow, 'Should be revoked after SCI status change');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetOrCreateConversationUnarchives() {
        User testUser = getTestUser();
        Contact other = getOtherContact();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> conv = FimbyConversationController.getOrCreateConversation(other.Id);
            Id convId = (Id) conv.get('conversationId');

            FimbyConversationController.archiveConversation(convId);

            Conversation__c archived = [SELECT Participant_1_Archived__c FROM Conversation__c WHERE Id = :convId];
            System.assertEquals(true, archived.Participant_1_Archived__c, 'Should be archived');

            Map<String, Object> reopened = FimbyConversationController.getOrCreateConversation(other.Id);
            System.assertEquals(convId, reopened.get('conversationId'), 'Should return same conversation');

            Conversation__c afterReopen = [SELECT Participant_1_Archived__c FROM Conversation__c WHERE Id = :convId];
            System.assertEquals(false, afterReopen.Participant_1_Archived__c, 'Should be unarchived after getOrCreate');
        }
        Test.stopTest();
    }

    private static Contact createOrgContactInNeighbourhood() {
        User u = getTestUser();
        Contact myContact = [SELECT Id, AccountId FROM Contact WHERE Id = :u.ContactId];

        Account orgAccount = new Account(Name = 'Test Org', Logo_URL__c = 'https://example.com/org-logo.jpg');
        try {
            orgAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();
        } catch (Exception e) { /* RT may not exist */ }
        insert orgAccount;

        Contact orgContact = new Contact(
            FirstName = 'Org', LastName = 'Representative',
            AccountId = myContact.AccountId,
            Is_Organization_Contact__c = true,
            Organization_Account__c = orgAccount.Id
        );
        insert orgContact;
        return orgContact;
    }

    @IsTest
    static void testGetOrCreateConversationBlockedByRevoke() {
        User testUser = getTestUser();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Contact revokedContact = new Contact(
            FirstName = 'Revoked',
            LastName = 'Person',
            AccountId = neighbourhood.Id
        );
        insert revokedContact;

        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = testUser.ContactId,
            Shared_To__c = revokedContact.Id,
            Email__c = 'revoked@test.com',
            Status__c = 'Revoked'
        );
        insert sci;

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyConversationController.getOrCreateConversation(revokedContact.Id);
                System.assert(false, 'Should have thrown exception for revoked SCI');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e.getMessage(), 'Should have an error message');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetOrCreateConversation_OrgContactBypassesSCI() {
        User testUser = getTestUser();
        Contact orgContact = createOrgContactInNeighbourhood();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyConversationController.getOrCreateConversation(orgContact.Id);
            System.assertEquals(true, result.get('success'), 'Should succeed without SCI for org contact');
            System.assertEquals(true, result.get('isNew'), 'Should be a new conversation');
            System.assertNotEquals(null, result.get('conversationId'), 'Should have conversation ID');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetOrCreateConversation_IgnoresExistingVouchThread() {
        User testUser = getTestUser();
        Contact other = getOtherContact();

        Conversation__c vouchConv = new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = other.Id,
            Context_Type__c = FimbyConstants.CTX_VOUCH_REQUEST,
            Vouch_Outcome__c = 'Pending',
            Is_Group__c = false,
            Status__c = 'Active'
        );
        insert vouchConv;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyConversationController.getOrCreateConversation(other.Id);
            System.assertEquals(true, result.get('success'), 'Should succeed');
            System.assertEquals(true, result.get('isNew'), 'Should create a new direct conversation');
            Id directConvId = (Id) result.get('conversationId');
            System.assertNotEquals(vouchConv.Id, directConvId, 'Should not return the vouch thread');

            Conversation__c directConv = [
                SELECT Context_Type__c
                FROM Conversation__c
                WHERE Id = :directConvId
            ];
            System.assertEquals(
                FimbyConstants.CTX_DIRECT,
                directConv.Context_Type__c,
                'New conversation should be Direct context'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testIsConversationRevoked_VouchRequestReturnsFalse() {
        User testUser = getTestUser();
        Contact myContact = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId];

        Contact voucher = new Contact(
            FirstName = 'Vouch',
            LastName = 'Ref',
            Email = 'vouchref@test.com',
            AccountId = myContact.AccountId
        );
        insert voucher;

        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c = myContact.Id,
            Reference_Contact__c = voucher.Id,
            Neighbourhood__c = myContact.AccountId,
            Status__c = 'Pending',
            Source__c = 'Peer',
            Requested_Date__c = System.now()
        );
        insert vr;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = myContact.Id,
            Participant_2__c = voucher.Id,
            Context_Type__c = FimbyConstants.CTX_VOUCH_REQUEST,
            Vouch_Record__c = vr.Id,
            Vouch_Outcome__c = 'Pending',
            Is_Group__c = false,
            Status__c = 'Active'
        );
        insert conv;

        Test.startTest();
        System.runAs(testUser) {
            Boolean revoked = FimbyConversationController.isConversationRevoked(conv.Id);
            System.assertEquals(false, revoked, 'Vouch_Request threads do not require shared contact info');
        }
        Test.stopTest();
    }

    @IsTest
    static void testIsConversationRevoked_OrgContactReturnsFalse() {
        User testUser = getTestUser();
        Contact orgContact = createOrgContactInNeighbourhood();

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testUser.ContactId,
            Participant_2__c = orgContact.Id,
            Status__c = 'Active',
            Participant_1_Unread_Count__c = 0,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false
        );
        insert conv;

        Test.startTest();
        System.runAs(testUser) {
            Boolean revoked = FimbyConversationController.isConversationRevoked(conv.Id);
            System.assertEquals(false, revoked, 'Should not be revoked when participant is org contact');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMessageableContacts_IncludesOrgContacts() {
        User testUser = getTestUser();
        Contact orgContact = createOrgContactInNeighbourhood();

        Test.startTest();
        System.runAs(testUser) {
            List<Map<String, Object>> contacts =
                FimbyConversationController.getMessageableContacts(null);

            Boolean foundOrg = false;
            for (Map<String, Object> c : contacts) {
                if ((Id) c.get('contactId') == orgContact.Id) {
                    foundOrg = true;
                    System.assertEquals(true, c.get('isOrgContact'), 'Org contact should have isOrgContact=true');
                    System.assertEquals('Test Org', c.get('contactName'), 'Should use org account name');
                }
            }
            System.assert(foundOrg, 'Org contact should appear in messageable contacts');
        }
        Test.stopTest();
    }

    @IsTest
    static void testPrepareDirectConversation_NoInsertWhenNoThread() {
        User testUser = getTestUser();
        Contact other = getOtherContact();
        Integer convCountBefore = [SELECT COUNT() FROM Conversation__c];

        Test.startTest();
        System.runAs(testUser) {
            FimbyConversationController.DraftConversationResult result =
                FimbyConversationController.prepareDirectConversation(other.Id);

            System.assertEquals(false, result.isExisting, 'Should not find an existing thread');
            System.assertEquals(null, result.conversationId, 'Should not return a conversation id');
            System.assertNotEquals(null, result.otherParticipantName, 'Should populate participant name');
            System.assertEquals(other.Id, result.otherParticipantId, 'Should return target contact id');
        }
        Test.stopTest();

        System.assertEquals(convCountBefore, [SELECT COUNT() FROM Conversation__c],
            'prepareDirectConversation must not insert a Conversation__c');
    }

    @IsTest
    static void testPrepareDirectConversation_ReturnsExistingDirectThread() {
        User testUser = getTestUser();
        Contact other = getOtherContact();
        Id existingConvId;
        System.runAs(testUser) {
            Map<String, Object> created = FimbyConversationController.getOrCreateConversation(other.Id);
            existingConvId = (Id) created.get('conversationId');
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyConversationController.DraftConversationResult result =
                FimbyConversationController.prepareDirectConversation(other.Id);

            System.assertEquals(true, result.isExisting, 'Should find existing Direct thread');
            System.assertEquals(existingConvId, result.conversationId, 'Should return existing conversation id');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSendDirectMessage_CreatesConversationAndMessage() {
        User testUser = getTestUser();
        Contact other = getOtherContact();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyConversationController.sendDirectMessage(other.Id, 'Hello neighbour');

            System.assertEquals(true, result.get('success'), 'Send should succeed');
            System.assertEquals(true, result.get('isNew'), 'Should create a new conversation');
            Id convId = (Id) result.get('conversationId');
            System.assertNotEquals(null, convId, 'Should return conversation id');

            Conversation__c conv = [
                SELECT Context_Type__c, Last_Message_Preview__c
                FROM Conversation__c WHERE Id = :convId
            ];
            System.assertEquals(FimbyConstants.CTX_DIRECT, conv.Context_Type__c, 'Should be Direct context');
            System.assertEquals('Hello neighbour', conv.Last_Message_Preview__c, 'Should set summary preview');

            Integer msgCount = [SELECT COUNT() FROM Message__c WHERE Conversation__c = :convId];
            System.assertEquals(1, msgCount, 'Should create exactly one message');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSendDirectMessage_ReusesExistingThread() {
        User testUser = getTestUser();
        Contact other = getOtherContact();
        Id existingConvId;
        System.runAs(testUser) {
            Map<String, Object> created = FimbyConversationController.getOrCreateConversation(other.Id);
            existingConvId = (Id) created.get('conversationId');
        }

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyConversationController.sendDirectMessage(other.Id, 'Follow up');

            System.assertEquals(true, result.get('success'), 'Send should succeed');
            System.assertEquals(false, result.get('isNew'), 'Should reuse existing conversation');
            System.assertEquals(existingConvId, result.get('conversationId'), 'Should return same conversation id');

            Integer convCount = [
                SELECT COUNT() FROM Conversation__c
                WHERE ((Participant_1__c = :testUser.ContactId AND Participant_2__c = :other.Id)
                    OR (Participant_1__c = :other.Id AND Participant_2__c = :testUser.ContactId))
                  AND (Context_Type__c = null OR Context_Type__c = :FimbyConstants.CTX_DIRECT)
            ];
            System.assertEquals(1, convCount, 'Should not create a duplicate Direct conversation');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSendDirectMessage_NoSharedContactThrows() {
        User testUser = getTestUser();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact stranger = new Contact(FirstName = 'Stranger', LastName = 'Person', AccountId = neighbourhood.Id);
        insert stranger;

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyConversationController.sendDirectMessage(stranger.Id, 'Hi');
                System.assert(false, 'Should throw for non-shared contact');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e.getMessage(), 'Should have an error message');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSendDirectMessage_RateLimitOnCreate() {
        User testUser = getTestUser();
        Integer dailyLimit = FimbySettings.maxNewConversationsPerDay();
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];

        Contact rateLimitTarget = new Contact(
            FirstName = 'Rate',
            LastName = 'Target',
            Email = 'ratelimit-target@test.com',
            AccountId = neighbourhood.Id
        );
        insert rateLimitTarget;

        insert new Shared_Contact_Info__c(
            Contact__c = testUser.ContactId,
            Shared_To__c = rateLimitTarget.Id,
            Email__c = 'ratelimit-target@test.com'
        );

        List<Contact> extraContacts = new List<Contact>();
        for (Integer i = 0; i < dailyLimit; i++) {
            extraContacts.add(new Contact(
                FirstName = 'Rate',
                LastName = 'Seed' + i,
                Email = 'ratelimit-seed' + i + '@test.com',
                AccountId = neighbourhood.Id
            ));
        }
        insert extraContacts;

        List<Conversation__c> seeded = new List<Conversation__c>();
        for (Contact c : extraContacts) {
            seeded.add(new Conversation__c(
                Participant_1__c = testUser.ContactId,
                Participant_2__c = c.Id,
                Context_Type__c = FimbyConstants.CTX_DIRECT,
                Status__c = 'Active',
                Participant_1_Unread_Count__c = 0,
                Participant_2_Unread_Count__c = 0,
                Participant_1_Archived__c = false,
                Participant_2_Archived__c = false
            ));
        }
        insert seeded;

        Boolean threw = false;
        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyConversationController.sendDirectMessage(rateLimitTarget.Id, 'Should fail');
            } catch (AuraHandledException e) {
                threw = true;
                System.assertNotEquals(null, e.getMessage(), 'Should have an error message');
            }
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Should throw when daily limit reached');
    }
}