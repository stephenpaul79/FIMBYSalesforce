@isTest
private class FimbyTestDataCleanupTest {

    private static final String RUN_ID = 'abc12345';
    private static final String PREFIX = '[E2E] ' + RUN_ID;

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact poster = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        List<Library_Item__c> libraryItems = FimbyTestDataFactory.createLibraryItems(neighbourhood.Id, poster.Id, 2, false);
        libraryItems[0].Name = PREFIX + ' library item';
        libraryItems[1].Name = 'Real Library Item';
        insert libraryItems;

        List<Needs_Offers__c> needs = FimbyTestDataFactory.createAskOfferItems(neighbourhood.Id, poster.Id, 2, false);
        needs[0].Name = PREFIX + ' need';
        needs[1].Name = 'Real neighbour ask';
        insert needs;

        List<Story__c> stories = FimbyTestDataFactory.createStories(neighbourhood.Id, poster.Id, 1, false);
        stories[0].Name = PREFIX + ' story';
        insert stories;
    }

    @isTest
    static void cleanupRun_rejectsShortRunId() {
        Boolean threw = false;
        try {
            FimbyTestDataCleanup.cleanupRun('abc');
        } catch (FimbyTestDataCleanup.CleanupException e) {
            threw = true;
        }
        System.assert(threw, 'Expected CleanupException for short runId');
    }

    @isTest
    static void cleanupRun_rejectsBlankRunId() {
        Boolean threw = false;
        try {
            FimbyTestDataCleanup.cleanupRun('');
        } catch (FimbyTestDataCleanup.CleanupException e) {
            threw = true;
        }
        System.assert(threw, 'Expected CleanupException for blank runId');
    }

    @isTest
    static void cleanupPrefix_rejectsBlank() {
        Boolean threw = false;
        try {
            FimbyTestDataCleanup.cleanupPrefix('');
        } catch (FimbyTestDataCleanup.CleanupException e) {
            threw = true;
        }
        System.assert(threw, 'Expected CleanupException for blank prefix');
    }

    @isTest
    static void cleanupPrefix_rejectsShort() {
        Boolean threw = false;
        try {
            FimbyTestDataCleanup.cleanupPrefix('[E]');
        } catch (FimbyTestDataCleanup.CleanupException e) {
            threw = true;
        }
        System.assert(threw, 'Expected CleanupException for short prefix');
    }

    @isTest
    static void cleanupPrefix_requiresE2EAnchor() {
        Boolean threw = false;
        try {
            FimbyTestDataCleanup.cleanupPrefix('TESTING ');
        } catch (FimbyTestDataCleanup.CleanupException e) {
            threw = true;
        }
        System.assert(threw, 'Expected CleanupException when [E2E] anchor missing');
    }

    @isTest
    static void cleanupRun_deletesAnchoredOnly() {
        Test.startTest();
        FimbyTestDataCleanup.CleanupResult result = FimbyTestDataCleanup.cleanupRun(RUN_ID);
        Test.stopTest();

        System.assert(result.recordsDeleted >= 3, 'Expected at least 3 records deleted, got ' + result.recordsDeleted);
        System.assertEquals(false, result.dryRun);
        System.assertEquals(0, [SELECT COUNT() FROM Library_Item__c WHERE Name LIKE :PREFIX + '%']);
        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c WHERE Name LIKE :PREFIX + '%']);
        System.assertEquals(0, [SELECT COUNT() FROM Story__c WHERE Name LIKE :PREFIX + '%']);
        System.assertEquals(1, [SELECT COUNT() FROM Library_Item__c WHERE Name = 'Real Library Item']);
        System.assertEquals(1, [SELECT COUNT() FROM Needs_Offers__c WHERE Name = 'Real neighbour ask']);
    }

    @isTest
    static void dryRun_countsButDoesNotDelete() {
        Test.startTest();
        FimbyTestDataCleanup.CleanupResult result = FimbyTestDataCleanup.dryRun(PREFIX);
        Test.stopTest();

        System.assertEquals(true, result.dryRun);
        System.assert(result.recordsDeleted >= 3, 'Expected dryRun to count >=3 records, got ' + result.recordsDeleted);
        System.assertEquals(1, [SELECT COUNT() FROM Library_Item__c WHERE Name LIKE :PREFIX + '%']);
        System.assertEquals(1, [SELECT COUNT() FROM Needs_Offers__c WHERE Name LIKE :PREFIX + '%']);
        System.assertEquals(1, [SELECT COUNT() FROM Story__c WHERE Name LIKE :PREFIX + '%']);
    }

    @isTest
    static void cleanupPrefix_handlesEmptyOrg() {
        delete [SELECT Id FROM Library_Item__c WHERE Name LIKE :PREFIX + '%'];
        delete [SELECT Id FROM Needs_Offers__c WHERE Name LIKE :PREFIX + '%'];
        delete [SELECT Id FROM Story__c WHERE Name LIKE :PREFIX + '%'];

        Test.startTest();
        FimbyTestDataCleanup.CleanupResult result = FimbyTestDataCleanup.cleanupPrefix('[E2E] zzzz9999');
        Test.stopTest();

        System.assertEquals(0, result.recordsDeleted, 'No matching records means no deletes');
        System.assertEquals(0, result.warnings.size(), 'No warnings expected on a no-op sweep');
    }
}
