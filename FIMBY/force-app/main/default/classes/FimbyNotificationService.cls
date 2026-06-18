/**
 * @description Static utility class for creating in-app notifications with creation-time
 * push gate checks. Every event creates its own Notification__c row — push consolidation
 * is handled at the batch layer (FimbyPushBatchJob sends one generic push per user per
 * gate). Gate logic determines whether Push_Status__c should be 'Pending' (eligible for
 * the batch push job) or null (in-app only).
 */
public without sharing class FimbyNotificationService {

    // Event-related notification types now route to the EVENTS push category,
    // which is gated by User.Push_Events__c instead of Push_Needs_Offers__c /
    // Push_Reminders__c. Migration note: previously a user who silenced
    // Asks & Offers (Push_Needs_Offers__c = false) also silenced event chat;
    // after this change those users will start receiving event chat unless
    // they opt out separately via the Events toggle. Deliberate decision per
    // prelaunch product alignment plan A4.
    private static final Map<String, FimbyPushNotificationService.NotificationType> PUSH_TYPE_MAP =
        new Map<String, FimbyPushNotificationService.NotificationType>{
            FimbyConstants.NOTIF_RESPONSE           => FimbyPushNotificationService.NotificationType.NEEDS_OFFERS,
            FimbyConstants.NOTIF_COMMENT            => FimbyPushNotificationService.NotificationType.STORY,
            FimbyConstants.NOTIF_LENDING_REQUEST    => FimbyPushNotificationService.NotificationType.LIBRARY,
            FimbyConstants.NOTIF_LOAN_APPROVED      => FimbyPushNotificationService.NotificationType.LIBRARY,
            FimbyConstants.NOTIF_EXTENSION_REQUEST  => FimbyPushNotificationService.NotificationType.LIBRARY,
            FimbyConstants.NOTIF_EXTENSION_APPROVED => FimbyPushNotificationService.NotificationType.LIBRARY,
            FimbyConstants.NOTIF_OVERDUE_REMINDER   => FimbyPushNotificationService.NotificationType.REMINDER,
            FimbyConstants.NOTIF_ITEM_RETURNED      => FimbyPushNotificationService.NotificationType.LIBRARY,
            FimbyConstants.NOTIF_BULK_BUY_RESERVATION => FimbyPushNotificationService.NotificationType.BULK_BUY,
            FimbyConstants.NOTIF_BULK_BUY_STATUS      => FimbyPushNotificationService.NotificationType.BULK_BUY,
            FimbyConstants.NOTIF_BULK_BUY_PICKUP      => FimbyPushNotificationService.NotificationType.BULK_BUY,
            FimbyConstants.NOTIF_MESSAGE            => FimbyPushNotificationService.NotificationType.MESSAGE,
            FimbyConstants.NOTIF_THANKS_RECEIVED    => FimbyPushNotificationService.NotificationType.MESSAGE,
            FimbyConstants.NOTIF_RESPONSE_REPLY     => FimbyPushNotificationService.NotificationType.MESSAGE,
            FimbyConstants.NOTIF_EVENT_CHAT         => FimbyPushNotificationService.NotificationType.EVENTS,
            FimbyConstants.NOTIF_EVENT_REMINDER     => FimbyPushNotificationService.NotificationType.EVENTS,
            FimbyConstants.NOTIF_EVENT_SERIES_NEW_OCCURRENCE => FimbyPushNotificationService.NotificationType.EVENTS,
            FimbyConstants.NOTIF_MODERATOR          => FimbyPushNotificationService.NotificationType.MODERATOR,
            FimbyConstants.NOTIF_VOUCH_REQUEST_RECEIVED => FimbyPushNotificationService.NotificationType.MESSAGE,
            FimbyConstants.NOTIF_VOUCH_REQUEST_REMINDER => FimbyPushNotificationService.NotificationType.MESSAGE,
            FimbyConstants.NOTIF_VOUCH_APPROVED         => FimbyPushNotificationService.NotificationType.MESSAGE,
            FimbyConstants.NOTIF_VOUCH_DECLINED         => FimbyPushNotificationService.NotificationType.MESSAGE,
            FimbyConstants.NOTIF_VOUCH_REVOKED          => FimbyPushNotificationService.NotificationType.MESSAGE,
            FimbyConstants.NOTIF_VOUCHER_PAUSED         => FimbyPushNotificationService.NotificationType.MESSAGE,
            FimbyConstants.NOTIF_REFRESH_REMINDER       => FimbyPushNotificationService.NotificationType.NEEDS_OFFERS
        };

    // Push notifications NEVER bypass user preferences. A user who disables the
    // master Push_Notifications_Enabled__c toggle (or a per-category toggle)
    // receives no push of any kind — urgent and safety messaging rides the email
    // lane instead, which is where opt-out is intentionally not honoured.
    //
    // This set is therefore EMPTY in production. The bypass code path in
    // shouldQueue() and the addSecurityBypassPushTypeForTest() hook are retained
    // as forward infrastructure so the path stays exercised, but no real
    // notification type may be added here. Account/safety bypass lives only on
    // the email side — see FimbyEmailAlertService.SECURITY_BYPASS_TYPES, which
    // still carries the vouch lifecycle types so urgent vouch info reaches the
    // user by email even when push is silenced.
    @TestVisible
    private static final Set<String> SECURITY_BYPASS_PUSH_TYPES = new Set<String>();

    @TestVisible
    private static final Map<String, String> GATE_TYPE_MAP = new Map<String, String>();
    static {
        for (String notifType : PUSH_TYPE_MAP.keySet()) {
            FimbyPushNotificationService.NotificationType pushType = PUSH_TYPE_MAP.get(notifType);
            GATE_TYPE_MAP.put(notifType, pushType == FimbyPushNotificationService.NotificationType.MESSAGE ? 'DM' : 'ACTIVITY');
        }
    }

    /**
     * Create a single notification with creation-time push gate check.
     */
    public static void createNotification(
        Id recipientContactId,
        String type,
        String title,
        String body,
        Id relatedRecordId,
        String relatedRecordType,
        String actionUrl,
        String actorName
    ) {
        createNotification(recipientContactId, type, title, body, relatedRecordId, relatedRecordType, actionUrl, actorName, false, null);
    }

    /**
     * Create a single notification with optional push suppression.
     * When skipPush is true, the notification is in-app only (Push_Status__c stays null).
     */
    public static void createNotification(
        Id recipientContactId,
        String type,
        String title,
        String body,
        Id relatedRecordId,
        String relatedRecordType,
        String actionUrl,
        String actorName,
        Boolean skipPush
    ) {
        createNotification(recipientContactId, type, title, body, relatedRecordId, relatedRecordType, actionUrl, actorName, skipPush, null);
    }

    /**
     * Create a single notification with optional push suppression and a structured
     * actor Contact reference. actorContactId is the represented (acting-as) Contact
     * that Actor_Name__c describes — it drives the card avatar and bold actor name.
     * Null for system/FIMBY/team messages. Backward compatible (null allowed).
     */
    public static void createNotification(
        Id recipientContactId,
        String type,
        String title,
        String body,
        Id relatedRecordId,
        String relatedRecordType,
        String actionUrl,
        String actorName,
        Boolean skipPush,
        Id actorContactId
    ) {
        if (recipientContactId == null || String.isBlank(type) || String.isBlank(title)) {
            return;
        }

        User recipientUser = (skipPush == true) ? null : queryRecipientUser(recipientContactId);

        Notification__c notif = new Notification__c(
            Contact__c = recipientContactId,
            Type__c = type,
            Title__c = title,
            Body__c = body,
            Related_Record_Id__c = (relatedRecordId != null) ? String.valueOf(relatedRecordId) : null,
            Related_Record_Type__c = relatedRecordType,
            Action_URL__c = actionUrl,
            Actor_Name__c = actorName,
            Actor_Contact__c = actorContactId
        );

        notif.Push_Status__c = (skipPush == true) ? null : shouldQueue(type, recipientUser);
        notif.Email_Status__c = FimbyEmailAlertService.shouldSendEmail(type, recipientUser);

        try {
            Database.insert(notif, true);
        } catch (Exception e) {
            FimbyLogger.error('FimbyNotificationService', 'createNotification', e);
        }
    }

    /**
     * Create notifications for multiple recipients with bulk gate check.
     * Insert-only — does NOT merge into existing unread notifications.
     */
    public static void createNotifications(List<Notification__c> notifications) {
        if (notifications == null || notifications.isEmpty()) {
            return;
        }

        Set<Id> contactIds = new Set<Id>();
        for (Notification__c n : notifications) {
            if (n.Contact__c != null) {
                contactIds.add(n.Contact__c);
            }
        }

        Map<Id, User> userByContactId = queryRecipientUsers(contactIds);

        for (Notification__c n : notifications) {
            User u = userByContactId.get(n.Contact__c);
            n.Push_Status__c = shouldQueue(n.Type__c, u);
            n.Email_Status__c = FimbyEmailAlertService.shouldSendEmail(n.Type__c, u);
        }

        try {
            Database.insert(notifications, true);
        } catch (Exception e) {
            FimbyLogger.error('FimbyNotificationService', 'createNotifications', e);
        }
    }

    /**
     * @description Bulk-creates notifications from NotificationRequest value objects with
     * per-record push gate checks. Every request inserts its own Notification__c row.
     */
    public static void createNotificationsFromRequests(List<NotificationRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        List<NotificationRequest> valid = new List<NotificationRequest>();
        Set<Id> allContactIds = new Set<Id>();

        for (NotificationRequest req : requests) {
            if (req.recipientContactId == null || String.isBlank(req.type) || String.isBlank(req.title)) {
                continue;
            }
            valid.add(req);
            allContactIds.add(req.recipientContactId);
        }
        if (valid.isEmpty()) {
            return;
        }

        Map<Id, User> userByContactId = queryRecipientUsers(allContactIds);

        List<Notification__c> toInsert = new List<Notification__c>();
        for (NotificationRequest req : valid) {
            User recipientUser = req.skipPush == true ? null : userByContactId.get(req.recipientContactId);
            toInsert.add(new Notification__c(
                Contact__c = req.recipientContactId,
                Type__c = req.type,
                Title__c = req.title,
                Body__c = req.body,
                Related_Record_Id__c = req.relatedRecordId != null ? String.valueOf(req.relatedRecordId) : null,
                Related_Record_Type__c = req.relatedRecordType,
                Action_URL__c = req.actionUrl,
                Actor_Name__c = req.actorName,
                Actor_Contact__c = req.actorContactId,
                Push_Status__c = (req.skipPush == true) ? null : shouldQueue(req.type, recipientUser),
                Email_Status__c = FimbyEmailAlertService.shouldSendEmail(req.type, recipientUser)
            ));
        }

        try {
            Database.insert(toInsert, true);
        } catch (Exception e) {
            FimbyLogger.error('FimbyNotificationService', 'createNotificationsFromRequests', e);
        }
    }

    /**
     * @description Value object for bulk notification requests.
     */
    public class NotificationRequest {
        public Id recipientContactId;
        public String type;
        public String title;
        public String body;
        public Id relatedRecordId;
        public String relatedRecordType;
        public String actionUrl;
        public String actorName;
        public Boolean skipPush;
        // Represented (acting-as) Contact that actorName describes; drives the
        // card avatar and bold actor name. Set directly after construction
        // (like skipPush) so the 8-arg constructor stays source-compatible.
        public Id actorContactId;

        public NotificationRequest(
            Id recipientContactId, String type, String title, String body,
            Id relatedRecordId, String relatedRecordType, String actionUrl, String actorName
        ) {
            this.recipientContactId = recipientContactId;
            this.type = type;
            this.title = title;
            this.body = body;
            this.relatedRecordId = relatedRecordId;
            this.relatedRecordType = relatedRecordType;
            this.actionUrl = actionUrl;
            this.actorName = actorName;
            this.skipPush = false;
        }
    }

    /* ---------------------------------------------------------------
     * Gate check logic
     * --------------------------------------------------------------- */

    /**
     * @description Returns the doorbell gate lane ('DM' or 'ACTIVITY') for a
     * notification type, from the SAME map used at creation time. The push
     * batch job uses this to stamp the delivered gate so creation and delivery
     * never disagree (fixes the historic Thanks_Received gate mismatch and keeps
     * Event_Chat on the ACTIVITY lane despite its MESSAGE push category).
     */
    public static String gateTypeFor(String notifType) {
        return GATE_TYPE_MAP.containsKey(notifType) ? GATE_TYPE_MAP.get(notifType) : 'ACTIVITY';
    }

    @TestVisible
    private static String shouldQueue(String notifType, User u) {
        if (u == null) {
            return null;
        }

        // Forward-infrastructure bypass hook. SECURITY_BYPASS_PUSH_TYPES is empty
        // in production (push always respects user preferences), so this branch
        // is exercised only by tests. See the set's declaration for the rationale.
        if (SECURITY_BYPASS_PUSH_TYPES.contains(notifType)) {
            return 'Pending';
        }

        if (u.Push_Notifications_Enabled__c == false) {
            return null;
        }
        if (!isTypeToggleEnabled(notifType, u)) {
            return null;
        }
        String gateType = GATE_TYPE_MAP.containsKey(notifType)
            ? GATE_TYPE_MAP.get(notifType) : 'ACTIVITY';
        // Master + category are ON (guards above). Gate open -> audible 'Pending';
        // gate closed (mid-window) -> 'Pending_Quiet' for a passive in-place
        // refresh (Phase 2). Suppression (null) is reserved for master/category off.
        return isGateOpen(u, gateType) ? 'Pending' : 'Pending_Quiet';
    }

    private static Boolean isTypeToggleEnabled(String notifType, User u) {
        // Response replies route/gate as MESSAGE (twin of Thanks_Received) but
        // the user-facing on/off stays on the legacy Asks & Offers toggle, so a
        // reply to an Ask/Offer thread is silenced by "Asks & Offers", not
        // "Messages" — matching the user's mental model of "this is about my post."
        if (notifType == FimbyConstants.NOTIF_RESPONSE_REPLY) {
            return u.Push_Needs_Offers__c != false;
        }
        FimbyPushNotificationService.NotificationType pushType = PUSH_TYPE_MAP.get(notifType);
        if (pushType == null) {
            return true;
        }
        switch on pushType {
            when MESSAGE      { return u.Push_Messages__c != false; }
            when NEEDS_OFFERS { return u.Push_Needs_Offers__c != false; }
            when EVENTS       { return u.Push_Events__c != false; }
            when LIBRARY      { return u.Push_Library__c != false; }
            when STORY        { return u.Push_Stories__c != false; }
            when REMINDER     { return u.Push_Reminders__c != false; }
            when BULK_BUY     { return u.Push_Bulk_Buy__c != false; }
            when else          { return true; }
        }
    }

    /**
     * @description Test-only hook that lets the test harness register a fake
     * security-bypass notification type so the bypass code path can be
     * exercised without committing to a real production NOTIF_* constant.
     */
    @TestVisible
    private static void addSecurityBypassPushTypeForTest(String notifType) {
        if (Test.isRunningTest() && String.isNotBlank(notifType)) {
            SECURITY_BYPASS_PUSH_TYPES.add(notifType);
        }
    }

    @TestVisible
    private static Boolean isGateOpen(User u, String gateType) {
        Datetime lastPush = (gateType == 'DM') ? u.Last_DM_Push_At__c : u.Last_Activity_Push_At__c;

        if (lastPush == null) {
            return true;
        }
        if (u.Last_App_Open_At__c != null && u.Last_App_Open_At__c > lastPush) {
            return true;
        }

        Datetime startOfToday = startOfTodayInUserTimezone(u.TimeZoneSidKey);
        if (lastPush < startOfToday) {
            Integer fatigueDays = FimbySettings.pushFatigueDays();
            if (u.Last_App_Open_At__c == null) {
                return false;
            }
            Long daysSinceLastOpen = u.Last_App_Open_At__c.date().daysBetween(Date.today());
            if (daysSinceLastOpen > fatigueDays) {
                return false;
            }
            return true;
        }

        return false;
    }

    /* ---------------------------------------------------------------
     * User query helpers — fetches all fields needed for gate checks
     * --------------------------------------------------------------- */

    private static User queryRecipientUser(Id contactId) {
        List<User> users = [
            SELECT Id, ContactId,
                   Push_Notifications_Enabled__c,
                   Push_Messages__c, Push_Needs_Offers__c, Push_Library__c,
                   Push_Stories__c, Push_Reminders__c, Push_Bulk_Buy__c,
                   Push_Events__c,
                   Last_DM_Push_At__c, Last_Activity_Push_At__c,
                   Last_App_Open_At__c, TimeZoneSidKey,
                   Email_Alerts_Enabled__c, Email_Alert_Messages__c,
                   Email_Alert_Needs_Offers__c, Email_Alert_Library__c,
                   Email_Alert_Stories__c, Email_Alert_Reminders__c,
                   Email_Alert_Bulk_Buy__c, Email_Alert_Events__c
            FROM User
            WHERE ContactId = :contactId AND IsActive = true
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    private static Map<Id, User> queryRecipientUsers(Set<Id> contactIds) {
        Map<Id, User> result = new Map<Id, User>();
        if (contactIds == null || contactIds.isEmpty()) {
            return result;
        }
        for (User u : [
            SELECT Id, ContactId,
                   Push_Notifications_Enabled__c,
                   Push_Messages__c, Push_Needs_Offers__c, Push_Library__c,
                   Push_Stories__c, Push_Reminders__c, Push_Bulk_Buy__c,
                   Push_Events__c,
                   Last_DM_Push_At__c, Last_Activity_Push_At__c,
                   Last_App_Open_At__c, TimeZoneSidKey,
                   Email_Alerts_Enabled__c, Email_Alert_Messages__c,
                   Email_Alert_Needs_Offers__c, Email_Alert_Library__c,
                   Email_Alert_Stories__c, Email_Alert_Reminders__c,
                   Email_Alert_Bulk_Buy__c, Email_Alert_Events__c
            FROM User
            WHERE ContactId IN :contactIds AND IsActive = true
        ]) {
            result.put(u.ContactId, u);
        }
        return result;
    }

    /* ---------------------------------------------------------------
     * Message-style read/unread sync — keeps the OS app-icon badge
     * (count of unread Notification__c rows) honest when a message/reply
     * is read or re-flagged from the Messages surface. Hidden types never
     * appear in the bell, so the badge is their only surface.
     * --------------------------------------------------------------- */

    /**
     * READ: mark ALL of a thread's hidden notifications read, clearing the
     * thread from the app-icon badge. Scoped to the acting-as recipient.
     */
    public static void markRelatedNotificationsRead(Id relatedRecordId, Set<String> types) {
        if (relatedRecordId == null || types == null || types.isEmpty()) {
            return;
        }
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) {
            return;
        }
        String relatedId = String.valueOf(relatedRecordId);
        List<Notification__c> unread = [
            SELECT Id FROM Notification__c
            WHERE Contact__c = :contactId AND Read_Date__c = null
              AND Type__c IN :types AND Related_Record_Id__c = :relatedId
            LIMIT 200
        ];
        if (unread.isEmpty()) {
            return;
        }
        Datetime now = Datetime.now();
        for (Notification__c n : unread) {
            n.Read_Date__c = now;
        }
        Database.update(unread, false);
    }

    /**
     * UNREAD: restore only the MOST RECENT hidden notification for the thread,
     * so a re-flagged thread contributes exactly one unread to the app-icon
     * badge rather than resurrecting every per-reply row.
     */
    public static void markLatestRelatedNotificationUnread(Id relatedRecordId, Set<String> types) {
        if (relatedRecordId == null || types == null || types.isEmpty()) {
            return;
        }
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        if (String.isBlank(contactId)) {
            return;
        }
        String relatedId = String.valueOf(relatedRecordId);
        List<Notification__c> latest = [
            SELECT Id, Read_Date__c FROM Notification__c
            WHERE Contact__c = :contactId
              AND Type__c IN :types AND Related_Record_Id__c = :relatedId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (latest.isEmpty() || latest[0].Read_Date__c == null) {
            return;
        }
        latest[0].Read_Date__c = null;
        Database.update(latest[0], false);
    }

    /* ---------------------------------------------------------------
     * Timezone helper — converts "now" to the user's local date
     * --------------------------------------------------------------- */

    @TestVisible
    private static Datetime startOfTodayInUserTimezone(String timeZoneSidKey) {
        if (String.isBlank(timeZoneSidKey)) {
            timeZoneSidKey = 'America/Vancouver';
        }
        TimeZone tz = TimeZone.getTimeZone(timeZoneSidKey);
        Datetime nowUtc = Datetime.now();
        Integer offsetMs = tz.getOffset(nowUtc);
        Datetime localNow = nowUtc.addSeconds(offsetMs / 1000);
        Date localDate = localNow.dateGmt();
        Datetime startOfDayLocal = Datetime.newInstanceGmt(localDate, Time.newInstance(0, 0, 0, 0));
        return startOfDayLocal.addSeconds(-offsetMs / 1000);
    }
}
