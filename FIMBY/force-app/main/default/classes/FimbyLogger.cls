/**
 * @description Centralized logging utility for FIMBY Apex classes. Publishes
 * Error_Log_Event__e Platform Events which are consumed by ErrorLogEventTrigger
 * to create Error_Log__c records. Using Platform Events ensures log writes never
 * fail the calling transaction and survive rollbacks.
 */
public without sharing class FimbyLogger {

    public enum Severity { ERROR_LEVEL, WARN_LEVEL, INFO_LEVEL }

    /**
     * @description Log an exception at ERROR severity.
     * @param className Fully qualified class name where the error was caught
     * @param methodName Method name where the error was caught
     * @param ex The caught exception
     */
    public static void error(String className, String methodName, Exception ex) {
        publishException(Severity.ERROR_LEVEL, className, methodName, ex, null);
    }

    /**
     * @description Log an exception at ERROR severity with a related record.
     * @param className Fully qualified class name where the error was caught
     * @param methodName Method name where the error was caught
     * @param ex The caught exception
     * @param recordId Related record Id for context
     */
    public static void error(String className, String methodName, Exception ex, Id recordId) {
        publishException(Severity.ERROR_LEVEL, className, methodName, ex, recordId);
    }

    /**
     * @description Log a warning message.
     * @param className Fully qualified class name
     * @param methodName Method name
     * @param message Warning description
     */
    public static void warn(String className, String methodName, String message) {
        publishMessage(Severity.WARN_LEVEL, className, methodName, message, null);
    }

    /**
     * @description Log an informational message.
     * @param className Fully qualified class name
     * @param methodName Method name
     * @param message Info description
     */
    public static void info(String className, String methodName, String message) {
        publishMessage(Severity.INFO_LEVEL, className, methodName, message, null);
    }

    private static void publishException(Severity sev, String className, String methodName, Exception ex, Id recordId) {
        Error_Log_Event__e evt = buildBaseEvent(sev, className, methodName, recordId);
        evt.Error_Message__c = ex.getMessage();
        evt.Stack_Trace__c = ex.getStackTraceString();
        evt.Exception_Type__c = ex.getTypeName();
        EventBus.publish(evt);
    }

    private static void publishMessage(Severity sev, String className, String methodName, String message, Id recordId) {
        Error_Log_Event__e evt = buildBaseEvent(sev, className, methodName, recordId);
        evt.Error_Message__c = message;
        EventBus.publish(evt);
    }

    private static Error_Log_Event__e buildBaseEvent(Severity sev, String className, String methodName, Id recordId) {
        Error_Log_Event__e evt = new Error_Log_Event__e();
        evt.Class_Name__c = className;
        evt.Method_Name__c = methodName;
        evt.Severity__c = sev.name();
        evt.User_Id__c = UserInfo.getUserId();
        evt.Running_User__c = UserInfo.getName();
        evt.Record_Id__c = recordId != null ? String.valueOf(recordId) : null;
        evt.Request_Id__c = Request.getCurrent().getRequestId();
        evt.Quiddity__c = Request.getCurrent().getQuiddity()?.name();
        evt.Governor_Limits_Snapshot__c = captureGovernorSnapshot();
        evt.Logged_At__c = String.valueOf(System.now());
        return evt;
    }

    private static String captureGovernorSnapshot() {
        Map<String, String> snapshot = new Map<String, String>{
            'soqlQueries' => Limits.getQueries() + '/' + Limits.getLimitQueries(),
            'dmlStatements' => Limits.getDmlStatements() + '/' + Limits.getLimitDmlStatements(),
            'cpuTime' => Limits.getCpuTime() + '/' + Limits.getLimitCpuTime(),
            'heapSize' => Limits.getHeapSize() + '/' + Limits.getLimitHeapSize(),
            'dmlRows' => Limits.getDmlRows() + '/' + Limits.getLimitDmlRows(),
            'queryRows' => Limits.getQueryRows() + '/' + Limits.getLimitQueryRows()
        };
        return JSON.serialize(snapshot);
    }
}
