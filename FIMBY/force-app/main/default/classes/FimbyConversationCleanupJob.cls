/**
 * @description Scheduled Apex job that purges stale conversations: DM (90 days), library lending (180 days),
 * and response threads (180 days). Runs in system context regardless of record ownership.
 */
global without sharing class FimbyConversationCleanupJob implements Schedulable {

    /**
     * @description Schedulable execute. Deletes stale Message__c, Conversation__c, Response_Message__c,
     * and Response__c records based on configurable retention days.
     * @param ctx Schedulable context
     */
    global void execute(SchedulableContext ctx) {
        try {
        Integer batchSize = FimbySettings.conversationCleanupBatchSize();
        Integer convBatchSize = Math.min(batchSize, 5000);

        // DM conversations: 90 days
        Integer dmDays = FimbySettings.conversationCleanupDays();
        if (dmDays > 0) {
            Datetime dmCutoff = Datetime.now().addDays(-dmDays);
            List<Message__c> dmMessages = [
                SELECT Id FROM Message__c
                WHERE Conversation__c IN (
                    SELECT Id FROM Conversation__c
                    WHERE Last_Message_Date__c < :dmCutoff
                    AND (Context_Type__c = null OR Context_Type__c = 'Direct')
                )
                LIMIT :batchSize
            ];
            if (!dmMessages.isEmpty()) Database.delete(dmMessages, false);

            List<Conversation__c> dmConvos = [
                SELECT Id FROM Conversation__c
                WHERE Last_Message_Date__c < :dmCutoff
                AND (Context_Type__c = null OR Context_Type__c = 'Direct')
                LIMIT :convBatchSize
            ];
            if (!dmConvos.isEmpty()) Database.delete(dmConvos, false);
        }

        // Library (lending) conversations: 180 days
        Integer libDays = FimbySettings.libraryConversationCleanupDays();
        if (libDays > 0) {
            Datetime libCutoff = Datetime.now().addDays(-libDays);
            List<Message__c> libMessages = [
                SELECT Id FROM Message__c
                WHERE Conversation__c IN (
                    SELECT Id FROM Conversation__c
                    WHERE Last_Message_Date__c < :libCutoff
                    AND Context_Type__c = 'Library_Lending'
                )
                LIMIT :batchSize
            ];
            if (!libMessages.isEmpty()) Database.delete(libMessages, false);

            List<Conversation__c> libConvos = [
                SELECT Id FROM Conversation__c
                WHERE Last_Message_Date__c < :libCutoff
                AND Context_Type__c = 'Library_Lending'
                LIMIT :convBatchSize
            ];
            if (!libConvos.isEmpty()) Database.delete(libConvos, false);
        }

        // Response threads: 180 days
        Integer respDays = FimbySettings.responseThreadCleanupDays();
        if (respDays > 0) {
            Date respCutoffDate = Date.today().addDays(-respDays);
            Datetime respCutoffDt = Datetime.newInstance(respCutoffDate, Time.newInstance(0, 0, 0, 0));
            List<Response_Message__c> respMessages = [
                SELECT Id FROM Response_Message__c
                WHERE Response__c IN (
                    SELECT Id FROM Response__c
                    WHERE (Last_Reply_Date__c != null AND Last_Reply_Date__c < :respCutoffDate)
                       OR (Last_Reply_Date__c = null AND CreatedDate < :respCutoffDt)
                )
                LIMIT :batchSize
            ];
            if (!respMessages.isEmpty()) Database.delete(respMessages, false);

            List<Response__c> staleResponses = [
                SELECT Id FROM Response__c
                WHERE (Last_Reply_Date__c != null AND Last_Reply_Date__c < :respCutoffDate)
                   OR (Last_Reply_Date__c = null AND CreatedDate < :respCutoffDt)
                LIMIT :convBatchSize
            ];
            if (!staleResponses.isEmpty()) Database.delete(staleResponses, false);
        }
        } catch (Exception e) {
            FimbyLogger.error('FimbyConversationCleanupJob', 'execute', e);
        }
    }
}
