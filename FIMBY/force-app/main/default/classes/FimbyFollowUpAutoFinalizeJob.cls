/**
 * @description Scheduled job (daily) that auto-confirms pending follow-ups after 48 hours.
 * Sets follow-up to No_Response, Response to No_Follow_Through, recalculates blocked flags.
 */
public without sharing class FimbyFollowUpAutoFinalizeJob implements Schedulable {

    public void execute(SchedulableContext sc) {
        List<Bulk_Buy_Follow_Up__c> pending = [
            SELECT Id, Reservation__c, Reported_User__c, Reported_User__r.FirstName,
                   Reporter__c, Checkin_Conversation__c, Auto_Finalize_Date__c
            FROM Bulk_Buy_Follow_Up__c
            WHERE Status__c = :FimbyConstants.FOLLOWUP_PENDING
            AND Auto_Finalize_Date__c <= :System.now()
            AND RecordType.DeveloperName = :FimbyConstants.RT_FOLLOW_UP
            LIMIT 200
        ];

        if (pending.isEmpty()) { return; }

        Set<Id> affectedContactIds = new Set<Id>();
        List<Response__c> responsesToUpdate = new List<Response__c>();

        for (Bulk_Buy_Follow_Up__c fu : pending) {
            fu.Status__c = FimbyConstants.FOLLOWUP_NO_RESPONSE;
            fu.Resolution_Date__c = System.now();

            responsesToUpdate.add(new Response__c(
                Id = fu.Reservation__c,
                Status__c = FimbyConstants.RESPONSE_NO_FOLLOW_THROUGH
            ));

            affectedContactIds.add(fu.Reported_User__c);

            if (fu.Checkin_Conversation__c != null) {
                try {
                    FimbyGroupConversationController.sendSystemMessage(
                        fu.Checkin_Conversation__c,
                        'This has been automatically recorded after 48 hours without a response.',
                        FimbyConstants.SYS_MSG_STATUS_CHANGE
                    );
                } catch (Exception e) {
                    FimbyLogger.error('FimbyFollowUpAutoFinalizeJob', 'execute-sysMsg', e, fu.Id);
                }
            }

            String reserverName = fu.Reported_User__r?.FirstName ?? 'A neighbour';
            try {
                FimbyNotificationService.createNotification(
                    fu.Reporter__c,
                    FimbyConstants.NOTIF_FOLLOW_UP_RESOLVED,
                    'didn\'t respond within 48 hours',
                    'No response was received. This has been recorded.',
                    fu.Checkin_Conversation__c,
                    'Conversation__c',
                    FimbySettings.getUrl('Conversation', String.valueOf(fu.Checkin_Conversation__c)),
                    reserverName,
                    false,
                    fu.Reported_User__c
                );
            } catch (Exception e) {
                FimbyLogger.error('FimbyFollowUpAutoFinalizeJob', 'execute-notif', e, fu.Id);
            }
        }

        update pending;
        if (!responsesToUpdate.isEmpty()) { update responsesToUpdate; }

        FimbyBulkBuyController.recalculateBlockedFlagsForContacts(affectedContactIds);
    }
}
