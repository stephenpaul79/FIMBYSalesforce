/**
 * @description Multi-phase data retention batch that cleans up old terminal posts,
 * dormant conversations, and archived library items along with their linked files.
 * Stories are preserved indefinitely. Counters are NOT decremented (lifetime activity).
 *
 * Ships dormant — an admin schedules it via FimbyDataRetentionScheduler or anonymous Apex.
 *
 * Phases execute sequentially via chaining:
 *   Phase A → Posts → Phase B → Conversations → Phase C → Library Items
 *
 * Set dryRun = true to log what would be deleted without performing DML.
 *
 * Usage:
 *   Database.executeBatch(new FimbyDataRetentionBatch('A'), FimbySettings.dataRetentionBatchSize());
 *   Database.executeBatch(new FimbyDataRetentionBatch('A', true), 50); // dry run
 */
public without sharing class FimbyDataRetentionBatch implements Database.Batchable<SObject> {

    private static final Set<String> TERMINAL_STATUSES = new Set<String>{
        'Completed (Offer Accepted / Need Met)', 'Expired', 'Cancelled', 'Closed'
    };

    @TestVisible private String phase;
    @TestVisible private Boolean dryRun;
    @TestVisible private Integer deletedCount = 0;

    public FimbyDataRetentionBatch(String phase) {
        this(phase, false);
    }

    public FimbyDataRetentionBatch(String phase, Boolean dryRun) {
        this.phase = phase;
        this.dryRun = dryRun;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Integer months = FimbySettings.dataRetentionMonths();
        Datetime cutoff = Datetime.now().addMonths(-months);

        if (phase == 'A') {
            return Database.getQueryLocator([
                SELECT Id FROM Needs_Offers__c
                WHERE CreatedDate < :cutoff
                  AND Status__c IN :TERMINAL_STATUSES
            ]);
        } else if (phase == 'B') {
            // Exclude vouch threads — they are retained indefinitely for trust + audit.
            return Database.getQueryLocator([
                SELECT Id FROM Conversation__c
                WHERE Last_Message_Date__c < :cutoff
                  AND (Context_Type__c = NULL OR Context_Type__c != 'Vouch_Request')
            ]);
        } else {
            return Database.getQueryLocator([
                SELECT Id FROM Library_Item__c
                WHERE CreatedDate < :cutoff
                  AND Status__c = 'Removed from Library'
            ]);
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (phase == 'A') {
            executePostCleanup(scope);
        } else if (phase == 'B') {
            executeConversationTrimming(scope);
        } else {
            executeLibraryCleanup(scope);
        }
    }

    public void finish(Database.BatchableContext bc) {
        String label = phase == 'A' ? 'Post Cleanup' : (phase == 'B' ? 'Conversation Trimming' : 'Library Cleanup');
        FimbyLogger.info('FimbyDataRetentionBatch', 'finish',
            label + ' complete. Deleted: ' + deletedCount + (dryRun ? ' (DRY RUN)' : ''));

        String nextPhase = phase == 'A' ? 'B' : (phase == 'B' ? 'C' : null);
        if (nextPhase != null) {
            Database.executeBatch(
                new FimbyDataRetentionBatch(nextPhase, dryRun),
                FimbySettings.dataRetentionBatchSize()
            );
        }
    }

    /* ---------------------------------------------------------------
     * Phase A: Post Cleanup (Needs_Offers__c + children + files)
     * --------------------------------------------------------------- */

    private void executePostCleanup(List<SObject> scope) {
        Set<Id> postIds = new Set<Id>();
        for (SObject s : scope) { postIds.add(s.Id); }

        List<SObject> toDelete = new List<SObject>();

        toDelete.addAll([SELECT Id FROM Response_Message__c
            WHERE Response__r.Need_Offer_Responded_To__c IN :postIds]);
        toDelete.addAll([SELECT Id FROM Response__c
            WHERE Need_Offer_Responded_To__c IN :postIds]);

        Set<Id> fileDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId IN :postIds
        ]) {
            fileDocIds.add(cdl.ContentDocumentId);
        }
        if (!fileDocIds.isEmpty()) {
            toDelete.addAll([SELECT Id FROM ContentDocument WHERE Id IN :fileDocIds]);
        }

        for (SObject s : scope) { toDelete.add(s); }

        if (!dryRun && !toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }
        deletedCount += toDelete.size();
    }

    /* ---------------------------------------------------------------
     * Phase B: Conversation Message Trimming
     * --------------------------------------------------------------- */

    private void executeConversationTrimming(List<SObject> scope) {
        Integer keepCount = FimbySettings.conversationTrimKeepCount();
        Integer months = FimbySettings.dataRetentionMonths();
        Datetime cutoff = Datetime.now().addMonths(-months);

        Set<Id> convIds = new Set<Id>();
        for (SObject s : scope) { convIds.add(s.Id); }

        List<SObject> toDelete = new List<SObject>();

        for (Id convId : convIds) {
            List<Message__c> allMessages = [
                SELECT Id FROM Message__c
                WHERE Conversation__c = :convId
                ORDER BY CreatedDate DESC
            ];

            if (allMessages.size() <= keepCount) {
                continue;
            }

            for (Integer i = keepCount; i < allMessages.size(); i++) {
                toDelete.add(allMessages[i]);
            }
        }

        if (!dryRun && !toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }
        deletedCount += toDelete.size();
    }

    /* ---------------------------------------------------------------
     * Phase C: Library Item Cleanup (archived items + children + files)
     * --------------------------------------------------------------- */

    private void executeLibraryCleanup(List<SObject> scope) {
        Set<Id> itemIds = new Set<Id>();
        for (SObject s : scope) { itemIds.add(s.Id); }

        List<SObject> toDelete = new List<SObject>();

        toDelete.addAll([SELECT Id FROM Lending_History__c
            WHERE Library_Item__c IN :itemIds]);
        toDelete.addAll([SELECT Id FROM Loaned_Item__c
            WHERE Library_Item__c IN :itemIds]);
        toDelete.addAll([SELECT Id FROM Lending_Request__c
            WHERE Library_Item__c IN :itemIds]);

        Set<Id> fileDocIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId IN :itemIds
        ]) {
            fileDocIds.add(cdl.ContentDocumentId);
        }
        if (!fileDocIds.isEmpty()) {
            toDelete.addAll([SELECT Id FROM ContentDocument WHERE Id IN :fileDocIds]);
        }

        for (SObject s : scope) { toDelete.add(s); }

        if (!dryRun && !toDelete.isEmpty()) {
            Database.delete(toDelete, false);
        }
        deletedCount += toDelete.size();
    }
}
