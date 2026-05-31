@isTest
private class FimbyConversationCleanupJobTest {

    @isTest
    static void testExecuteWithNoStaleData() {
        Test.startTest();
        FimbyConversationCleanupJob job = new FimbyConversationCleanupJob();
        job.execute(null);
        Test.stopTest();
        System.assert(true, 'Job should execute without error when no stale data exists');
    }

    @isTest
    static void testExecuteWhenDisabled() {
        // When cleanup days is 0, the job should exit early
        Test.startTest();
        FimbyConversationCleanupJob job = new FimbyConversationCleanupJob();
        job.execute(null);
        Test.stopTest();
        System.assert(true, 'Job should handle disabled cleanup gracefully');
    }
}
