/**
 * @description Handles sending push notifications to the FIMBY mobile app via the auth bridge.
 * Supports real-time (sendPushNotification) and batch-ready architecture (queuePushNotifications,
 * processPushNotificationQueue). Payload structure is consistent across modes.
 */
public with sharing class FimbyPushNotificationService {

    // Auth bridge endpoint for push notifications
    private static final String PUSH_ENDPOINT = 'callout:FIMBY_Auth_Bridge/api/notifications/push';

    // Custom Metadata or Custom Setting could toggle this
    // For now, default to real-time
    public static Boolean USE_BATCH_MODE = false;

    // ─────────────────────────────────────────────────────────────────────────────
    // NOTIFICATION TYPES - Define your notification categories here
    // ─────────────────────────────────────────────────────────────────────────────
    public enum NotificationType {
        MESSAGE,           // Direct messages
        NEEDS_OFFERS,      // Needs & Offers activity
        EVENTS,            // Event chat replies, RSVP changes, event reminders
        LIBRARY,           // Library lending activity
        STORY,             // New stories in neighbourhood
        REMINDER,          // Scheduled reminders (non-event)
        BULK_BUY,          // Bulk buy activity
        GENERAL,           // General/system notifications
        MODERATOR          // Moderator dashboard alerts
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // PAYLOAD WRAPPER - Consistent structure for real-time and batch
    // ─────────────────────────────────────────────────────────────────────────────
    /**
     * @description Payload wrapper for push notifications. Consistent structure for real-time and batch.
     */
    public class PushPayload {
        public String userId;           // Salesforce User ID (18 char)
        public String title;            // Notification title
        public String body;             // Notification body text
        public NotificationType notificationType;
        public Map<String, Object> data; // Additional data payload
        public Integer badge;           // Badge count (null = don't change)

        /**
         * @description Default constructor. Initializes empty data map.
         */
        public PushPayload() {
            this.data = new Map<String, Object>();
        }

        /**
         * @description Constructor with required push notification fields.
         * @param userId Salesforce User ID (18 char)
         * @param title Notification title
         * @param body Notification body text
         * @param notificationType Category for user preference checking
         */
        public PushPayload(String userId, String title, String body, NotificationType notificationType) {
            this();
            this.userId = userId;
            this.title = title;
            this.body = body;
            this.notificationType = notificationType;
        }

        // Convert to JSON for HTTP callout
        public String toJson() {
            Map<String, Object> payload = new Map<String, Object>{
                'user_id' => this.userId,
                'title' => this.title,
                'body' => this.body,
                'notification_type' => this.notificationType?.name(),
                'data' => this.data
            };

            if (this.badge != null) {
                payload.put('badge', this.badge);
            }

            return JSON.serialize(payload);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // REAL-TIME SENDING (via Queueable)
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Send a push notification asynchronously via Queueable.
     * Checks user preferences before enqueuing.
     */
    public static void sendPushNotification(PushPayload payload) {
        if (!isNotificationEnabled(payload.userId, payload.notificationType)) {
            return;
        }

        if (USE_BATCH_MODE) {
            queuePushNotification(payload);
        } else {
            enqueuePayloads(new List<String>{ payload.toJson() });
        }
    }

    /**
     * Send multiple push notifications in a single Queueable job.
     * Filters by user preferences, then sends all eligible payloads
     * in one async job instead of one @future per recipient.
     */
    public static void sendPushNotifications(List<PushPayload> payloads) {
        if (USE_BATCH_MODE) {
            queuePushNotifications(payloads);
            return;
        }

        Set<String> userIds = new Set<String>();
        for (PushPayload payload : payloads) {
            if (String.isNotBlank(payload.userId)) {
                userIds.add(payload.userId);
            }
        }
        Map<Id, User> prefsById = getNotificationPreferences(userIds);

        List<String> eligibleJsonPayloads = new List<String>();
        for (PushPayload payload : payloads) {
            if (isEnabledFromMap(prefsById, payload.userId, payload.notificationType)) {
                eligibleJsonPayloads.add(payload.toJson());
            }
        }

        if (!eligibleJsonPayloads.isEmpty()) {
            enqueuePayloads(eligibleJsonPayloads);
        }
    }

    /**
     * Enqueue payloads for async delivery. Falls back to synchronous
     * sending if already inside a Queueable context (chaining limit).
     */
    private static void enqueuePayloads(List<String> jsonPayloads) {
        if (System.isQueueable() || System.isFuture() || System.isBatch()) {
            return;
        }
        try {
            System.enqueueJob(new FimbyPushQueueable(jsonPayloads));
        } catch (Exception e) {
            FimbyLogger.warn('FimbyPushNotificationService', 'enqueuePayloads',
                'Failed to enqueue push job: ' + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // QUEUEABLE — replaces the old @future pattern
    // Sends push payloads in a single async job (max per job: FimbySettings.pushNotificationBatchSize()).
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * @description Queueable job that sends push payloads to the auth bridge. Attaches finalizer for error logging.
     */
    public class FimbyPushQueueable implements Queueable, Database.AllowsCallouts, System.Finalizer {
        private List<String> jsonPayloads;

        /**
         * @description Constructs the queueable with pre-serialized JSON payloads.
         * @param jsonPayloads List of JSON strings to send
         */
        public FimbyPushQueueable(List<String> jsonPayloads) {
            this.jsonPayloads = jsonPayloads;
        }

        /**
         * @description Sends each payload to the auth bridge via HTTP POST. Attaches finalizer for error handling.
         * @param ctx Queueable context
         */
        public void execute(QueueableContext ctx) {
            System.attachFinalizer(this);
            String pushSecret = getPushSecret();
            Http http = new Http();

            for (String payloadJson : jsonPayloads) {
                try {
                    HttpRequest req = new HttpRequest();
                    req.setEndpoint(PUSH_ENDPOINT);
                    req.setMethod('POST');
                    req.setHeader('Content-Type', 'application/json');
                    req.setTimeout(30000);
                    req.setBody(payloadJson);

                    if (String.isNotBlank(pushSecret)) {
                        req.setHeader('X-SF-Secret', pushSecret);
                    }

                    HttpResponse res = http.send(req);

                    if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
                        FimbyLogger.warn('FimbyPushQueueable', 'execute',
                            'Push notification failed: ' + res.getStatusCode() + ' ' + res.getBody());
                    }
                } catch (Exception e) {
                    FimbyLogger.error('FimbyPushQueueable', 'execute', e);
                }
            }
        }

        /**
         * @description Finalizer callback. Logs unhandled exceptions from the queueable execution.
         * @param fc Finalizer context with result and exception info
         */
        public void execute(System.FinalizerContext fc) {
            switch on fc?.getResult() {
                when UNHANDLED_EXCEPTION {
                    FimbyLogger.error('FimbyPushQueueable', 'finalizer',
                        new System.CalloutException(
                            'Unhandled exception in push queueable: ' + fc.getException()?.getMessage()
                        ));
                }
                when else {
                    // Success — no action needed
                }
            }
        }
    }

    /**
     * Get the push secret from Custom Label
     * Setup → Custom Labels → SF_PUSH_SECRET
     */
    private static String getPushSecret() {
        try {
            return System.Label.SF_PUSH_SECRET;
        } catch (Exception e) {
            FimbyLogger.warn('FimbyPushNotificationService', 'getPushSecret',
                'SF_PUSH_SECRET label not found');
            return null;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // BATCH MODE - Queue notifications for bulk processing
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Queue a single notification for batch processing
     * Creates a Platform Event or stores in a staging object
     */
    public static void queuePushNotification(PushPayload payload) {
        queuePushNotifications(new List<PushPayload>{ payload });
    }

    /**
     * Queue multiple notifications for batch processing
     * For MVP: Store in a custom object. For scale: Use Platform Events.
     */
    public static void queuePushNotifications(List<PushPayload> payloads) {
        // TODO: Implement when switching to batch mode
        // Option 1: Insert into Push_Notification_Queue__c custom object
        // Option 2: Publish FIMBY_Push_Event__e Platform Event

        // Placeholder for future implementation:
        // List<Push_Notification_Queue__c> queueRecords = new List<Push_Notification_Queue__c>();
        // for (PushPayload payload : payloads) {
        //     queueRecords.add(new Push_Notification_Queue__c(
        //         User__c = payload.userId,
        //         Payload__c = payload.toJson(),
        //         Status__c = 'Pending'
        //     ));
        // }
        // insert queueRecords;
    }

    /**
     * Process queued notifications (call from Scheduled Apex)
     * Sends batch of notifications to auth bridge in a single callout
     */
    public static void processPushNotificationQueue() {
        // TODO: Implement when switching to batch mode
        // 1. Query pending Push_Notification_Queue__c records
        // 2. Group by user and send batch to auth bridge
        // 3. Update records as Sent or Failed
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // USER PREFERENCE HELPERS
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Check if a user has notifications enabled for a specific type.
     * Single-record convenience method — performs one SOQL query.
     * For bulk checks, use getNotificationPreferences() + isEnabledFromMap().
     */
    public static Boolean isNotificationEnabled(String userId, NotificationType notificationType) {
        try {
            Map<Id, User> prefs = getNotificationPreferences(new Set<String>{ userId });
            return isEnabledFromMap(prefs, userId, notificationType);
        } catch (Exception e) {
            FimbyLogger.error('FimbyPushNotificationService', 'isNotificationEnabled', e);
            return true;
        }
    }

    /**
     * Bulk-query notification preferences for a set of user IDs.
     * Returns a map of User ID → User with all push preference fields.
     */
    public static Map<Id, User> getNotificationPreferences(Set<String> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new Map<Id, User>();
        }
        return new Map<Id, User>([
            SELECT Id,
                   Push_Notifications_Enabled__c,
                   Push_Messages__c,
                   Push_Needs_Offers__c,
                   Push_Events__c,
                   Push_Library__c,
                   Push_Stories__c,
                   Push_Reminders__c,
                   Push_Bulk_Buy__c
            FROM User
            WHERE Id IN :userIds
        ]);
    }

    /**
     * Check notification preference from a pre-queried map (no SOQL).
     * Defaults to enabled if the user is not found in the map.
     */
    public static Boolean isEnabledFromMap(Map<Id, User> prefsById, String userId, NotificationType notificationType) {
        if (String.isBlank(userId)) {
            return false;
        }
        Id uid;
        try {
            uid = Id.valueOf(userId);
        } catch (Exception e) {
            return false;
        }
        User u = prefsById.get(uid);
        if (u == null) {
            return true;
        }
        if (u.Push_Notifications_Enabled__c == false) {
            return false;
        }
        switch on notificationType {
            when MESSAGE {
                return u.Push_Messages__c != false;
            }
            when NEEDS_OFFERS {
                return u.Push_Needs_Offers__c != false;
            }
            when EVENTS {
                return u.Push_Events__c != false;
            }
            when LIBRARY {
                return u.Push_Library__c != false;
            }
            when STORY {
                return u.Push_Stories__c != false;
            }
            when REMINDER {
                return u.Push_Reminders__c != false;
            }
            when BULK_BUY {
                return u.Push_Bulk_Buy__c != false;
            }
            when GENERAL, MODERATOR {
                return true;
            }
            when else {
                return true;
            }
        }
    }

    /**
     * Get users in a neighbourhood who have a specific notification type enabled
     */
    public static List<User> getNotifiableUsers(String neighbourhoodAccountId, NotificationType notificationType) {
        String fieldToCheck;
        switch on notificationType {
            when MESSAGE { fieldToCheck = 'Push_Messages__c'; }
            when NEEDS_OFFERS { fieldToCheck = 'Push_Needs_Offers__c'; }
            when EVENTS { fieldToCheck = 'Push_Events__c'; }
            when LIBRARY { fieldToCheck = 'Push_Library__c'; }
            when STORY { fieldToCheck = 'Push_Stories__c'; }
            when REMINDER { fieldToCheck = 'Push_Reminders__c'; }
            when BULK_BUY { fieldToCheck = 'Push_Bulk_Buy__c'; }
            when else { fieldToCheck = 'Push_Messages__c'; }
        }

        String query = 'SELECT Id, Name, ContactId ' +
                      'FROM User ' +
                      'WHERE Neighbourhood_Account_ID__c = :neighbourhoodAccountId ' +
                      'AND IsActive = true ' +
                      'AND Push_Notifications_Enabled__c = true ' +
                      'AND ' + fieldToCheck + ' != false';

        return Database.query(query);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // CONVENIENCE METHODS - Common notification scenarios
    // ─────────────────────────────────────────────────────────────────────────────

    /**
     * Send a message notification to a specific user
     */
    public static void notifyNewMessage(String recipientUserId, String senderName, String messagePreview) {
        PushPayload payload = new PushPayload(
            recipientUserId,
            'New message from ' + senderName,
            messagePreview.length() > 100 ? messagePreview.substring(0, 100) + '...' : messagePreview,
            NotificationType.MESSAGE
        );
        payload.badge = 1;
        // Client-side route allowlist keys on channelId -> /messages vs /notifications
        payload.data.put('channelId', 'messages');

        sendPushNotification(payload);
    }

    /**
     * Notify about library item request/return
     */
    public static void notifyLibraryActivity(String ownerUserId, String borrowerName, String itemName, String activity) {
        String title;
        String body;

        if (activity == 'REQUEST') {
            title = 'Lending request';
            body = borrowerName + ' wants to borrow your ' + itemName;
        } else if (activity == 'RETURN') {
            title = 'Item returned';
            body = borrowerName + ' returned ' + itemName;
        } else {
            title = 'Library activity';
            body = itemName + ': ' + activity;
        }

        PushPayload payload = new PushPayload(ownerUserId, title, body, NotificationType.LIBRARY);

        sendPushNotification(payload);
    }
}