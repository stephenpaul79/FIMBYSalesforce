@IsTest
private class FimbyLiveTourStatusBackfillBatchTest {

    @IsTest
    static void backfillSetsNotStartedWhenBlank() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        c.Live_Tour_Status__c = null;
        update c;

        Test.startTest();
        Database.executeBatch(new FimbyLiveTourStatusBackfillBatch(), 200);
        Test.stopTest();

        Contact updated = [
            SELECT Live_Tour_Status__c
            FROM Contact
            WHERE Id = :c.Id
        ];
        System.assertEquals(
            FimbyConstants.ONBOARDING_NOT_STARTED,
            updated.Live_Tour_Status__c,
            'Blank tour status should backfill to Not Started'
        );
    }

    @IsTest
    static void backfillSkipsOrganizationContacts() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact orgContact = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        orgContact.Is_Organization_Contact__c = true;
        orgContact.Live_Tour_Status__c = null;
        update orgContact;

        Test.startTest();
        Database.executeBatch(new FimbyLiveTourStatusBackfillBatch(), 200);
        Test.stopTest();

        Contact updated = [
            SELECT Live_Tour_Status__c
            FROM Contact
            WHERE Id = :orgContact.Id
        ];
        System.assertEquals(null, updated.Live_Tour_Status__c,
            'Organization contacts are excluded from tour status backfill');
    }
}
