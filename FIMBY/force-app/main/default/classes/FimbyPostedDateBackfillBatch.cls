/**
 * @description One-time backfill: sets Posted_Date__c = CreatedDate for existing Need/Offer/Bulk_Buy rows.
 */
global without sharing class FimbyPostedDateBackfillBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, CreatedDate
            FROM Needs_Offers__c
            WHERE Posted_Date__c = null
              AND RecordType.DeveloperName IN ('Need', 'Offer', 'Bulk_Buy')
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Needs_Offers__c> scope) {
        for (Needs_Offers__c post : scope) {
            post.Posted_Date__c = post.CreatedDate;
        }
        update scope;
    }

    global void finish(Database.BatchableContext bc) {}
}
