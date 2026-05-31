@IsTest
private class FimbyFeedbackAnonymizationBatchTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact submitter = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        Contact subject = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        insert new Feedback__c(
            Name = 'Due Yesterday',
            Type__c = 'Bug',
            Details__c = 'Anonymize me',
            Posted_By__c = submitter.Id,
            Contact__c = submitter.Id,
            Posted_For_Person__c = subject.Id,
            Neighbourhood__c = neighbourhood.Id,
            Anonymize_After__c = Date.today().addDays(-1)
        );

        insert new Feedback__c(
            Name = 'Due Today',
            Type__c = 'Bug',
            Details__c = 'Anonymize me too',
            Posted_By__c = submitter.Id,
            Neighbourhood__c = neighbourhood.Id,
            Anonymize_After__c = Date.today()
        );

        insert new Feedback__c(
            Name = 'Due Tomorrow',
            Type__c = 'Bug',
            Details__c = 'Wait one more day',
            Posted_By__c = submitter.Id,
            Neighbourhood__c = neighbourhood.Id,
            Anonymize_After__c = Date.today().addDays(1)
        );

        insert new Feedback__c(
            Name = 'No Marker',
            Type__c = 'Bug',
            Details__c = 'Submitter still active',
            Posted_By__c = submitter.Id,
            Neighbourhood__c = neighbourhood.Id
        );
    }

    @IsTest
    static void anonymizesFeedbackWithDuePastOrToday() {
        Test.startTest();
        Database.executeBatch(new FimbyFeedbackAnonymizationBatch(), 200);
        Test.stopTest();

        Map<String, Feedback__c> byName = new Map<String, Feedback__c>();
        for (Feedback__c f : [
            SELECT Id, Name, Posted_By__c, Contact__c, Posted_For_Person__c,
                   Anonymize_After__c
            FROM Feedback__c
        ]) {
            byName.put(f.Name, f);
        }

        Feedback__c yesterday = byName.get('Due Yesterday');
        System.assertEquals(null, yesterday.Posted_By__c, 'Past-due submitter ref nulled');
        System.assertEquals(null, yesterday.Contact__c);
        System.assertEquals(null, yesterday.Posted_For_Person__c);
        System.assertEquals(null, yesterday.Anonymize_After__c, 'Marker cleared after processing');

        Feedback__c today = byName.get('Due Today');
        System.assertEquals(null, today.Posted_By__c, 'Today is inclusive');
        System.assertEquals(null, today.Anonymize_After__c);

        Feedback__c tomorrow = byName.get('Due Tomorrow');
        System.assertNotEquals(null, tomorrow.Posted_By__c, 'Future-due rows not yet anonymized');
        System.assertNotEquals(null, tomorrow.Anonymize_After__c, 'Marker preserved for future runs');

        Feedback__c noMarker = byName.get('No Marker');
        System.assertNotEquals(null, noMarker.Posted_By__c,
            'Rows without Anonymize_After__c are out of scope');
    }

    @IsTest
    static void schedulableInstanceCanBeScheduled() {
        Test.startTest();
        String jobId = System.schedule(
            'Test FIMBY Feedback Anonymization',
            '0 0 1 * * ?',
            new FimbyFeedbackAnonymizationBatch()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }
}
