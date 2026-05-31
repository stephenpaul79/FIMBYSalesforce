/**
 * @description Queueable that delivers push notifications via the auth bridge and performs
 * all DML after confirmed delivery. Accepts payloads from FimbyPushBatchJob along with
 * notification IDs to mark Sent and user gate timestamps to stamp.
 *
 * On success: marks Notification__c records as Sent, stamps gate timestamps on User.
 * On failure: marks as Failed with error detail; does NOT stamp gates (gate stays open).
 * If more than 100 payloads, chains to process the next batch via finalizer.
 */
public without sharing class FimbyPushQueueable implements Queueable, Database.AllowsCallouts {

    private static final String PUSH_ENDPOINT = 'callout:FIMBY_Auth_Bridge/api/notifications/push';

    private List<FimbyPushNotificationService.PushPayload> payloads;
    private List<Id> notifIdsToMarkSent;
    private Map<Id, String> userGateUpdates;

    public FimbyPushQueueable(
        List<FimbyPushNotificationService.PushPayload> payloads,
        List<Id> notifIdsToMarkSent,
        Map<Id, String> userGateUpdates
    ) {
        this.payloads = payloads;
        this.notifIdsToMarkSent = notifIdsToMarkSent;
        this.userGateUpdates = userGateUpdates;
    }

    public void execute(QueueableContext ctx) {
        if (payloads == null || payloads.isEmpty()) {
            return;
        }

        Integer batchSize = Math.min(payloads.size(), 100);
        List<FimbyPushNotificationService.PushPayload> currentBatch =
            new List<FimbyPushNotificationService.PushPayload>();
        for (Integer i = 0; i < batchSize; i++) {
            currentBatch.add(payloads[i]);
        }

        Boolean success = sendBatch(currentBatch);

        if (success) {
            markNotificationsSent();
            stampGateTimestamps();
        } else {
            markNotificationsFailed('Batch callout failed');
        }

        if (payloads.size() > 100) {
            chainRemainder();
        }
    }

    private Boolean sendBatch(List<FimbyPushNotificationService.PushPayload> batch) {
        String pushSecret = getPushSecret();
        Http http = new Http();

        for (FimbyPushNotificationService.PushPayload payload : batch) {
            try {
                HttpRequest req = new HttpRequest();
                req.setEndpoint(PUSH_ENDPOINT);
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/json');
                req.setTimeout(30000);
                req.setBody(payload.toJson());

                if (String.isNotBlank(pushSecret)) {
                    req.setHeader('X-SF-Secret', pushSecret);
                }

                HttpResponse res = http.send(req);

                if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                    FimbyLogger.warn('FimbyPushQueueable', 'sendBatch',
                        'Push failed for user ' + payload.userId + ': ' +
                        res.getStatusCode() + ' ' + res.getBody());
                    return false;
                }
            } catch (Exception e) {
                FimbyLogger.error('FimbyPushQueueable', 'sendBatch', e);
                return false;
            }
        }
        return true;
    }

    private void markNotificationsSent() {
        if (notifIdsToMarkSent == null || notifIdsToMarkSent.isEmpty()) {
            return;
        }
        List<Notification__c> toUpdate = new List<Notification__c>();
        for (Id nId : notifIdsToMarkSent) {
            toUpdate.add(new Notification__c(Id = nId, Push_Status__c = 'Sent'));
        }
        try {
            Database.update(toUpdate, false);
        } catch (Exception e) {
            FimbyLogger.error('FimbyPushQueueable', 'markNotificationsSent', e);
        }
    }

    private void markNotificationsFailed(String errorMsg) {
        if (notifIdsToMarkSent == null || notifIdsToMarkSent.isEmpty()) {
            return;
        }
        String truncated = String.isNotBlank(errorMsg) && errorMsg.length() > 255
            ? errorMsg.substring(0, 255) : errorMsg;
        List<Notification__c> toUpdate = new List<Notification__c>();
        for (Id nId : notifIdsToMarkSent) {
            toUpdate.add(new Notification__c(
                Id = nId,
                Push_Status__c = 'Failed',
                Push_Error__c = truncated
            ));
        }
        try {
            Database.update(toUpdate, false);
        } catch (Exception e) {
            FimbyLogger.error('FimbyPushQueueable', 'markNotificationsFailed', e);
        }
    }

    private void stampGateTimestamps() {
        if (userGateUpdates == null || userGateUpdates.isEmpty()) {
            return;
        }
        Datetime now = Datetime.now();
        List<User> usersToUpdate = new List<User>();
        for (Id userId : userGateUpdates.keySet()) {
            String gateType = userGateUpdates.get(userId);
            User u = new User(Id = userId);
            if (gateType == 'DM' || gateType == 'BOTH') {
                u.Last_DM_Push_At__c = now;
            }
            if (gateType == 'ACTIVITY' || gateType == 'BOTH') {
                u.Last_Activity_Push_At__c = now;
            }
            usersToUpdate.add(u);
        }
        try {
            Database.update(usersToUpdate, false);
        } catch (Exception e) {
            FimbyLogger.error('FimbyPushQueueable', 'stampGateTimestamps', e);
        }
    }

    private void chainRemainder() {
        List<FimbyPushNotificationService.PushPayload> remaining =
            new List<FimbyPushNotificationService.PushPayload>();
        for (Integer i = 100; i < payloads.size(); i++) {
            remaining.add(payloads[i]);
        }
        try {
            System.enqueueJob(new FimbyPushQueueable(
                remaining,
                new List<Id>(),
                new Map<Id, String>()
            ));
        } catch (Exception e) {
            FimbyLogger.error('FimbyPushQueueable', 'chainRemainder', e);
        }
    }

    private static String getPushSecret() {
        try {
            return System.Label.SF_PUSH_SECRET;
        } catch (Exception e) {
            return null;
        }
    }
}
