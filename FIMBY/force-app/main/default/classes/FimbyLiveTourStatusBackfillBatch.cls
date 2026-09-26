/**
 * @description One-time backfill: sets Live_Tour_Status__c to Not Started where blank.
 */
global without sharing class FimbyLiveTourStatusBackfillBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id
            FROM Contact
            WHERE Live_Tour_Status__c = null
              AND Is_Organization_Contact__c = false
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Contact> scope) {
        for (Contact c : scope) {
            c.Live_Tour_Status__c = FimbyConstants.ONBOARDING_NOT_STARTED;
        }
        update scope;
    }

    global void finish(Database.BatchableContext bc) {}
}
