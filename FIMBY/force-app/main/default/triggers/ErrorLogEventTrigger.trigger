trigger ErrorLogEventTrigger on Error_Log_Event__e (after insert) {
    List<Error_Log__c> logs = new List<Error_Log__c>();
    for (Error_Log_Event__e evt : Trigger.New) {
        Error_Log__c log = new Error_Log__c();
        log.Class_Name__c = evt.Class_Name__c;
        log.Method_Name__c = evt.Method_Name__c;
        log.Error_Message__c = evt.Error_Message__c;
        log.Stack_Trace__c = evt.Stack_Trace__c;
        log.Exception_Type__c = evt.Exception_Type__c;
        log.Severity__c = evt.Severity__c;
        log.Running_User__c = evt.Running_User__c;
        log.Record_Id__c = evt.Record_Id__c;
        log.Context_Type__c = evt.Context_Type__c;
        log.Request_Id__c = evt.Request_Id__c;
        log.Quiddity__c = evt.Quiddity__c;
        log.Governor_Limits_Snapshot__c = evt.Governor_Limits_Snapshot__c;

        if (String.isNotBlank(evt.User_Id__c)) {
            try {
                log.User__c = Id.valueOf(evt.User_Id__c);
            } catch (Exception e) {
                log.Running_User__c = evt.Running_User__c + ' (ID: ' + evt.User_Id__c + ')';
            }
        }

        if (String.isNotBlank(evt.Logged_At__c)) {
            try {
                log.Logged_At__c = DateTime.valueOf(evt.Logged_At__c);
            } catch (Exception e) {
                log.Logged_At__c = System.now();
            }
        } else {
            log.Logged_At__c = System.now();
        }

        logs.add(log);
    }

    if (!logs.isEmpty()) {
        Database.insert(logs, false);
    }
}
