@isTest
public class FimbyAskOfferControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User testUser = FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);

        Account orgAccount = new Account(Name = 'Test Community Organization', Type = 'Organization');
        try {
            Id orgRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Organization').getRecordTypeId();
            orgAccount.RecordTypeId = orgRecordTypeId;
        } catch (Exception e) {}
        insert orgAccount;
    }

    private static User getTestUser() {
        // Community users inherit the linked Contact's Email on insert, so match on Username
        // (which retains the '@testorg.com' suffix) rather than Email.
        return [SELECT Id, ContactId FROM User WHERE Username LIKE '%@testorg.com' AND IsActive = true LIMIT 1];
    }

    private static Contact getTestContact() {
        return [SELECT Id, AccountId, Logged_In_As_Contact__c FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1];
    }

    @isTest
    static void testGetNeedsOffersTypePicklist() {
        Test.startTest();
        List<Map<String, String>> types = FimbyAskOfferController.getNeedsOffersTypePicklist();
        Test.stopTest();

        System.assertNotEquals(null, types, 'Should return types list');
        System.assert(types.size() > 0, 'Should have at least one type');
        Map<String, String> firstType = types[0];
        System.assert(firstType.containsKey('label'), 'Type should have label');
        System.assert(firstType.containsKey('value'), 'Type should have value');
    }

    @isTest
    static void testCreateNeedsOffersPost_Need() {
        User testUser = getTestUser();

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Need',
            'title' => 'Test Need Title',
            'description' => 'Test need description',
            'type' => 'Services - Paid',
            'quantity' => 1,
            'perResponseLimit' => 1,
            'autoAcceptResponses' => false,
            'autoShareContactInfo' => false
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('recordId'), 'Should return recordId');

        String recordId = (String) result.get('recordId');
        Needs_Offers__c created = [
            SELECT Contact__c, Posted_By__c, Giver_Recipient_Type__c, Posted_Date__c, Refresh_Count__c
            FROM Needs_Offers__c WHERE Id = :recordId
        ];
        System.assertEquals(testUser.ContactId, created.Contact__c, 'Contact__c should be the acting-as contact');
        System.assertEquals(testUser.ContactId, created.Posted_By__c, 'Posted_By__c should be the real contact');
        System.assertEquals('Self', created.Giver_Recipient_Type__c, 'Giver_Recipient_Type__c should be Self');
        System.assertNotEquals(null, created.Posted_Date__c, 'Posted_Date__c should be stamped on insert');
        System.assertEquals(0, created.Refresh_Count__c, 'Refresh_Count__c should default to 0');
    }

    @isTest
    static void testCreateNeedsOffersPost_Offer() {
        User testUser = getTestUser();

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Test Offer Title',
            'description' => 'Test offer description',
            'type' => 'Services - Paid',
            'quantity' => 5,
            'perResponseLimit' => 2,
            'autoAcceptResponses' => true,
            'autoShareContactInfo' => true
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testCreateNeedsOffersPost_NoOrgPickerNeeded() {
        User testUser = getTestUser();

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Simple Offer',
            'description' => 'No org picker fields in payload',
            'type' => 'Services - Paid',
            'quantity' => 10,
            'perResponseLimit' => 5
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        String recordId = (String) result.get('recordId');
        Needs_Offers__c created = [SELECT Giver_Recipient_Type__c, Organization__c FROM Needs_Offers__c WHERE Id = :recordId];
        System.assertEquals('Self', created.Giver_Recipient_Type__c, 'Should always set Giver_Recipient_Type__c to Self');
        System.assertEquals(null, created.Organization__c, 'Organization should not be set');
    }

    @isTest
    static void testCreateNeedsOffersPost_Event() {
        User testUser = getTestUser();

        String startIso = String.valueOf(Date.today().addDays(7)) + 'T10:00';
        String endIso = String.valueOf(Date.today().addDays(7)) + 'T14:30';

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Neighbourhood Picnic',
            'description' => 'A community picnic event',
            'type' => 'Event',
            'quantity' => 50,
            'perResponseLimit' => 5,
            'endDate' => String.valueOf(Date.today().addDays(14)),
            'eventStart' => startIso,
            'eventEnd' => endIso,
            'location' => 'Community Center'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        String recordId = (String) result.get('recordId');
        Needs_Offers__c created = [SELECT Start_Date__c, Start_Time__c, Start_Time_Text__c, End_Time__c, End_Time_Text__c, Location__c FROM Needs_Offers__c WHERE Id = :recordId];
        System.assertEquals(Date.today().addDays(7), created.Start_Date__c, 'Start date should be parsed from event ISO');
        System.assertEquals(Time.newInstance(10, 0, 0, 0), created.Start_Time__c, 'Start_Time__c should be set from ISO');
        System.assertEquals('10:00 am', created.Start_Time_Text__c, 'Start time should be formatted from ISO');
        System.assertEquals(Time.newInstance(14, 30, 0, 0), created.End_Time__c, 'End_Time__c should be set from ISO');
        System.assertEquals('2:30 pm', created.End_Time_Text__c, 'End time should be formatted from ISO');
        System.assertEquals('Community Center', created.Location__c, 'Location should be saved');
    }

    @isTest
    static void testCreateNeedsOffersPost_OpenEvent() {
        User testUser = getTestUser();

        String startIso = String.valueOf(Date.today().addDays(7)) + 'T10:00';

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Block Party on Elm St',
            'description' => 'Come one come all',
            'type' => 'Event',
            'endDate' => String.valueOf(Date.today().addDays(14)),
            'eventStart' => startIso,
            'location' => 'Elm Street',
            'eventType' => 'Open_Event',
            'expectedAttendance' => 50,
            'eventNotes' => 'Bring a lawn chair'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        String recordId = (String) result.get('recordId');
        Needs_Offers__c created = [SELECT Event_Type__c, Expected_Attendance__c, Event_Notes__c, Auto_Accept_Responses__c, Total_Quantity__c FROM Needs_Offers__c WHERE Id = :recordId];
        System.assertEquals('Open_Event', created.Event_Type__c, 'Event type should be Open_Event');
        System.assertEquals(50, created.Expected_Attendance__c, 'Expected attendance should be saved');
        System.assertEquals('Bring a lawn chair', created.Event_Notes__c, 'Event notes should be saved');
        System.assertEquals(true, created.Auto_Accept_Responses__c, 'Open Event should force auto-accept');
        System.assertEquals(null, created.Total_Quantity__c, 'Open Event should have no capacity limit');
    }

    @isTest
    static void testCreateNeedsOffersPost_CommunityEvent() {
        User testUser = getTestUser();

        String startIso = String.valueOf(Date.today().addDays(14)) + 'T18:00';

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Fireworks Show Downtown',
            'description' => 'Annual fireworks show at the waterfront',
            'type' => 'Event',
            'endDate' => String.valueOf(Date.today().addDays(21)),
            'eventStart' => startIso,
            'eventType' => 'Community_Event',
            'eventNotes' => 'Parking available at lot B',
            'eventLink' => 'https://example.com/fireworks'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        String recordId = (String) result.get('recordId');
        Needs_Offers__c created = [SELECT Event_Type__c, Event_Notes__c, Event_Link__c, Total_Quantity__c FROM Needs_Offers__c WHERE Id = :recordId];
        System.assertEquals('Community_Event', created.Event_Type__c, 'Event type should be Community_Event');
        System.assertEquals('Parking available at lot B', created.Event_Notes__c, 'Event notes should be saved');
        System.assertEquals('https://example.com/fireworks', created.Event_Link__c, 'Event link should be saved');
        System.assertEquals(null, created.Total_Quantity__c, 'Community Event should have no capacity limit');
    }

    @isTest
    static void testCreateNeedsOffersPost_AskQuantityDefaults() {
        User testUser = getTestUser();

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Need',
            'title' => 'Ask Without Quantity',
            'description' => 'Should default quantity to 1'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        String recordId = (String) result.get('recordId');
        Needs_Offers__c created = [SELECT Total_Quantity__c FROM Needs_Offers__c WHERE Id = :recordId];
        System.assertEquals(1, created.Total_Quantity__c, 'Ask quantity should default to 1');
    }

    @isTest
    static void testCreateNeedsOffersPost_LongDescription() {
        User testUser = getTestUser();

        String longDescription = '';
        for (Integer i = 0; i < 300; i++) {
            longDescription += 'X';
        }

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Need',
            'title' => 'Long Description Test',
            'description' => longDescription,
            'type' => 'Services - Paid',
            'quantity' => 1,
            'perResponseLimit' => 1
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should handle long descriptions');
    }

    @isTest
    static void testGetResponsesForNeedOffer() {
        User testUser = getTestUser();

        // Create a need first
        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Need',
            'title' => 'Need For Responses Test',
            'description' => 'Testing responses list',
            'type' => 'Services - Paid',
            'quantity' => 1,
            'perResponseLimit' => 1
        };

        Map<String, Object> createResult;
        System.runAs(testUser) {
            createResult = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        String needId = (String) createResult.get('recordId');

        Test.startTest();
        List<Map<String, Object>> responses;
        System.runAs(testUser) {
            responses = FimbyAskOfferController.getResponsesForNeedOffer(needId);
        }
        Test.stopTest();

        System.assertNotEquals(null, responses, 'Should return responses list');
        // No responses created, so list should be empty
        System.assertEquals(0, responses.size(), 'Should have no responses initially');
    }

    @isTest
    static void testGetResponsesForNeedOffer_PosterSeesResponderOwnedRow() {
        User posterUser = getTestUser();
        Contact posterContact = getTestContact();

        Contact responderContact = new Contact(
            FirstName = 'List',
            LastName = 'Responder',
            AccountId = posterContact.AccountId,
            Email = 'list.responder@fimby.test.com'
        );
        insert responderContact;
        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Need',
            'title' => 'Need For Poster Response List',
            'description' => 'Testing poster can list responder-owned responses',
            'type' => 'Services - Paid',
            'quantity' => 1,
            'perResponseLimit' => 1
        };

        Map<String, Object> createResult;
        System.runAs(posterUser) {
            createResult = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        String needId = (String) createResult.get('recordId');

        Response__c resp = new Response__c(
            Name = 'Poster List Response',
            Need_Offer_Responded_To__c = needId,
            Contact__c = responderContact.Id,
            On_Behalf_Of_Contact__c = responderContact.Id,
            Reply_To_Contact__c = posterContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(responderUser) {
            insert resp;
        }

        Test.startTest();
        List<Map<String, Object>> responses;
        System.runAs(posterUser) {
            responses = FimbyAskOfferController.getResponsesForNeedOffer(needId);
        }
        Test.stopTest();

        System.assertEquals(1, responses.size(), 'Poster should see responder-owned response');
        System.assertEquals(resp.Id, responses[0].get('id'), 'Should return the responder response id');
    }

    @isTest
    static void testDeleteNeedsOffersPost() {
        User testUser = getTestUser();

        // Create a need first
        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Need',
            'title' => 'Need To Delete',
            'description' => 'Testing delete',
            'type' => 'Services - Paid',
            'quantity' => 1,
            'perResponseLimit' => 1
        };

        Map<String, Object> createResult;
        System.runAs(testUser) {
            createResult = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        String needId = (String) createResult.get('recordId');

        Test.startTest();
        Map<String, Object> deleteResult;
        System.runAs(testUser) {
            deleteResult = FimbyAskOfferController.deleteNeedsOffersPost(needId, null);
        }
        Test.stopTest();

        System.assertEquals(true, deleteResult.get('success'), 'Should return success');
        // Verify deleted
        List<Needs_Offers__c> remaining = [SELECT Id FROM Needs_Offers__c WHERE Id = :needId];
        System.assertEquals(0, remaining.size(), 'Record should be deleted');
    }

    @isTest
    static void testDeleteNeedsOffersPost_NotifiesResponders() {
        User posterUser = getTestUser();
        Contact posterContact = getTestContact();

        Contact responderContact = new Contact(
            FirstName = 'Delete',
            LastName = 'NotifyResponder',
            AccountId = posterContact.AccountId,
            Email = 'delete.notify.responder@fimby.test.com'
        );
        insert responderContact;
        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Need',
            'title' => 'Need Delete Notify Test',
            'description' => 'Testing delete notifications',
            'type' => 'Services - Paid',
            'quantity' => 1,
            'perResponseLimit' => 1
        };

        Map<String, Object> createResult;
        System.runAs(posterUser) {
            createResult = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        String needId = (String) createResult.get('recordId');

        Response__c resp = new Response__c(
            Name = 'Delete Notify Response',
            Need_Offer_Responded_To__c = needId,
            Contact__c = responderContact.Id,
            On_Behalf_Of_Contact__c = responderContact.Id,
            Reply_To_Contact__c = posterContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(responderUser) {
            insert resp;
        }

        Test.startTest();
        System.runAs(posterUser) {
            FimbyAskOfferController.deleteNeedsOffersPost(needId, null);
        }
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Id, Title__c, Contact__c
            FROM Notification__c
            WHERE Contact__c = :responderContact.Id
              AND Title__c LIKE '%removed a post you responded to%'
        ];
        System.assert(!notifs.isEmpty(), 'Responder should be notified when post with pending response is deleted');
    }

    @isTest
    static void testCreateNeedsOffersPost_UrgentNeed() {
        User testUser = getTestUser();

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Need',
            'title' => 'Urgent Help Needed',
            'description' => 'I need help moving furniture today',
            'type' => 'Services - Free',
            'isUrgent' => true
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        String recordId = (String) result.get('recordId');
        Needs_Offers__c created = [SELECT Is_Urgent__c, Visibility_Scope__c FROM Needs_Offers__c WHERE Id = :recordId];
        System.assertEquals(true, created.Is_Urgent__c, 'Is_Urgent__c should be true');
        System.assertEquals('Adjacent', created.Visibility_Scope__c, 'Urgent needs should get Adjacent scope');
    }

    @isTest
    static void testCreateNeedsOffersPost_GatheringScope() {
        User testUser = getTestUser();

        String startIso = String.valueOf(Date.today().addDays(7)) + 'T18:00';

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Dinner Party',
            'description' => 'Join us for dinner',
            'type' => 'Event',
            'quantity' => 8,
            'perResponseLimit' => 2,
            'endDate' => String.valueOf(Date.today().addDays(14)),
            'eventStart' => startIso,
            'location' => '123 Maple Ave',
            'eventType' => 'Gathering'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        String recordId = (String) result.get('recordId');
        Needs_Offers__c created = [SELECT Visibility_Scope__c, Event_Type__c FROM Needs_Offers__c WHERE Id = :recordId];
        System.assertEquals('Gathering', created.Event_Type__c, 'Event type should be Gathering');
        System.assertEquals('Neighbourhood', created.Visibility_Scope__c, 'Gatherings should get Neighbourhood scope');
    }

    @isTest
    static void testGetNeedOfferVisibility_NullId() {
        Test.startTest();
        FimbyAskOfferController.VisibilityResult result = FimbyAskOfferController.getNeedOfferVisibility(null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.removed, 'Null id should return removed stub');
        System.assertEquals(false, result.visible, 'Null id should not be visible');
    }

    @isTest
    static void testGetNeedOfferVisibility_Visible() {
        User testUser = getTestUser();
        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Visibility Test Offer',
            'description' => 'Test',
            'type' => 'Services - Paid',
            'quantity' => 1,
            'perResponseLimit' => 1
        };
        Map<String, Object> created;
        System.runAs(testUser) {
            created = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Id recordId = (Id) created.get('recordId');

        Test.startTest();
        FimbyAskOfferController.VisibilityResult result = FimbyAskOfferController.getNeedOfferVisibility(recordId);
        Test.stopTest();

        System.assertEquals(true, result.visible, 'Newly created visible post should be visible');
        System.assertEquals(false, result.removed, 'Visible post should not be reported as removed');
    }

    @isTest
    static void testGetNeedOfferVisibility_Hidden() {
        User testUser = getTestUser();
        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Visibility Test Hidden',
            'description' => 'Test',
            'type' => 'Services - Paid',
            'quantity' => 1,
            'perResponseLimit' => 1
        };
        Map<String, Object> created;
        System.runAs(testUser) {
            created = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Id recordId = (Id) created.get('recordId');

        Needs_Offers__c hide = new Needs_Offers__c(Id = recordId, Moderation_Status__c = 'Hidden_By_Moderator');
        update hide;

        Test.startTest();
        FimbyAskOfferController.VisibilityResult result = FimbyAskOfferController.getNeedOfferVisibility(recordId);
        Test.stopTest();

        System.assertEquals(true, result.removed, 'Hidden post should be reported as removed');
        System.assertEquals(false, result.visible, 'Hidden post should not be visible');
        System.assertNotEquals(null, result.message, 'Removed stub should include a message');
    }

    @isTest
    static void testGetNeedOfferVisibility_ReturnsGroupConversationId() {
        User testUser = getTestUser();
        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Group Chat Visibility Offer',
            'description' => 'Test',
            'type' => 'Services - Paid',
            'quantity' => 1,
            'perResponseLimit' => 1
        };
        Map<String, Object> created;
        System.runAs(testUser) {
            created = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
        }
        Id recordId = (Id) created.get('recordId');
        Conversation__c conv = new Conversation__c(
            Is_Group__c = true,
            Group_Name__c = 'Group Chat Visibility Offer',
            Status__c = FimbyConstants.CONVERSATION_ACTIVE
        );
        insert conv;
        update new Needs_Offers__c(Id = recordId, Group_Conversation__c = conv.Id);

        Test.startTest();
        FimbyAskOfferController.VisibilityResult result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.getNeedOfferVisibility(recordId);
        }
        Test.stopTest();

        System.assertEquals(true, result.visible, 'Post should be visible');
        System.assertEquals(conv.Id, result.groupConversationId, 'Should return linked group conversation');
        System.assertEquals(conv.Id, FimbyAskOfferController.getGroupConversationIdForPost(recordId));
    }

    @isTest
    static void testCreateNeedsOffersPost_InvalidRecordType() {
        User testUser = getTestUser();

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'InvalidType',
            'title' => 'Test',
            'description' => 'Test',
            'type' => 'Services - Paid'
        };

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
            }
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            // Either record type error or other error is acceptable
            System.assert(e.getMessage() != null, 'Should have thrown an exception with a message');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateNeedsOffersPost_Need() {
        User testUser = getTestUser();

        Map<String, Object> createData = new Map<String, Object>{
            'postType' => 'Need',
            'title' => 'Original Need',
            'description' => 'Original description',
            'type' => 'Services - Paid',
            'quantity' => 1,
            'perResponseLimit' => 1,
            'isUrgent' => false,
            'autoAcceptResponses' => false,
            'autoShareContactInfo' => false
        };

        String recordId;
        System.runAs(testUser) {
            Map<String, Object> created = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(createData));
            recordId = (String) created.get('recordId');
        }

        Map<String, Object> updateData = new Map<String, Object>{
            'recordId' => recordId,
            'title' => 'Updated Need Title',
            'description' => 'Updated full description text',
            'endDate' => String.valueOf(Date.today().addDays(14)),
            'isUrgent' => true,
            'autoAcceptResponses' => true,
            'autoShareContactInfo' => true
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.updateNeedsOffersPost(JSON.serialize(updateData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        Needs_Offers__c updated = [
            SELECT Name, Full_Details__c, Is_Urgent__c, Auto_Accept_Responses__c, Visibility_Scope__c
            FROM Needs_Offers__c WHERE Id = :recordId
        ];
        System.assertEquals('Updated Need Title', updated.Name);
        System.assertEquals('Updated full description text', updated.Full_Details__c);
        System.assertEquals(true, updated.Is_Urgent__c);
        System.assertEquals('Adjacent', updated.Visibility_Scope__c);
    }

    @isTest
    static void testUpdateNeedsOffersPost_NotOwner() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Contact otherContact = FimbyTestDataFactory.createNeighbourhoodContact(testContact.AccountId, true);
        User otherUser = FimbyTestDataFactory.createCommunityUser(otherContact.Id, null, true);

        Map<String, Object> createData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Offer to protect',
            'description' => 'Description',
            'type' => 'Services - Paid',
            'quantity' => 5,
            'perResponseLimit' => 1
        };

        String recordId;
        System.runAs(testUser) {
            Map<String, Object> created = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(createData));
            recordId = (String) created.get('recordId');
        }

        Map<String, Object> updateData = new Map<String, Object>{
            'recordId' => recordId,
            'title' => 'Should Not Update'
        };

        Test.startTest();
        Boolean caught = false;
        FimbyIdentityRepository.clearCache();
        System.runAs(otherUser) {
            try {
                FimbyAskOfferController.updateNeedsOffersPost(JSON.serialize(updateData));
            } catch (Exception e) {
                caught = true;
            }
        }
        Test.stopTest();

        System.assert(caught, 'Non-owner should not be able to update');
        Needs_Offers__c unchanged = [SELECT Name FROM Needs_Offers__c WHERE Id = :recordId];
        System.assertEquals('Offer to protect', unchanged.Name, 'Title should remain unchanged');
    }

    @isTest
    static void testCreateNeedsOffersPost_EventEndBeforeStart() {
        User testUser = getTestUser();

        String startIso = String.valueOf(Date.today().addDays(7)) + 'T14:00';
        String endIso = String.valueOf(Date.today().addDays(7)) + 'T10:00';

        Map<String, Object> postData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Bad Dates Event',
            'description' => 'End before start',
            'type' => 'Event',
            'endDate' => String.valueOf(Date.today().addDays(14)),
            'eventStart' => startIso,
            'eventEnd' => endIso,
            'location' => 'Community Center'
        };

        Test.startTest();
        Boolean caught = false;
        System.runAs(testUser) {
            try {
                FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(postData));
            } catch (AuraHandledException e) {
                caught = true;
                System.assert(
                    e.getMessage().contains('after the start time'),
                    'Should explain end must follow start: ' + e.getMessage()
                );
            }
        }
        Test.stopTest();

        System.assert(caught, 'Create should reject end time before start time');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Needs_Offers__c WHERE Name = 'Bad Dates Event'],
            'Invalid event should not be inserted'
        );
    }

    @isTest
    static void testUpdateNeedsOffersPost_EventEndBeforeStart() {
        User testUser = getTestUser();

        String startIso = String.valueOf(Date.today().addDays(7)) + 'T10:00';
        String endIso = String.valueOf(Date.today().addDays(7)) + 'T14:00';

        Map<String, Object> createData = new Map<String, Object>{
            'postType' => 'Offer',
            'title' => 'Valid Event',
            'description' => 'Original event',
            'type' => 'Event',
            'endDate' => String.valueOf(Date.today().addDays(14)),
            'eventStart' => startIso,
            'eventEnd' => endIso,
            'location' => 'Community Center'
        };

        String recordId;
        System.runAs(testUser) {
            Map<String, Object> created = FimbyAskOfferController.createNeedsOffersPost(JSON.serialize(createData));
            recordId = (String) created.get('recordId');
        }

        String badEndIso = String.valueOf(Date.today().addDays(6)) + 'T22:00';
        Map<String, Object> updateData = new Map<String, Object>{
            'recordId' => recordId,
            'title' => 'Valid Event',
            'description' => 'Original event',
            'eventStart' => startIso,
            'eventEnd' => badEndIso,
            'location' => 'Community Center'
        };

        Test.startTest();
        Boolean caught = false;
        System.runAs(testUser) {
            try {
                FimbyAskOfferController.updateNeedsOffersPost(JSON.serialize(updateData));
            } catch (AuraHandledException e) {
                caught = true;
                System.assert(
                    e.getMessage().contains('after the start time'),
                    'Should explain end must follow start: ' + e.getMessage()
                );
            }
        }
        Test.stopTest();

        System.assert(caught, 'Update should reject end time before start time');
        Needs_Offers__c unchanged = [
            SELECT End_Date__c, End_Time__c
            FROM Needs_Offers__c
            WHERE Id = :recordId
        ];
        System.assertEquals(Date.today().addDays(7), unchanged.End_Date__c, 'End date should remain unchanged');
        System.assertEquals(Time.newInstance(14, 0, 0, 0), unchanged.End_Time__c, 'End time should remain unchanged');
    }

    @isTest
    static void testRefreshPost_bumpsPostedDateAndExtendsEnd() {
        User testUser = getTestUser();
        Contact contact = getTestContact();
        Account nh = [SELECT Id FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
        Id needRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Refresh Test Need',
            Details__c = 'Need help',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = needRt,
            Contact__c = contact.Id,
            Posted_By__c = contact.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(2),
            Posted_Date__c = Datetime.now().addDays(-10),
            Refresh_Count__c = 0
        );
        insert post;

        Datetime beforeRefresh = post.Posted_Date__c;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyAskOfferController.refreshPost(post.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        Needs_Offers__c updated = [
            SELECT Posted_Date__c, End_Date__c, Refresh_Count__c, Last_Refreshed_Date__c,
                   Last_Refresh_Reminder_Date__c
            FROM Needs_Offers__c WHERE Id = :post.Id
        ];
        System.assert(updated.Posted_Date__c > beforeRefresh, 'Posted_Date__c should bump');
        System.assertEquals(Date.today().addDays(FimbySettings.needDefaultEndDays()), updated.End_Date__c);
        System.assertEquals(1, updated.Refresh_Count__c.intValue());
        System.assertEquals(Date.today(), updated.Last_Refreshed_Date__c);
        System.assertEquals(null, updated.Last_Refresh_Reminder_Date__c);
    }

    @isTest
    static void testClosePost_resolvedNotifiesPendingResponder() {
        User testUser = getTestUser();
        Contact contact = getTestContact();
        Account nh = [SELECT Id FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
        Id needRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Close Test Need',
            Details__c = 'Need help',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = needRt,
            Contact__c = contact.Id,
            Posted_By__c = contact.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(3),
            Posted_Date__c = Datetime.now()
        );
        insert post;

        Contact responder = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = responder.Id,
            On_Behalf_Of_Contact__c = responder.Id,
            Status__c = FimbyConstants.RESPONSE_NEW
        );
        insert resp;

        Test.startTest();
        System.runAs(testUser) {
            FimbyAskOfferController.closePost(post.Id, 'resolved');
        }
        Test.stopTest();

        post = [SELECT Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_COMPLETED, post.Status__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Notification__c WHERE Contact__c = :responder.Id AND Type__c = :FimbyConstants.NOTIF_RESPONSE],
            'Pending responder should be notified'
        );
    }

    @isTest
    static void testGetRefreshPostState_authorSeesPanel() {
        User testUser = getTestUser();
        Contact contact = getTestContact();
        Account nh = [SELECT Id FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
        Id offerRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'State Test Offer',
            Details__c = 'Offering help',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = offerRt,
            Contact__c = contact.Id,
            Posted_By__c = contact.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(1),
            Posted_Date__c = Datetime.now().addDays(-8)
        );
        insert post;
        Test.setCreatedDate(post.Id, Datetime.now().addDays(-8));

        Test.startTest();
        Map<String, Object> state;
        System.runAs(testUser) {
            state = FimbyAskOfferController.getRefreshPostState(post.Id);
        }
        Test.stopTest();

        System.assertEquals(true, state.get('showPanel'));
        System.assertEquals(true, state.get('canRefresh'));
        System.assertEquals('Is this still available?', state.get('prompt'));
        System.assertEquals('Still available', state.get('refreshLabel'));
    }

    @isTest
    static void testGetRefreshPostState_hidesForNewPost() {
        User testUser = getTestUser();
        Contact contact = getTestContact();
        Account nh = [SELECT Id FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
        Id offerRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Brand New Offer',
            Details__c = 'Just posted',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = offerRt,
            Contact__c = contact.Id,
            Posted_By__c = contact.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(14),
            Posted_Date__c = Datetime.now()
        );
        insert post;

        Test.startTest();
        Map<String, Object> state;
        System.runAs(testUser) {
            state = FimbyAskOfferController.getRefreshPostState(post.Id);
        }
        Test.stopTest();

        System.assertEquals(false, state.get('showPanel'), 'New posts should not show the refresh panel');
    }

    @isTest
    static void testGetRefreshPostState_hidesForEvent() {
        User testUser = getTestUser();
        Contact contact = getTestContact();
        Account nh = [SELECT Id FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
        Id offerRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Festival Event',
            Details__c = 'Community gathering',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = offerRt,
            Type__c = 'Event',
            Event_Type__c = 'Open_Event',
            Contact__c = contact.Id,
            Posted_By__c = contact.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(1),
            Posted_Date__c = Datetime.now().addDays(-8)
        );
        insert post;
        Test.setCreatedDate(post.Id, Datetime.now().addDays(-8));

        Test.startTest();
        Map<String, Object> state;
        System.runAs(testUser) {
            state = FimbyAskOfferController.getRefreshPostState(post.Id);
        }
        Test.stopTest();

        System.assertEquals(false, state.get('showPanel'), 'Events should not show the refresh panel');
    }

    @isTest
    static void testRefreshPost_rejectsCooldown() {
        User testUser = getTestUser();
        Contact contact = getTestContact();
        Account nh = [SELECT Id FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
        Id needRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Cooldown Need',
            Details__c = 'Too soon',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = needRt,
            Contact__c = contact.Id,
            Posted_By__c = contact.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(5),
            Posted_Date__c = Datetime.now(),
            Refresh_Count__c = 1,
            Last_Refreshed_Date__c = Date.today()
        );
        insert post;

        Boolean caught = false;
        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyAskOfferController.refreshPost(post.Id);
            } catch (AuraHandledException e) {
                caught = true;
                System.assert(e.getMessage().contains('wait'), e.getMessage());
            }
        }
        Test.stopTest();
        System.assert(caught, 'Should reject refresh during cooldown');
    }

    @isTest
    static void testClosePost_withdrawnSetsCancelled() {
        User testUser = getTestUser();
        Contact contact = getTestContact();
        Account nh = [SELECT Id FROM Account WHERE Type = 'Neighbourhood' LIMIT 1];
        Id offerRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Withdraw Offer',
            Details__c = 'Gone',
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            RecordTypeId = offerRt,
            Contact__c = contact.Id,
            Posted_By__c = contact.Id,
            Neighbourhood__c = nh.Id,
            End_Date__c = Date.today().addDays(10),
            Posted_Date__c = Datetime.now()
        );
        insert post;

        Test.startTest();
        System.runAs(testUser) {
            FimbyAskOfferController.closePost(post.Id, 'withdrawn');
        }
        Test.stopTest();

        post = [SELECT Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals(FimbyConstants.NEEDS_OFFERS_CANCELLED, post.Status__c);
    }
}