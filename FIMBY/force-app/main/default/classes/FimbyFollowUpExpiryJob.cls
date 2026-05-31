/**
 * @description Scheduled job (weekly) that expires follow-ups older than 180 days.
 * Skips Restoration RecordType records. Recalculates blocked flags.
 */
public without sharing class FimbyFollowUpExpiryJob implements Schedulable {

    public void execute(SchedulableContext sc) {
        Datetime cutoff = System.now().addDays(-180);
        Id followUpRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c
            .getRecordTypeInfosByDeveloperName().get(FimbyConstants.RT_FOLLOW_UP)?.getRecordTypeId();

        List<Bulk_Buy_Follow_Up__c> toExpire = [
            SELECT Id, Reported_User__c
            FROM Bulk_Buy_Follow_Up__c
            WHERE RecordTypeId = :followUpRtId
            AND Status__c IN (:FimbyConstants.FOLLOWUP_NO_RESPONSE, :FimbyConstants.FOLLOWUP_ADMIN_CONFIRMED)
            AND Reported_Date__c <= :cutoff
            LIMIT 200
        ];

        if (toExpire.isEmpty()) { return; }

        Set<Id> affectedContactIds = new Set<Id>();
        for (Bulk_Buy_Follow_Up__c fu : toExpire) {
            fu.Status__c = FimbyConstants.FOLLOWUP_EXPIRED;
            affectedContactIds.add(fu.Reported_User__c);
        }

        update toExpire;
        FimbyBulkBuyController.recalculateBlockedFlagsForContacts(affectedContactIds);
    }
}
