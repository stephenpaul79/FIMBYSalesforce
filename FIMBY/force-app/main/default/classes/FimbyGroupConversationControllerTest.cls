@isTest
public class FimbyGroupConversationControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);

        Contact organiser = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(organiser.Id, null, true);

        Contact member = new Contact(
            FirstName = 'Member',
            LastName = 'Test',
            Email = 'member@fimby.test.com',
            AccountId = neighbourhood.Id,
            Image_URL__c = 'https://example.com/member.jpg'
        );
        insert member;
        FimbyTestDataFactory.createCommunityUser(member.Id, null, true);
    }

    private static User getOrganiserUser() {
        Contact c = [SELECT Id FROM Contact WHERE Email LIKE 'testuser%@fimby.test.com' LIMIT 1];
        return [SELECT Id, ContactId FROM User WHERE ContactId = :c.Id AND IsActive = true LIMIT 1];
    }

    private static User getMemberUser() {
        Contact c = [SELECT Id FROM Contact WHERE Email = 'member@fimby.test.com' LIMIT 1];
        return [SELECT Id, ContactId FROM User WHERE ContactId = :c.Id AND IsActive = true LIMIT 1];
    }

    private static Contact getOrganiserContact() {
        return [SELECT Id, AccountId FROM Contact WHERE Email LIKE 'testuser%@fimby.test.com' LIMIT 1];
    }

    private static Contact getMemberContact() {
        return [SELECT Id FROM Contact WHERE Email = 'member@fimby.test.com' LIMIT 1];
    }

    private static Needs_Offers__c createBulkBuyPost(Contact poster, Id neighbourhoodId) {
        Id rtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Bulk_Buy').getRecordTypeId();
        Needs_Offers__c post = new Needs_Offers__c(
            RecordTypeId = rtId,
            Name = 'Test Bulk Buy',
            Details__c = 'Test details',
            Full_Details__c = 'Full test details',
            Status__c = 'Available',
            Posted_By__c = poster.Id,
            Contact__c = poster.Id,
            Neighbourhood__c = neighbourhoodId,
            Giver_Recipient_Type__c = 'Self',
            Total_Quantity__c = 10,
            Allocation_Unit_Label__c = 'shares',
            Availability_Rule__c = 'Open_Until_Full_Or_Closed',
            Auto_Accept_Responses__c = true,
            Auto_Lock_Days__c = '7'
        );
        insert post;
        return post;
    }

    @isTest
    static void testGetOrCreateGroupConversation_Creates() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId);

        Test.startTest();
        Id convId;
        System.runAs(organiserUser) {
            convId = FimbyGroupConversationController.getOrCreateGroupConversation(post.Id);
        }
        Test.stopTest();

        System.assertNotEquals(null, convId, 'Should create conversation');
        Conversation__c conv = [SELECT Is_Group__c, Group_Name__c FROM Conversation__c WHERE Id = :convId];
        System.assertEquals(true, conv.Is_Group__c, 'Should be group');
    }

    @isTest
    static void testGetOrCreateGroupConversation_ReturnsExisting() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId);

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Existing', Context_Type__c = 'Bulk_Buy',
            Related_Record_Id__c = post.Id, Status__c = 'Active'
        );
        insert conv;
        post.Group_Conversation__c = conv.Id;
        update post;

        Test.startTest();
        Id convId;
        System.runAs(organiserUser) {
            convId = FimbyGroupConversationController.getOrCreateGroupConversation(post.Id);
        }
        Test.stopTest();

        System.assertEquals(conv.Id, convId, 'Should return existing conversation');
    }

    @isTest
    static void testSendGroupMessage_Success() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Test', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id, Contact__c = organiserContact.Id,
            Role__c = 'Owner', Status__c = 'Active', Joined_Date__c = System.now()
        );

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyGroupConversationController.sendGroupMessage(conv.Id, 'Hello group');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed');
        System.assertNotEquals(null, result.get('messageId'), 'Should return messageId');
    }

    @isTest
    static void testSendGroupMessage_LockedConversation() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Locked', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active', Locked__c = true
        );
        insert conv;

        Test.startTest();
        Boolean caught = false;
        try {
            System.runAs(organiserUser) {
                FimbyGroupConversationController.sendGroupMessage(conv.Id, 'Should fail');
            }
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Should throw AuraHandledException for locked conversation');
    }

    @isTest
    static void testGetGroupMessages_Success() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Test', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id, Contact__c = organiserContact.Id,
            Role__c = 'Owner', Status__c = 'Active', Joined_Date__c = System.now()
        );

        insert new Message__c(
            Conversation__c = conv.Id, Body__c = 'Test message',
            Sender__c = organiserContact.Id, Sent_Date__c = System.now(),
            Status__c = 'Sent', Is_System_Message__c = false
        );

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyGroupConversationController.getGroupMessages(conv.Id, 50, 0);
        }
        Test.stopTest();

        List<Map<String, Object>> messages = (List<Map<String, Object>>) result.get('messages');
        System.assertEquals(1, messages.size(), 'Should have 1 message');
        System.assertEquals(1, result.get('totalCount'), 'Total should be 1');
    }

    @isTest
    static void testSendSystemMessage() {
        Contact organiserContact = getOrganiserContact();
        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Test', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        Test.startTest();
        FimbyGroupConversationController.sendSystemMessage(conv.Id, 'System event', 'Status_Change');
        Test.stopTest();

        List<Message__c> msgs = [SELECT Is_System_Message__c, System_Message_Type__c FROM Message__c WHERE Conversation__c = :conv.Id];
        System.assertEquals(1, msgs.size(), 'Should have 1 system message');
        System.assertEquals(true, msgs[0].Is_System_Message__c, 'Should be system');
    }

    @isTest
    static void testSendSystemMessage_ReservationDoesNotBumpConversationSummary() {
        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Test', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        Test.startTest();
        FimbyGroupConversationController.sendSystemMessage(conv.Id, 'Alex reserved 2 shares', FimbyConstants.SYS_MSG_RESERVATION_CREATED);
        Test.stopTest();

        Conversation__c updated = [
            SELECT Last_Message_Preview__c, Last_Message_Date__c
            FROM Conversation__c WHERE Id = :conv.Id
        ];
        System.assertEquals(null, updated.Last_Message_Preview__c, 'Reservation system line should not bump preview');
        System.assertEquals(null, updated.Last_Message_Date__c, 'Reservation system line should not bump activity date');

        FimbyGroupConversationController.sendSystemMessage(conv.Id, 'Pickup is ready!', FimbyConstants.SYS_MSG_PICKUP_READY);
        updated = [
            SELECT Last_Message_Preview__c, Last_Message_Date__c
            FROM Conversation__c WHERE Id = :conv.Id
        ];
        System.assertNotEquals(null, updated.Last_Message_Date__c, 'Non-suppressed system message should bump activity');
    }

    @isTest
    static void testAddAndRemoveMember() {
        Contact memberContact = getMemberContact();
        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Test', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        Test.startTest();
        FimbyGroupConversationController.addMember(conv.Id, memberContact.Id);
        List<Conversation_Member__c> members = [SELECT Status__c FROM Conversation_Member__c WHERE Conversation__c = :conv.Id AND Contact__c = :memberContact.Id];
        System.assertEquals(1, members.size(), 'Should add member');
        System.assertEquals('Active', members[0].Status__c, 'Should be active');

        FimbyGroupConversationController.removeMember(conv.Id, memberContact.Id);
        Test.stopTest();

        members = [SELECT Status__c FROM Conversation_Member__c WHERE Conversation__c = :conv.Id AND Contact__c = :memberContact.Id];
        System.assertEquals('Removed', members[0].Status__c, 'Should be removed');
    }

    @isTest
    static void testLockConversation() {
        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Test', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        Test.startTest();
        FimbyGroupConversationController.lockConversation(conv.Id);
        Test.stopTest();

        Conversation__c updated = [SELECT Locked__c FROM Conversation__c WHERE Id = :conv.Id];
        System.assertEquals(true, updated.Locked__c, 'Should be locked');
    }

    @isTest
    static void testToggleMute_Success() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Test', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id, Contact__c = organiserContact.Id,
            Role__c = 'Owner', Status__c = 'Active', Joined_Date__c = System.now(),
            Muted__c = false
        );

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyGroupConversationController.toggleMute(conv.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed');
        System.assertEquals(true, result.get('muted'), 'Should be muted after toggle');
    }

    @isTest
    static void testGetGroupMembers_Success() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact memberContact = getMemberContact();

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Test', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        insert new List<Conversation_Member__c>{
            new Conversation_Member__c(
                Conversation__c = conv.Id, Contact__c = organiserContact.Id,
                Role__c = 'Owner', Status__c = 'Active', Joined_Date__c = System.now()
            ),
            new Conversation_Member__c(
                Conversation__c = conv.Id, Contact__c = memberContact.Id,
                Role__c = 'Member', Status__c = 'Active', Joined_Date__c = System.now()
            )
        };

        Test.startTest();
        List<Map<String, Object>> members;
        System.runAs(organiserUser) {
            members = FimbyGroupConversationController.getGroupMembers(conv.Id);
        }
        Test.stopTest();

        System.assertEquals(2, members.size(), 'Should have 2 members');
    }

    @isTest
    static void testGetMyGroupConversations_Success() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'My Group', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active', Last_Message_Date__c = System.now()
        );
        insert conv;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id, Contact__c = organiserContact.Id,
            Role__c = 'Owner', Status__c = 'Active', Joined_Date__c = System.now()
        );

        Test.startTest();
        List<Map<String, Object>> results;
        System.runAs(organiserUser) {
            results = FimbyGroupConversationController.getMyGroupConversations();
        }
        Test.stopTest();

        System.assert(results.size() >= 1, 'Should have at least 1 group conversation');
    }

    private static Needs_Offers__c createOpenEventPost(Contact poster, Id neighbourhoodId) {
        Id rtId;
        try {
            rtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();
        } catch (Exception e) {
            rtId = null;
        }
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Test Open Event',
            Details__c = 'Open event details',
            Status__c = 'Posted',
            Type__c = 'Event',
            Event_Type__c = 'Open_Event',
            Posted_By__c = poster.Id,
            Contact__c = poster.Id,
            Neighbourhood__c = neighbourhoodId,
            Giver_Recipient_Type__c = 'Self',
            Total_Quantity__c = 50,
            Per_Response_Limit__c = 5,
            Auto_Accept_Responses__c = true,
            End_Date__c = Date.today().addDays(14)
        );
        if (rtId != null) post.RecordTypeId = rtId;
        insert post;
        return post;
    }

    private static Needs_Offers__c createCommunityEventPost(Contact poster, Id neighbourhoodId) {
        Id rtId;
        try {
            rtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();
        } catch (Exception e) {
            rtId = null;
        }
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Test Community Event',
            Details__c = 'Community event details',
            Status__c = 'Posted',
            Type__c = 'Event',
            Event_Type__c = 'Community_Event',
            Posted_By__c = poster.Id,
            Contact__c = poster.Id,
            Neighbourhood__c = neighbourhoodId,
            Giver_Recipient_Type__c = 'Self',
            Total_Quantity__c = 1,
            Per_Response_Limit__c = 1,
            Auto_Accept_Responses__c = false,
            End_Date__c = Date.today().addDays(14)
        );
        if (rtId != null) post.RecordTypeId = rtId;
        insert post;
        return post;
    }

    @isTest
    static void testCreateEventGroupChat_OpenEvent() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact memberContact = getMemberContact();
        User memberUser = getMemberUser();
        Needs_Offers__c post = createOpenEventPost(organiserContact, organiserContact.AccountId);

        insert new Response__c(
            Name = 'Test Response',
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = memberContact.Id,
            On_Behalf_Of_Contact__c = memberContact.Id,
            Response__c = 'Quick event response',
            Status__c = 'Accepted',
            Amount_Requested__c = 1,
            Neighbourhood__c = organiserContact.AccountId
        );

        Test.startTest();
        Id convId;
        System.runAs(organiserUser) {
            convId = FimbyGroupConversationController.createEventGroupChat(post.Id);
        }
        Test.stopTest();

        System.assertNotEquals(null, convId, 'Should create conversation');
        Conversation__c conv = [SELECT Is_Group__c, Context_Type__c FROM Conversation__c WHERE Id = :convId];
        System.assertEquals(true, conv.Is_Group__c);
        System.assertEquals('Event', conv.Context_Type__c);

        List<Conversation_Member__c> members = [
            SELECT Contact__c, Role__c FROM Conversation_Member__c
            WHERE Conversation__c = :convId AND Status__c = 'Active'
        ];
        System.assertEquals(2, members.size(), 'Should have poster + 1 attendee');
    }

    @isTest
    static void testCreateEventGroupChat_RejectsCommunityEvent() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Needs_Offers__c post = createCommunityEventPost(organiserContact, organiserContact.AccountId);

        Test.startTest();
        Boolean caught = false;
        System.runAs(organiserUser) {
            try {
                FimbyGroupConversationController.createEventGroupChat(post.Id);
            } catch (AuraHandledException e) {
                caught = true;
            }
        }
        Test.stopTest();
        System.assert(caught, 'Should reject Community Event group chat creation');
    }

    @isTest
    static void testSyncEventChatMember_AddAndRemove() {
        Contact organiserContact = getOrganiserContact();
        Contact memberContact = getMemberContact();
        Needs_Offers__c post = createOpenEventPost(organiserContact, organiserContact.AccountId);

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Event Chat', Context_Type__c = 'Event',
            Related_Record_Id__c = post.Id, Status__c = 'Active'
        );
        insert conv;
        post.Group_Conversation__c = conv.Id;
        update post;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id, Contact__c = organiserContact.Id,
            Role__c = 'Owner', Status__c = 'Active', Joined_Date__c = System.now()
        );

        Test.startTest();
        FimbyGroupConversationController.syncEventChatMember(post.Id, memberContact.Id, 'add');
        List<Conversation_Member__c> membersAfterAdd = [
            SELECT Status__c FROM Conversation_Member__c
            WHERE Conversation__c = :conv.Id AND Contact__c = :memberContact.Id
        ];
        System.assertEquals(1, membersAfterAdd.size(), 'Should add member');
        System.assertEquals('Active', membersAfterAdd[0].Status__c);

        FimbyGroupConversationController.syncEventChatMember(post.Id, memberContact.Id, 'remove');
        Test.stopTest();

        List<Conversation_Member__c> membersAfterRemove = [
            SELECT Status__c FROM Conversation_Member__c
            WHERE Conversation__c = :conv.Id AND Contact__c = :memberContact.Id
        ];
        System.assertEquals('Removed', membersAfterRemove[0].Status__c, 'Should remove member');
    }

    @isTest
    static void testDoSendMessage_CreatesNotifications() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact memberContact = getMemberContact();

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Event Chat', Context_Type__c = 'Event',
            Status__c = 'Active'
        );
        insert conv;

        insert new List<Conversation_Member__c>{
            new Conversation_Member__c(
                Conversation__c = conv.Id, Contact__c = organiserContact.Id,
                Role__c = 'Owner', Status__c = 'Active', Joined_Date__c = System.now()
            ),
            new Conversation_Member__c(
                Conversation__c = conv.Id, Contact__c = memberContact.Id,
                Role__c = 'Member', Status__c = 'Active', Joined_Date__c = System.now()
            )
        };

        Test.startTest();
        System.runAs(organiserUser) {
            FimbyGroupConversationController.sendGroupMessage(conv.Id, 'Hello everyone');
        }
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Contact__c, Type__c, Title__c, Related_Record_Id__c
            FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_EVENT_CHAT
        ];
        System.assertEquals(1, notifs.size(), 'Should create notification for member (not sender)');
        System.assertEquals(memberContact.Id, notifs[0].Contact__c);
        System.assert(notifs[0].Title__c.contains('Event Chat'),
            'Title should contain group name');
    }

    @isTest
    static void testCreateEventGroupChat_NotifiesAttendees() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact memberContact = getMemberContact();
        Needs_Offers__c post = createOpenEventPost(organiserContact, organiserContact.AccountId);

        insert new Response__c(
            Name = 'Test Response',
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = memberContact.Id,
            On_Behalf_Of_Contact__c = memberContact.Id,
            Response__c = 'Quick event response',
            Status__c = 'Accepted',
            Amount_Requested__c = 1,
            Neighbourhood__c = organiserContact.AccountId
        );

        Test.startTest();
        System.runAs(organiserUser) {
            FimbyGroupConversationController.createEventGroupChat(post.Id);
        }
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Contact__c, Type__c, Title__c, Body__c
            FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_EVENT_CHAT
            AND Contact__c = :memberContact.Id
        ];
        System.assertEquals(1, notifs.size(), 'Attendee should get chat-created notification');
        System.assertEquals('Event chat started', notifs[0].Title__c);
        System.assert(notifs[0].Body__c.contains('started an event chat'),
            'Body should describe chat creation');
    }

    @isTest
    static void testSyncEventChatMember_NotifiesNewMember() {
        Contact organiserContact = getOrganiserContact();
        Contact memberContact = getMemberContact();
        Needs_Offers__c post = createOpenEventPost(organiserContact, organiserContact.AccountId);

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Event Chat', Context_Type__c = 'Event',
            Related_Record_Id__c = post.Id, Status__c = 'Active'
        );
        insert conv;
        post.Group_Conversation__c = conv.Id;
        update post;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id, Contact__c = organiserContact.Id,
            Role__c = 'Owner', Status__c = 'Active', Joined_Date__c = System.now()
        );

        Test.startTest();
        FimbyGroupConversationController.syncEventChatMember(post.Id, memberContact.Id, 'add');
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Contact__c, Type__c, Title__c
            FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_EVENT_CHAT
            AND Contact__c = :memberContact.Id
        ];
        System.assertEquals(1, notifs.size(), 'New member should get added-to-chat notification');
        System.assert(notifs[0].Title__c.contains('added to an event chat'));
    }

    @isTest
    static void testSyncEventChatMember_NoNotifOnReactivation() {
        Contact organiserContact = getOrganiserContact();
        Contact memberContact = getMemberContact();
        Needs_Offers__c post = createOpenEventPost(organiserContact, organiserContact.AccountId);

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Event Chat', Context_Type__c = 'Event',
            Related_Record_Id__c = post.Id, Status__c = 'Active'
        );
        insert conv;
        post.Group_Conversation__c = conv.Id;
        update post;

        insert new List<Conversation_Member__c>{
            new Conversation_Member__c(
                Conversation__c = conv.Id, Contact__c = organiserContact.Id,
                Role__c = 'Owner', Status__c = 'Active', Joined_Date__c = System.now()
            ),
            new Conversation_Member__c(
                Conversation__c = conv.Id, Contact__c = memberContact.Id,
                Role__c = 'Member', Status__c = 'Active', Joined_Date__c = System.now()
            )
        };

        Test.startTest();
        FimbyGroupConversationController.syncEventChatMember(post.Id, memberContact.Id, 'add');
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Id FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_EVENT_CHAT
            AND Contact__c = :memberContact.Id
        ];
        System.assertEquals(0, notifs.size(),
            'No notification for already-active member (reactivation no-op)');
    }

    @isTest
    static void testSyncEventChatMember_NoOpWithoutChat() {
        Contact organiserContact = getOrganiserContact();
        Contact memberContact = getMemberContact();
        Needs_Offers__c post = createOpenEventPost(organiserContact, organiserContact.AccountId);

        Test.startTest();
        FimbyGroupConversationController.syncEventChatMember(post.Id, memberContact.Id, 'add');
        Test.stopTest();

        List<Conversation_Member__c> members = [
            SELECT Id FROM Conversation_Member__c WHERE Contact__c = :memberContact.Id
        ];
        System.assertEquals(0, members.size(), 'Should no-op when no group chat exists');
    }

    @isTest
    static void testSendGroupMessage_DualIdentityForOrg() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();

        Account orgAccount = new Account(Name = 'Test Org', Logo_URL__c = 'https://example.com/org-logo.jpg');
        try {
            orgAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();
        } catch (Exception e) { /* RT may not exist */ }
        insert orgAccount;

        Contact orgContact = new Contact(
            FirstName = 'OrgRep', LastName = 'TestOrg',
            AccountId = organiserContact.AccountId,
            Is_Organization_Contact__c = true,
            Organization_Account__c = orgAccount.Id
        );
        insert orgContact;

        insert new Support_Relationship__c(
            Contact__c = organiserContact.Id,
            Related_Organization__c = orgAccount.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved',
            Neighbourhood__c = organiserContact.AccountId
        );

        organiserContact.Logged_In_As_Contact__c = orgContact.Id;
        organiserContact.Logged_In_As_Neighbourhood__c = organiserContact.AccountId;
        update organiserContact;

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Org Test', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        insert new Conversation_Member__c(
            Conversation__c = conv.Id, Contact__c = orgContact.Id,
            Role__c = 'Owner', Status__c = 'Active', Joined_Date__c = System.now()
        );

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyGroupConversationController.sendGroupMessage(conv.Id, 'Hello from org');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed');

        Message__c msg = [
            SELECT Sender__c, Sent_By__c FROM Message__c
            WHERE Conversation__c = :conv.Id AND Is_System_Message__c = false
            LIMIT 1
        ];
        System.assertEquals(orgContact.Id, msg.Sender__c, 'Sender should be org contact (acting-as identity)');
        System.assertEquals(organiserContact.Id, msg.Sent_By__c, 'Sent_By should be real contact (who typed)');
        System.assertNotEquals(msg.Sender__c, msg.Sent_By__c, 'Sender and Sent_By should differ for org identity');
    }

    @isTest
    static void testGetGroupMembers_OrgContactFields() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();

        Account orgAccount = new Account(Name = 'Test Org', Logo_URL__c = 'https://example.com/org-logo.jpg');
        try {
            orgAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();
        } catch (Exception e) { /* RT may not exist */ }
        insert orgAccount;

        Contact orgContact = new Contact(
            FirstName = 'OrgRep', LastName = 'TestOrg',
            AccountId = organiserContact.AccountId,
            Is_Organization_Contact__c = true,
            Organization_Account__c = orgAccount.Id
        );
        insert orgContact;

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Org Members Test', Context_Type__c = 'Bulk_Buy',
            Status__c = 'Active'
        );
        insert conv;

        insert new List<Conversation_Member__c>{
            new Conversation_Member__c(
                Conversation__c = conv.Id, Contact__c = organiserContact.Id,
                Role__c = 'Owner', Status__c = 'Active', Joined_Date__c = System.now()
            ),
            new Conversation_Member__c(
                Conversation__c = conv.Id, Contact__c = orgContact.Id,
                Role__c = 'Member', Status__c = 'Active', Joined_Date__c = System.now()
            )
        };

        Test.startTest();
        List<Map<String, Object>> members;
        System.runAs(organiserUser) {
            members = FimbyGroupConversationController.getGroupMembers(conv.Id);
        }
        Test.stopTest();

        System.assertEquals(2, members.size(), 'Should have 2 members');
        Boolean foundOrg = false;
        for (Map<String, Object> m : members) {
            if ((Id) m.get('contactId') == orgContact.Id) {
                foundOrg = true;
                System.assertEquals(true, m.get('isOrgContact'), 'Org member should have isOrgContact=true');
                System.assertEquals('Test Org', m.get('displayName'), 'Should use org account name');
                System.assertEquals('https://example.com/org-logo.jpg', m.get('avatarUrl'), 'Should use org logo');
            }
        }
        System.assert(foundOrg, 'Should find org contact member');
    }
}
