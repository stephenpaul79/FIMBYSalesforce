@isTest
public class FimbyFollowUpControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);

        Contact organiserContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(organiserContact.Id, null, true);

        Contact reserverContact = new Contact(
            FirstName = 'Reserver',
            LastName = 'TestUser',
            Email = 'reserver@fimby.test.com',
            AccountId = neighbourhood.Id,
            Image_URL__c = 'https://example.com/reserver.jpg'
        );
        insert reserverContact;
        FimbyTestDataFactory.createCommunityUser(reserverContact.Id, null, true);
    }

    private static User getOrganiserUser() {
        return [SELECT Id, ContactId FROM User WHERE Email LIKE '%@testorg.com' AND IsActive = true AND Contact.Email LIKE 'testuser%' LIMIT 1];
    }

    private static User getReserverUser() {
        return [SELECT Id, ContactId FROM User WHERE Email LIKE '%@testorg.com' AND IsActive = true AND Contact.Email = 'reserver@fimby.test.com' LIMIT 1];
    }

    private static Contact getOrganiserContact() {
        return [SELECT Id, AccountId, Logged_In_As_Contact__c FROM Contact WHERE Email LIKE 'testuser%@fimby.test.com' LIMIT 1];
    }

    private static Contact getReserverContact() {
        return [SELECT Id, AccountId, Logged_In_As_Contact__c FROM Contact WHERE Email = 'reserver@fimby.test.com' LIMIT 1];
    }

    private static Needs_Offers__c createBulkBuyPost(Contact poster, Id neighbourhoodId, String status) {
        Id rtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Bulk_Buy').getRecordTypeId();
        Needs_Offers__c post = new Needs_Offers__c(
            RecordTypeId = rtId,
            Name = 'Test Bulk Buy',
            Details__c = 'Test details',
            Full_Details__c = 'Full test details',
            Status__c = status,
            Posted_By__c = poster.Id,
            Contact__c = poster.Id,
            Neighbourhood__c = neighbourhoodId,
            Giver_Recipient_Type__c = 'Self',
            Total_Quantity__c = 10,
            Allocation_Unit_Label__c = 'shares',
            Availability_Rule__c = 'Open_Until_Full_Or_Closed',
            Auto_Accept_Responses__c = true,
            Auto_Lock_Days__c = '7',
            Pickup_Notified__c = (status == FimbyConstants.NEEDS_OFFERS_PICKUP_READY),
            Pickup_Notified_Date__c = (status == FimbyConstants.NEEDS_OFFERS_PICKUP_READY) ? System.now().addHours(-72) : null
        );
        insert post;
        return post;
    }

    private static Response__c createReservation(Needs_Offers__c post, Contact reserver) {
        Response__c resp = new Response__c(
            Name = 'Test Reservation',
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = reserver.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        insert resp;
        resp.Status__c = FimbyConstants.RESPONSE_RESERVED;
        update resp;
        return resp;
    }

    private static Bulk_Buy_Follow_Up__c createFollowUpRecord(Needs_Offers__c post, Response__c resp, Contact organiser, Contact reserver, String status) {
        Id fuRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c.getRecordTypeInfosByDeveloperName().get('Follow_Up').getRecordTypeId();
        Bulk_Buy_Follow_Up__c fu = new Bulk_Buy_Follow_Up__c(
            RecordTypeId = fuRtId,
            Bulk_Buy__c = post.Id,
            Reservation__c = resp.Id,
            Reporter__c = organiser.Id,
            Reported_User__c = reserver.Id,
            Status__c = status,
            Reason_Subtype__c = 'Missed_Pickup_Window',
            Reported_Date__c = System.now()
        );
        insert fu;
        return fu;
    }

    @isTest
    static void testReportFollowUp_Success() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId, FimbyConstants.NEEDS_OFFERS_PICKUP_READY);
        Response__c resp = createReservation(post, reserverContact);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyFollowUpController.reportFollowUp(resp.Id, 'Checking in about pickup', 'Missed_Pickup_Window');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('followUpId'), 'Should return a followUpId');
        System.assertNotEquals(null, result.get('conversationId'), 'Should return a conversationId');
    }

    @isTest
    static void testResolveFollowUp_Success() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId, FimbyConstants.NEEDS_OFFERS_PICKUP_READY);
        Response__c resp = createReservation(post, reserverContact);
        Bulk_Buy_Follow_Up__c fu = createFollowUpRecord(post, resp, organiserContact, reserverContact, FimbyConstants.FOLLOWUP_PENDING);

        Conversation__c dmConv = new Conversation__c(
            Context_Type__c = 'Missed_Pickup',
            Related_Record_Id__c = post.Id,
            Status__c = 'Active',
            Participant_1__c = organiserContact.Id,
            Participant_2__c = reserverContact.Id
        );
        insert dmConv;
        fu.Checkin_Conversation__c = dmConv.Id;
        update fu;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyFollowUpController.resolveFollowUp(fu.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        Bulk_Buy_Follow_Up__c updated = [SELECT Status__c FROM Bulk_Buy_Follow_Up__c WHERE Id = :fu.Id];
        System.assertEquals(FimbyConstants.FOLLOWUP_RESOLVED, updated.Status__c, 'Status should be Resolved');

        List<Notification__c> notifs = [
            SELECT Type__c, Title__c, Action_URL__c FROM Notification__c
            WHERE Contact__c = :organiserContact.Id
            AND Type__c = :FimbyConstants.NOTIF_FOLLOW_UP_RESOLVED
        ];
        System.assertEquals(1, notifs.size(), 'Should create a follow-up resolved notification for organiser');
        System.assert(notifs[0].Action_URL__c.contains('/conversation?id='), 'URL should link to conversation');
    }

    @isTest
    static void testEscalateFollowUp_Success() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId, FimbyConstants.NEEDS_OFFERS_PICKUP_READY);
        Response__c resp = createReservation(post, reserverContact);
        Bulk_Buy_Follow_Up__c fu = createFollowUpRecord(post, resp, organiserContact, reserverContact, FimbyConstants.FOLLOWUP_PENDING);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyFollowUpController.escalateFollowUp(fu.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        Bulk_Buy_Follow_Up__c updated = [SELECT Status__c FROM Bulk_Buy_Follow_Up__c WHERE Id = :fu.Id];
        System.assertEquals(FimbyConstants.FOLLOWUP_ESCALATED, updated.Status__c, 'Status should be Escalated');
    }

    @isTest
    static void testGetFollowUpStatus_Success() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId, FimbyConstants.NEEDS_OFFERS_PICKUP_READY);
        Response__c resp = createReservation(post, reserverContact);
        createFollowUpRecord(post, resp, organiserContact, reserverContact, FimbyConstants.FOLLOWUP_PENDING);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyFollowUpController.getFollowUpStatus(post.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        Map<String, Object> statusByReservation = (Map<String, Object>) result.get('statusByReservation');
        System.assert(statusByReservation.containsKey(resp.Id), 'Should have an entry for the reservation');
    }

    @isTest
    static void testGetFollowUpByConversation_Success() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId, FimbyConstants.NEEDS_OFFERS_PICKUP_READY);
        Response__c resp = createReservation(post, reserverContact);
        Bulk_Buy_Follow_Up__c fu = createFollowUpRecord(post, resp, organiserContact, reserverContact, FimbyConstants.FOLLOWUP_PENDING);
        Id conversationId = fu.Checkin_Conversation__c;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyFollowUpController.getFollowUpByConversation(conversationId);
        }
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return follow-up');
        System.assertEquals(fu.Id, result.get('followUpId'), 'Should return follow-up Id');
        System.assertEquals(FimbyConstants.FOLLOWUP_PENDING, result.get('status'), 'Should return Pending status');
    }

    @isTest
    static void testGetBulkBuyHistory_NoHistory() {
        User organiserUser = getOrganiserUser();
        Contact reserverContact = getReserverContact();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyFollowUpController.getBulkBuyHistory(reserverContact.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        List<Object> slots = (List<Object>) result.get('slots');
        System.assertEquals(3, slots.size(), 'Should have 3 slots');
        for (Object slot : slots) {
            System.assertEquals('neutral', (String) slot, 'All slots should be neutral with no history');
        }
        System.assertEquals(false, result.get('hasActiveAmber'), 'Should not have active amber');
    }

    @isTest
    static void testAdminResolveFollowUp_Confirmed() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId, FimbyConstants.NEEDS_OFFERS_PICKUP_READY);
        Response__c resp = createReservation(post, reserverContact);
        Bulk_Buy_Follow_Up__c fu = createFollowUpRecord(post, resp, organiserContact, reserverContact, FimbyConstants.FOLLOWUP_ESCALATED);

        Conversation__c dmConv = new Conversation__c(
            Context_Type__c = 'Missed_Pickup',
            Related_Record_Id__c = post.Id,
            Status__c = 'Active',
            Participant_1__c = organiserContact.Id,
            Participant_2__c = reserverContact.Id
        );
        insert dmConv;
        fu.Checkin_Conversation__c = dmConv.Id;
        update fu;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyFollowUpController.adminResolveFollowUp(fu.Id, 'Confirmed no pickup', true);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        Bulk_Buy_Follow_Up__c updated = [SELECT Status__c FROM Bulk_Buy_Follow_Up__c WHERE Id = :fu.Id];
        System.assertEquals(FimbyConstants.FOLLOWUP_ADMIN_CONFIRMED, updated.Status__c, 'Status should be Admin_Confirmed');
        Response__c updatedResp = [SELECT Status__c FROM Response__c WHERE Id = :resp.Id];
        System.assertEquals(FimbyConstants.RESPONSE_NO_FOLLOW_THROUGH, updatedResp.Status__c, 'Response should be No_Follow_Through');
    }

    @isTest
    static void testAutoFinalizeJob_NotifiesOrganiser() {
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId, FimbyConstants.NEEDS_OFFERS_PICKUP_READY);
        Response__c resp = createReservation(post, reserverContact);

        Conversation__c dmConv = new Conversation__c(
            Context_Type__c = 'Missed_Pickup',
            Related_Record_Id__c = post.Id,
            Status__c = 'Active',
            Participant_1__c = organiserContact.Id,
            Participant_2__c = reserverContact.Id
        );
        insert dmConv;

        Id fuRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c.getRecordTypeInfosByDeveloperName().get('Follow_Up').getRecordTypeId();
        Bulk_Buy_Follow_Up__c fu = new Bulk_Buy_Follow_Up__c(
            RecordTypeId = fuRtId,
            Bulk_Buy__c = post.Id,
            Reservation__c = resp.Id,
            Reporter__c = organiserContact.Id,
            Reported_User__c = reserverContact.Id,
            Status__c = FimbyConstants.FOLLOWUP_PENDING,
            Reason_Subtype__c = 'Missed_Pickup_Window',
            Reported_Date__c = System.now().addDays(-3),
            Checkin_Conversation__c = dmConv.Id
        );
        insert fu;

        Test.startTest();
        new FimbyFollowUpAutoFinalizeJob().execute(null);
        Test.stopTest();

        Bulk_Buy_Follow_Up__c updated = [SELECT Status__c FROM Bulk_Buy_Follow_Up__c WHERE Id = :fu.Id];
        System.assertEquals(FimbyConstants.FOLLOWUP_NO_RESPONSE, updated.Status__c, 'Status should be No_Response');

        List<Notification__c> notifs = [
            SELECT Type__c, Title__c, Action_URL__c FROM Notification__c
            WHERE Contact__c = :organiserContact.Id
            AND Type__c = :FimbyConstants.NOTIF_FOLLOW_UP_RESOLVED
        ];
        System.assertEquals(1, notifs.size(), 'Should create auto-finalize notification for organiser');
        System.assert(notifs[0].Title__c.contains('didn\'t respond'), 'Title should mention non-response');
        System.assert(notifs[0].Action_URL__c.contains('/conversation?id='), 'URL should link to conversation');
    }

    @isTest
    static void testGetBulkBuyHistory_NewestOnLeft() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId, FimbyConstants.NEEDS_OFFERS_PICKUP_READY);
        Response__c resp = createReservation(post, reserverContact);
        resp.Status__c = FimbyConstants.RESPONSE_COMPLETED;
        update resp;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyFollowUpController.getBulkBuyHistory(reserverContact.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        List<Object> slots = (List<Object>) result.get('slots');
        System.assertEquals(3, slots.size(), 'Should have 3 slots');
        System.assertEquals('green', (String) slots[0], 'Newest event should be in the leftmost slot');
        System.assertEquals('neutral', (String) slots[1], 'Older slot should be empty');
        System.assertEquals('neutral', (String) slots[2], 'Oldest slot should be empty');
    }

    @isTest
    static void testAdminRestoreEligibility_Success() {
        User organiserUser = getOrganiserUser();
        Contact reserverContact = getReserverContact();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyFollowUpController.adminRestoreEligibility(
                reserverContact.Id, 'Spoke with user', 'Will pick up on time going forward'
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('restorationId'), 'Should return a restorationId');
    }
}