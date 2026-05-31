@isTest
private class FimbyLoggerTest {

    @isTest
    static void testErrorWithException() {
        Test.startTest();
        try {
            Integer x = 1 / 0;
        } catch (Exception ex) {
            FimbyLogger.error('FimbyLoggerTest', 'testErrorWithException', ex);
        }
        Test.stopTest();

        List<Error_Log__c> logs = [
            SELECT Class_Name__c, Method_Name__c, Error_Message__c,
                   Stack_Trace__c, Exception_Type__c, Severity__c,
                   User__c, Running_User__c, Request_Id__c, Quiddity__c,
                   Governor_Limits_Snapshot__c, Logged_At__c
            FROM Error_Log__c
        ];
        System.assertEquals(1, logs.size(), 'Expected one Error_Log__c record');

        Error_Log__c log = logs[0];
        System.assertEquals('FimbyLoggerTest', log.Class_Name__c);
        System.assertEquals('testErrorWithException', log.Method_Name__c);
        System.assert(log.Error_Message__c != null, 'Error message should be populated');
        System.assert(log.Stack_Trace__c != null, 'Stack trace should be populated');
        System.assertEquals('System.MathException', log.Exception_Type__c);
        System.assertEquals('ERROR_LEVEL', log.Severity__c);
        System.assertEquals(UserInfo.getUserId(), log.User__c);
        System.assert(String.isNotBlank(log.Running_User__c), 'Running user should be set');
        System.assert(String.isNotBlank(log.Request_Id__c), 'Request ID should be set');
        System.assert(String.isNotBlank(log.Governor_Limits_Snapshot__c), 'Governor snapshot should be set');
        System.assert(log.Logged_At__c != null, 'Logged_At should be set');
    }

    @isTest
    static void testErrorWithExceptionAndRecordId() {
        Account acc = new Account(Name = 'Test Org');
        insert acc;

        Test.startTest();
        try {
            Integer x = 1 / 0;
        } catch (Exception ex) {
            FimbyLogger.error('FimbyLoggerTest', 'testErrorWithRecordId', ex, acc.Id);
        }
        Test.stopTest();

        List<Error_Log__c> logs = [
            SELECT Record_Id__c FROM Error_Log__c
        ];
        System.assertEquals(1, logs.size(), 'Expected one Error_Log__c record');
        System.assertEquals(String.valueOf(acc.Id), logs[0].Record_Id__c);
    }

    @isTest
    static void testWarnMessage() {
        Test.startTest();
        FimbyLogger.warn('FimbyLoggerTest', 'testWarnMessage', 'Something looks off');
        Test.stopTest();

        List<Error_Log__c> logs = [
            SELECT Severity__c, Error_Message__c, Exception_Type__c FROM Error_Log__c
        ];
        System.assertEquals(1, logs.size(), 'Expected one Error_Log__c record');
        System.assertEquals('WARN_LEVEL', logs[0].Severity__c);
        System.assertEquals('Something looks off', logs[0].Error_Message__c);
        System.assertEquals(null, logs[0].Exception_Type__c, 'No exception type for warn messages');
    }

    @isTest
    static void testInfoMessage() {
        Test.startTest();
        FimbyLogger.info('FimbyLoggerTest', 'testInfoMessage', 'Process completed');
        Test.stopTest();

        List<Error_Log__c> logs = [
            SELECT Severity__c, Error_Message__c FROM Error_Log__c
        ];
        System.assertEquals(1, logs.size(), 'Expected one Error_Log__c record');
        System.assertEquals('INFO_LEVEL', logs[0].Severity__c);
        System.assertEquals('Process completed', logs[0].Error_Message__c);
    }

    @isTest
    static void testGovernorSnapshotFormat() {
        Test.startTest();
        FimbyLogger.info('FimbyLoggerTest', 'testGovernorSnapshot', 'Snapshot test');
        Test.stopTest();

        List<Error_Log__c> logs = [
            SELECT Governor_Limits_Snapshot__c FROM Error_Log__c
        ];
        System.assertEquals(1, logs.size());

        Map<String, Object> snapshot = (Map<String, Object>) JSON.deserializeUntyped(
            logs[0].Governor_Limits_Snapshot__c
        );
        System.assert(snapshot.containsKey('soqlQueries'), 'Snapshot should contain soqlQueries');
        System.assert(snapshot.containsKey('dmlStatements'), 'Snapshot should contain dmlStatements');
        System.assert(snapshot.containsKey('cpuTime'), 'Snapshot should contain cpuTime');
        System.assert(snapshot.containsKey('heapSize'), 'Snapshot should contain heapSize');
    }
}
