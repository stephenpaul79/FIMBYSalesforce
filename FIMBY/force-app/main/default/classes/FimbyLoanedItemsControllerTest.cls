@isTest
private class FimbyLoanedItemsControllerTest {

    @testSetup
    static void setupTestData() {
        Account testNeighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, true);
        List<Library_Item__c> libraryItems = FimbyTestDataFactory.createLibraryItems(testNeighbourhood.Id, testContact.Id, 2, true);
        
        // Create loaned items - Status__c is a formula field, so we don't set it
        List<Loaned_Item__c> loanedItems = new List<Loaned_Item__c>();
        for (Library_Item__c item : libraryItems) {
            Loaned_Item__c loan = new Loaned_Item__c(
                Name = 'Loan - ' + item.Name,
                Library_Item__c = item.Id,
                Loaned_To__c = testContact.Id,
                Loan_Due_Date__c = Date.today().addDays(14)
            );
            loanedItems.add(loan);
        }
        insert loanedItems;
    }

    @isTest
    static void testGetLoanedItemsList_NoFilter() {
        Test.startTest();
        FimbyLoanedItemsController.LoanedItemListResult result = 
            FimbyLoanedItemsController.getLoanedItemsList(null, null, 'Name', 'ASC', 10, 0);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.records.size() > 0);
    }

    @isTest
    static void testGetLoanedItemsList_WithSearch() {
        Test.startTest();
        FimbyLoanedItemsController.LoanedItemListResult result = 
            FimbyLoanedItemsController.getLoanedItemsList(null, 'Loan', 'Name', 'ASC', 10, 0);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGetLoanedItemsList_Pagination() {
        Test.startTest();
        FimbyLoanedItemsController.LoanedItemListResult result = 
            FimbyLoanedItemsController.getLoanedItemsList(null, null, 'Name', 'ASC', 1, 0);
        Test.stopTest();

        System.assert(result.records.size() <= 1);
    }

    @isTest
    static void testGetLoanedItemsList_Sorting() {
        Test.startTest();
        FimbyLoanedItemsController.LoanedItemListResult result = 
            FimbyLoanedItemsController.getLoanedItemsList(null, null, 'Loan_Due_Date__c', 'DESC', 10, 0);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }
}