@IsTest
public class FimbyDataRetentionBatchTest {

    @TestSetup
    static void setupTestData() {
        FimbyTestDataFactory.createCompleteTestSetup();
    }

    private static Contact getTestContact() {
        User u = [SELECT Id, ContactId FROM User
            WHERE Profile.Name = 'Customer Community User' AND IsActive = true LIMIT 1];
        return [SELECT Id, AccountId, npsp__Primary_Affiliation__c FROM Contact WHERE Id = :u.ContactId];
    }

    private static Id getNeighbourhoodId() {
        return [SELECT Id FROM Account
            WHERE RecordType.DeveloperName = 'Boundary_Account' LIMIT 1].Id;
    }

    @IsTest
    static void testPhaseA_DeletesTerminalPosts() {
        Contact c = getTestContact();
        Id neighbourhoodId = getNeighbourhoodId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Old Post',
            Contact__c = c.Id,
            Posted_By__c = c.Id,
            Status__c = 'Expired',
            Neighbourhood__c = neighbourhoodId,
            RecordTypeId = Schema.SObjectType.Needs_Offers__c
                .getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId()
        );
        insert post;
        Test.setCreatedDate(post.Id, Datetime.now().addMonths(-7));

        Test.startTest();
        Database.executeBatch(new FimbyDataRetentionBatch('A'), 10);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c WHERE Id = :post.Id],
            'Terminal post older than retention period should be deleted');
    }

    @IsTest
    static void testPhaseA_PreservesActivePosts() {
        Contact c = getTestContact();
        Id neighbourhoodId = getNeighbourhoodId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Active Post',
            Contact__c = c.Id,
            Posted_By__c = c.Id,
            Status__c = 'Posted',
            Neighbourhood__c = neighbourhoodId,
            RecordTypeId = Schema.SObjectType.Needs_Offers__c
                .getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId()
        );
        insert post;
        Test.setCreatedDate(post.Id, Datetime.now().addMonths(-7));

        Test.startTest();
        Database.executeBatch(new FimbyDataRetentionBatch('A'), 10);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Needs_Offers__c WHERE Id = :post.Id],
            'Active post should be preserved regardless of age');
    }

    @IsTest
    static void testPhaseB_TrimsDormantConversation() {
        Contact c = getTestContact();

        Conversation__c conv = new Conversation__c(
            Status__c = 'Active',
            Last_Message_Date__c = Datetime.now().addMonths(-7)
        );
        insert conv;

        List<Message__c> messages = new List<Message__c>();
        for (Integer i = 0; i < 5; i++) {
            messages.add(new Message__c(
                Conversation__c = conv.Id,
                Sender__c = c.Id,
                Body__c = 'Message ' + i,
                Status__c = 'Sent'
            ));
        }
        insert messages;

        Test.startTest();
        Database.executeBatch(new FimbyDataRetentionBatch('B'), 10);
        Test.stopTest();

        Integer remaining = [SELECT COUNT() FROM Message__c WHERE Conversation__c = :conv.Id];
        System.assert(remaining <= FimbySettings.conversationTrimKeepCount(),
            'Messages should be trimmed to keep count');
    }

    @IsTest
    static void testPhaseC_DeletesArchivedLibraryItems() {
        Contact c = getTestContact();
        Id neighbourhoodId = getNeighbourhoodId();

        Library_Item__c item = new Library_Item__c(
            Name = 'Old Item',
            Owner_Contact__c = c.Id,
            Listed_By__c = c.Id,
            Status__c = 'Removed from Library',
            Neighbourhood__c = neighbourhoodId
        );
        insert item;
        Test.setCreatedDate(item.Id, Datetime.now().addMonths(-7));

        Test.startTest();
        Database.executeBatch(new FimbyDataRetentionBatch('C'), 10);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Library_Item__c WHERE Id = :item.Id],
            'Archived library item older than retention period should be deleted');
    }

    @IsTest
    static void testDryRun_NoDeletes() {
        Contact c = getTestContact();
        Id neighbourhoodId = getNeighbourhoodId();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Dry Run Post',
            Contact__c = c.Id,
            Posted_By__c = c.Id,
            Status__c = 'Expired',
            Neighbourhood__c = neighbourhoodId,
            RecordTypeId = Schema.SObjectType.Needs_Offers__c
                .getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId()
        );
        insert post;
        Test.setCreatedDate(post.Id, Datetime.now().addMonths(-7));

        Test.startTest();
        Database.executeBatch(new FimbyDataRetentionBatch('A', true), 10);
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Needs_Offers__c WHERE Id = :post.Id],
            'Dry run should not delete any records');
    }

    @IsTest
    static void testScheduler() {
        Test.startTest();
        String jobId = System.schedule('Test Retention', '0 0 2 ? * SUN', new FimbyDataRetentionScheduler());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}
