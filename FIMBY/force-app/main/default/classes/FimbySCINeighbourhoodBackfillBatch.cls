/**
 * @description Batch job that backfills Contact_Neighbourhood__c and Shared_To_Neighbourhood__c
 * on existing Shared_Contact_Info__c records. Derives values from the related Contact's AccountId.
 * Idempotent — only touches records where at least one field is null.
 *   Database.executeBatch(new FimbySCINeighbourhoodBackfillBatch(), 200);
 */
public without sharing class FimbySCINeighbourhoodBackfillBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Contact__c, Contact__r.AccountId,
                   Shared_To__c, Shared_To__r.AccountId,
                   Contact_Neighbourhood__c, Shared_To_Neighbourhood__c
            FROM Shared_Contact_Info__c
            WHERE Contact_Neighbourhood__c = null
               OR Shared_To_Neighbourhood__c = null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Shared_Contact_Info__c> scope) {
        List<Shared_Contact_Info__c> toUpdate = new List<Shared_Contact_Info__c>();

        for (Shared_Contact_Info__c sci : scope) {
            Boolean changed = false;
            Shared_Contact_Info__c upd = new Shared_Contact_Info__c(Id = sci.Id);

            if (sci.Contact_Neighbourhood__c == null && sci.Contact__r.AccountId != null) {
                upd.Contact_Neighbourhood__c = sci.Contact__r.AccountId;
                changed = true;
            }
            if (sci.Shared_To_Neighbourhood__c == null && sci.Shared_To__r.AccountId != null) {
                upd.Shared_To_Neighbourhood__c = sci.Shared_To__r.AccountId;
                changed = true;
            }

            if (changed) {
                toUpdate.add(upd);
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
    }
}
