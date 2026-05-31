@isTest
public class FimbyScheduledJobsTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);

        Contact organiser = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        Contact reserver = new Contact(
            FirstName = 'Reserver',
            LastName = 'Test',
            Email = 'reserver@fimby.test.com',
            AccountId = neighbourhood.Id,
            Image_URL__c = 'https://example.com/reserver.jpg'
        );
        insert reserver;
    }

    private static Contact getOrganiserContact() {
        return [SELECT Id, AccountId FROM Contact WHERE Email LIKE 'testuser%@fimby.test.com' LIMIT 1];
    }

    private static Contact getReserverContact() {
        return [SELECT Id FROM Contact WHERE Email = 'reserver@fimby.test.com' LIMIT 1];
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
            Auto_Lock_Days__c = '7'
        );
        insert post;
        return post;
    }

    @isTest
    static void testBulkBuyExpiryJob() {
        Contact organiser = getOrganiserContact();
        Id rtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Bulk_Buy').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            RecordTypeId = rtId,
            Name = 'Expiring Buy',
            Details__c = 'Test',
            Full_Details__c = 'Test',
            Status__c = 'Available',
            Posted_By__c = organiser.Id,
            Contact__c = organiser.Id,
            Neighbourhood__c = organiser.AccountId,
            Giver_Recipient_Type__c = 'Self',
            Total_Quantity__c = 5,
            Allocation_Unit_Label__c = 'units',
            Availability_Rule__c = 'Expires_At_Date',
            Expiry_DateTime__c = System.now().addHours(-1),
            Auto_Accept_Responses__c = true,
            Auto_Lock_Days__c = '7'
        );
        insert post;

        Test.startTest();
        new FimbyBulkBuyExpiryJob().execute(null);
        Test.stopTest();

        Needs_Offers__c updated = [SELECT Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Expired', updated.Status__c, 'Should be expired');
    }

    @isTest
    static void testBulkBuyExpiryJob_NotExpired() {
        Contact organiser = getOrganiserContact();
        Id rtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Bulk_Buy').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            RecordTypeId = rtId,
            Name = 'Future Buy',
            Details__c = 'Test',
            Full_Details__c = 'Test',
            Status__c = 'Available',
            Posted_By__c = organiser.Id,
            Contact__c = organiser.Id,
            Neighbourhood__c = organiser.AccountId,
            Giver_Recipient_Type__c = 'Self',
            Total_Quantity__c = 5,
            Allocation_Unit_Label__c = 'units',
            Availability_Rule__c = 'Expires_At_Date',
            Expiry_DateTime__c = System.now().addDays(7),
            Auto_Accept_Responses__c = true,
            Auto_Lock_Days__c = '7'
        );
        insert post;

        Test.startTest();
        new FimbyBulkBuyExpiryJob().execute(null);
        Test.stopTest();

        Needs_Offers__c updated = [SELECT Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Available', updated.Status__c, 'Should still be Available');
    }

    @isTest
    static void testFollowUpAutoFinalizeJob() {
        Contact organiser = getOrganiserContact();
        Contact reserver = getReserverContact();
        Needs_Offers__c post = createBulkBuyPost(organiser, organiser.AccountId, 'Pickup_Ready');
        post.Pickup_Notified__c = true;
        post.Pickup_Notified_Date__c = System.now().addDays(-5);
        update post;

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = reserver.Id,
            Amount_Requested__c = 2,
            Status__c = 'New'
        );
        insert resp;
        resp.Status__c = 'Reserved';
        update resp;

        Id fuRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c.getRecordTypeInfosByDeveloperName().get('Follow_Up').getRecordTypeId();
        Bulk_Buy_Follow_Up__c fu = new Bulk_Buy_Follow_Up__c(
            RecordTypeId = fuRtId,
            Bulk_Buy__c = post.Id,
            Reservation__c = resp.Id,
            Reporter__c = organiser.Id,
            Reported_User__c = reserver.Id,
            Status__c = 'Pending',
            Reason_Subtype__c = 'Missed_Pickup_Window',
            Reported_Date__c = System.now().addDays(-3)
        );
        insert fu;

        Test.startTest();
        new FimbyFollowUpAutoFinalizeJob().execute(null);
        Test.stopTest();

        Bulk_Buy_Follow_Up__c updatedFu = [SELECT Status__c FROM Bulk_Buy_Follow_Up__c WHERE Id = :fu.Id];
        System.assertEquals('No_Response', updatedFu.Status__c, 'Follow-up should be No_Response');

        Response__c updatedResp = [SELECT Status__c FROM Response__c WHERE Id = :resp.Id];
        System.assertEquals('No_Follow_Through', updatedResp.Status__c, 'Response should be No_Follow_Through');
    }

    @isTest
    static void testBulkBuyAutoLockJob_CompletesPost() {
        Contact organiser = getOrganiserContact();
        Contact reserver = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiser, organiser.AccountId, 'Pickup_Ready');
        post.Pickup_Notified__c = true;
        post.Pickup_Notified_Date__c = System.now().addDays(-10);
        update post;

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = reserver.Id,
            Amount_Requested__c = 2,
            Status__c = 'New'
        );
        insert resp;
        resp.Status__c = 'Reserved';
        update resp;

        Test.startTest();
        new FimbyBulkBuyAutoLockJob().execute(null);
        Test.stopTest();

        Needs_Offers__c updated = [SELECT Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Completed (Offer Accepted / Need Met)', updated.Status__c, 'Should be completed');

        Response__c updatedResp = [SELECT Status__c FROM Response__c WHERE Id = :resp.Id];
        System.assertEquals('Completed', updatedResp.Status__c, 'Response should be completed');
    }

    @isTest
    static void testBulkBuyAutoLockJob_DefersForPendingFollowUp() {
        Contact organiser = getOrganiserContact();
        Contact reserver = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiser, organiser.AccountId, 'Pickup_Ready');
        post.Pickup_Notified__c = true;
        post.Pickup_Notified_Date__c = System.now().addDays(-8);
        update post;

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = reserver.Id,
            Amount_Requested__c = 2,
            Status__c = 'New'
        );
        insert resp;
        resp.Status__c = 'Reserved';
        update resp;

        Id fuRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c.getRecordTypeInfosByDeveloperName().get('Follow_Up').getRecordTypeId();
        insert new Bulk_Buy_Follow_Up__c(
            RecordTypeId = fuRtId,
            Bulk_Buy__c = post.Id,
            Reservation__c = resp.Id,
            Reporter__c = organiser.Id,
            Reported_User__c = reserver.Id,
            Status__c = 'Pending',
            Reason_Subtype__c = 'Missed_Pickup_Window',
            Reported_Date__c = System.now().addDays(-2)
        );

        Test.startTest();
        new FimbyBulkBuyAutoLockJob().execute(null);
        Test.stopTest();

        Needs_Offers__c updated = [SELECT Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Pickup_Ready', updated.Status__c, 'Should still be Pickup_Ready (deferred)');
    }

    @isTest
    static void testBulkBuyExpiryJob_WithGroupConversation() {
        Contact organiser = getOrganiserContact();
        Needs_Offers__c post = createBulkBuyPost(organiser, organiser.AccountId, 'Available');
        post.Availability_Rule__c = 'Expires_At_Date';
        post.Expiry_DateTime__c = System.now().addHours(-1);

        Conversation__c conv = new Conversation__c(
            Is_Group__c = true,
            Group_Name__c = 'Test Group',
            Context_Type__c = 'Bulk_Buy',
            Related_Record_Id__c = post.Id,
            Status__c = 'Active'
        );
        insert conv;
        post.Group_Conversation__c = conv.Id;
        update post;

        Test.startTest();
        new FimbyBulkBuyExpiryJob().execute(null);
        Test.stopTest();

        Needs_Offers__c updated = [SELECT Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Expired', updated.Status__c, 'Should be expired');
        Conversation__c updatedConv = [SELECT Locked__c FROM Conversation__c WHERE Id = :conv.Id];
        System.assertEquals(true, updatedConv.Locked__c, 'Conversation should be locked');
    }

    @isTest
    static void testAutoLockJob_EscalatesPendingAfterGrace() {
        Contact organiser = getOrganiserContact();
        Contact reserver = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiser, organiser.AccountId, 'Pickup_Ready');
        post.Pickup_Notified__c = true;
        post.Pickup_Notified_Date__c = System.now().addDays(-20);
        update post;

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = reserver.Id,
            Amount_Requested__c = 2,
            Status__c = 'New'
        );
        insert resp;
        resp.Status__c = 'Reserved';
        update resp;

        Id fuRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c.getRecordTypeInfosByDeveloperName().get('Follow_Up').getRecordTypeId();
        Bulk_Buy_Follow_Up__c fu = new Bulk_Buy_Follow_Up__c(
            RecordTypeId = fuRtId,
            Bulk_Buy__c = post.Id,
            Reservation__c = resp.Id,
            Reporter__c = organiser.Id,
            Reported_User__c = reserver.Id,
            Status__c = 'Pending',
            Reason_Subtype__c = 'Missed_Pickup_Window',
            Reported_Date__c = System.now().addDays(-15)
        );
        insert fu;

        Test.startTest();
        new FimbyBulkBuyAutoLockJob().execute(null);
        Test.stopTest();

        Bulk_Buy_Follow_Up__c updatedFu = [SELECT Status__c FROM Bulk_Buy_Follow_Up__c WHERE Id = :fu.Id];
        System.assertEquals('Escalated', updatedFu.Status__c, 'Follow-up should be escalated after grace');

        Needs_Offers__c updatedPost = [SELECT Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Completed (Offer Accepted / Need Met)', updatedPost.Status__c, 'Post should be completed');
    }

    @isTest
    static void testAutoFinalizeJob_WithConversation() {
        Contact organiser = getOrganiserContact();
        Contact reserver = getReserverContact();
        Needs_Offers__c post = createBulkBuyPost(organiser, organiser.AccountId, 'Pickup_Ready');
        post.Pickup_Notified__c = true;
        post.Pickup_Notified_Date__c = System.now().addDays(-5);
        update post;

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = reserver.Id,
            Amount_Requested__c = 2,
            Status__c = 'New'
        );
        insert resp;
        resp.Status__c = 'Reserved';
        update resp;

        Conversation__c conv = new Conversation__c(
            Is_Group__c = false,
            Context_Type__c = 'Missed_Pickup',
            Related_Record_Id__c = post.Id,
            Status__c = 'Active',
            Participant_1__c = organiser.Id,
            Participant_2__c = reserver.Id
        );
        insert conv;

        Id fuRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c.getRecordTypeInfosByDeveloperName().get('Follow_Up').getRecordTypeId();
        Bulk_Buy_Follow_Up__c fu = new Bulk_Buy_Follow_Up__c(
            RecordTypeId = fuRtId,
            Bulk_Buy__c = post.Id,
            Reservation__c = resp.Id,
            Reporter__c = organiser.Id,
            Reported_User__c = reserver.Id,
            Status__c = 'Pending',
            Reason_Subtype__c = 'Missed_Pickup_Window',
            Reported_Date__c = System.now().addDays(-3),
            Checkin_Conversation__c = conv.Id
        );
        insert fu;

        Test.startTest();
        new FimbyFollowUpAutoFinalizeJob().execute(null);
        Test.stopTest();

        Bulk_Buy_Follow_Up__c updatedFu = [SELECT Status__c FROM Bulk_Buy_Follow_Up__c WHERE Id = :fu.Id];
        System.assertEquals('No_Response', updatedFu.Status__c, 'Follow-up should be No_Response');
    }

    @isTest
    static void testFollowUpExpiryJob() {
        Contact organiser = getOrganiserContact();
        Contact reserver = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiser, organiser.AccountId, 'Pickup_Ready');

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = reserver.Id,
            Amount_Requested__c = 1,
            Status__c = 'New'
        );
        insert resp;
        resp.Status__c = 'No_Follow_Through';
        update resp;

        Id fuRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c.getRecordTypeInfosByDeveloperName().get('Follow_Up').getRecordTypeId();
        Bulk_Buy_Follow_Up__c fu = new Bulk_Buy_Follow_Up__c(
            RecordTypeId = fuRtId,
            Bulk_Buy__c = post.Id,
            Reservation__c = resp.Id,
            Reporter__c = organiser.Id,
            Reported_User__c = reserver.Id,
            Status__c = 'No_Response',
            Reason_Subtype__c = 'Missed_Pickup_Window',
            Reported_Date__c = System.now().addDays(-200)
        );
        insert fu;

        Test.startTest();
        new FimbyFollowUpExpiryJob().execute(null);
        Test.stopTest();

        Bulk_Buy_Follow_Up__c updated = [SELECT Status__c FROM Bulk_Buy_Follow_Up__c WHERE Id = :fu.Id];
        System.assertEquals('Expired', updated.Status__c, 'Should be expired after 180 days');
    }

    @isTest
    static void testFollowUpExpiryJob_SkipsRecent() {
        Contact organiser = getOrganiserContact();
        Contact reserver = getReserverContact();

        Needs_Offers__c post = createBulkBuyPost(organiser, organiser.AccountId, 'Pickup_Ready');

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = reserver.Id,
            Amount_Requested__c = 1,
            Status__c = 'New'
        );
        insert resp;
        resp.Status__c = 'No_Follow_Through';
        update resp;

        Id fuRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c.getRecordTypeInfosByDeveloperName().get('Follow_Up').getRecordTypeId();
        Bulk_Buy_Follow_Up__c fu = new Bulk_Buy_Follow_Up__c(
            RecordTypeId = fuRtId,
            Bulk_Buy__c = post.Id,
            Reservation__c = resp.Id,
            Reporter__c = organiser.Id,
            Reported_User__c = reserver.Id,
            Status__c = 'No_Response',
            Reason_Subtype__c = 'Missed_Pickup_Window',
            Reported_Date__c = System.now().addDays(-30)
        );
        insert fu;

        Test.startTest();
        new FimbyFollowUpExpiryJob().execute(null);
        Test.stopTest();

        Bulk_Buy_Follow_Up__c updated = [SELECT Status__c FROM Bulk_Buy_Follow_Up__c WHERE Id = :fu.Id];
        System.assertEquals('No_Response', updated.Status__c, 'Should still be No_Response (< 180 days)');
    }
}
