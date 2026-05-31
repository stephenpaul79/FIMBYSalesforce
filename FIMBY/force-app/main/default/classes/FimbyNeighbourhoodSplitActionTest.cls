@isTest
private class FimbyNeighbourhoodSplitActionTest {

    @TestSetup
    static void makeData() {
        Account source = FimbyTestDataFactory.createNeighbourhood(true);
        source.Active__c = 'Yes';
        update source;

        Account target = FimbyTestDataFactory.createNeighbourhood(true);
        target.Active__c = 'Yes';
        update target;

        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(source.Id, 4, false);
        contacts[0].MailingPostalCode = 'V6A 1A1';
        contacts[1].MailingPostalCode = 'V6A 1A1';
        contacts[2].MailingPostalCode = 'V6B 2B2';
        contacts[3].MailingPostalCode = 'V6B 2B2';
        insert contacts;

        Postal_Codes__c pc = new Postal_Codes__c(
            Name = 'V6A 1A1',
            Boundary_Account__c = source.Id
        );
        insert pc;

        FimbyTestDataFactory.createAskOfferItems(source.Id, contacts[0].Id, 2, true);
        FimbyTestDataFactory.createStories(source.Id, contacts[0].Id, 1, true);
        FimbyTestDataFactory.createLibraryItems(source.Id, contacts[0].Id, 1, true);

        insert new Shared_Contact_Info__c(
            Contact__c = contacts[0].Id,
            Shared_To__c = contacts[2].Id,
            Contact_Neighbourhood__c = source.Id,
            Shared_To_Neighbourhood__c = source.Id,
            Status__c = 'Active'
        );

        Neighbourhood_Split__c split = new Neighbourhood_Split__c(
            Source_Neighbourhood__c = source.Id,
            New_Neighbourhood__c = target.Id,
            Status__c = 'In Progress',
            Current_Step__c = 3
        );
        insert split;
    }

    @isTest
    static void testFullSplitExecution() {
        Account source = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' ORDER BY CreatedDate ASC LIMIT 1];
        Account target = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' AND Id != :source.Id LIMIT 1];
        Neighbourhood_Split__c split = [SELECT Id FROM Neighbourhood_Split__c LIMIT 1];
        Postal_Codes__c pc = [SELECT Id FROM Postal_Codes__c WHERE Name = 'V6A 1A1' LIMIT 1];

        FimbyNeighbourhoodSplitAction.SplitInput input = new FimbyNeighbourhoodSplitAction.SplitInput();
        input.sourceAccountId = source.Id;
        input.newAccountId = target.Id;
        input.splitRecordId = split.Id;
        input.movedPostalCodeIds = new List<Id>{ pc.Id };
        input.sendNotification = false;

        Test.startTest();
        FimbyNeighbourhoodSplitAction.execute(new List<FimbyNeighbourhoodSplitAction.SplitInput>{ input });
        Test.stopTest();

        List<Contact> movedContacts = [SELECT Id FROM Contact WHERE AccountId = :target.Id];
        System.assertEquals(2, movedContacts.size(), 'Two contacts with V6A 1A1 should move');

        List<Contact> remainingContacts = [SELECT Id FROM Contact WHERE AccountId = :source.Id];
        System.assertEquals(2, remainingContacts.size(), 'Two contacts with V6B 2B2 should remain');

        Neighbourhood_Split__c updatedSplit = [SELECT Status__c, Completed_At__c FROM Neighbourhood_Split__c WHERE Id = :split.Id];
        System.assertEquals('Completed', updatedSplit.Status__c);
        System.assertNotEquals(null, updatedSplit.Completed_At__c);

        Integer restampedNO = [SELECT COUNT() FROM Needs_Offers__c WHERE Neighbourhood__c = :target.Id];
        System.assert(restampedNO > 0, 'Needs/Offers should be restamped to new neighbourhood');
    }

    @isTest
    static void testSplitWithNotification() {
        Account source = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' ORDER BY CreatedDate ASC LIMIT 1];
        Account target = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' AND Id != :source.Id LIMIT 1];
        Neighbourhood_Split__c split = [SELECT Id FROM Neighbourhood_Split__c LIMIT 1];
        Postal_Codes__c pc = [SELECT Id FROM Postal_Codes__c WHERE Name = 'V6A 1A1' LIMIT 1];

        FimbyNeighbourhoodSplitAction.SplitInput input = new FimbyNeighbourhoodSplitAction.SplitInput();
        input.sourceAccountId = source.Id;
        input.newAccountId = target.Id;
        input.splitRecordId = split.Id;
        input.movedPostalCodeIds = new List<Id>{ pc.Id };
        input.sendNotification = true;

        Test.startTest();
        FimbyNeighbourhoodSplitAction.execute(new List<FimbyNeighbourhoodSplitAction.SplitInput>{ input });
        Test.stopTest();

        List<Notification__c> notifications = [
            SELECT Contact__c, Title__c, Type__c
            FROM Notification__c
            WHERE Type__c = 'System'
        ];
        System.assertEquals(2, notifications.size(), 'Each moved contact should receive a notification');
    }

    @isTest
    static void testSplitQueueable() {
        Account source = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' ORDER BY CreatedDate ASC LIMIT 1];
        Neighbourhood_Split__c split = [SELECT Id FROM Neighbourhood_Split__c LIMIT 1];

        Story__c story = [SELECT Id FROM Story__c WHERE Neighbourhood__c = :source.Id LIMIT 1];
        List<SObject> records = new List<SObject>{
            new Story__c(Id = story.Id, Neighbourhood__c = source.Id)
        };

        Test.startTest();
        System.enqueueJob(new FimbyNeighbourhoodSplitQueueable(records, split.Id));
        Test.stopTest();

        Neighbourhood_Split__c updatedSplit = [SELECT Records_Restamped__c FROM Neighbourhood_Split__c WHERE Id = :split.Id];
        System.assert(updatedSplit.Records_Restamped__c >= 1, 'Should track restamped count');
    }

    @isTest
    static void testSplitQueueableEmpty() {
        Neighbourhood_Split__c split = [SELECT Id FROM Neighbourhood_Split__c LIMIT 1];

        Test.startTest();
        System.enqueueJob(new FimbyNeighbourhoodSplitQueueable(new List<SObject>(), split.Id));
        Test.stopTest();
    }

    @isTest
    static void testSplitQueueableWithFailures() {
        Account source = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' ORDER BY CreatedDate ASC LIMIT 1];
        Neighbourhood_Split__c split = [SELECT Id FROM Neighbourhood_Split__c LIMIT 1];

        Story__c story = [SELECT Id FROM Story__c WHERE Neighbourhood__c = :source.Id LIMIT 1];
        Id storyId = story.Id;
        delete story;

        List<SObject> records = new List<SObject>{
            new Story__c(Id = storyId, Neighbourhood__c = source.Id)
        };

        Test.startTest();
        System.enqueueJob(new FimbyNeighbourhoodSplitQueueable(records, split.Id));
        Test.stopTest();
    }

    @isTest
    static void testSplitQueueableNull() {
        Neighbourhood_Split__c split = [SELECT Id FROM Neighbourhood_Split__c LIMIT 1];

        Test.startTest();
        System.enqueueJob(new FimbyNeighbourhoodSplitQueueable(null, split.Id));
        Test.stopTest();
    }

    @isTest
    static void testTruncateHelper() {
        System.assertEquals(null, FimbyNeighbourhoodSplitQueueable.truncate(null, 10));
        System.assertEquals('', FimbyNeighbourhoodSplitQueueable.truncate('', 10));
        System.assertEquals('hello', FimbyNeighbourhoodSplitQueueable.truncate('hello', 10));
        System.assertEquals('hel', FimbyNeighbourhoodSplitQueueable.truncate('hello', 3));
    }

    @isTest
    static void testMarkSplitFailed() {
        Neighbourhood_Split__c split = [SELECT Id, Status__c FROM Neighbourhood_Split__c LIMIT 1];

        Test.startTest();
        FimbyNeighbourhoodSplitQueueable.markSplitFailed(split.Id, 'Test error message that is very long and should be truncated');
        Test.stopTest();

        Neighbourhood_Split__c updated = [SELECT Status__c, Error_Detail__c FROM Neighbourhood_Split__c WHERE Id = :split.Id];
        System.assertEquals('Failed', updated.Status__c);
        System.assertNotEquals(null, updated.Error_Detail__c);
    }

    @isTest
    static void testResumeFromStep() {
        Account source = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' ORDER BY CreatedDate ASC LIMIT 1];
        Account target = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' AND Id != :source.Id LIMIT 1];
        Neighbourhood_Split__c split = [SELECT Id FROM Neighbourhood_Split__c LIMIT 1];
        Postal_Codes__c pc = [SELECT Id FROM Postal_Codes__c WHERE Name = 'V6A 1A1' LIMIT 1];

        FimbyNeighbourhoodSplitAction.SplitInput input = new FimbyNeighbourhoodSplitAction.SplitInput();
        input.sourceAccountId = source.Id;
        input.newAccountId = target.Id;
        input.splitRecordId = split.Id;
        input.movedPostalCodeIds = new List<Id>{ pc.Id };
        input.sendNotification = false;
        input.resumeFromStep = 6;

        Test.startTest();
        FimbyNeighbourhoodSplitAction.execute(new List<FimbyNeighbourhoodSplitAction.SplitInput>{ input });
        Test.stopTest();

        Neighbourhood_Split__c updatedSplit = [SELECT Status__c FROM Neighbourhood_Split__c WHERE Id = :split.Id];
        System.assertEquals('Completed', updatedSplit.Status__c, 'Split should complete when resuming from step 6');
    }
}
