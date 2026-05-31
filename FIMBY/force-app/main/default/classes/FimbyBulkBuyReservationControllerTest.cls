@isTest
public class FimbyBulkBuyReservationControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);

        Contact organiser = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(organiser.Id, null, true);

        Contact reserver = new Contact(
            FirstName = 'Reserver',
            LastName = 'Test',
            Email = 'reserver@fimby.test.com',
            AccountId = neighbourhood.Id,
            Image_URL__c = 'https://example.com/reserver.jpg'
        );
        insert reserver;
        FimbyTestDataFactory.createCommunityUser(reserver.Id, null, true);
    }

    private static User getOrganiserUser() {
        Contact c = [SELECT Id FROM Contact WHERE Email LIKE 'testuser%@fimby.test.com' LIMIT 1];
        return [SELECT Id, ContactId FROM User WHERE ContactId = :c.Id AND IsActive = true LIMIT 1];
    }

    private static User getReserverUser() {
        Contact c = [SELECT Id FROM Contact WHERE Email = 'reserver@fimby.test.com' LIMIT 1];
        return [SELECT Id, ContactId FROM User WHERE ContactId = :c.Id AND IsActive = true LIMIT 1];
    }

    private static Contact getOrganiserContact() {
        return [SELECT Id, AccountId FROM Contact WHERE Email LIKE 'testuser%@fimby.test.com' LIMIT 1];
    }

    private static Contact getReserverContact() {
        return [SELECT Id, AccountId FROM Contact WHERE Email = 'reserver@fimby.test.com' LIMIT 1];
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
            Per_Response_Limit__c = 5,
            Allocation_Unit_Label__c = 'shares',
            Availability_Rule__c = 'Open_Until_Full_Or_Closed',
            Auto_Accept_Responses__c = true,
            Auto_Lock_Days__c = '7'
        );
        insert post;
        return post;
    }

    @isTest
    static void testGetReservationContext_FormState() {
        User reserverUser = getReserverUser();
        Contact organiserContact = getOrganiserContact();
        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(reserverUser) {
            result = FimbyBulkBuyReservationController.getReservationContext(post.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed');
        System.assertEquals('form', result.get('viewState'), 'Should be form state for reserver');
        System.assertEquals(false, result.get('isBlocked'), 'Should not be blocked');
    }

    @isTest
    static void testGetReservationContext_FormWhenRealAuthorDiffersFromPostOwner() {
        User helperUser = getOrganiserUser();
        Contact helper = getOrganiserContact();
        Contact postOwner = getReserverContact();

        Id rtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Bulk_Buy').getRecordTypeId();
        Needs_Offers__c post = new Needs_Offers__c(
            RecordTypeId = rtId,
            Name = 'Dual-stamp bulk buy',
            Details__c = 'Test',
            Full_Details__c = 'Test',
            Status__c = 'Available',
            Posted_By__c = helper.Id,
            Contact__c = postOwner.Id,
            Neighbourhood__c = helper.AccountId,
            Giver_Recipient_Type__c = 'Self',
            Total_Quantity__c = 10,
            Per_Response_Limit__c = 5,
            Allocation_Unit_Label__c = 'shares',
            Availability_Rule__c = 'Open_Until_Full_Or_Closed',
            Auto_Accept_Responses__c = true,
            Auto_Lock_Days__c = '7'
        );
        insert post;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(helperUser) {
            result = FimbyBulkBuyReservationController.getReservationContext(post.Id);
        }
        Test.stopTest();

        System.assertEquals('form', result.get('viewState'),
            'Real author acting as self should reserve when post owner is another contact');
    }

    @isTest
    static void testGetReservationContext_UnavailableForOrganiser() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyBulkBuyReservationController.getReservationContext(post.Id);
        }
        Test.stopTest();

        System.assertEquals('unavailable', result.get('viewState'), 'Organiser cannot reserve own post');
    }

    @isTest
    static void testCreateReservation_Success() {
        User reserverUser = getReserverUser();
        Contact organiserContact = getOrganiserContact();
        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(reserverUser) {
            result = FimbyBulkBuyReservationController.createReservation(post.Id, 2);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed');
        System.assertNotEquals(null, result.get('responseId'), 'Should have responseId');
        System.assertNotEquals(null, result.get('groupConversationId'), 'Should have group conversation');
    }

    @isTest
    static void testCreateReservation_ExceedsAvailable() {
        User reserverUser = getReserverUser();
        Contact organiserContact = getOrganiserContact();
        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId);

        Test.startTest();
        Boolean caught = false;
        try {
            System.runAs(reserverUser) {
                FimbyBulkBuyReservationController.createReservation(post.Id, 20);
            }
        } catch (AuraHandledException e) {
            caught = true;
        }
        Test.stopTest();

        System.assert(caught, 'Should throw when exceeding available shares');
    }

    @isTest
    static void testCancelReservation_Success() {
        User reserverUser = getReserverUser();
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();
        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId);

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Test', Context_Type__c = 'Bulk_Buy',
            Related_Record_Id__c = post.Id, Status__c = 'Active'
        );
        insert conv;
        post.Group_Conversation__c = conv.Id;
        update post;

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = reserverContact.Id,
            Amount_Requested__c = 2,
            Status__c = 'New'
        );
        insert resp;
        resp.Status__c = 'Reserved';
        update resp;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(reserverUser) {
            result = FimbyBulkBuyReservationController.cancelReservation(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed');
        Response__c updated = [SELECT Status__c FROM Response__c WHERE Id = :resp.Id];
        System.assertEquals('Cancelled', updated.Status__c, 'Should be cancelled');
    }

    @isTest
    static void testRevokeReservation_Success() {
        User organiserUser = getOrganiserUser();
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();
        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId);

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true, Group_Name__c = 'Test', Context_Type__c = 'Bulk_Buy',
            Related_Record_Id__c = post.Id, Status__c = 'Active'
        );
        insert conv;
        post.Group_Conversation__c = conv.Id;
        update post;

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = reserverContact.Id,
            Amount_Requested__c = 3,
            Status__c = 'New'
        );
        insert resp;
        resp.Status__c = 'Reserved';
        update resp;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(organiserUser) {
            result = FimbyBulkBuyReservationController.revokeReservation(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed');
        Response__c updated = [SELECT Status__c FROM Response__c WHERE Id = :resp.Id];
        System.assertEquals('Cancelled', updated.Status__c, 'Should be cancelled after revoke');
    }

    @isTest
    static void testUpdateReservationAmount_Success() {
        User reserverUser = getReserverUser();
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();
        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId);

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = reserverContact.Id,
            Amount_Requested__c = 2,
            Status__c = 'New'
        );
        insert resp;
        resp.Status__c = 'Reserved';
        update resp;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(reserverUser) {
            result = FimbyBulkBuyReservationController.updateReservationAmount(resp.Id, 4);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed');
        Response__c updated = [SELECT Amount_Requested__c FROM Response__c WHERE Id = :resp.Id];
        System.assertEquals(4, updated.Amount_Requested__c, 'Amount should be updated');
    }

    @isTest
    static void testCreateReservation_BlockedUser() {
        User reserverUser = getReserverUser();
        Contact organiserContact = getOrganiserContact();
        Contact reserverContact = getReserverContact();
        Needs_Offers__c post = createBulkBuyPost(organiserContact, organiserContact.AccountId);

        reserverContact.Is_Bulk_Buy_Blocked__c = true;
        update reserverContact;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(reserverUser) {
            result = FimbyBulkBuyReservationController.createReservation(post.Id, 1);
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should fail for blocked user');
        System.assertEquals(true, result.get('blocked'), 'Should indicate blocked');
    }
}
