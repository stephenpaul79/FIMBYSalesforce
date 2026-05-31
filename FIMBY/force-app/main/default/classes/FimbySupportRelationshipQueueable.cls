/**
 * @description Queueable to auto-switch helpers back to self when their
 * Support_Relationship__c is revoked by admin. Required because the trigger
 * context on Support_Relationship__c cannot safely DML the parent Contact
 * (master-detail cross-object DML constraint).
 */
public without sharing class FimbySupportRelationshipQueueable implements Queueable {

    private List<Support_Relationship__c> revokedRelationships;

    public FimbySupportRelationshipQueueable(List<Support_Relationship__c> revokedRelationships) {
        this.revokedRelationships = revokedRelationships;
    }

    public void execute(QueueableContext context) {
        Set<Id> helperContactIds = new Set<Id>();
        Map<Id, Id> helperToTarget = new Map<Id, Id>();

        for (Support_Relationship__c rel : revokedRelationships) {
            helperContactIds.add(rel.Contact__c);
            Id target = (rel.Related_Contact__c != null)
                ? rel.Related_Contact__c
                : rel.Related_Organization__c;
            helperToTarget.put(rel.Contact__c, target);
        }

        List<Contact> helpers = [
            SELECT Id, Logged_In_As_Contact__c
            FROM Contact
            WHERE Id IN :helperContactIds
              AND Logged_In_As_Contact__c != null
        ];

        List<Contact> toUpdate = new List<Contact>();
        for (Contact c : helpers) {
            Id revokedTarget = helperToTarget.get(c.Id);
            if (c.Logged_In_As_Contact__c == revokedTarget) {
                c.Logged_In_As_Contact__c = null;
                c.Logged_In_As_Neighbourhood__c = null;
                toUpdate.add(c);
            }
        }

        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (Exception e) {
                FimbyLogger.error('FimbySupportRelationshipQueueable', 'execute', e);
            }
        }
    }
}
