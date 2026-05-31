@isTest
private class FimbyNeighbourhoodServiceTest {

    @TestSetup
    static void makeData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        neighbourhood.Active__c = 'Yes';
        update neighbourhood;

        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(neighbourhood.Id, 4, false);
        contacts[0].MailingPostalCode = 'V6A 1A1';
        contacts[1].MailingPostalCode = 'V6A 1A1';
        contacts[2].MailingPostalCode = 'V6B 2B2';
        contacts[3].MailingPostalCode = 'V6B 2B2';
        insert contacts;

        List<Needs_Offers__c> posts = FimbyTestDataFactory.createAskOfferItems(
            neighbourhood.Id, contacts[0].Id, 2, true
        );

        insert new Response__c(
            Contact__c = contacts[2].Id,
            Need_Offer_Responded_To__c = posts[0].Id,
            Neighbourhood__c = neighbourhood.Id,
            Response__c = 'Test response'
        );

        FimbyTestDataFactory.createStories(neighbourhood.Id, contacts[1].Id, 1, true);

        insert new Shared_Contact_Info__c(
            Contact__c = contacts[0].Id,
            Shared_To__c = contacts[2].Id,
            Status__c = 'Active'
        );
    }

    @isTest
    static void testPreviewViability() {
        Account neighbourhood = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' LIMIT 1];

        Test.startTest();
        FimbyNeighbourhoodService.ViabilityResult result =
            FimbyNeighbourhoodService.previewViability(neighbourhood.Id, new List<String>{ 'V6A 1A1' });
        Test.stopTest();

        System.assertEquals(neighbourhood.Id, result.sourceAccountId);
        System.assertEquals(2, result.newCellHouseholds, 'Two contacts share postal code V6A 1A1');
        System.assertEquals(2, result.remainCellHouseholds, 'Two contacts remain in V6B 2B2');
        System.assertNotEquals(null, result.newCellPostsPerWeek);
        System.assertNotEquals(null, result.remainCellPostsPerWeek);
        System.assertNotEquals(null, result.newCellInternalTieRatio);
        System.assertNotEquals(null, result.remainCellInternalTieRatio);
        System.assert(result.crossCellSharedContacts >= 1, 'At least one cross-cell SCI exists');
    }

    @isTest
    static void testPreviewViabilityEmptyPostalCodes() {
        Account neighbourhood = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' LIMIT 1];

        Test.startTest();
        FimbyNeighbourhoodService.ViabilityResult result =
            FimbyNeighbourhoodService.previewViability(neighbourhood.Id, new List<String>{ 'Z9Z 9Z9' });
        Test.stopTest();

        System.assertEquals(0, result.newCellHouseholds, 'No contacts match bogus postal code');
        System.assertEquals(4, result.remainCellHouseholds);
    }

    @isTest
    static void testClearCache() {
        Test.startTest();
        FimbyNeighbourhoodService.clearCache();
        Test.stopTest();
    }
}
