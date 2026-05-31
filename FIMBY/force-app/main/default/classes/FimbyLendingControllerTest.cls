@isTest
public class FimbyLendingControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User testUser = FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);
    }

    private static User getTestUser() {
        return [SELECT Id, ContactId FROM User WHERE Email LIKE '%@testorg.com' AND IsActive = true LIMIT 1];
    }

    private static Contact getTestContact() {
        return [SELECT Id, AccountId, Logged_In_As_Contact__c FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1];
    }

    private static Library_Item__c createTestLibraryItem(User owner, Contact ownerContact) {
        Library_Item__c item = new Library_Item__c(
            Name = 'Test Lending Item',
            Description__c = 'Test item for lending',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = ownerContact.Id,
            Neighbourhood__c = ownerContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7
        );
        System.runAs(owner) {
            insert item;
        }
        return item;
    }

    private static Lending_Request__c createTestLendingRequest(Library_Item__c item, Contact requester, String status) {
        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = requester.Id,
            Item_Owner__c = requester.Id, // Will be set properly in real scenario
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = status,
            Waitlist_Position__c = 1,
            Neighbourhood__c = requester.AccountId
        );
        insert request;
        return request;
    }

    @isTest
    static void testGetLendingRequestForApproval_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        // Item owner is set via Owner_Contact__c (already set in createTestLibraryItem)

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingRequestForApproval(request.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('lendingRequest'), 'Should return lending request data');
        System.assertNotEquals(null, result.get('libraryItem'), 'Should return library item data');
    }

    @isTest
    static void testGetLendingRequestForApproval_NoRecordId() {
        Test.startTest();
        Map<String, Object> result = FimbyLendingController.getLendingRequestForApproval(null);
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure');
        System.assertEquals('noRecordId', result.get('error'), 'Should have noRecordId error');
    }

    @isTest
    static void testGetLendingRequestForApproval_NothingToApprove() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Approved', // Already approved
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingRequestForApproval(request.Id);
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure');
        System.assertEquals('nothingToApprove', result.get('error'), 'Should have nothingToApprove error');
    }

    @isTest
    static void testGetLendingRequestForHandoff_Success_Approved() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Approved',
            Approved_and_Available_Date__c = Date.today(),
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingRequestForHandoff(request.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success for approved request');
        System.assertNotEquals(null, result.get('lendingRequest'), 'Should return lending request data');
        System.assertNotEquals(null, result.get('libraryItem'), 'Should return library item data');
    }

    @isTest
    static void testGetLendingRequestForHandoff_WrongStatus() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingRequestForHandoff(request.Id);
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure when not Approved');
        System.assertEquals('wrongStatus', result.get('error'), 'Should have wrongStatus error');
    }

    @isTest
    static void testApproveLendingRequest_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Map<String, Object> shareData = new Map<String, Object>{
            'shareEmail' => true,
            'sharePhone' => true,
            'shareAddress' => false,
            'email' => 'test@example.com',
            'phone' => '555-1234'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.approveLendingRequest(
                request.Id,
                String.valueOf(Date.today()),
                JSON.serialize(shareData)
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        // Verify request was updated
        Lending_Request__c updated = [SELECT Status__c, Date_Approved__c FROM Lending_Request__c WHERE Id = :request.Id];
        System.assertEquals('Approved', updated.Status__c, 'Status should be Approved');
        System.assertEquals(Date.today(), updated.Date_Approved__c, 'Date approved should be today');
    }

    @isTest
    static void testDeclineLendingRequest_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.declineLendingRequest(
                request.Id,
                'Item not available during requested time'
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        Lending_Request__c updated = [SELECT Status__c, Decline_Reason__c FROM Lending_Request__c WHERE Id = :request.Id];
        System.assertEquals('Declined', updated.Status__c, 'Status should be Declined');
        System.assertEquals('Item not available during requested time', updated.Decline_Reason__c, 'Decline reason should be set');

        List<Notification__c> notifs = [SELECT Type__c, Title__c, Body__c FROM Notification__c WHERE Contact__c = :testContact.Id AND Type__c = 'Lending_Request'];
        System.assert(!notifs.isEmpty(), 'Decline notification should be created for borrower');
        System.assertEquals('Your borrow request was declined', notifs[0].Title__c);
    }

    @isTest
    static void testGetLendingRequestForConfirmation_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Waitlisted',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingRequestForConfirmation(request.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testGetLendingRequestForConfirmation_NotOnWaitlist() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Pending Approval', // Not waitlisted
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingRequestForConfirmation(request.Id);
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure');
        System.assertEquals('notOnWaitlist', result.get('error'), 'Should have notOnWaitlist error');
    }

    @isTest
    static void testGetLendingRequestForConfirmation_RequestingConfirmation() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Requesting Confirmation',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingRequestForConfirmation(request.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'),
            'Promoted waitlist requests in Requesting Confirmation should load');
    }

    @isTest
    static void testConfirmLendingRequest_RequestingConfirmation() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Requesting Confirmation',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.confirmLendingRequest(
                request.Id,
                String.valueOf(Date.today().addDays(3))
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should confirm promoted waitlist request');
        Lending_Request__c updated = [
            SELECT Status__c FROM Lending_Request__c WHERE Id = :request.Id
        ];
        System.assertEquals('Pending Approval', updated.Status__c);
    }

    @isTest
    static void testConfirmLendingRequest_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Waitlisted',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.confirmLendingRequest(
                request.Id,
                String.valueOf(Date.today().addDays(3))
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        Lending_Request__c updated = [SELECT Status__c FROM Lending_Request__c WHERE Id = :request.Id];
        System.assertEquals('Pending Approval', updated.Status__c, 'Status should be Pending Approval');

        List<Notification__c> notifs = [SELECT Type__c, Title__c FROM Notification__c WHERE Contact__c = :testContact.Id AND Type__c = 'Lending_Request' AND Title__c LIKE '%confirmed%'];
        System.assert(!notifs.isEmpty(), 'Confirmation notification should be sent to owner');
    }

    @isTest
    static void testCancelLendingRequest_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Waitlisted',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.cancelLendingRequest(request.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        Lending_Request__c updated = [SELECT Status__c, Neighbourhood__c FROM Lending_Request__c WHERE Id = :request.Id];
        System.assertEquals('Cancelled', updated.Status__c, 'Status should be Cancelled');
        System.assertEquals(null, updated.Neighbourhood__c, 'Neighbourhood should be cleared');

        List<Notification__c> notifs = [SELECT Type__c, Title__c FROM Notification__c WHERE Contact__c = :testContact.Id AND Type__c = 'Lending_Request' AND Title__c LIKE '%cancelled%'];
        System.assert(!notifs.isEmpty(), 'Cancel notification should be sent to owner');
    }

    @isTest
    static void testGetLoanedItemForExtension_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        // Create library item in system context
        Library_Item__c item = new Library_Item__c(
            Name = 'Extension Test Item',
            Description__c = 'Test item for extension',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;

        // Create loaned item in system context with OwnerId
        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today().addDays(7),
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLoanedItemForExtension(loanedItem.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testGetLoanedItemForExtension_NoRecordId() {
        Test.startTest();
        Map<String, Object> result = FimbyLendingController.getLoanedItemForExtension(null);
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure for no record ID');
        System.assertEquals('noRecordId', result.get('error'), 'Should have noRecordId error');
    }

    @isTest
    static void testGetLoanedItemForExtension_WithWaitlist() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        // Create library item
        Library_Item__c item = new Library_Item__c(
            Name = 'Waitlist Test Item',
            Description__c = 'Test item with waitlist',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;

        // Create loaned item
        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today().addDays(7),
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            // As owner, even with waitlist, should succeed
            result = FimbyLendingController.getLoanedItemForExtension(loanedItem.Id);
        }
        Test.stopTest();

        // Owner should still be able to extend even with waitlist
        System.assertEquals(true, result.get('success'), 'Owner should be able to request extension');
    }

    @isTest
    static void testRequestLoanExtension_AsOwner() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        // Create library item in system context
        Library_Item__c item = new Library_Item__c(
            Name = 'Extension Test Item 2',
            Description__c = 'Test item for extension',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;

        // Create loaned item in system context with OwnerId
        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today().addDays(7),
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.requestLoanExtension(
                loanedItem.Id,
                String.valueOf(Date.today().addDays(14))
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('approved'), 'Should be approved immediately for owner');

        Loaned_Item__c updated = [SELECT Loan_Due_Date__c FROM Loaned_Item__c WHERE Id = :loanedItem.Id];
        System.assertEquals(Date.today().addDays(14), updated.Loan_Due_Date__c, 'Due date should be updated');

        List<Notification__c> notifs = [SELECT Type__c, Title__c FROM Notification__c WHERE Contact__c = :testContact.Id AND Type__c = 'Extension_Approved'];
        System.assert(!notifs.isEmpty(), 'Due date change notification should be sent to borrower');
    }

    @isTest
    static void testGetLoanedItemForExtensionApproval_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        
        Library_Item__c item = new Library_Item__c(
            Name = 'Extension Approval Item',
            Description__c = 'Test item',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;
        
        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today().addDays(7),
            Requested_Due_Date_Extension__c = Date.today().addDays(14),
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLoanedItemForExtensionApproval(loanedItem.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testGetLoanedItemForExtensionApproval_NoExtension() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        
        Library_Item__c item = new Library_Item__c(
            Name = 'No Extension Item',
            Description__c = 'Test item',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;
        
        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today().addDays(7),
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLoanedItemForExtensionApproval(loanedItem.Id);
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure');
        System.assertEquals('noExtension', result.get('error'), 'Should have noExtension error');
    }

    @isTest
    static void testApproveExtension_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        
        Library_Item__c item = new Library_Item__c(
            Name = 'Approve Extension Item',
            Description__c = 'Test item',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;
        
        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today().addDays(7),
            Requested_Due_Date_Extension__c = Date.today().addDays(14),
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.approveExtension(loanedItem.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        // Verify loaned item was updated
        Loaned_Item__c updated = [SELECT Loan_Due_Date__c, Requested_Due_Date_Extension__c FROM Loaned_Item__c WHERE Id = :loanedItem.Id];
        System.assertEquals(Date.today().addDays(14), updated.Loan_Due_Date__c, 'Due date should be updated');
        System.assertEquals(null, updated.Requested_Due_Date_Extension__c, 'Request should be cleared');
    }

    @isTest
    static void testDeclineExtension_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        
        Library_Item__c item = new Library_Item__c(
            Name = 'Decline Extension Item',
            Description__c = 'Test item',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;
        
        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today().addDays(7),
            Requested_Due_Date_Extension__c = Date.today().addDays(14),
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.declineExtension(loanedItem.Id, 'Item needed back');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        Loaned_Item__c updated = [SELECT Requested_Due_Date_Extension__c, Extension_Decline_Reason__c FROM Loaned_Item__c WHERE Id = :loanedItem.Id];
        System.assertEquals(null, updated.Requested_Due_Date_Extension__c, 'Request should be cleared');
        System.assertEquals('Item needed back', updated.Extension_Decline_Reason__c, 'Decline reason should be set');

        List<Notification__c> notifs = [SELECT Type__c, Title__c FROM Notification__c WHERE Contact__c = :testContact.Id AND Type__c = 'Extension_Declined'];
        System.assert(!notifs.isEmpty(), 'Extension declined notification should be sent to borrower');
    }

    @isTest
    static void testGetLoanedItemForExtensionApproval_NoRecordId() {
        Test.startTest();
        Map<String, Object> result = FimbyLendingController.getLoanedItemForExtensionApproval(null);
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure');
        System.assertEquals('noRecordId', result.get('error'), 'Should have noRecordId error');
    }

    @isTest
    static void testGetLendingRequestForConfirmation_NoRecordId() {
        Test.startTest();
        Map<String, Object> result = FimbyLendingController.getLendingRequestForConfirmation(null);
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure');
        System.assertEquals('noRecordId', result.get('error'), 'Should have noRecordId error');
    }

    @isTest
    static void testGetLendingRequestForConfirmation_NotFirstInLine() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Waitlisted',
            Waitlist_Position__c = 2, // Not first in line
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingRequestForConfirmation(request.Id);
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure');
        System.assertEquals('notFirst', result.get('error'), 'Should have notFirst error');
    }

    @isTest
    static void testRequestLoanExtension_AsBorrower() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        // Create a second contact to act as owner
        Account neighbourhood = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' LIMIT 1];
        Contact ownerContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        // Create library item owned by ownerContact
        Library_Item__c item = new Library_Item__c(
            Name = 'Borrower Extension Item',
            Description__c = 'Test item',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = ownerContact.Id,
            Neighbourhood__c = neighbourhood.Id,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7
        );
        insert item;

        // Create loaned item where testContact is the borrower
        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id, // testUser's contact is the borrower
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today().addDays(7)
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.requestLoanExtension(
                loanedItem.Id,
                String.valueOf(Date.today().addDays(14))
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(false, result.get('approved'), 'Should not be approved immediately for borrower');

        Loaned_Item__c updated = [SELECT Requested_Due_Date_Extension__c FROM Loaned_Item__c WHERE Id = :loanedItem.Id];
        System.assertEquals(Date.today().addDays(14), updated.Requested_Due_Date_Extension__c, 'Extension request should be set');

        List<Notification__c> notifs = [SELECT Type__c, Title__c FROM Notification__c WHERE Contact__c = :ownerContact.Id AND Type__c = 'Extension_Request'];
        System.assert(!notifs.isEmpty(), 'Extension request notification should be sent to owner');
    }

    @isTest
    static void testApproveLendingRequest_WithAddress() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Map<String, Object> shareData = new Map<String, Object>{
            'shareEmail' => true,
            'sharePhone' => false,
            'shareAddress' => true,
            'email' => 'test@example.com',
            'street' => '123 Test St',
            'city' => 'Vancouver',
            'state' => 'BC',
            'postalCode' => 'V5V 1V1',
            'country' => 'Canada',
            'additionalInfo' => 'Buzz 123'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.approveLendingRequest(
                request.Id,
                String.valueOf(Date.today()),
                JSON.serialize(shareData)
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        // Verify shared contact info was created with Origin and Lending_Request
        List<Shared_Contact_Info__c> sharedInfos = [
            SELECT Id, Email__c, Street__c, City__c, Origin__c, Lending_Request__c
            FROM Shared_Contact_Info__c
            WHERE Contact__c = :testContact.Id
        ];
        System.assert(sharedInfos.size() > 0, 'Should have created shared contact info');
        System.assertEquals('Lending', sharedInfos[0].Origin__c, 'Origin__c should be Lending');
        System.assertEquals(request.Id, sharedInfos[0].Lending_Request__c, 'Lending_Request__c should be set');
    }

    @isTest
    static void testApproveLendingRequest_ShareContactEmailFirstShareOnly() {
        User ownerUser = getTestUser();
        Contact ownerContact = getTestContact();
        Id neighbourhoodId = ownerContact.AccountId;

        Contact borrowerContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhoodId, true);
        User borrowerUser = FimbyTestDataFactory.createCommunityUser(borrowerContact.Id, null, true);

        FimbyTransactionalEmailService.transactionalTemplateId = borrowerUser.Id;
        FimbyTransactionalEmailService.oweaCached = null;
        FimbyTransactionalEmailService.testRenderedHtml =
            '<html><!-- FIMBY_DYNAMIC_CONTENT --><!-- FIMBY_INTRO_TEXT --><!-- FIMBY_INTENT_LINE --></html>';
        FimbyTransactionalEmailService.testSendInvocationCount = 0;

        Library_Item__c item = createTestLibraryItem(ownerUser, ownerContact);

        Map<String, Object> shareData = new Map<String, Object>{
            'shareEmail' => true,
            'sharePhone' => true,
            'shareAddress' => false,
            'email' => 'owner@test.com',
            'phone' => '555-1234'
        };

        Lending_Request__c firstRequest = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = borrowerContact.Id,
            Item_Owner__c = ownerContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1,
            Neighbourhood__c = neighbourhoodId
        );
        insert firstRequest;

        System.runAs(ownerUser) {
            FimbyLendingController.approveLendingRequest(
                firstRequest.Id,
                String.valueOf(Date.today()),
                JSON.serialize(shareData)
            );
        }
        System.assertEquals(1, FimbyTransactionalEmailService.testSendInvocationCount, 'Should email recipient on first share');

        Library_Item__c secondItem = new Library_Item__c(
            Name = 'Second Lending Item',
            Description__c = 'Second borrow',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = ownerContact.Id,
            Neighbourhood__c = neighbourhoodId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7
        );
        System.runAs(ownerUser) {
            insert secondItem;
        }

        Lending_Request__c secondRequest = new Lending_Request__c(
            Library_Item__c = secondItem.Id,
            Requested_By__c = borrowerContact.Id,
            Item_Owner__c = ownerContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1,
            Neighbourhood__c = neighbourhoodId
        );
        insert secondRequest;

        FimbyTransactionalEmailService.testSendInvocationCount = 0;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(ownerUser) {
            result = FimbyLendingController.approveLendingRequest(
                secondRequest.Id,
                String.valueOf(Date.today()),
                JSON.serialize(shareData)
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Re-share approval should succeed');
        System.assertEquals(0, FimbyTransactionalEmailService.testSendInvocationCount, 'Should not email when share content is unchanged');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Shared_Contact_Info__c WHERE Contact__c = :ownerContact.Id AND Shared_To__c = :borrowerContact.Id],
            'Should still have one shared contact record'
        );
    }

    @isTest
    static void testApproveLendingRequest_ShareContactEmailOnExpandedReshare() {
        User ownerUser = getTestUser();
        Contact ownerContact = getTestContact();
        Id neighbourhoodId = ownerContact.AccountId;

        Contact borrowerContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhoodId, true);
        User borrowerUser = FimbyTestDataFactory.createCommunityUser(borrowerContact.Id, null, true);

        FimbyTransactionalEmailService.transactionalTemplateId = borrowerUser.Id;
        FimbyTransactionalEmailService.oweaCached = null;
        FimbyTransactionalEmailService.testRenderedHtml =
            '<html><!-- FIMBY_DYNAMIC_CONTENT --><!-- FIMBY_INTRO_TEXT --><!-- FIMBY_INTENT_LINE --></html>';
        FimbyTransactionalEmailService.testSendInvocationCount = 0;

        Library_Item__c item = createTestLibraryItem(ownerUser, ownerContact);

        Map<String, Object> emailOnlyShare = new Map<String, Object>{
            'shareEmail' => true,
            'sharePhone' => false,
            'shareAddress' => false,
            'email' => 'owner@test.com'
        };

        Lending_Request__c firstRequest = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = borrowerContact.Id,
            Item_Owner__c = ownerContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1,
            Neighbourhood__c = neighbourhoodId
        );
        insert firstRequest;

        System.runAs(ownerUser) {
            FimbyLendingController.approveLendingRequest(
                firstRequest.Id,
                String.valueOf(Date.today()),
                JSON.serialize(emailOnlyShare)
            );
        }

        Library_Item__c secondItem = new Library_Item__c(
            Name = 'Expanded Share Item',
            Description__c = 'Second borrow with more contact info',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = ownerContact.Id,
            Neighbourhood__c = neighbourhoodId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7
        );
        System.runAs(ownerUser) {
            insert secondItem;
        }

        Lending_Request__c secondRequest = new Lending_Request__c(
            Library_Item__c = secondItem.Id,
            Requested_By__c = borrowerContact.Id,
            Item_Owner__c = ownerContact.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1,
            Neighbourhood__c = neighbourhoodId
        );
        insert secondRequest;

        Map<String, Object> expandedShare = new Map<String, Object>{
            'shareEmail' => true,
            'sharePhone' => true,
            'shareAddress' => false,
            'email' => 'owner@test.com',
            'phone' => '555-9999'
        };

        FimbyTransactionalEmailService.testSendInvocationCount = 0;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(ownerUser) {
            result = FimbyLendingController.approveLendingRequest(
                secondRequest.Id,
                String.valueOf(Date.today()),
                JSON.serialize(expandedShare)
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Expanded re-share approval should succeed');
        System.assertEquals(1, FimbyTransactionalEmailService.testSendInvocationCount, 'Should email when newly sharing phone');
    }

    // ===== Loaned Item Return Tests =====

    @isTest
    static void testGetLoanedItemForReturn_AsOwner() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Return Test Item',
            Description__c = 'Test item for return',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;

        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today(),
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLoanedItemForReturn(loanedItem.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('isOwner'), 'Should be identified as owner');
    }

    @isTest
    static void testGetLoanedItemForReturn_AlreadyReturned() {
        Test.startTest();
        // Use a fake ID that doesn't exist
        Map<String, Object> result = FimbyLendingController.getLoanedItemForReturn('a0000000000FAKE');
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure');
        System.assertEquals('alreadyReturned', result.get('error'), 'Should have alreadyReturned error');
    }

    @isTest
    static void testGetLoanedItemForReturn_NoRecordId() {
        Test.startTest();
        Map<String, Object> result = FimbyLendingController.getLoanedItemForReturn(null);
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure');
        System.assertEquals('noRecordId', result.get('error'), 'Should have noRecordId error');
    }

    @isTest
    static void testGetConditionPicklistValues() {
        Test.startTest();
        List<String> values = FimbyLendingController.getConditionPicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, values, 'Should return picklist values');
        // At minimum, should have some values
        System.assert(values.size() >= 0, 'Should return a list');
    }

    @isTest
    static void testSubmitBorrowerReturn_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Borrower Return Item',
            Description__c = 'Test item',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;

        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today(),
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.submitBorrowerReturn(
                loanedItem.Id,
                String.valueOf(Date.today()),
                false,
                'Yes'
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        Loaned_Item__c updated = [SELECT Return_Confirmed_By_Borrower__c, Borrow_From_Again__c FROM Loaned_Item__c WHERE Id = :loanedItem.Id];
        System.assertEquals(true, updated.Return_Confirmed_By_Borrower__c, 'Return should be confirmed');
        System.assertEquals('Yes', updated.Borrow_From_Again__c, 'Feedback should be saved');

        List<Notification__c> notifs = [SELECT Type__c, Title__c FROM Notification__c WHERE Contact__c = :testContact.Id AND Type__c = 'Item_Returned'];
        System.assert(!notifs.isEmpty(), 'Return notification should be sent to owner');
    }

    @isTest
    static void testSubmitBorrowerReturn_Damaged() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Damaged Return Item',
            Description__c = 'Test item',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;

        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today(),
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.submitBorrowerReturn(
                loanedItem.Id,
                String.valueOf(Date.today()),
                true,  // isDamaged
                'No'
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        // Verify loaned item was marked as damaged
        Loaned_Item__c updated = [SELECT Damaged_Lost__c FROM Loaned_Item__c WHERE Id = :loanedItem.Id];
        System.assertEquals(true, updated.Damaged_Lost__c, 'Should be marked as damaged');
    }

    @isTest
    static void testSubmitOwnerReturn_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Owner Return Item',
            Description__c = 'Test item',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;

        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today(),
            Neighbourhood__c = testContact.AccountId,
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.submitOwnerReturn(
                loanedItem.Id,
                String.valueOf(Date.today()),
                false,
                'Unchanged',
                'Yes'
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        Library_Item__c updatedItem = [SELECT Status__c FROM Library_Item__c WHERE Id = :item.Id];
        System.assertEquals('Available', updatedItem.Status__c, 'Status should be Available');

        List<Loaned_Item__c> remaining = [SELECT Id FROM Loaned_Item__c WHERE Id = :loanedItem.Id];
        System.assertEquals(0, remaining.size(), 'Loaned item should be deleted');

        List<Lending_History__c> histories = [SELECT Id FROM Lending_History__c WHERE Library_Item__c = :item.Id];
        System.assertEquals(1, histories.size(), 'Lending history should be created');

        List<Notification__c> notifs = [SELECT Type__c, Title__c FROM Notification__c WHERE Contact__c = :testContact.Id AND Type__c = 'Item_Returned' AND Title__c LIKE 'Return confirmed%'];
        System.assert(!notifs.isEmpty(), 'Return confirmed notification should be sent to borrower');
    }

    @isTest
    static void testSubmitOwnerReturn_Damaged() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Damaged Owner Return',
            Description__c = 'Test item',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;

        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today(),
            Neighbourhood__c = testContact.AccountId,
            OwnerId = testUser.Id
        );
        insert loanedItem;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.submitOwnerReturn(
                loanedItem.Id,
                String.valueOf(Date.today()),
                true,  // isDamaged
                'Badly Damaged',
                'No'
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        // Verify library item was removed from library
        Library_Item__c updatedItem = [SELECT Status__c FROM Library_Item__c WHERE Id = :item.Id];
        System.assertEquals('Removed from Library', updatedItem.Status__c, 'Status should be Removed from Library');
    }

    @isTest
    static void testSubmitOwnerReturn_WithWaitlist() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Waitlist Return Item',
            Description__c = 'Test item',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;

        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today(),
            Neighbourhood__c = testContact.AccountId,
            OwnerId = testUser.Id
        );
        insert loanedItem;

        // Create a waitlisted request
        Lending_Request__c waitlistRequest = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(7),
            of_Days_Needed__c = 3,
            Status__c = 'Waitlisted',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert waitlistRequest;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.submitOwnerReturn(
                loanedItem.Id,
                String.valueOf(Date.today()),
                false,
                'Unchanged',
                'Yes'
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        Lending_Request__c updatedRequest = [SELECT Status__c FROM Lending_Request__c WHERE Id = :waitlistRequest.Id];
        System.assertEquals('Requesting Confirmation', updatedRequest.Status__c, 'Waitlist request should be updated');

        List<Notification__c> notifs = [SELECT Type__c, Title__c, Action_URL__c FROM Notification__c WHERE Contact__c = :testContact.Id AND Type__c = 'Lending_Request' AND Title__c LIKE '%available%'];
        System.assert(!notifs.isEmpty(), 'Waitlist promotion notification should be sent');
        System.assert(notifs[0].Action_URL__c.contains('action=confirmWaitlist'), 'Action URL should contain deep link params');
    }

    /* ================================================================
     * recordHandoff Tests
     * ================================================================ */

    @isTest
    static void testRecordHandoff_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today(),
            of_Days_Needed__c = 5,
            Status__c = 'Approved',
            Approved_and_Available_Date__c = Date.today(),
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.recordHandoff(request.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Handoff should succeed');
        System.assertNotEquals(null, result.get('loanedItemId'), 'Should return loaned item id');

        // Verify lending request was deleted
        List<Lending_Request__c> remaining = [SELECT Id FROM Lending_Request__c WHERE Id = :request.Id];
        System.assertEquals(0, remaining.size(), 'Lending request should be deleted');

        // Verify loaned item was created
        List<Loaned_Item__c> loans = [SELECT Id, Loan_Due_Date__c FROM Loaned_Item__c WHERE Library_Item__c = :item.Id];
        System.assertEquals(1, loans.size(), 'Loaned item should be created');
    }

    @isTest
    static void testRecordHandoff_WithConversation() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today(),
            of_Days_Needed__c = 5,
            Status__c = 'Approved',
            Approved_and_Available_Date__c = Date.today(),
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testContact.Id,
            Participant_2__c = testContact.Id,
            Status__c = 'Active',
            Context_Type__c = 'Library_Lending',
            Related_Record_Id__c = request.Id
        );
        insert conv;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.recordHandoff(request.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Handoff should succeed');

        // Verify conversation was transferred to loan
        Conversation__c updatedConv = [SELECT Related_Record_Id__c FROM Conversation__c WHERE Id = :conv.Id];
        Id loanedItemId = (Id) result.get('loanedItemId');
        System.assertEquals(String.valueOf(loanedItemId), updatedConv.Related_Record_Id__c,
            'Conversation should point to loaned item');

        // Verify system message was created
        List<Message__c> messages = [SELECT Body__c FROM Message__c WHERE Conversation__c = :conv.Id];
        System.assert(!messages.isEmpty(), 'System message should be created');
    }

    @isTest
    static void testRecordHandoff_NotApproved() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today(),
            of_Days_Needed__c = 5,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.recordHandoff(request.Id);
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should fail for non-Approved request');
    }

    @isTest
    static void testRecordHandoff_NullId() {
        Test.startTest();
        Map<String, Object> result = FimbyLendingController.recordHandoff(null);
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should fail for null id');
    }

    /* ================================================================
     * getLendingConversationContext Tests
     * ================================================================ */

    @isTest
    static void testGetLendingConversationContext_ApprovedPhase() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today(),
            of_Days_Needed__c = 3,
            Status__c = 'Approved',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testContact.Id,
            Participant_2__c = testContact.Id,
            Status__c = 'Active',
            Context_Type__c = 'Library_Lending',
            Related_Record_Id__c = request.Id
        );
        insert conv;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingConversationContext(conv.Id);
        }
        Test.stopTest();

        System.assertEquals('approved', result.get('phase'), 'Phase should be approved');
        System.assertNotEquals(null, result.get('libraryItemId'), 'Should return library item id');
    }

    @isTest
    static void testGetLendingConversationContext_OnLoanPhase() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Loaned_Item__c loan = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today(),
            Loan_Due_Date__c = Date.today().addDays(7),
            Neighbourhood__c = testContact.AccountId,
            OwnerId = testUser.Id
        );
        insert loan;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testContact.Id,
            Participant_2__c = testContact.Id,
            Status__c = 'Active',
            Context_Type__c = 'Library_Lending',
            Related_Record_Id__c = loan.Id
        );
        insert conv;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingConversationContext(conv.Id);
        }
        Test.stopTest();

        System.assertNotEquals(null, result.get('phase'), 'Should return a loan phase');
        System.assertNotEquals(null, result.get('loanId'), 'Should return loan id');
    }

    @isTest
    static void testGetLendingConversationContext_NonLendingConversation() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testContact.Id,
            Participant_2__c = testContact.Id,
            Status__c = 'Active'
        );
        insert conv;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingConversationContext(conv.Id);
        }
        Test.stopTest();

        System.assertEquals(null, result.get('phase'), 'Phase should be null for non-lending conversation');
    }

    @isTest
    static void testGetLendingConversationContext_NullId() {
        Test.startTest();
        try {
            FimbyLendingController.getLendingConversationContext(null);
            System.assert(false, 'Should have thrown exception for null id');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetLendingConversationContext_ReturnedPhase() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Library_Item__c item = createTestLibraryItem(testUser, testContact);

        Lending_History__c history = new Lending_History__c(
            Library_Item__c = item.Id,
            Borrowed_By__c = testContact.Id,
            Start_Date__c = Date.today().addDays(-14),
            End_Date__c = Date.today(),
            Neighbourhood__c = testContact.AccountId
        );
        insert history;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testContact.Id,
            Participant_2__c = testContact.Id,
            Status__c = 'Active',
            Context_Type__c = 'Library_Lending',
            Related_Record_Id__c = history.Id
        );
        insert conv;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.getLendingConversationContext(conv.Id);
        }
        Test.stopTest();

        System.assertEquals('returned', result.get('phase'), 'Phase should be returned');
    }

    /* ================================================================
     * Damaged Item Waitlist Cancellation Test
     * ================================================================ */

    @isTest
    static void testSubmitOwnerReturn_DamagedCancelsWaitlist() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Damage Test Item',
            Description__c = 'Test item',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            OwnerId = testUser.Id
        );
        insert item;

        Loaned_Item__c loanedItem = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today(),
            Neighbourhood__c = testContact.AccountId,
            OwnerId = testUser.Id
        );
        insert loanedItem;

        // Create multiple waitlisted requests
        Lending_Request__c waitReq1 = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(7),
            of_Days_Needed__c = 3,
            Status__c = 'Waitlisted',
            Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert waitReq1;

        Lending_Request__c waitReq2 = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today().addDays(10),
            of_Days_Needed__c = 3,
            Status__c = 'Requesting Confirmation',
            Waitlist_Position__c = 2,
            Neighbourhood__c = testContact.AccountId
        );
        insert waitReq2;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLendingController.submitOwnerReturn(
                loanedItem.Id,
                String.valueOf(Date.today()),
                true,  // isDamaged
                'Badly Damaged',
                'No'
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        // Verify all active requests were cancelled
        List<Lending_Request__c> cancelled = [
            SELECT Status__c FROM Lending_Request__c
            WHERE Library_Item__c = :item.Id AND Status__c = 'Cancelled'
        ];
        System.assertEquals(2, cancelled.size(), 'All waitlisted requests should be cancelled');
    }
}