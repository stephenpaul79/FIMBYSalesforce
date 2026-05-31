/**
 * @description Scheduled job (daily) that auto-locks bulk buys after the configurable window.
 * Includes follow-up-aware completion: retries if Pending, escalates after grace, allows
 * completion with Escalated follow-ups (Responses stay Reserved for admin resolution).
 */
public without sharing class FimbyBulkBuyAutoLockJob implements Schedulable {

    public void execute(SchedulableContext sc) {
        Id bulkBuyRtId = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get(FimbyConstants.RT_BULK_BUY)?.getRecordTypeId();

        List<Needs_Offers__c> candidates = [
            SELECT Id, Name, Group_Conversation__c, Pickup_Notified_Date__c, Auto_Lock_Days__c, Posted_By__c
            FROM Needs_Offers__c
            WHERE RecordTypeId = :bulkBuyRtId
            AND Status__c = :FimbyConstants.NEEDS_OFFERS_PICKUP_READY
            AND Pickup_Notified_Date__c != null
            LIMIT 200
        ];

        for (Needs_Offers__c post : candidates) {
            Integer lockDays = post.Auto_Lock_Days__c != null ? Integer.valueOf(post.Auto_Lock_Days__c) : 7;
            Datetime lockDate = post.Pickup_Notified_Date__c.addDays(lockDays);
            Datetime graceDate = lockDate.addDays(7);

            if (System.now() < lockDate) { continue; }

            List<Bulk_Buy_Follow_Up__c> activeFollowUps = [
                SELECT Id, Status__c
                FROM Bulk_Buy_Follow_Up__c
                WHERE Bulk_Buy__c = :post.Id
                AND Status__c IN (:FimbyConstants.FOLLOWUP_PENDING, :FimbyConstants.FOLLOWUP_ESCALATED)
            ];

            Boolean hasPending = false;
            for (Bulk_Buy_Follow_Up__c fu : activeFollowUps) {
                if (fu.Status__c == FimbyConstants.FOLLOWUP_PENDING) {
                    hasPending = true;
                    break;
                }
            }

            if (hasPending && System.now() < graceDate) {
                continue;
            }

            if (hasPending && System.now() >= graceDate) {
                for (Bulk_Buy_Follow_Up__c fu : activeFollowUps) {
                    if (fu.Status__c == FimbyConstants.FOLLOWUP_PENDING) {
                        fu.Status__c = FimbyConstants.FOLLOWUP_ESCALATED;
                        if (fu.Id != null) {
                            try {
                                Bulk_Buy_Follow_Up__c full = [
                                    SELECT Checkin_Conversation__c FROM Bulk_Buy_Follow_Up__c WHERE Id = :fu.Id
                                ];
                                if (full.Checkin_Conversation__c != null) {
                                    FimbyGroupConversationController.sendSystemMessage(
                                        full.Checkin_Conversation__c,
                                        'Escalated to admin for review -- auto-lock grace period reached.',
                                        FimbyConstants.SYS_MSG_STATUS_CHANGE
                                    );
                                }
                            } catch (Exception e) {
                                FimbyLogger.error('FimbyBulkBuyAutoLockJob', 'escalate-sysMsg', e, fu.Id);
                            }
                        }
                    }
                }
                update activeFollowUps;
            }

            FimbyBulkBuyController.completePost(post);
        }
    }
}
