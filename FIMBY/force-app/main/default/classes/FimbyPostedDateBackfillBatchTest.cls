@isTest
private class FimbyPostedDateBackfillBatchTest {

    @isTest
    static void backfillSetsPostedDateFromCreatedDate() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Id needRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Legacy Need',
            Details__c = 'No posted date yet',
            Status__c = 'Posted',
            RecordTypeId = needRt,
            Contact__c = c.Id,
            Posted_By__c = c.Id,
            Neighbourhood__c = nh.Id
        );
        insert post;
        post = [SELECT CreatedDate, Posted_Date__c FROM Needs_Offers__c WHERE Id = :post.Id];
        post.Posted_Date__c = null;
        update post;

        Test.startTest();
        Database.executeBatch(new FimbyPostedDateBackfillBatch(), 200);
        Test.stopTest();

        post = [SELECT Posted_Date__c, CreatedDate FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertNotEquals(null, post.Posted_Date__c, 'Backfill should set Posted_Date__c');
    }

    @isTest
    static void backfillSetsPostedDateForBulkBuy() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        Id bulkRt = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Bulk_Buy').getRecordTypeId();

        Needs_Offers__c bulkBuy = new Needs_Offers__c(
            Name = 'Legacy Bulk Buy',
            Details__c = 'No posted date yet',
            Status__c = 'Posted',
            RecordTypeId = bulkRt,
            Contact__c = c.Id,
            Posted_By__c = c.Id,
            Neighbourhood__c = nh.Id,
            Total_Quantity__c = 10,
            Per_Response_Limit__c = 1
        );
        insert bulkBuy;
        bulkBuy = [SELECT CreatedDate, Posted_Date__c FROM Needs_Offers__c WHERE Id = :bulkBuy.Id];
        bulkBuy.Posted_Date__c = null;
        update bulkBuy;

        Test.startTest();
        Database.executeBatch(new FimbyPostedDateBackfillBatch(), 200);
        Test.stopTest();

        bulkBuy = [SELECT Posted_Date__c FROM Needs_Offers__c WHERE Id = :bulkBuy.Id];
        System.assertNotEquals(null, bulkBuy.Posted_Date__c, 'Bulk buy backfill should set Posted_Date__c');
    }
}
