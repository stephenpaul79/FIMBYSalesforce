@isTest
private class FimbySharedContactsControllerTest {

    @testSetup
    static void setupTestData() {
        Account testNeighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, true);
        Contact testContact2 = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, true);
        
        // Create shared contact info
        Shared_Contact_Info__c shared = new Shared_Contact_Info__c(
            Contact__c = testContact.Id,
            Shared_To__c = testContact2.Id,
            Email__c = 'test@example.com',
            Phone__c = '555-1234'
        );
        insert shared;
    }

    @isTest
    static void testGetSharedContactsList_NoFilter() {
        Test.startTest();
        FimbySharedContactsController.SharedContactListResult result = 
            FimbySharedContactsController.getSharedContactsList(null, 'CreatedDate', 'DESC', 10, 0);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.records.size() > 0);
    }

    @isTest
    static void testGetSharedContactsList_WithSearch() {
        Test.startTest();
        FimbySharedContactsController.SharedContactListResult result = 
            FimbySharedContactsController.getSharedContactsList('test', 'CreatedDate', 'DESC', 10, 0);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGetSharedContactsList_Pagination() {
        Test.startTest();
        FimbySharedContactsController.SharedContactListResult result = 
            FimbySharedContactsController.getSharedContactsList(null, 'CreatedDate', 'DESC', 1, 0);
        Test.stopTest();

        System.assert(result.records.size() <= 1);
    }
}