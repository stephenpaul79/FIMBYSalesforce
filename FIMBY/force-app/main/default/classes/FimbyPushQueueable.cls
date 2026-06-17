/**
 * @description Queueable that delivers push notifications via the auth bridge and performs
 * all DML after confirmed delivery. Accepts payloads from FimbyPushBatchJob along with a
 * user-keyed map of notification IDs to mark Sent and user gate timestamps to stamp.
 *
 * Transport: POSTs the ≤100-payload slice as a single batch request
 * ({ "notifications": [...] }) to dodge the bridge's per-IP rate limit. The bridge
 * returns a per-entry results array ([{ user_id, accepted, reason? }]); we mark each
 * user's rows granularly:
 *   - accepted              → Sent
 *   - not accepted, quiet   → left Pending_Quiet (retried next cycle; no permanent drop)
 *   - not accepted, audible → Failed (user still gets the next audible buzz)
 * Gate timestamps are stamped only for accepted users, in a separate @future
 * transaction (avoids mixed DML with Notification__c).
 * If more than 100 payloads, chains to process the next batch.
 */
public without sharing class FimbyPushQueueable implements Queueable, Database.AllowsCallouts {

    private static final String PUSH_ENDPOINT = 'callout:FIMBY_Auth_Bridge/api/notifications/push';

    private List<FimbyPushNotificationService.PushPayload> payloads;
    private Map<Id, List<Id>> notifIdsByUser;
    private Map<Id, String> userGateUpdates;

    public FimbyPushQueueable(
        List<FimbyPushNotificationService.PushPayload> payloads,
        Map<Id, List<Id>> notifIdsByUser,
        Map<Id, String> userGateUpdates
    ) {
        this.payloads = payloads;
        this.notifIdsByUser = notifIdsByUser == null ? new Map<Id, List<Id>>() : notifIdsByUser;
        this.userGateUpdates = userGateUpdates == null ? new Map<Id, String>() : userGateUpdates;
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

        // Per-user quiet flag for this slice (decides Failed vs leave-on-failure).
        Map<Id, Boolean> quietByUser = new Map<Id, Boolean>();
        for (FimbyPushNotificationService.PushPayload p : currentBatch) {
            if (p.userId != null) {
                quietByUser.put(p.userId, p.quiet == true);
            }
        }

        // Map<userId, accepted?> from the bridge's per-entry response. An empty
        // map (HTTP error / parse failure) means "nothing accepted" — quiet rows
        // stay Pending_Quiet, audible rows go Failed; no all-or-nothing drop.
        Map<Id, Boolean> acceptedByUser = sendBatch(currentBatch);

        applyResults(quietByUser, acceptedByUser);
        scheduleGateStampJob(acceptedByUser);

        if (payloads.size() > 100) {
            chainRemainder();
        }
    }

    /**
     * POSTs the slice as one batch request and returns userId → accepted.
     * Returns an empty map on any transport/parse failure.
     */
    private Map<Id, Boolean> sendBatch(List<FimbyPushNotificationService.PushPayload> batch) {
        Map<Id, Boolean> acceptedByUser = new Map<Id, Boolean>();
        try {
            List<String> jsonPayloads = new List<String>();
            for (FimbyPushNotificationService.PushPayload payload : batch) {
                jsonPayloads.add(payload.toJson());
            }
            String body = '{"notifications":[' + String.join(jsonPayloads, ',') + ']}';

            HttpRequest req = new HttpRequest();
            req.setEndpoint(PUSH_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(30000);
            req.setBody(body);

            String pushSecret = getPushSecret();
            if (String.isNotBlank(pushSecret)) {
                req.setHeader('X-SF-Secret', pushSecret);
            }

            HttpResponse res = new Http().send(req);

            if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                FimbyLogger.warn('FimbyPushQueueable', 'sendBatch',
                    'Batch push failed: ' + res.getStatusCode() + ' ' + res.getBody());
                return acceptedByUser;
            }

            parseResults(res.getBody(), acceptedByUser);
        } catch (Exception e) {
            FimbyLogger.error('FimbyPushQueueable', 'sendBatch', e);
        }
        return acceptedByUser;
    }

    /**
     * Parses the bridge's per-entry results array into userId → accepted.
     * Shape: { ..., "results": [ { "user_id": "005...", "accepted": true } ] }.
     */
    private void parseResults(String responseBody, Map<Id, Boolean> acceptedByUser) {
        if (String.isBlank(responseBody)) {
            return;
        }
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            Object resultsRaw = parsed.get('results');
            if (!(resultsRaw instanceof List<Object>)) {
                return;
            }
            for (Object entryRaw : (List<Object>) resultsRaw) {
                if (!(entryRaw instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> entry = (Map<String, Object>) entryRaw;
                Object uid = entry.get('user_id');
                Object accepted = entry.get('accepted');
                if (uid == null) {
                    continue;
                }
                try {
                    acceptedByUser.put(Id.valueOf(String.valueOf(uid)), accepted == true);
                } catch (Exception ignored) {
                    // skip malformed user_id
                }
            }
        } catch (Exception e) {
            FimbyLogger.warn('FimbyPushQueueable', 'parseResults',
                'Could not parse batch results: ' + e.getMessage());
        }
    }

    /**
     * Marks each user's rows by delivery outcome. Iterates the current slice's
     * users (via quietByUser) so a chained job only touches its own rows.
     */
    private void applyResults(Map<Id, Boolean> quietByUser, Map<Id, Boolean> acceptedByUser) {
        List<Notification__c> toUpdate = new List<Notification__c>();
        for (Id userId : quietByUser.keySet()) {
            List<Id> ids = notifIdsByUser.get(userId);
            if (ids == null || ids.isEmpty()) {
                continue;
            }
            Boolean accepted = acceptedByUser.get(userId) == true;
            Boolean isQuiet = quietByUser.get(userId) == true;

            if (accepted) {
                for (Id nId : ids) {
                    toUpdate.add(new Notification__c(Id = nId, Push_Status__c = 'Sent'));
                }
            } else if (isQuiet) {
                // Leave as Pending_Quiet — retried next cycle. A transient blip
                // never permanently strands a quiet card.
                continue;
            } else {
                for (Id nId : ids) {
                    toUpdate.add(new Notification__c(
                        Id = nId,
                        Push_Status__c = 'Failed',
                        Push_Error__c = 'Batch push not accepted'
                    ));
                }
            }
        }
        if (toUpdate.isEmpty()) {
            return;
        }
        try {
            Database.update(toUpdate, false);
        } catch (Exception e) {
            FimbyLogger.error('FimbyPushQueueable', 'applyResults', e);
        }
    }

    /**
     * Stamps gates only for users whose push was accepted. A quiet ('QUIET')
     * gate type stamps observability only and never moves the doorbell.
     */
    private void scheduleGateStampJob(Map<Id, Boolean> acceptedByUser) {
        if (userGateUpdates == null || userGateUpdates.isEmpty()) {
            return;
        }
        Map<String, String> serializable = new Map<String, String>();
        for (Id userId : userGateUpdates.keySet()) {
            if (acceptedByUser.get(userId) == true) {
                serializable.put(String.valueOf(userId), userGateUpdates.get(userId));
            }
        }
        if (serializable.isEmpty()) {
            return;
        }
        try {
            if (Test.isRunningTest()) {
                System.runAs(new User(Id = UserInfo.getUserId())) {
                    FimbyPushGateStampAction.stampGatesSync(serializable);
                }
            } else {
                FimbyPushGateStampAction.stampGates(serializable);
            }
        } catch (Exception e) {
            FimbyLogger.error('FimbyPushQueueable', 'scheduleGateStampJob', e);
        }
    }

    private void chainRemainder() {
        List<FimbyPushNotificationService.PushPayload> remaining =
            new List<FimbyPushNotificationService.PushPayload>();
        for (Integer i = 100; i < payloads.size(); i++) {
            remaining.add(payloads[i]);
        }
        try {
            // Pass the full maps; the chained job only marks/stamps users in its
            // own slice (iteration is driven by its payloads, not the maps).
            System.enqueueJob(new FimbyPushQueueable(remaining, notifIdsByUser, userGateUpdates));
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
