@isTest
private class FimbySCINeighbourhoodBackfillBatchTest {

    @TestSetup
    static void makeData() {
        List<Account> neighbourhoods = FimbyTestDataFactory.createNeighbourhoods(2, true);

        Contact c1 = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhoods[0].Id, true);
        Contact c2 = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhoods[1].Id, true);

        insert new Shared_Contact_Info__c(
            Contact__c = c1.Id,
            Shared_To__c = c2.Id,
            Status__c = 'Active'
            // Deliberately omitting neighbourhood fields to test backfill
        );
    }

    @isTest
    static void testBackfillBatch() {
        List<Account> neighbourhoods = [
            SELECT Id FROM Account
            WHERE RecordType.DeveloperName = 'Boundary_Account'
            ORDER BY CreatedDate ASC
        ];
        Id neighbourhood1Id = neighbourhoods[0].Id;
        Id neighbourhood2Id = neighbourhoods[1].Id;

        // Verify neighbourhood fields are null before batch
        Shared_Contact_Info__c sciBefore = [
            SELECT Contact_Neighbourhood__c, Shared_To_Neighbourhood__c
            FROM Shared_Contact_Info__c LIMIT 1
        ];
        System.assertEquals(null, sciBefore.Contact_Neighbourhood__c, 'Should be null before backfill');
        System.assertEquals(null, sciBefore.Shared_To_Neighbourhood__c, 'Should be null before backfill');

        Test.startTest();
        Database.executeBatch(new FimbySCINeighbourhoodBackfillBatch(), 200);
        Test.stopTest();

        Shared_Contact_Info__c sciAfter = [
            SELECT Contact_Neighbourhood__c, Shared_To_Neighbourhood__c
            FROM Shared_Contact_Info__c LIMIT 1
        ];
        System.assertEquals(neighbourhood1Id, sciAfter.Contact_Neighbourhood__c,
            'Contact neighbourhood should be backfilled from Contact AccountId');
        System.assertEquals(neighbourhood2Id, sciAfter.Shared_To_Neighbourhood__c,
            'Shared To neighbourhood should be backfilled from Shared To Contact AccountId');
    }

    @isTest
    static void testIdempotent() {
        List<Account> neighbourhoods = [
            SELECT Id FROM Account
            WHERE RecordType.DeveloperName = 'Boundary_Account'
            ORDER BY CreatedDate ASC
        ];

        // Pre-populate neighbourhood fields
        Shared_Contact_Info__c sci = [SELECT Id FROM Shared_Contact_Info__c LIMIT 1];
        sci.Contact_Neighbourhood__c = neighbourhoods[0].Id;
        sci.Shared_To_Neighbourhood__c = neighbourhoods[1].Id;
        update sci;

        Test.startTest();
        Database.executeBatch(new FimbySCINeighbourhoodBackfillBatch(), 200);
        Test.stopTest();

        // The batch WHERE clause filters out records where both fields are non-null,
        // so the record should not have been touched
        Shared_Contact_Info__c sciAfter = [
            SELECT Contact_Neighbourhood__c, Shared_To_Neighbourhood__c
            FROM Shared_Contact_Info__c LIMIT 1
        ];
        System.assertEquals(neighbourhoods[0].Id, sciAfter.Contact_Neighbourhood__c,
            'Contact neighbourhood should remain unchanged');
        System.assertEquals(neighbourhoods[1].Id, sciAfter.Shared_To_Neighbourhood__c,
            'Shared To neighbourhood should remain unchanged');
    }
}
