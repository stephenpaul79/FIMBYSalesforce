/**
 * @description Scheduled batch that nulls submitter references on Feedback__c
 * rows whose 90-day post-deactivation hold has elapsed. Set by
 * FimbyAccountDeactivationBatch via Anonymize_After__c. Operational data
 * (text, status, related-record link) is preserved so admins can still
 * see complaint history without the original submitter's identity.
 *
 * Schedule daily:
 *   System.schedule('FIMBY Feedback Anonymization', '0 30 0 * * ?', new FimbyFeedbackAnonymizationBatch());
 */
global without sharing class FimbyFeedbackAnonymizationBatch implements Database.Batchable<SObject>, Schedulable {

    global void execute(SchedulableContext sc) {
        Database.executeBatch(this, 200);
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        Date today = Date.today();
        return Database.getQueryLocator([
            SELECT Id, Posted_By__c, Contact__c, Posted_For_Person__c,
                   Anonymize_After__c
            FROM Feedback__c
            WHERE Anonymize_After__c != null
              AND Anonymize_After__c <= :today
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Feedback__c> rows) {
        // Posted_By__c, Contact__c, Posted_For_Person__c are the submitter and
        // beneficiary references. The First_Name__c text formula derives from
        // Posted_By__r so nulling the lookup also blanks the displayed name.
        for (Feedback__c f : rows) {
            f.Posted_By__c = null;
            f.Contact__c = null;
            f.Posted_For_Person__c = null;
            f.Anonymize_After__c = null;
        }
        if (!rows.isEmpty()) {
            Database.update(rows, false);
        }
    }

    global void finish(Database.BatchableContext bc) {
    }
}
