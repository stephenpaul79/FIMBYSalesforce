@isTest
private class FimbyNeighbourhoodHealthBatchTest {

    @TestSetup
    static void makeData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        neighbourhood.Active__c = 'Yes';
        update neighbourhood;

        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(neighbourhood.Id, 2, true);

        FimbyTestDataFactory.createAskOfferItems(neighbourhood.Id, contacts[0].Id, 1, true);
        FimbyTestDataFactory.createStories(neighbourhood.Id, contacts[1].Id, 1, true);
    }

    @isTest
    static void testBatchExecution() {
        Test.startTest();
        Database.executeBatch(new FimbyNeighbourhoodHealthBatch(), 1);
        Test.stopTest();

        List<Neighbourhood_Health_Snapshot__c> snapshots = [
            SELECT Id, Neighbourhood__c, Snapshot_Date__c, Period_Type__c,
                   Total_Member_Count__c, Posts_Per_Week__c
            FROM Neighbourhood_Health_Snapshot__c
        ];
        System.assertEquals(1, snapshots.size(), 'One snapshot should be created');
        System.assertEquals('Weekly', snapshots[0].Period_Type__c);
        System.assertEquals(Date.today(), snapshots[0].Snapshot_Date__c);
        System.assert(snapshots[0].Total_Member_Count__c >= 2, 'Should count at least 2 members');
    }

    @isTest
    static void testSchedulable() {
        Test.startTest();
        String jobId = System.schedule(
            'Test FIMBY Health', '0 0 3 ? * SUN', new FimbyNeighbourhoodHealthBatch()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be scheduled');
    }

    @isTest
    static void testParseAdjacentIdsNull() {
        Set<Id> result = FimbyNeighbourhoodHealthBatch.parseAdjacentIds(null);
        System.assert(result.isEmpty(), 'Null input should return empty set');
    }

    @isTest
    static void testParseAdjacentIdsBlank() {
        Set<Id> result = FimbyNeighbourhoodHealthBatch.parseAdjacentIds('');
        System.assert(result.isEmpty(), 'Blank input should return empty set');
    }

    @isTest
    static void testParseAdjacentIdsValid() {
        Account a1 = FimbyTestDataFactory.createNeighbourhood(true);
        Account a2 = FimbyTestDataFactory.createNeighbourhood(true);
        String csv = a1.Id + ',' + a2.Id;

        Set<Id> result = FimbyNeighbourhoodHealthBatch.parseAdjacentIds(csv);
        System.assertEquals(2, result.size());
        System.assert(result.contains(a1.Id));
        System.assert(result.contains(a2.Id));
    }

    @isTest
    static void testParseAdjacentIdsWithBlanksAndMalformed() {
        Account a1 = FimbyTestDataFactory.createNeighbourhood(true);
        String csv = a1.Id + ',,badvalue, ';

        Set<Id> result = FimbyNeighbourhoodHealthBatch.parseAdjacentIds(csv);
        System.assertEquals(1, result.size(), 'Only the valid ID should be parsed');
        System.assert(result.contains(a1.Id));
    }

    @isTest
    static void testShouldFlagForSplitReview() {
        FimbyNeighbourhoodHealthBatch batch = new FimbyNeighbourhoodHealthBatch();

        Neighbourhood_Health_Snapshot__c overCap = new Neighbourhood_Health_Snapshot__c(
            Household_Count__c = 200,
            Recognition_Score__c = 50,
            Lurker_Ratio__c = 30
        );
        System.assert(batch.shouldFlagForSplitReview(overCap), 'Should flag when household count exceeds soft cap');

        Neighbourhood_Health_Snapshot__c lowRecognition = new Neighbourhood_Health_Snapshot__c(
            Household_Count__c = 50,
            Recognition_Score__c = 10,
            Lurker_Ratio__c = 30
        );
        System.assert(batch.shouldFlagForSplitReview(lowRecognition), 'Should flag when recognition score is below threshold');

        Neighbourhood_Health_Snapshot__c highLurker = new Neighbourhood_Health_Snapshot__c(
            Household_Count__c = 50,
            Recognition_Score__c = 50,
            Lurker_Ratio__c = 80
        );
        System.assert(batch.shouldFlagForSplitReview(highLurker), 'Should flag when lurker ratio exceeds threshold');

        Neighbourhood_Health_Snapshot__c healthy = new Neighbourhood_Health_Snapshot__c(
            Household_Count__c = 50,
            Recognition_Score__c = 50,
            Lurker_Ratio__c = 30
        );
        System.assert(!batch.shouldFlagForSplitReview(healthy), 'Should not flag a healthy neighbourhood');
    }
}
