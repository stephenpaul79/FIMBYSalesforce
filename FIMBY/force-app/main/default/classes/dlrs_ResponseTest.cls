/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
@IsTest
private class dlrs_ResponseTest
{
    @IsTest
    private static void testTrigger()
    {
        // Force the dlrs_ResponseTrigger to be invoked, fails the test if org config or other Apex code prevents this.
        dlrs.RollupService.testHandler(new Response__c());
    }
}