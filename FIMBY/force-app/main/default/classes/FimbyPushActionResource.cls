/**
 * @description Apex REST endpoint for push-notification quick actions performed
 * from the device WITHOUT opening the app. Today it serves "mark read".
 *
 * URL: /services/apexrest/fimby/push-action
 * Method: POST  Body: { "action": "mark_read", "notificationId": "a0X..." }
 *
 * Auth: the auth bridge calls this with a Salesforce session minted (JWT Bearer)
 * for the authenticated app user, so the running user IS the recipient. We still
 * dual-check ownership server-side (notification-contract §9): the caller may
 * mark a notification read only when it belongs to their acting-as OR real
 * identity. A "mark_read" on a Message notification also marks the underlying
 * conversation read so the in-app DM list and tab badge stay honest.
 *
 * Runs `with sharing`; no field-level data is returned beyond a small status.
 */
@RestResource(urlMapping='/fimby/push-action/*')
global with sharing class FimbyPushActionResource {

    @HttpPost
    global static void handle() {
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');
        try {
            String body = RestContext.request.requestBody != null
                ? RestContext.request.requestBody.toString() : '';
            Map<String, Object> payload = String.isBlank(body)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(body);

            String action = (String) payload.get('action');
            String notificationId = (String) payload.get('notificationId');

            if (action == null) {
                action = 'mark_read'; // default action
            }
            if (action != 'mark_read') {
                respond(res, 400, 'unsupported_action');
                return;
            }
            if (String.isBlank(notificationId)) {
                respond(res, 400, 'missing_notification_id');
                return;
            }

            Boolean ok = new ActionHelper().markReadInternal(notificationId);
            if (ok) {
                respond(res, 200, 'ok');
            } else {
                // Not found / not owned / already read — all non-fatal. 200 so the
                // device treats the badge update as done and does not retry.
                respond(res, 200, 'noop');
            }
        } catch (Exception e) {
            FimbyLogger.error('FimbyPushActionResource', 'handle', e);
            respond(res, 500, 'server_error');
        }
    }

    private static void respond(RestResponse res, Integer code, String status) {
        res.statusCode = code;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'status' => status }));
    }

    /**
     * @description Elevated helper. `without sharing` so the recipient can always
     * mark their own notification read even if record-sharing wouldn't surface it;
     * ownership is enforced explicitly via the dual-check below.
     */
    private without sharing class ActionHelper {

        /**
         * Marks the notification read (and, for Message notifications, the
         * underlying conversation). Returns false on not-found / not-owned /
         * already-read so the caller can no-op.
         */
        public Boolean markReadInternal(String notificationId) {
            Id notifId;
            try {
                notifId = Id.valueOf(notificationId);
            } catch (Exception e) {
                return false;
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            if (identity == null) {
                return false;
            }
            Id actingAsId = identity.actingAsContactId;
            Id realId = identity.contact != null ? identity.contact.Id : null;

            List<Notification__c> notifs = [
                SELECT Id, Contact__c, Type__c, Read_Date__c, Related_Record_Id__c
                FROM Notification__c
                WHERE Id = :notifId
                LIMIT 1
            ];
            if (notifs.isEmpty()) {
                return false;
            }
            Notification__c notif = notifs[0];

            // Dual-check ownership (notification-contract §9): the recipient
            // identity must match either the acting-as or the real contact.
            Boolean owned = (notif.Contact__c != null)
                && (notif.Contact__c == actingAsId || notif.Contact__c == realId);
            if (!owned) {
                return false;
            }

            Boolean didWork = false;

            if (notif.Read_Date__c == null) {
                notif.Read_Date__c = Datetime.now();
                update notif;
                didWork = true;
            }

            // For a DM notification, also mark the conversation read so the
            // in-app thread + tab badge agree with the cleared push.
            if (notif.Type__c == FimbyConstants.NOTIF_MESSAGE
                && notif.Related_Record_Id__c != null) {
                didWork = markConversationRead(notif.Related_Record_Id__c, notif.Contact__c) || didWork;
            }

            return didWork;
        }

        /**
         * Marks unread inbound messages in the conversation read and resets the
         * recipient's unread counter. Recipient is the notification's Contact__c
         * (the represented identity that received the DM).
         */
        private Boolean markConversationRead(Id conversationId, Id recipientContactId) {
            List<Conversation__c> convs = [
                SELECT Id, Participant_1__c, Participant_2__c,
                       Participant_1_Unread_Count__c, Participant_2_Unread_Count__c
                FROM Conversation__c
                WHERE Id = :conversationId
                LIMIT 1
            ];
            if (convs.isEmpty()) {
                return false;
            }
            Conversation__c conv = convs[0];
            Boolean isP1 = (conv.Participant_1__c == recipientContactId);
            Boolean isP2 = (conv.Participant_2__c == recipientContactId);
            if (!isP1 && !isP2) {
                return false;
            }

            Boolean didWork = false;

            List<Message__c> unread = [
                SELECT Id, Read_Date__c
                FROM Message__c
                WHERE Conversation__c = :conversationId
                  AND Sender__c != :recipientContactId
                  AND Read_Date__c = null
            ];
            if (!unread.isEmpty()) {
                Datetime now = Datetime.now();
                for (Message__c m : unread) {
                    m.Read_Date__c = now;
                }
                update unread;
                didWork = true;
            }

            Boolean counterChanged = false;
            if (isP1 && conv.Participant_1_Unread_Count__c != 0) {
                conv.Participant_1_Unread_Count__c = 0;
                counterChanged = true;
            } else if (isP2 && conv.Participant_2_Unread_Count__c != 0) {
                conv.Participant_2_Unread_Count__c = 0;
                counterChanged = true;
            }
            if (counterChanged) {
                update conv;
                didWork = true;
            }

            return didWork;
        }
    }
}
