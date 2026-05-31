@isTest
private class FimbyAdjacentIdRepairBatchTest {

    @TestSetup
    static void makeData() {
        List<Account> neighbourhoods = FimbyTestDataFactory.createNeighbourhoods(2, true);

        insert new Neighbourhood_Adjacency__c(
            Core_Neighbourhood__c = neighbourhoods[0].Id,
            Adjacent_Neighbour__c = neighbourhoods[1].Id,
            Adjacency_Type__c = 'Geographic_Neighbour',
            Active__c = true
        );
    }

    @isTest
    static void testRepairBatch() {
        List<Account> neighbourhoods = [
            SELECT Id, Name FROM Account
            WHERE RecordType.DeveloperName = 'Boundary_Account'
            ORDER BY CreatedDate ASC
        ];
        Account acct1 = neighbourhoods[0];
        Account acct2 = neighbourhoods[1];

        Test.startTest();
        Database.executeBatch(new FimbyAdjacentIdRepairBatch(), 50);
        Test.stopTest();

        Account updated = [
            SELECT Adjacent_Neighbourhood_Ids__c, Adjacent_Neighbourhood_Links__c
            FROM Account WHERE Id = :acct1.Id
        ];
        System.assert(
            updated.Adjacent_Neighbourhood_Ids__c != null
                && updated.Adjacent_Neighbourhood_Ids__c.contains(String.valueOf(acct2.Id)),
            'Adjacent IDs should contain the second neighbourhood ID'
        );
        System.assert(
            updated.Adjacent_Neighbourhood_Links__c != null
                && updated.Adjacent_Neighbourhood_Links__c.contains(acct2.Name),
            'Adjacent links should contain the second neighbourhood name'
        );
    }

    @isTest
    static void testRepairBatchNoAdjacencies() {
        // Remove the adjacency created in setup
        delete [SELECT Id FROM Neighbourhood_Adjacency__c];

        Test.startTest();
        Database.executeBatch(new FimbyAdjacentIdRepairBatch(), 50);
        Test.stopTest();

        for (Account a : [
            SELECT Adjacent_Neighbourhood_Ids__c, Adjacent_Neighbourhood_Links__c
            FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account'
        ]) {
            System.assert(
                a.Adjacent_Neighbourhood_Ids__c == null || a.Adjacent_Neighbourhood_Ids__c == '',
                'Should be null or empty when no adjacencies exist');
            System.assert(
                a.Adjacent_Neighbourhood_Links__c == null || a.Adjacent_Neighbourhood_Links__c == '',
                'Should be null or empty when no adjacencies exist');
        }
    }

    @isTest
    static void testInvocableMethod() {
        Test.startTest();
        FimbyAdjacentIdRepairBatch.run(new List<String>{ 'unused' });
        Test.stopTest();

        // Confirm no unhandled exceptions — batch was enqueued
        List<AsyncApexJob> jobs = [
            SELECT Id FROM AsyncApexJob
            WHERE ApexClass.Name = 'FimbyAdjacentIdRepairBatch'
            AND JobType = 'BatchApex'
        ];
        System.assert(!jobs.isEmpty(), 'Batch job should be enqueued via invocable');
    }
}
