@IsTest
public class FimbySearchControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User communityUser = FimbyTestDataFactory.createCommunityUser(contact.Id, 'Customer Community User - Mobile App', true);

        List<Story__c> stories = FimbyTestDataFactory.createStories(neighbourhood.Id, contact.Id, 3, true);
        List<Needs_Offers__c> askOfferItems = FimbyTestDataFactory.createAskOfferItems(neighbourhood.Id, contact.Id, 3, true);
        List<Library_Item__c> libraryItems = FimbyTestDataFactory.createLibraryItems(neighbourhood.Id, contact.Id, 2, true);

        // Create a second contact to be a shared contact
        Contact secondContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        // Create Shared_Contact_Info__c record between the two contacts
        Shared_Contact_Info__c sharedInfo = new Shared_Contact_Info__c(
            Contact__c = secondContact.Id,
            Shared_To__c = contact.Id
        );
        insert sharedInfo;
    }

    @IsTest
    static void testSearchAllFilter() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            // SOSL requires setting fixed search results in tests
            List<Id> fixedSearchResults = new List<Id>();
            for (Story__c s : [SELECT Id FROM Story__c]) { fixedSearchResults.add(s.Id); }
            for (Needs_Offers__c no : [SELECT Id FROM Needs_Offers__c]) { fixedSearchResults.add(no.Id); }
            for (Library_Item__c li : [SELECT Id FROM Library_Item__c]) { fixedSearchResults.add(li.Id); }
            for (Contact c : [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id]) { fixedSearchResults.add(c.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'all', 'relevance', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertNotEquals(null, result.items, 'Items should not be null');
            System.assert(result.items.size() > 0, 'Should return at least one result');
            System.assertNotEquals(null, result.countsByType, 'Counts by type should not be null');
            System.assert(result.countsByType.get('stories') >= 0, 'Stories count should exist');
            System.assert(result.countsByType.get('askOffer') >= 0, 'AskOffer count should exist');
            System.assert(result.countsByType.get('library') >= 0, 'Library count should exist');
            System.assert(result.countsByType.get('people') >= 0, 'People count should exist');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchStoriesFilter() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Story__c s : [SELECT Id FROM Story__c]) { fixedSearchResults.add(s.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'stories', 'newest', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertEquals('story', item.resultType, 'All results should be stories');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchAskOfferFilter() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Needs_Offers__c no : [SELECT Id FROM Needs_Offers__c]) { fixedSearchResults.add(no.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'askOffer', 'relevance', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertEquals('askOffer', item.resultType, 'All results should be askOffer');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchLibraryFilter() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Library_Item__c li : [SELECT Id FROM Library_Item__c]) { fixedSearchResults.add(li.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'library', 'relevance', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertEquals('library', item.resultType, 'All results should be library');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchPeopleFilter() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Contact c : [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id]) {
                fixedSearchResults.add(c.Id);
            }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'people', 'relevance', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertEquals('people', item.resultType, 'All results should be people');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchSharedContactFlag() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Contact c : [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id]) {
                fixedSearchResults.add(c.Id);
            }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'people', 'relevance', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            // Verify that people results carry the hasSharedContact flag (boolean, not null)
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertNotEquals(null, item.hasSharedContact,
                    'People results must have hasSharedContact flag set');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchEmptyTerm() {
        Test.startTest();
        FimbySearchController.SearchResult result = FimbySearchController.search(
            '', 'all', 'relevance', 20, 0
        );

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.totalCount, 'Empty search should return 0 results');
        System.assertEquals(false, result.hasMore, 'Empty search should have no more results');
        Test.stopTest();
    }

    @IsTest
    static void testSearchShortTerm() {
        Test.startTest();
        FimbySearchController.SearchResult result = FimbySearchController.search(
            'a', 'all', 'relevance', 20, 0
        );

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.totalCount, 'Short search term should return 0 results');
        Test.stopTest();
    }

    @IsTest
    static void testSearchNullTerm() {
        Test.startTest();
        FimbySearchController.SearchResult result = FimbySearchController.search(
            null, 'all', 'relevance', 20, 0
        );

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.totalCount, 'Null search should return 0 results');
        Test.stopTest();
    }

    @IsTest
    static void testSearchSortNewest() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Story__c s : [SELECT Id FROM Story__c]) { fixedSearchResults.add(s.Id); }
            for (Needs_Offers__c no : [SELECT Id FROM Needs_Offers__c]) { fixedSearchResults.add(no.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'all', 'newest', 50, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            // Verify newest-first ordering for items with dates
            List<FimbySearchController.SearchResultItem> items = result.items;
            for (Integer i = 0; i < items.size() - 1; i++) {
                if (items[i].createdDate != null && items[i + 1].createdDate != null) {
                    System.assert(items[i].createdDate >= items[i + 1].createdDate,
                        'Items should be sorted newest first');
                }
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchSortOldest() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Story__c s : [SELECT Id FROM Story__c]) { fixedSearchResults.add(s.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'stories', 'oldest', 50, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            List<FimbySearchController.SearchResultItem> items = result.items;
            for (Integer i = 0; i < items.size() - 1; i++) {
                if (items[i].createdDate != null && items[i + 1].createdDate != null) {
                    System.assert(items[i].createdDate <= items[i + 1].createdDate,
                        'Items should be sorted oldest first');
                }
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchPagination() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Story__c s : [SELECT Id FROM Story__c]) { fixedSearchResults.add(s.Id); }
            for (Needs_Offers__c no : [SELECT Id FROM Needs_Offers__c]) { fixedSearchResults.add(no.Id); }
            for (Library_Item__c li : [SELECT Id FROM Library_Item__c]) { fixedSearchResults.add(li.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            // First page: small page size
            FimbySearchController.SearchResult firstPage = FimbySearchController.search(
                'Test', 'all', 'relevance', 2, 0
            );

            System.assertNotEquals(null, firstPage, 'First page should not be null');
            System.assert(firstPage.items.size() <= 2, 'First page should respect pageSize');

            if (firstPage.hasMore) {
                FimbySearchController.SearchResult secondPage = FimbySearchController.search(
                    'Test', 'all', 'relevance', 2, 2
                );

                System.assertNotEquals(null, secondPage, 'Second page should not be null');
                System.assert(secondPage.items.size() > 0, 'Second page should have items');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchDefaultParameters() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            Test.setFixedSearchResults(new List<Id>());

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', null, null, null, null
            );

            System.assertNotEquals(null, result, 'Result should not be null with null parameters');
        }
        Test.stopTest();
    }
}