@IsTest
public class FimbyMessageControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(neighbourhood.Id, 2, true);
        User communityUser = FimbyTestDataFactory.createCommunityUser(contacts[0].Id, 'Customer Community User - Mobile App', true);

        // Create shared contact info so messaging is allowed
        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = contacts[0].Id,
            Shared_To__c = contacts[1].Id,
            Email__c = 'shared@test.com'
        );
        insert sci;

        // Create a conversation between the two contacts
        Conversation__c conv = new Conversation__c(
            Participant_1__c = contacts[0].Id,
            Participant_2__c = contacts[1].Id,
            Status__c = 'Active',
            Participant_1_Unread_Count__c = 0,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false
        );
        insert conv;
    }

    private static User getTestUser() {
        return [SELECT Id, ContactId FROM User WHERE Profile.Name = 'Customer Community User - Mobile App' AND IsActive = true ORDER BY CreatedDate DESC LIMIT 1];
    }

    private static Conversation__c getTestConversation() {
        return [SELECT Id, Participant_1__c, Participant_2__c FROM Conversation__c LIMIT 1];
    }

    @IsTest
    static void testSendMessage() {
        User testUser = getTestUser();
        Conversation__c conv = getTestConversation();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyMessageController.sendMessage(conv.Id, 'Hello there!');

            System.assertEquals(true, result.get('success'), 'Send should succeed');
            System.assertNotEquals(null, result.get('messageId'), 'Should have message ID');
            System.assertNotEquals(null, result.get('sentDate'), 'Should have sent date');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSendEmptyMessage() {
        User testUser = getTestUser();
        Conversation__c conv = getTestConversation();

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyMessageController.sendMessage(conv.Id, '');
                System.assert(false, 'Should have thrown exception for empty message');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e.getMessage(), 'Should have an error message');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSendMessageTooLong() {
        User testUser = getTestUser();
        Conversation__c conv = getTestConversation();

        String longMessage = '';
        for (Integer i = 0; i < 510; i++) {
            longMessage += '0123456789';
        }

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyMessageController.sendMessage(conv.Id, longMessage);
                System.assert(false, 'Should have thrown exception for long message');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e.getMessage(), 'Should have an error message');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMessages() {
        User testUser = getTestUser();
        Conversation__c conv = getTestConversation();

        // Insert a message directly for the test
        Message__c msg = new Message__c(
            Conversation__c = conv.Id,
            Sender__c = conv.Participant_1__c,
            Sent_By__c = conv.Participant_1__c,
            Body__c = 'Test message body',
            Sent_Date__c = Datetime.now(),
            Status__c = 'Sent'
        );
        insert msg;

        Test.startTest();
        System.runAs(testUser) {
            FimbyMessageController.MessageListResult result =
                FimbyMessageController.getMessages(conv.Id, 50, 0);

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assert(result.messages.size() >= 1, 'Should have at least 1 message');
            System.assertNotEquals(null, result.otherParticipantName, 'Should have other participant name');
            System.assertNotEquals(null, result.myContactId, 'Should have my contact ID');

            // Check message wrapper fields
            FimbyMessageController.MessageWrapper firstMsg = result.messages[0];
            System.assertNotEquals(null, firstMsg.body, 'Message should have body');
            System.assertNotEquals(null, firstMsg.sentDate, 'Message should have sent date');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMessagesMarksAsRead() {
        User testUser = getTestUser();
        Conversation__c conv = getTestConversation();

        // Insert a message from the OTHER participant so it appears unread
        Message__c msg = new Message__c(
            Conversation__c = conv.Id,
            Sender__c = conv.Participant_2__c,
            Sent_By__c = conv.Participant_2__c,
            Body__c = 'Unread message from other person',
            Sent_Date__c = Datetime.now(),
            Status__c = 'Sent'
        );
        insert msg;

        // Set unread count on participant 1
        conv.Participant_1_Unread_Count__c = 1;
        update conv;

        Test.startTest();
        System.runAs(testUser) {
            FimbyMessageController.MessageListResult result =
                FimbyMessageController.getMessages(conv.Id, 50, 0);

            System.assert(result.messages.size() >= 1, 'Should have messages');
        }
        Test.stopTest();

        // Verify unread count was reset
        Conversation__c updatedConv = [SELECT Participant_1_Unread_Count__c FROM Conversation__c WHERE Id = :conv.Id];
        System.assertEquals(0, updatedConv.Participant_1_Unread_Count__c, 'Unread count should be reset');
    }

    @IsTest
    static void testSendMessageUpdatesConversation() {
        User testUser = getTestUser();
        Conversation__c conv = getTestConversation();

        Test.startTest();
        System.runAs(testUser) {
            FimbyMessageController.sendMessage(conv.Id, 'Hello, updating the preview!');
        }
        Test.stopTest();

        Conversation__c updatedConv = [
            SELECT Last_Message_Preview__c, Last_Message_Date__c, Participant_2_Unread_Count__c
            FROM Conversation__c WHERE Id = :conv.Id
        ];
        System.assertEquals('Hello, updating the preview!', updatedConv.Last_Message_Preview__c, 'Preview should be updated');
        System.assertNotEquals(null, updatedConv.Last_Message_Date__c, 'Last message date should be set');
        System.assertEquals(1, updatedConv.Participant_2_Unread_Count__c, 'Other participant unread count should be 1');

        List<Notification__c> notifs = [
            SELECT Type__c, Push_Status__c, Actor_Name__c
            FROM Notification__c WHERE Contact__c = :conv.Participant_2__c AND Type__c = :FimbyConstants.NOTIF_MESSAGE
        ];
        System.assertEquals(1, notifs.size(), 'Should create a Message notification for recipient');
    }

    @IsTest
    static void testSendMessageToRevokedConversation() {
        User testUser = getTestUser();
        Conversation__c conv = getTestConversation();

        // Revoke the SCI
        List<Shared_Contact_Info__c> scis = [
            SELECT Id FROM Shared_Contact_Info__c
            WHERE (Contact__c = :conv.Participant_1__c AND Shared_To__c = :conv.Participant_2__c)
               OR (Contact__c = :conv.Participant_2__c AND Shared_To__c = :conv.Participant_1__c)
        ];
        for (Shared_Contact_Info__c s : scis) {
            s.Status__c = 'Revoked';
        }
        update scis;

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyMessageController.sendMessage(conv.Id, 'Should fail — revoked');
                System.assert(false, 'Should have thrown exception for revoked sharing');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e.getMessage(), 'Should have an error message');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSendMessageToBlockedConversation() {
        User testUser = getTestUser();
        Conversation__c conv = getTestConversation();

        conv.Status__c = 'Blocked';
        update conv;

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyMessageController.sendMessage(conv.Id, 'Should fail');
                System.assert(false, 'Should have thrown exception for blocked conversation');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null, e.getMessage(), 'Should have an error message');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testOnBehalfOfMessageFields() {
        User testUser = getTestUser();
        Conversation__c conv = getTestConversation();

        // Insert a message where sender != sent_by (on behalf of)
        Message__c msg = new Message__c(
            Conversation__c = conv.Id,
            Sender__c = conv.Participant_1__c,
            Sent_By__c = conv.Participant_2__c,
            Body__c = 'Sent on behalf',
            Sent_Date__c = Datetime.now(),
            Status__c = 'Sent'
        );
        insert msg;

        Test.startTest();
        System.runAs(testUser) {
            FimbyMessageController.MessageListResult result =
                FimbyMessageController.getMessages(conv.Id, 50, 0);

            Boolean foundOnBehalf = false;
            for (FimbyMessageController.MessageWrapper m : result.messages) {
                if (m.isOnBehalfOf == true) {
                    foundOnBehalf = true;
                    System.assertNotEquals(m.senderContactId, m.sentByContactId, 'Sender and SentBy should differ');
                }
            }
            System.assert(foundOnBehalf, 'Should find at least one on-behalf-of message');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSendMessage_OrgContactBypassesSCI() {
        User testUser = getTestUser();
        Conversation__c existingConv = getTestConversation();
        Id neighbourhoodId = [SELECT AccountId FROM Contact WHERE Id = :existingConv.Participant_1__c].AccountId;

        Account orgAccount = new Account(Name = 'Helpers United', Logo_URL__c = 'https://example.com/org-logo.jpg');
        try {
            orgAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();
        } catch (Exception e) { /* RT may not exist */ }
        insert orgAccount;

        Contact orgContact = new Contact(
            FirstName = 'Org', LastName = 'Rep',
            AccountId = neighbourhoodId,
            Is_Organization_Contact__c = true,
            Organization_Account__c = orgAccount.Id
        );
        insert orgContact;

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
            Map<String, Object> result = FimbyMessageController.sendMessage(conv.Id, 'Hello org!');
            System.assertEquals(true, result.get('success'), 'Should succeed without SCI for org contact');
            System.assertNotEquals(null, result.get('messageId'), 'Should have message ID');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMessages_RelatedRecordTitle() {
        User testUser = getTestUser();
        Conversation__c existingConv = getTestConversation();
        Id neighbourhoodId = [SELECT AccountId FROM Contact WHERE Id = :existingConv.Participant_1__c].AccountId;

        Id bulkBuyRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName()
            .get('Bulk_Buy').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            RecordTypeId = bulkBuyRt,
            Contact__c = existingConv.Participant_2__c,
            Posted_By__c = existingConv.Participant_2__c,
            Neighbourhood__c = neighbourhoodId,
            Status__c = 'Posted'
        );
        insert post;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = existingConv.Participant_1__c,
            Participant_2__c = existingConv.Participant_2__c,
            Status__c = 'Active',
            Context_Type__c = 'Bulk_Buy',
            Related_Record_Id__c = post.Id,
            Participant_1_Unread_Count__c = 0,
            Participant_2_Unread_Count__c = 0,
            Participant_1_Archived__c = false,
            Participant_2_Archived__c = false
        );
        insert conv;

        insert new Message__c(
            Conversation__c = conv.Id,
            Sender__c = existingConv.Participant_2__c,
            Sent_By__c = existingConv.Participant_2__c,
            Body__c = 'Bulk buy message',
            Sent_Date__c = Datetime.now(),
            Status__c = 'Sent'
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbyMessageController.MessageListResult result =
                FimbyMessageController.getMessages(conv.Id, 50, 0);

            System.assertEquals('Bulk_Buy', result.contextType, 'Context type should be Bulk_Buy');
            System.assertNotEquals(null, result.relatedRecordTitle, 'Related record title should be resolved');
            System.assertEquals(String.valueOf(post.Id), result.relatedRecordId, 'Related record ID should match');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMessages_DirectConversationNoTitle() {
        User testUser = getTestUser();
        Conversation__c conv = getTestConversation();

        Test.startTest();
        System.runAs(testUser) {
            FimbyMessageController.MessageListResult result =
                FimbyMessageController.getMessages(conv.Id, 50, 0);

            System.assertEquals(null, result.relatedRecordTitle, 'Direct conversation should have no related record title');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMessages_OrgContactFields() {
        User testUser = getTestUser();
        Conversation__c existingConv = getTestConversation();
        Id neighbourhoodId = [SELECT AccountId FROM Contact WHERE Id = :existingConv.Participant_1__c].AccountId;

        Account orgAccount = new Account(Name = 'Helpers United', Logo_URL__c = 'https://example.com/org-logo.jpg');
        try {
            orgAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();
        } catch (Exception e) { /* RT may not exist */ }
        insert orgAccount;

        Contact orgContact = new Contact(
            FirstName = 'Org', LastName = 'Rep',
            AccountId = neighbourhoodId,
            Is_Organization_Contact__c = true,
            Organization_Account__c = orgAccount.Id
        );
        insert orgContact;

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

        insert new Message__c(
            Conversation__c = conv.Id,
            Sender__c = orgContact.Id,
            Sent_By__c = orgContact.Id,
            Body__c = 'Message from org',
            Sent_Date__c = Datetime.now(),
            Status__c = 'Sent'
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbyMessageController.MessageListResult result =
                FimbyMessageController.getMessages(conv.Id, 50, 0);

            System.assertEquals(true, result.isOtherParticipantOrg, 'Other participant should be org');
            System.assertEquals('Helpers United', result.otherParticipantName,
                'Other participant name should be org account name');
            System.assertEquals('https://example.com/org-logo.jpg', result.otherParticipantImageUrl,
                'Other participant image should be org logo');

            System.assert(result.messages.size() >= 1, 'Should have at least 1 message');
            FimbyMessageController.MessageWrapper orgMsg = result.messages[0];
            System.assertEquals(true, orgMsg.senderIsOrg, 'Sender should be org');
            System.assertNotEquals(null, orgMsg.senderImageUrl, 'Org sender should have image URL');
        }
        Test.stopTest();
    }
}