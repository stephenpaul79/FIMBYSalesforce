/**
 * Test class for FimbyContactsController
 */
@isTest
private class FimbyContactsControllerTest {

    @testSetup
    static void setupTestData() {
        // Create a test account for neighbourhood
        Account testAccount = new Account(Name = 'Test Strathcona Neighbourhood');
        insert testAccount;

        // Create contacts
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            Contact c = new Contact(
                FirstName = 'Test',
                LastName = 'Contact' + i,
                Email = 'test' + i + '@example.com',
                AccountId = testAccount.Id
            );
            contacts.add(c);
        }
        insert contacts;
    }

    @isTest
    static void testGetContactsList_NoFilter() {
        Test.startTest();
        FimbyContactsController.ContactListResult result =
            FimbyContactsController.getContactsList(null, null, 'Name', 'ASC', 10, 0);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.records.size() > 0, 'Should return contacts');
        System.assert(result.totalCount > 0, 'Total count should be greater than 0');
    }

    @isTest
    static void testGetContactsList_WithSearch() {
        Test.startTest();
        FimbyContactsController.ContactListResult result =
            FimbyContactsController.getContactsList(null, 'Contact0', 'Name', 'ASC', 10, 0);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        // Search should filter results
        for (Contact c : result.records) {
            System.assert(c.Name.contains('Contact0') || (c.Email != null && c.Email.contains('Contact0')),
                'Results should match search term');
        }
    }

    @isTest
    static void testGetContactsList_WithSorting() {
        Test.startTest();
        FimbyContactsController.ContactListResult resultAsc =
            FimbyContactsController.getContactsList(null, null, 'Name', 'ASC', 10, 0);
        FimbyContactsController.ContactListResult resultDesc =
            FimbyContactsController.getContactsList(null, null, 'Name', 'DESC', 10, 0);
        Test.stopTest();

        System.assert(resultAsc.records.size() > 0, 'Should have results for ASC sort');
        System.assert(resultDesc.records.size() > 0, 'Should have results for DESC sort');
    }

    @isTest
    static void testGetContactsList_WithPagination() {
        Test.startTest();
        FimbyContactsController.ContactListResult page1 =
            FimbyContactsController.getContactsList(null, null, 'Name', 'ASC', 2, 0);
        FimbyContactsController.ContactListResult page2 =
            FimbyContactsController.getContactsList(null, null, 'Name', 'ASC', 2, 2);
        Test.stopTest();

        System.assert(page1.records.size() <= 2, 'Page 1 should have max 2 records');

        if (page1.totalCount > 2) {
            System.assert(page2.records.size() > 0, 'Page 2 should have records if total > 2');
        }
    }

    @isTest
    static void testGetContactsList_WithFilter() {
        Test.startTest();
        // Test with Strathcona filter - should find our test account
        FimbyContactsController.ContactListResult result =
            FimbyContactsController.getContactsList('All Strathcona / DTES Contacts', null, 'Name', 'ASC', 10, 0);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.records.size() > 0, 'Should return contacts for Strathcona filter');
    }

    @isTest
    static void testGetContactsList_InvalidSortField() {
        Test.startTest();
        // Should handle invalid sort field gracefully by defaulting to Name
        FimbyContactsController.ContactListResult result =
            FimbyContactsController.getContactsList(null, null, 'InvalidField__c', 'ASC', 10, 0);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null even with invalid sort field');
    }

    @isTest
    static void testGetContactsList_AccountNameSort() {
        Test.startTest();
        FimbyContactsController.ContactListResult result =
            FimbyContactsController.getContactsList(null, null, 'AccountName', 'ASC', 10, 0);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }
}