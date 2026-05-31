/**
 * @description Queueable that performs large-volume DML for neighbourhood split restamping
 * when the synchronous action would exceed governor limits. Receives a list of SObjects to
 * update and the split record ID for progress tracking.
 */
public without sharing class FimbyNeighbourhoodSplitQueueable implements Queueable, Database.AllowsCallouts, System.Finalizer {

    private List<SObject> recordsToUpdate;
    private Id splitRecordId;

    public FimbyNeighbourhoodSplitQueueable(List<SObject> recordsToUpdate, Id splitRecordId) {
        this.recordsToUpdate = recordsToUpdate;
        this.splitRecordId = splitRecordId;
    }

    public void execute(QueueableContext ctx) {
        System.attachFinalizer(this);

        if (recordsToUpdate == null || recordsToUpdate.isEmpty()) {
            return;
        }

        List<Database.SaveResult> results = Database.update(recordsToUpdate, false);

        Integer successCount = 0;
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                successCount++;
            } else {
                FimbyLogger.warn('FimbyNeighbourhoodSplitQueueable', 'execute',
                    'Failed to update ' + sr.getId() + ': ' + sr.getErrors()[0].getMessage());
            }
        }

        updateSplitProgress(successCount);
    }

    public void execute(System.FinalizerContext fc) {
        if (fc?.getResult() == System.ParentJobResult.UNHANDLED_EXCEPTION) {
            markSplitFailed(splitRecordId, fc.getException()?.getMessage());
        }
    }

    @TestVisible
    private static void markSplitFailed(Id splitId, String errorMsg) {
        try {
            Neighbourhood_Split__c split = new Neighbourhood_Split__c(
                Id = splitId,
                Status__c = 'Failed',
                Error_Detail__c = truncate(errorMsg, 255)
            );
            Database.update(split, false);
        } catch (Exception e) {
            FimbyLogger.error('FimbyNeighbourhoodSplitQueueable', 'markSplitFailed', e);
        }
    }

    @TestVisible
    private void updateSplitProgress(Integer count) {
        try {
            Neighbourhood_Split__c split = [
                SELECT Records_Restamped__c FROM Neighbourhood_Split__c
                WHERE Id = :splitRecordId
                LIMIT 1
            ];
            Decimal existing = split.Records_Restamped__c != null ? split.Records_Restamped__c : 0;
            split.Records_Restamped__c = existing + count;
            Database.update(split, false);
        } catch (Exception e) {
            FimbyLogger.error('FimbyNeighbourhoodSplitQueueable', 'updateSplitProgress', e);
        }
    }

    @TestVisible
    private static String truncate(String value, Integer maxLen) {
        if (String.isBlank(value)) return value;
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }
}
