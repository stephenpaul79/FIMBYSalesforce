/**
 * @description Scheduled Apex job that purges stale conversations and response threads on a
 * single, consolidated 180-day window across ALL Context_Type values (Direct, Library_Lending,
 * Bulk_Buy, Missed_Pickup, Event, Vouch_Request, Skill) plus null/childless orphans. Runs in
 * system context regardless of record ownership. Cascade children delete via master-detail.
 */
global without sharing class FimbyConversationCleanupJob implements Schedulable {

    /**
     * @description Schedulable execute. Deletes stale Message__c, Conversation__c, Response_Message__c,
     * and Response__c records on one retention window, and purge-syncs the related hidden notifications.
     * @param ctx Schedulable context
     */
    global void execute(SchedulableContext ctx) {
        try {
            Integer batchSize = FimbySettings.conversationCleanupBatchSize();
            Integer convBatchSize = Math.min(batchSize, 5000);

            Integer days = FimbySettings.conversationCleanupDays();
            if (days <= 0) {
                return;
            }

            // ── Conversations: single window for ALL Context_Type values + null ──
            // Most-recent-child (Last_Message_Date__c) governs when messages exist
            // (current behaviour); parent CreatedDate governs for never-stamped /
            // childless orphans. The old job left Bulk_Buy/Missed_Pickup/Event/
            // Vouch_Request/Skill conversations uncleaned forever — closing that gap.
            Datetime cutoff = Datetime.now().addDays(-days);
            List<Conversation__c> staleConvos = [
                SELECT Id FROM Conversation__c
                WHERE (Last_Message_Date__c != null AND Last_Message_Date__c < :cutoff)
                   OR (Last_Message_Date__c = null AND CreatedDate < :cutoff)
                LIMIT :convBatchSize
            ];
            if (!staleConvos.isEmpty()) {
                Set<Id> convoIds = new Map<Id, Conversation__c>(staleConvos).keySet();

                // Pre-delete children in batches for governor safety on large threads.
                List<Message__c> convMessages = [
                    SELECT Id FROM Message__c WHERE Conversation__c IN :convoIds LIMIT :batchSize
                ];
                if (!convMessages.isEmpty()) Database.delete(convMessages, false);

                // Purge-sync: delete this thread's hidden notifications BEFORE the
                // parent (Notification__c is MD to Contact, not the thread, and
                // Related_Record_Id__c is plain text, so it never cascades).
                purgeHiddenNotifications(convoIds, FimbyConstants.CONVERSATION_HIDDEN_TYPES);

                // Conversation_Member__c + any remaining Message__c cascade via master-detail.
                Database.delete(staleConvos, false);
            }

            // ── Response threads: same window, same most-recent-child + CreatedDate fallback ──
            Date cutoffDate = Date.today().addDays(-days);
            Datetime cutoffDt = Datetime.newInstance(cutoffDate, Time.newInstance(0, 0, 0, 0));
            List<Response__c> staleResponses = [
                SELECT Id FROM Response__c
                WHERE (Last_Reply_Date__c != null AND Last_Reply_Date__c < :cutoffDate)
                   OR (Last_Reply_Date__c = null AND CreatedDate < :cutoffDt)
                LIMIT :convBatchSize
            ];
            if (!staleResponses.isEmpty()) {
                Set<Id> respIds = new Map<Id, Response__c>(staleResponses).keySet();

                List<Response_Message__c> respMessages = [
                    SELECT Id FROM Response_Message__c WHERE Response__c IN :respIds LIMIT :batchSize
                ];
                if (!respMessages.isEmpty()) Database.delete(respMessages, false);

                purgeHiddenNotifications(respIds, FimbyConstants.RESPONSE_HIDDEN_TYPES);

                // Response_Message__c cascades via master-detail.
                Database.delete(staleResponses, false);
            }
        } catch (Exception e) {
            FimbyLogger.error('FimbyConversationCleanupJob', 'execute', e);
        }
    }

    /**
     * @description Deletes hidden Notification__c rows whose plain-text
     * Related_Record_Id__c matches one of the soon-to-be-deleted thread ids.
     */
    private void purgeHiddenNotifications(Set<Id> threadIds, Set<String> types) {
        if (threadIds == null || threadIds.isEmpty()) {
            return;
        }
        Set<String> idStrings = new Set<String>();
        for (Id tid : threadIds) {
            idStrings.add(String.valueOf(tid));
        }
        // LIMIT-capped for governor safety; any stragglers left when a thread is
        // deleted are reclaimed by FimbyNotificationCleanupJob's age-based backstop.
        List<Notification__c> notifs = [
            SELECT Id FROM Notification__c
            WHERE Type__c IN :types AND Related_Record_Id__c IN :idStrings
            LIMIT 10000
        ];
        if (!notifs.isEmpty()) {
            Database.delete(notifs, false);
        }
    }
}
