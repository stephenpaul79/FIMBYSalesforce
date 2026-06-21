/**
 * @description Provides AuraEnabled methods for the notifications LWC and header bell icon.
 * Identity resolution is delegated to FimbyIdentityRepository. Uses a without sharing inner
 * class for Notification queries that community users cannot access through standard sharing.
 */
public with sharing class FimbyNotificationController {

    private static final Map<String, List<String>> FILTER_TYPE_MAP = new Map<String, List<String>>{
        'Comments'  => new List<String>{ FimbyConstants.NOTIF_COMMENT },
        'Responses' => new List<String>{ FimbyConstants.NOTIF_RESPONSE },
        'Library'   => new List<String>{ FimbyConstants.NOTIF_LENDING_REQUEST, FimbyConstants.NOTIF_LOAN_APPROVED, FimbyConstants.NOTIF_EXTENSION_REQUEST, FimbyConstants.NOTIF_EXTENSION_APPROVED, FimbyConstants.NOTIF_ITEM_RETURNED },
        'Reminders' => new List<String>{ FimbyConstants.NOTIF_OVERDUE_REMINDER }
    };

    /**
     * @description LWC-callable method that returns paginated notifications for the current user.
     * Supports filter by type (Comments, Responses, Library, Reminders).
     * @param pageSize Number of items per page (defaults to settings)
     * @param offset Pagination offset (defaults to 0)
     * @param typeFilter Filter key: All, Comments, Responses, Library, or Reminders
     * @return NotificationResult with items and totalCount
     */
    @AuraEnabled(cacheable=false)
    public static NotificationResult getNotifications(Integer pageSize, Integer offset, String typeFilter) {
        List<String> typeValues = null;
        if (String.isNotBlank(typeFilter) && typeFilter != 'All' && FILTER_TYPE_MAP.containsKey(typeFilter)) {
            typeValues = FILTER_TYPE_MAP.get(typeFilter);
        }
        return new NotificationHelper().getNotificationsInternal(pageSize, offset, typeValues);
    }

    /**
     * @description LWC-callable method that returns the count of unread notifications for the current user.
     * @return Number of unread Notification__c records
     */
    @AuraEnabled(cacheable=false)
    public static Integer getUnreadCount() {
        return new NotificationHelper().getUnreadCountInternal();
    }

    /**
     * @description LWC-callable method that marks a single notification as read.
     * @param notificationId The Notification__c record ID
     */
    @AuraEnabled(cacheable=false)
    public static void markAsRead(Id notificationId) {
        new NotificationHelper().markAsReadInternal(notificationId);
    }

    /**
     * @description LWC-callable method that marks all notifications as read for the current user.
     * Respects markAllReadLimit from settings.
     */
    @AuraEnabled(cacheable=false)
    public static void markAllAsRead() {
        new NotificationHelper().markAllAsReadInternal();
    }

    /**
     * @description LWC-callable method that marks a notification as unread.
     * @param notificationId The Notification__c record ID
     */
    @AuraEnabled(cacheable=false)
    public static void markAsUnread(Id notificationId) {
        new NotificationHelper().markAsUnreadInternal(notificationId);
    }

    @AuraEnabled(cacheable=false)
    public static void deleteNotification(Id notificationId) {
        new NotificationHelper().deleteNotificationInternal(notificationId);
    }

    /**
     * @description LWC-callable method that deletes all notifications for the current user.
     * Respects deleteAllNotificationsLimit from settings.
     */
    @AuraEnabled(cacheable=false)
    public static void deleteAllNotifications() {
        new NotificationHelper().deleteAllNotificationsInternal();
    }

    /* ---------------------------------------------------------------
     * Without sharing helper — community users need elevated access
     * to query and modify Notification__c records.
     * --------------------------------------------------------------- */
    private without sharing class NotificationHelper {

        /**
         * @description Loads paginated notifications for a contact. Applies type filter if provided.
         * @param pageSize Page size (defaults to settings)
         * @param offset Pagination offset
         * @param typeValues Optional list of Type__c values to filter by
         * @return NotificationResult with items and totalCount
         */
        public NotificationResult getNotificationsInternal(Integer pageSize, Integer offset, List<String> typeValues) {
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            NotificationResult result = new NotificationResult();

            if (String.isBlank(contactId)) {
                result.items = new List<NotificationWrapper>();
                result.totalCount = 0;
                return result;
            }

            Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : FimbySettings.notificationsPageSize();
            Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;
            Boolean hasTypeFilter = (typeValues != null && !typeValues.isEmpty());
            Set<Id> blockedContactIds = FimbyBlockingHelper.getBidirectionalBlocks((Id) contactId);

            Set<String> hiddenTypes = FimbyConstants.BELL_HIDDEN_NOTIF_TYPES;
            String query = 'SELECT Id, Name, Type__c, Title__c, Body__c, Read_Date__c, '
                + 'Related_Record_Id__c, Related_Record_Type__c, '
                + 'Action_URL__c, Actor_Name__c, CreatedDate, '
                + 'Actor_Contact__c, Actor_Contact__r.Display_Avatar_URL__c, '
                + 'Actor_Contact__r.Full_Name__c, Actor_Contact__r.FirstName, '
                + 'Actor_Contact__r.Is_Organization_Contact__c, '
                + 'Actor_Contact__r.Organization_Account__c, '
                + 'Actor_Contact__r.Organization_Account__r.Logo_URL__c '
                + 'FROM Notification__c '
                + 'WHERE Contact__c = :contactId'
                + ' AND Type__c NOT IN :hiddenTypes';

            if (hasTypeFilter) {
                query += ' AND Type__c IN :typeValues';
            }

            // Order strictly newest-first; the unread-before-read grouping is
            // applied in Apex below so that WITHIN each group rows stay in
            // CreatedDate DESC order (sorting read rows by Read_Date__c scatters
            // them out of chronological order, which reads as confusing).
            Integer fetchLimit = Math.min(500, limitSize + offsetVal + 100);
            query += ' ORDER BY CreatedDate DESC'
                + ' LIMIT :fetchLimit';

            List<Notification__c> notifications = Database.query(query);
            List<Notification__c> visibleNotifications = filterBlockedNotifications(
                notifications, blockedContactIds
            );
            visibleNotifications = sortUnreadFirstNewestWithin(visibleNotifications);

            result.totalCount = visibleNotifications.size();

            List<Notification__c> pageNotifications = new List<Notification__c>();
            Integer endIdx = Math.min(offsetVal + limitSize, visibleNotifications.size());
            for (Integer i = offsetVal; i < endIdx; i++) {
                pageNotifications.add(visibleNotifications[i]);
            }

            result.items = new List<NotificationWrapper>();
            for (Notification__c n : pageNotifications) {
                NotificationWrapper w = new NotificationWrapper();
                w.id = n.Id;
                w.name = n.Name;
                w.type = n.Type__c;
                w.title = n.Title__c;
                w.body = n.Body__c;
                w.isUnread = (n.Read_Date__c == null);
                w.readDate = n.Read_Date__c;
                w.relatedRecordId = n.Related_Record_Id__c;
                w.relatedRecordType = n.Related_Record_Type__c;
                w.actionUrl = n.Action_URL__c;
                w.actorName = n.Actor_Name__c;
                w.createdDate = n.CreatedDate;

                // Structured actor: drives the card avatar + bold actor name.
                if (n.Actor_Contact__c != null && n.Actor_Contact__r != null) {
                    w.actorContactId = n.Actor_Contact__c;
                    // Prefer the org logo for organization contacts, mirroring
                    // FimbyMessageController; otherwise the privacy-gated personal
                    // avatar (empty when Mask_Avatar__c, falls back to initials).
                    Boolean actorIsOrg = n.Actor_Contact__r.Is_Organization_Contact__c == true;
                    String orgLogo = (n.Actor_Contact__r.Organization_Account__r != null)
                        ? n.Actor_Contact__r.Organization_Account__r.Logo_URL__c : null;
                    w.actorPhotoUrl = (actorIsOrg && String.isNotBlank(orgLogo))
                        ? orgLogo
                        : n.Actor_Contact__r.Display_Avatar_URL__c;
                    // Full_Name__c already respects Mask_Last_Name__c; fall back to
                    // the stored Actor_Name__c label when the lookup name is blank.
                    w.actorDisplayName = String.isNotBlank(n.Actor_Contact__r.Full_Name__c)
                        ? n.Actor_Contact__r.Full_Name__c
                        : n.Actor_Name__c;
                    w.actorIsOrg = actorIsOrg;
                    w.actorOrgAccountId = n.Actor_Contact__r.Organization_Account__c;
                } else {
                    w.actorDisplayName = n.Actor_Name__c;
                }
                result.items.add(w);
            }

            return result;
        }

        /**
         * @description Returns the count of unread notifications for the acting-as contact.
         * @return Count of Notification__c where Read_Date__c is null
         */
        public Integer getUnreadCountInternal() {
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(contactId)) {
                return 0;
            }
            Set<Id> blockedContactIds = FimbyBlockingHelper.getBidirectionalBlocks((Id) contactId);
            List<Notification__c> unread = [
                SELECT Id, Related_Record_Id__c, Related_Record_Type__c
                FROM Notification__c
                WHERE Contact__c = :contactId AND Read_Date__c = null
                  AND Type__c NOT IN :FimbyConstants.BELL_HIDDEN_NOTIF_TYPES
                LIMIT 500
            ];
            return filterBlockedNotifications(unread, blockedContactIds).size();
        }

        /**
         * @description Marks a single notification as read. No-op if not found or already read.
         * @param notificationId The Notification__c record ID
         */
        public void markAsReadInternal(Id notificationId) {
            if (notificationId == null) {
                return;
            }
            List<Notification__c> notifs = [SELECT Id, Read_Date__c FROM Notification__c WHERE Id = :notificationId LIMIT 1];
            if (!notifs.isEmpty() && notifs[0].Read_Date__c == null) {
                notifs[0].Read_Date__c = Datetime.now();
                update notifs[0];
            }
        }

        /**
         * @description Marks all unread notifications as read for the acting-as contact.
         * Respects markAllReadLimit.
         */
        public void markAllAsReadInternal() {
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(contactId)) {
                return;
            }

            Integer markLimit = FimbySettings.markAllReadLimit();
            List<Notification__c> unread = [
                SELECT Id, Read_Date__c
                FROM Notification__c
                WHERE Contact__c = :contactId AND Read_Date__c = null
                LIMIT :markLimit
            ];

            if (!unread.isEmpty()) {
                Datetime now = Datetime.now();
                for (Notification__c n : unread) {
                    n.Read_Date__c = now;
                }
                update unread;
            }
        }

        /**
         * @description Marks a notification as unread by clearing Read_Date__c.
         * @param notificationId The Notification__c record ID
         */
        public void markAsUnreadInternal(Id notificationId) {
            if (notificationId == null) {
                return;
            }
            List<Notification__c> notifs = [SELECT Id, Read_Date__c FROM Notification__c WHERE Id = :notificationId LIMIT 1];
            if (!notifs.isEmpty() && notifs[0].Read_Date__c != null) {
                notifs[0].Read_Date__c = null;
                update notifs[0];
            }
        }

        public void deleteNotificationInternal(Id notificationId) {
            if (notificationId == null) {
                return;
            }
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(contactId)) {
                return;
            }
            List<Notification__c> notifs = [
                SELECT Id FROM Notification__c
                WHERE Id = :notificationId AND Contact__c = :contactId
                LIMIT 1
            ];
            if (!notifs.isEmpty()) {
                delete notifs;
            }
        }

        /**
         * @description Deletes all notifications for the acting-as contact, up to deleteAllNotificationsLimit.
         */
        public void deleteAllNotificationsInternal() {
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(contactId)) {
                return;
            }
            Integer deleteLimit = FimbySettings.deleteAllNotificationsLimit();
            List<Notification__c> allNotifs = [
                SELECT Id FROM Notification__c
                WHERE Contact__c = :contactId
                LIMIT :deleteLimit
            ];
            if (!allNotifs.isEmpty()) {
                delete allNotifs;
            }
        }

        /**
         * @description Floats unread rows above read rows while keeping each group
         * in the input's order. The caller passes a CreatedDate DESC list, so the
         * result is unread (newest-first) then read (newest-first) — consistent
         * chronological order within both groups.
         */
        private List<Notification__c> sortUnreadFirstNewestWithin(List<Notification__c> ordered) {
            List<Notification__c> unread = new List<Notification__c>();
            List<Notification__c> read = new List<Notification__c>();
            for (Notification__c n : ordered) {
                if (n.Read_Date__c == null) {
                    unread.add(n);
                } else {
                    read.add(n);
                }
            }
            unread.addAll(read);
            return unread;
        }

        private List<Notification__c> filterBlockedNotifications(
            List<Notification__c> notifications,
            Set<Id> blockedContactIds
        ) {
            if (notifications == null || notifications.isEmpty()) {
                return new List<Notification__c>();
            }
            if (blockedContactIds == null || blockedContactIds.isEmpty()) {
                return notifications;
            }

            Map<Id, Set<Id>> actorContactsByRecord = resolveNotificationActorContacts(notifications);
            List<Notification__c> visible = new List<Notification__c>();
            for (Notification__c n : notifications) {
                if (!notificationInvolvesBlockedParty(n, blockedContactIds, actorContactsByRecord)) {
                    visible.add(n);
                }
            }
            return visible;
        }

        private Boolean notificationInvolvesBlockedParty(
            Notification__c notification,
            Set<Id> blockedContactIds,
            Map<Id, Set<Id>> actorContactsByRecord
        ) {
            if (String.isBlank(notification.Related_Record_Id__c)) {
                return false;
            }
            try {
                Id recordId = Id.valueOf(notification.Related_Record_Id__c);
                Set<Id> actors = actorContactsByRecord.get(recordId);
                if (actors == null || actors.isEmpty()) {
                    return false;
                }
                for (Id actorId : actors) {
                    if (blockedContactIds.contains(actorId)) {
                        return true;
                    }
                }
            } catch (Exception e) {
                return false;
            }
            return false;
        }

        private Map<Id, Set<Id>> resolveNotificationActorContacts(List<Notification__c> notifications) {
            Map<Id, Set<Id>> recordActors = new Map<Id, Set<Id>>();
            Map<String, Set<Id>> idsByType = new Map<String, Set<Id>>();

            for (Notification__c n : notifications) {
                if (String.isBlank(n.Related_Record_Id__c) || String.isBlank(n.Related_Record_Type__c)) {
                    continue;
                }
                try {
                    Id recordId = Id.valueOf(n.Related_Record_Id__c);
                    String recordType = n.Related_Record_Type__c;
                    if (!idsByType.containsKey(recordType)) {
                        idsByType.put(recordType, new Set<Id>());
                    }
                    idsByType.get(recordType).add(recordId);
                } catch (Exception e) { /* skip invalid ids */ }
            }

            if (idsByType.containsKey('Needs_Offers__c')) {
                for (Needs_Offers__c r : [
                    SELECT Id, Contact__c, Posted_By__c FROM Needs_Offers__c
                    WHERE Id IN :idsByType.get('Needs_Offers__c')
                ]) {
                    recordActors.put(r.Id, actorContactSet(r.Contact__c, r.Posted_By__c));
                }
            }
            if (idsByType.containsKey('Story__c')) {
                for (Story__c r : [
                    SELECT Id, Posted_By__c, Contact__c FROM Story__c
                    WHERE Id IN :idsByType.get('Story__c')
                ]) {
                    recordActors.put(r.Id, actorContactSet(r.Posted_By__c, r.Contact__c));
                }
            }
            if (idsByType.containsKey('Story_Comment__c')) {
                for (Story_Comment__c r : [
                    SELECT Id, Posted_By__c, Contact__c FROM Story_Comment__c
                    WHERE Id IN :idsByType.get('Story_Comment__c')
                ]) {
                    recordActors.put(r.Id, actorContactSet(r.Posted_By__c, r.Contact__c));
                }
            }
            if (idsByType.containsKey('Response__c')) {
                for (Response__c r : [
                    SELECT Id, On_Behalf_Of_Contact__c, Contact__c FROM Response__c
                    WHERE Id IN :idsByType.get('Response__c')
                ]) {
                    recordActors.put(r.Id, actorContactSet(r.On_Behalf_Of_Contact__c, r.Contact__c));
                }
            }
            if (idsByType.containsKey('Message__c')) {
                for (Message__c r : [
                    SELECT Id, On_Behalf_Of__c, Sender__c FROM Message__c
                    WHERE Id IN :idsByType.get('Message__c')
                ]) {
                    recordActors.put(r.Id, actorContactSet(r.On_Behalf_Of__c, r.Sender__c));
                }
            }
            if (idsByType.containsKey('Response_Message__c')) {
                for (Response_Message__c r : [
                    SELECT Id, On_Behalf_Of__c, Sender__c FROM Response_Message__c
                    WHERE Id IN :idsByType.get('Response_Message__c')
                ]) {
                    recordActors.put(r.Id, actorContactSet(r.On_Behalf_Of__c, r.Sender__c));
                }
            }
            if (idsByType.containsKey('Library_Item__c')) {
                for (Library_Item__c r : [
                    SELECT Id, Owner_Contact__c, Listed_By__c FROM Library_Item__c
                    WHERE Id IN :idsByType.get('Library_Item__c')
                ]) {
                    recordActors.put(r.Id, actorContactSet(r.Owner_Contact__c, r.Listed_By__c));
                }
            }
            if (idsByType.containsKey('Lending_Request__c')) {
                for (Lending_Request__c r : [
                    SELECT Id, Requested_By__c, Requested_By_Real_Contact__c FROM Lending_Request__c
                    WHERE Id IN :idsByType.get('Lending_Request__c')
                ]) {
                    recordActors.put(r.Id, actorContactSet(r.Requested_By__c, r.Requested_By_Real_Contact__c));
                }
            }
            if (idsByType.containsKey('Loaned_Item__c')) {
                for (Loaned_Item__c r : [
                    SELECT Id, Loaned_To__c, Loaned_To_Real_Contact__c FROM Loaned_Item__c
                    WHERE Id IN :idsByType.get('Loaned_Item__c')
                ]) {
                    recordActors.put(r.Id, actorContactSet(r.Loaned_To__c, r.Loaned_To_Real_Contact__c));
                }
            }
            if (idsByType.containsKey('Conversation__c')) {
                for (Conversation__c r : [
                    SELECT Id, Participant_1__c, Participant_2__c FROM Conversation__c
                    WHERE Id IN :idsByType.get('Conversation__c')
                ]) {
                    recordActors.put(r.Id, actorContactSet(r.Participant_1__c, r.Participant_2__c));
                }
            }

            return recordActors;
        }

        private Set<Id> actorContactSet(Id contactA, Id contactB) {
            Set<Id> contacts = new Set<Id>();
            if (contactA != null) {
                contacts.add(contactA);
            }
            if (contactB != null) {
                contacts.add(contactB);
            }
            return contacts;
        }
    }

    /* ---------------------------------------------------------------
     * Wrapper classes
     * --------------------------------------------------------------- */
    /**
     * @description Wrapper returned by getNotifications. Used by LWC for paginated notification list.
     */
    public class NotificationResult {
        @AuraEnabled public List<NotificationWrapper> items { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
    }

    /**
     * @description Wrapper for a single notification. Used by LWC to display notification details.
     */
    public class NotificationWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String body { get; set; }
        @AuraEnabled public Boolean isUnread { get; set; }
        @AuraEnabled public Datetime readDate { get; set; }
        @AuraEnabled public String relatedRecordId { get; set; }
        @AuraEnabled public String relatedRecordType { get; set; }
        @AuraEnabled public String actionUrl { get; set; }
        @AuraEnabled public String actorName { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Id actorContactId { get; set; }
        @AuraEnabled public String actorPhotoUrl { get; set; }
        @AuraEnabled public String actorDisplayName { get; set; }
        @AuraEnabled public Boolean actorIsOrg { get; set; }
        @AuraEnabled public Id actorOrgAccountId { get; set; }
    }
}