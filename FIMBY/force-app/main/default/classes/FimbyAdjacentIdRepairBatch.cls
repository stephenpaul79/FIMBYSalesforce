/**
 * @description Batch job that rebuilds the denormalized Adjacent_Neighbourhood_Ids__c and
 * Adjacent_Neighbourhood_Links__c fields on all Boundary Accounts from the source-of-truth
 * Neighbourhood_Adjacency__c records. Run via invocable action or Developer Console:
 *   Database.executeBatch(new FimbyAdjacentIdRepairBatch(), 50);
 */
public without sharing class FimbyAdjacentIdRepairBatch implements Database.Batchable<SObject> {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Adjacent_Neighbourhood_Ids__c, Adjacent_Neighbourhood_Links__c
            FROM Account
            WHERE RecordType.DeveloperName = 'Boundary_Account'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        Set<Id> accountIds = new Set<Id>();
        for (Account a : scope) {
            accountIds.add(a.Id);
        }

        Map<Id, List<Neighbourhood_Adjacency__c>> adjacenciesByAccount = new Map<Id, List<Neighbourhood_Adjacency__c>>();
        for (Neighbourhood_Adjacency__c na : [
            SELECT Core_Neighbourhood__c, Adjacent_Neighbour__c, Adjacent_Neighbour__r.Name
            FROM Neighbourhood_Adjacency__c
            WHERE Core_Neighbourhood__c IN :accountIds
            AND Active__c = true
        ]) {
            if (!adjacenciesByAccount.containsKey(na.Core_Neighbourhood__c)) {
                adjacenciesByAccount.put(na.Core_Neighbourhood__c, new List<Neighbourhood_Adjacency__c>());
            }
            adjacenciesByAccount.get(na.Core_Neighbourhood__c).add(na);
        }

        List<Account> toUpdate = new List<Account>();
        for (Account a : scope) {
            List<Neighbourhood_Adjacency__c> adjacencies = adjacenciesByAccount.get(a.Id);
            String ids = '';
            String links = '';

            if (adjacencies != null && !adjacencies.isEmpty()) {
                List<String> idParts = new List<String>();
                List<String> linkParts = new List<String>();
                for (Neighbourhood_Adjacency__c na : adjacencies) {
                    idParts.add(String.valueOf(na.Adjacent_Neighbour__c));
                    linkParts.add(
                        '<a href="/' + na.Adjacent_Neighbour__c + '">' +
                        String.valueOf(na.Adjacent_Neighbour__r.Name).escapeHtml4() +
                        '</a>'
                    );
                }
                ids = String.join(idParts, ',');
                links = String.join(linkParts, ' | ');
            }

            if (a.Adjacent_Neighbourhood_Ids__c != ids || a.Adjacent_Neighbourhood_Links__c != links) {
                toUpdate.add(new Account(
                    Id = a.Id,
                    Adjacent_Neighbourhood_Ids__c = ids,
                    Adjacent_Neighbourhood_Links__c = links
                ));
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
    }

    @InvocableMethod(label='Rebuild Adjacent Neighbourhood IDs'
                     description='Runs the FimbyAdjacentIdRepairBatch to rebuild denormalized adjacency fields on Boundary Accounts')
    public static void run(List<String> unused) {
        Database.executeBatch(new FimbyAdjacentIdRepairBatch(), 50);
    }
}
