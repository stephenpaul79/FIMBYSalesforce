/**
 * @description Tests for FimbyGraceExpiryBatch. Covers:
 *   - Contact still inside grace window is NOT flagged
 *   - Contact past grace window IS flagged (default 30 days)
 *   - Per-contact Grace_Window_Days__c override wins over org default
 *   - Already-flagged Contacts are skipped (idempotency)
 */
@IsTest
private class FimbyGraceExpiryBatchTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        FimbyTestDataFactory.createNeighbourhoodContacts(neighbourhood.Id, 4, true);
    }

    @IsTest
    static void contactInsideGraceIsNotFlagged() {
        List<Contact> contacts = [SELECT Id FROM Contact ORDER BY Id LIMIT 4];
        update new Contact(
            Id = contacts[0].Id,
            Grace_Started_At__c = System.now().addDays(-10)
        );

        Test.startTest();
        Database.executeBatch(new FimbyGraceExpiryBatch(), 200);
        Test.stopTest();

        Contact after = [SELECT Deactivation_Requested__c FROM Contact WHERE Id = :contacts[0].Id];
        System.assertEquals(false, after.Deactivation_Requested__c,
            'Day-10 contact should still be in grace window');
    }

    @IsTest
    static void contactPastGraceIsFlaggedForScrub() {
        List<Contact> contacts = [SELECT Id FROM Contact ORDER BY Id LIMIT 4];
        update new Contact(
            Id = contacts[1].Id,
            Grace_Started_At__c = System.now().addDays(-31)
        );

        Test.startTest();
        Database.executeBatch(new FimbyGraceExpiryBatch(), 200);
        Test.stopTest();

        Contact after = [SELECT Deactivation_Requested__c FROM Contact WHERE Id = :contacts[1].Id];
        System.assertEquals(true, after.Deactivation_Requested__c,
            'Day-31 contact should be flagged for tonight\'s scrub');
    }

    @IsTest
    static void perContactWindowOverrideIsHonoured() {
        List<Contact> contacts = [SELECT Id FROM Contact ORDER BY Id LIMIT 4];
        update new Contact(
            Id = contacts[2].Id,
            Grace_Started_At__c = System.now().addDays(-40),
            Grace_Window_Days__c = 60
        );

        Test.startTest();
        Database.executeBatch(new FimbyGraceExpiryBatch(), 200);
        Test.stopTest();

        Contact after = [SELECT Deactivation_Requested__c FROM Contact WHERE Id = :contacts[2].Id];
        System.assertEquals(false, after.Deactivation_Requested__c,
            'A 60-day per-contact override should keep a day-40 contact in grace');
    }

    @IsTest
    static void alreadyFlaggedContactIsLeftAlone() {
        List<Contact> contacts = [SELECT Id FROM Contact ORDER BY Id LIMIT 4];
        update new Contact(
            Id = contacts[3].Id,
            Grace_Started_At__c = System.now().addDays(-40),
            Deactivation_Requested__c = true
        );

        Test.startTest();
        Database.executeBatch(new FimbyGraceExpiryBatch(), 200);
        Test.stopTest();

        Contact after = [SELECT Deactivation_Requested__c FROM Contact WHERE Id = :contacts[3].Id];
        System.assertEquals(true, after.Deactivation_Requested__c,
            'Already-flagged contacts stay flagged (idempotent)');
    }

    @IsTest
    static void schedulableEntrypointEnqueuesBatch() {
        Test.startTest();
        String cron = '0 0 0 1 1 ? 2099';
        Id jobId = System.schedule('FIMBY Grace Expiry Test',
            cron, new FimbyGraceExpiryBatch());
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }
}
