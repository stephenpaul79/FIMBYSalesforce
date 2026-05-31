@IsTest
private class FimbyModeratorTaskStalenessJobTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact mod = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        insert new Moderator_Assignment__c(
            Contact__c = mod.Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Active',
            Role__c = 'Primary'
        );
    }

    private static Account getNeighbourhood() {
        return [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' LIMIT 1];
    }

    @IsTest
    static void execute_escalatesStaleApprovalTask() {
        Account nh = getNeighbourhood();
        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Organization_Approval',
            Priority__c = 'Standard',
            Status__c = 'New',
            Summary__c = 'Stale org approval',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Organization_Approval:stale:' + String.valueOf(Crypto.getRandomInteger())
        );
        insert task;

        FimbyModeratorTaskStalenessJob.testEscalateHoursOverride = 0;

        Test.startTest();
        new FimbyModeratorTaskStalenessJob().execute(null);
        Test.stopTest();

        FimbyModeratorTaskStalenessJob.testEscalateHoursOverride = null;

        Moderator_Task__c updated = [
            SELECT Status__c, Auto_Escalated__c
            FROM Moderator_Task__c WHERE Id = :task.Id
        ];
        System.assertEquals('Escalated', updated.Status__c);
        System.assertEquals(true, updated.Auto_Escalated__c);
    }

    @IsTest
    static void execute_sendsReminderBeforeEscalation() {
        Account nh = getNeighbourhood();
        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Support_Relationship_Approval',
            Priority__c = 'Standard',
            Status__c = 'New',
            Summary__c = 'Reminder window',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Support_Relationship_Approval:reminder:' + String.valueOf(Crypto.getRandomInteger())
        );
        insert task;

        FimbyModeratorTaskStalenessJob.testReminderHoursOverride = 0;
        FimbyModeratorTaskStalenessJob.testEscalateHoursOverride = 9999;

        Test.startTest();
        new FimbyModeratorTaskStalenessJob().execute(null);
        Test.stopTest();

        FimbyModeratorTaskStalenessJob.testReminderHoursOverride = null;
        FimbyModeratorTaskStalenessJob.testEscalateHoursOverride = null;

        Moderator_Task__c updated = [
            SELECT Reminder_Sent_Date__c, Status__c
            FROM Moderator_Task__c WHERE Id = :task.Id
        ];
        System.assertNotEquals(null, updated.Reminder_Sent_Date__c);
        System.assertEquals('New', updated.Status__c);
    }
}
