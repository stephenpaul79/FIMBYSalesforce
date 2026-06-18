/**
 * @description Aggregates DM conversations and Need/Offer response threads into a unified communication list for the My Messages hub. Used by fimbyMessagesList and fimbyUniversalHeader.
 */
public with sharing class FimbyCommunicationController {

    /**
     * Get a unified, sorted, paginated list of communication threads.
     * Merges DM conversations and response threads, sorted by last activity.
     *
     * @param pageSize  Number of items per page (default 20)
     * @param offset    Pagination offset (default 0)
     * @param filter    'all', 'direct', 'responses', 'library'
     * @param searchTerm  Free-text search against participant name
     */
    @AuraEnabled(cacheable=false)
    public static ThreadListResult getThreads(
        Integer pageSize, Integer offset, String filter, String searchTerm
    ) {
        return new CommunicationHelper().getThreadsInternal(pageSize, offset, filter, searchTerm);
    }

    /**
     * Get the total unread count across DMs + Response threads.
     * Used for the nav bar badge.
     */
    @AuraEnabled(cacheable=false)
    public static Integer getUnifiedUnreadCount() {
        return new CommunicationHelper().getUnifiedUnreadCountInternal();
    }

    /**
     * @description Returns both notification and message unread counts in a
     * single Apex transaction so the header badge only needs one server call
     * instead of two. Saves one identity resolution + transaction overhead.
     * @return Map with keys 'notifications' and 'messages'
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Integer> getBadgeCounts() {
        String contactId = FimbyIdentityRepository.getActingAsContactId();
        Integer notifCount = 0;
        if (String.isNotBlank(contactId)) {
            notifCount = [SELECT COUNT() FROM Notification__c
                          WHERE Contact__c = :contactId AND Read_Date__c = null
                            AND Type__c NOT IN :FimbyConstants.BELL_HIDDEN_NOTIF_TYPES];
        }
        Integer msgCount = new CommunicationHelper().getUnifiedUnreadCountInternal();
        return new Map<String, Integer>{
            'notifications' => notifCount,
            'messages' => msgCount
        };
    }

    /**
     * Mark a response thread as viewed by the current user.
     * Updates Poster_Last_Viewed__c or Responder_Last_Viewed__c.
     */
    @AuraEnabled
    public static void markResponseViewed(Id responseId) {
        new CommunicationHelper().markResponseViewedInternal(responseId);
    }

    /**
     * Mark a thread as unread from the inbox.
     * For direct/library: sets Participant_X_Unread_Count__c to 1.
     * For response: sets Poster_Last_Viewed__c or Responder_Last_Viewed__c to null.
     */
    @AuraEnabled
    public static void markThreadUnread(String threadType, Id threadId) {
        new CommunicationHelper().markThreadUnreadInternal(threadType, threadId);
    }

    /**
     * Mark a thread as read from the inbox.
     * For direct/library: sets Participant_X_Unread_Count__c to 0.
     * For response: sets Poster_Last_Viewed__c or Responder_Last_Viewed__c to now.
     */
    @AuraEnabled
    public static void markThreadRead(String threadType, Id threadId) {
        new CommunicationHelper().markThreadReadInternal(threadType, threadId);
    }

    /**
     * Archive a thread for the current user (soft delete).
     * For direct/library: uses FimbyConversationController.archiveConversation.
     * For response: sets Poster_Archived__c or Responder_Archived__c.
     * Thread reappears if the other user sends a new message.
     */
    @AuraEnabled
    public static void archiveThread(String threadType, Id threadId) {
        new CommunicationHelper().archiveThreadInternal(threadType, threadId);
    }

    /**
     * Unarchive a thread for the current user.
     * For direct/library: uses FimbyConversationController.unarchiveConversation.
     * For response: clears Poster_Archived__c or Responder_Archived__c.
     */
    @AuraEnabled
    public static void unarchiveThread(String threadType, Id threadId) {
        new CommunicationHelper().unarchiveThreadInternal(threadType, threadId);
    }

    /**
     * Returns retention days from app settings for the inbox disclaimer.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getRetentionDaysForDisclaimer() {
        return new Map<String, Integer>{
            'dmDays' => FimbySettings.conversationCleanupDays(),
            'responseDays' => FimbySettings.responseThreadCleanupDays(),
            'libraryDays' => FimbySettings.libraryConversationCleanupDays()
        };
    }

    /**
     * @description Lightweight check used by the conversation router to
     * decide whether to render the 1:1 or group conversation component.
     * Delegates to without-sharing helper because Conversation__c OWD is Private.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isGroupConversation(String conversationId) {
        return new CommunicationHelper().isGroupConversationInternal(conversationId);
    }

    /**
     * @description Without sharing helper for community user access to unified threads.
     */
    private without sharing class CommunicationHelper {

        /**
         * @description Merges DM and response threads, sorted by last activity, with optional filter and search.
         * @param pageSize Number of threads per page
         * @param offset Pagination offset
         * @param filter all (active inbox), unread (active + unread only), archived
         * @param searchTerm Free-text search against participant name
         * @return ThreadListResult with threads and totalCount
         */
        public ThreadListResult getThreadsInternal(
            Integer pageSize, Integer offset, String filter, String searchTerm
        ) {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            ThreadListResult result = new ThreadListResult();
            result.threads = new List<CommunicationThread>();

            if (identity == null) {
                result.totalCount = 0;
                return result;
            }

            String myContactId = identity.actingAsContactId;
            String filterVal = String.isNotBlank(filter) ? filter.toLowerCase() : 'all';
            Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : FimbySettings.messagesPageSize();
            Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;
            String searchLower = String.isNotBlank(searchTerm) ? searchTerm.toLowerCase() : null;

            Boolean showArchived = (filterVal == 'archived');
            Boolean unreadOnly = (filterVal == 'unread');

            List<CommunicationThread> allThreads = new List<CommunicationThread>();

            if (filterVal == 'all' || filterVal == 'unread' || filterVal == 'archived') {
                allThreads.addAll(getDmThreads(myContactId, 'all', searchLower, showArchived));
                allThreads.addAll(getGroupThreads(myContactId, searchLower, showArchived));
                allThreads.addAll(getResponseThreads(myContactId, searchLower, showArchived));
            } else if (filterVal == 'direct' || filterVal == 'library') {
                allThreads.addAll(getDmThreads(myContactId, filterVal, searchLower, false));
            } else if (filterVal == 'responses') {
                allThreads.addAll(getResponseThreads(myContactId, searchLower, false));
            }

            if (unreadOnly) {
                List<CommunicationThread> unreadThreads = new List<CommunicationThread>();
                for (CommunicationThread t : allThreads) {
                    if (t.isUnread) {
                        unreadThreads.add(t);
                    }
                }
                allThreads = unreadThreads;
            }

            allThreads.sort();

            result.totalCount = allThreads.size();

            Integer endIdx = Math.min(offsetVal + limitSize, allThreads.size());
            for (Integer i = offsetVal; i < endIdx; i++) {
                result.threads.add(allThreads[i]);
            }

            return result;
        }

        private List<CommunicationThread> getDmThreads(
            String myContactId, String filterVal, String searchLower, Boolean showArchived
        ) {
            List<CommunicationThread> threads = new List<CommunicationThread>();
            Set<Id> blockedContactIds = FimbyBlockingHelper.getBidirectionalBlocks((Id) myContactId);

            String contextFilter = '';
            if (filterVal == 'direct') {
                contextFilter = ' AND (Context_Type__c = \'Direct\' OR Context_Type__c = null)';
            } else if (filterVal == 'library') {
                contextFilter = ' AND Context_Type__c = \'Library_Lending\'';
            }

            String archiveFilter;
            if (showArchived) {
                archiveFilter = ' AND ((Participant_1__c = :myContactId AND Participant_1_Archived__c = true)'
                    + '  OR (Participant_2__c = :myContactId AND Participant_2_Archived__c = true))';
            } else {
                archiveFilter = ' AND ((Participant_1__c = :myContactId AND Participant_1_Archived__c = false)'
                    + '  OR (Participant_2__c = :myContactId AND Participant_2_Archived__c = false))';
            }

            String query = 'SELECT Id, Participant_1__c, Participant_2__c,'
                + ' Participant_1__r.Name, Participant_1__r.Full_Name__c, Participant_1__r.FirstName, Participant_1__r.LastName,'
                + ' Participant_1__r.Image_URL__c, Participant_1__r.Display_Avatar_URL__c, Participant_1__r.Is_Organization_Contact__c,'
                + ' Participant_1__r.Organization_Account__r.Name, Participant_1__r.Organization_Account__r.Logo_URL__c,'
                + ' Participant_2__r.Name, Participant_2__r.Full_Name__c, Participant_2__r.FirstName, Participant_2__r.LastName,'
                + ' Participant_2__r.Image_URL__c, Participant_2__r.Display_Avatar_URL__c, Participant_2__r.Is_Organization_Contact__c,'
                + ' Participant_2__r.Organization_Account__r.Name, Participant_2__r.Organization_Account__r.Logo_URL__c,'
                + ' Last_Message_Preview__c, Last_Message_Date__c, Last_Message_Sender__c,'
                + ' Participant_1_Unread_Count__c, Participant_2_Unread_Count__c,'
                + ' Participant_1_Archived__c, Participant_2_Archived__c,'
                + ' Context_Type__c, Related_Record_Id__c, Status__c'
                + ' FROM Conversation__c'
                + ' WHERE (Participant_1__c = :myContactId OR Participant_2__c = :myContactId)'
                + ' AND (Is_Group__c = false OR Is_Group__c = null)'
                + ' AND Status__c != \'Blocked\''
                + archiveFilter
                + contextFilter
                + ' ORDER BY Last_Message_Date__c DESC NULLS LAST'
                + ' LIMIT ' + FimbySettings.dmThreadsLimit();

            List<Conversation__c> convos = Database.query(query);

            Set<Id> relatedRecordIds = new Set<Id>();
            for (Conversation__c conv : convos) {
                if (String.isNotBlank(conv.Related_Record_Id__c)) {
                    try {
                        relatedRecordIds.add(Id.valueOf(conv.Related_Record_Id__c));
                    } catch (Exception e) { /* skip invalid ids */ }
                }
            }

            Map<Id, String> libraryItemNames = new Map<Id, String>();
            if (!relatedRecordIds.isEmpty()) {
                for (Lending_Request__c lr : [
                    SELECT Id, Library_Item__r.Name
                    FROM Lending_Request__c
                    WHERE Id IN :relatedRecordIds
                ]) {
                    if (lr.Library_Item__r?.Name != null) {
                        libraryItemNames.put(lr.Id, lr.Library_Item__r.Name);
                    }
                }
                Set<Id> remaining = new Set<Id>(relatedRecordIds);
                remaining.removeAll(libraryItemNames.keySet());
                if (!remaining.isEmpty()) {
                    for (Loaned_Item__c li : [
                        SELECT Id, Library_Item__r.Name
                        FROM Loaned_Item__c
                        WHERE Id IN :remaining
                    ]) {
                        if (li.Library_Item__r?.Name != null) {
                            libraryItemNames.put(li.Id, li.Library_Item__r.Name);
                        }
                    }
                    remaining.removeAll(libraryItemNames.keySet());
                }
                if (!remaining.isEmpty()) {
                    for (Lending_History__c lh : [
                        SELECT Id, Library_Item__r.Name
                        FROM Lending_History__c
                        WHERE Id IN :remaining
                    ]) {
                        if (lh.Library_Item__r?.Name != null) {
                            libraryItemNames.put(lh.Id, lh.Library_Item__r.Name);
                        }
                    }
                }
            }

            Set<Id> convIds = new Set<Id>();
            for (Conversation__c c : convos) convIds.add(c.Id);
            Map<Id, Integer> dmMsgCounts = new Map<Id, Integer>();
            if (!convIds.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT Conversation__c convId, COUNT(Id) cnt
                    FROM Message__c WHERE Conversation__c IN :convIds
                    GROUP BY Conversation__c
                ]) {
                    dmMsgCounts.put((Id)ar.get('convId'), (Integer)ar.get('cnt'));
                }
            }

            for (Conversation__c conv : convos) {
                Boolean isP1 = (conv.Participant_1__c == myContactId);
                Id otherContactId = isP1 ? conv.Participant_2__c : conv.Participant_1__c;
                if (otherContactId != null && blockedContactIds.contains(otherContactId)) {
                    continue;
                }
                Contact other = isP1 ? conv.Participant_2__r : conv.Participant_1__r;
                Boolean otherIsOrg = other?.Is_Organization_Contact__c == true;

                String otherName;
                String otherImageUrl;
                String otherInitials;
                if (otherIsOrg) {
                    otherName = other.Organization_Account__r?.Name;
                    otherImageUrl = other.Organization_Account__r?.Logo_URL__c;
                    otherInitials = buildOrgInitials(otherName);
                } else {
                    otherName = other?.Full_Name__c;
                    otherImageUrl = other?.Display_Avatar_URL__c;
                    otherInitials = buildInitials(other?.FirstName, other?.LastName);
                }

                if (searchLower != null && (otherName == null || !otherName.toLowerCase().contains(searchLower))) {
                    continue;
                }

                Boolean isLibrary = conv.Context_Type__c == FimbyConstants.CTX_LIBRARY_LENDING;
                String slug = contextToBadgeType(conv.Context_Type__c);
                Integer unread = isP1
                    ? (conv.Participant_1_Unread_Count__c != null ? conv.Participant_1_Unread_Count__c.intValue() : 0)
                    : (conv.Participant_2_Unread_Count__c != null ? conv.Participant_2_Unread_Count__c.intValue() : 0);

                String contextLabel = null;
                if (isLibrary && String.isNotBlank(conv.Related_Record_Id__c)) {
                    try {
                        contextLabel = libraryItemNames.get(Id.valueOf(conv.Related_Record_Id__c));
                    } catch (Exception e) { /* skip invalid ids */ }
                }

                CommunicationThread t = new CommunicationThread();
                t.threadType = slug;
                t.badgeType = slug;
                t.contextType = conv.Context_Type__c;
                t.isGroup = false;
                t.threadId = conv.Id;
                t.participantName = otherName;
                t.participantInitials = otherInitials;
                t.participantImageUrl = otherImageUrl;
                t.isOrgContact = otherIsOrg;
                t.contextLabel = contextLabel;
                t.lastMessagePreview = conv.Last_Message_Preview__c;
                t.lastActivityDate = conv.Last_Message_Date__c;
                t.isUnread = unread > 0;
                t.unreadCount = unread;
                t.messageCount = dmMsgCounts.containsKey(conv.Id) ? dmMsgCounts.get(conv.Id) : 0;
                t.statusBadge = null;
                t.actionUrl = FimbySettings.getUrl('Conversation', String.valueOf(conv.Id));
                threads.add(t);
            }

            return threads;
        }

        private List<CommunicationThread> getGroupThreads(
            String myContactId, String searchLower, Boolean showArchived
        ) {
            List<CommunicationThread> threads = new List<CommunicationThread>();
            Integer groupLim = FimbySettings.dmThreadsLimit();

            List<Conversation_Member__c> members = [
                SELECT Conversation__c, Conversation__r.Group_Name__c,
                       Conversation__r.Last_Message_Preview__c,
                       Conversation__r.Last_Message_Date__c,
                       Conversation__r.Context_Type__c,
                       Conversation__r.Related_Record_Id__c,
                       Unread_Count__c, Archived__c
                FROM Conversation_Member__c
                WHERE Contact__c = :myContactId
                AND Status__c = :FimbyConstants.MEMBER_ACTIVE
                AND Conversation__r.Is_Group__c = true
                AND Archived__c = :showArchived
                ORDER BY Conversation__r.Last_Message_Date__c DESC NULLS LAST
                LIMIT :groupLim
            ];

            Set<Id> postIds = new Set<Id>();
            Set<Id> convIds = new Set<Id>();
            for (Conversation_Member__c cm : members) {
                convIds.add(cm.Conversation__c);
                if (String.isNotBlank(cm.Conversation__r.Related_Record_Id__c)) {
                    try {
                        postIds.add(Id.valueOf(cm.Conversation__r.Related_Record_Id__c));
                    } catch (Exception e) { /* skip invalid ids */ }
                }
            }

            Map<Id, String> postImageUrls = new Map<Id, String>();
            Map<Id, String> postEventBadgeSlugs = new Map<Id, String>();
            if (!postIds.isEmpty()) {
                for (Needs_Offers__c post : [
                    SELECT Id, Image_1_URL__c, Type__c, Event_Type__c,
                           RecordType.DeveloperName
                    FROM Needs_Offers__c
                    WHERE Id IN :postIds
                ]) {
                    if (String.isNotBlank(post.Image_1_URL__c)) {
                        postImageUrls.put(post.Id, post.Image_1_URL__c);
                    }
                    postEventBadgeSlugs.put(
                        post.Id,
                        postContextToBadgeSlug(
                            post.RecordType?.DeveloperName,
                            post.Type__c,
                            post.Event_Type__c
                        )
                    );
                }
            }

            Map<Id, Integer> groupMsgCounts = new Map<Id, Integer>();
            if (!convIds.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT Conversation__c convId, COUNT(Id) cnt
                    FROM Message__c WHERE Conversation__c IN :convIds
                    GROUP BY Conversation__c
                ]) {
                    groupMsgCounts.put((Id) ar.get('convId'), (Integer) ar.get('cnt'));
                }
            }

            for (Conversation_Member__c cm : members) {
                String groupName = cm.Conversation__r.Group_Name__c;
                if (searchLower != null
                    && (groupName == null || !groupName.toLowerCase().contains(searchLower))) {
                    continue;
                }

                String badgeSlug = contextToBadgeType(cm.Conversation__r.Context_Type__c);
                Integer unread = cm.Unread_Count__c != null ? cm.Unread_Count__c.intValue() : 0;
                String imageUrl = null;
                if (String.isNotBlank(cm.Conversation__r.Related_Record_Id__c)) {
                    try {
                        Id postId = Id.valueOf(cm.Conversation__r.Related_Record_Id__c);
                        imageUrl = postImageUrls.get(postId);
                        if (cm.Conversation__r.Context_Type__c == FimbyConstants.CTX_EVENT
                            && postEventBadgeSlugs.containsKey(postId)) {
                            badgeSlug = postEventBadgeSlugs.get(postId);
                        }
                    } catch (Exception e) { /* skip */ }
                }

                CommunicationThread t = new CommunicationThread();
                t.threadType = 'group';
                t.badgeType = badgeSlug;
                t.contextType = cm.Conversation__r.Context_Type__c;
                t.isGroup = true;
                t.threadId = cm.Conversation__c;
                t.participantName = groupName;
                t.participantInitials = buildGroupInitials(groupName);
                t.participantImageUrl = imageUrl;
                t.isOrgContact = false;
                t.contextLabel = null;
                t.lastMessagePreview = cm.Conversation__r.Last_Message_Preview__c;
                t.lastActivityDate = cm.Conversation__r.Last_Message_Date__c;
                t.isUnread = unread > 0;
                t.unreadCount = unread;
                t.messageCount = groupMsgCounts.containsKey(cm.Conversation__c)
                    ? groupMsgCounts.get(cm.Conversation__c) : 0;
                t.statusBadge = null;
                t.actionUrl = FimbySettings.getUrl('Conversation', String.valueOf(cm.Conversation__c));
                threads.add(t);
            }

            return threads;
        }

        private String buildGroupInitials(String groupName) {
            if (String.isBlank(groupName)) return '?';
            String trimmed = groupName.trim();
            if (trimmed.length() >= 2) {
                return trimmed.substring(0, 2).toUpperCase();
            }
            return trimmed.substring(0, 1).toUpperCase();
        }

        private List<CommunicationThread> getResponseThreads(
            String myContactId, String searchLower, Boolean showArchived
        ) {
            List<CommunicationThread> threads = new List<CommunicationThread>();
            Set<Id> blockedContactIds = FimbyBlockingHelper.getBidirectionalBlocks((Id) myContactId);

            Integer responseThreadsLim = FimbySettings.responseThreadsLimit();
            List<Response__c> responses = [
                SELECT Id, Name, Status__c, Response__c, Last_Reply__c, Last_Reply_Date__c,
                       Last_Reply_Contact_Lookup__c,
                       Contact__c, Contact__r.Name, Contact__r.Full_Name__c, Contact__r.FirstName, Contact__r.LastName,
                       Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c, Contact__r.Is_Organization_Contact__c,
                       Contact__r.Organization_Account__r.Name, Contact__r.Organization_Account__r.Logo_URL__c,
                       On_Behalf_Of_Contact__c, On_Behalf_Of_Contact__r.Name, On_Behalf_Of_Contact__r.Full_Name__c,
                       On_Behalf_Of_Contact__r.FirstName, On_Behalf_Of_Contact__r.LastName,
                       On_Behalf_Of_Contact__r.Image_URL__c, On_Behalf_Of_Contact__r.Display_Avatar_URL__c, On_Behalf_Of_Contact__r.Is_Organization_Contact__c,
                       On_Behalf_Of_Contact__r.Organization_Account__r.Name,
                       On_Behalf_Of_Contact__r.Organization_Account__r.Logo_URL__c,
                       Need_Offer_Responded_To__c, Need_Offer_Responded_To__r.Name,
                       Need_Offer_Responded_To__r.RecordType.DeveloperName,
                       Need_Offer_Responded_To__r.Type__c,
                       Need_Offer_Responded_To__r.Event_Type__c,
                       Need_Offer_Responded_To__r.Contact__c,
                       Need_Offer_Responded_To__r.Posted_By__c,
                       Need_Offer_Responded_To__r.Posted_By__r.Name,
                       Need_Offer_Responded_To__r.Posted_By__r.Full_Name__c,
                       Need_Offer_Responded_To__r.Posted_By__r.FirstName,
                       Need_Offer_Responded_To__r.Posted_By__r.LastName,
                       Need_Offer_Responded_To__r.Posted_By__r.Image_URL__c,
                       Need_Offer_Responded_To__r.Posted_By__r.Display_Avatar_URL__c,
                       Need_Offer_Responded_To__r.Posted_By__r.Is_Organization_Contact__c,
                       Need_Offer_Responded_To__r.Posted_By__r.Organization_Account__r.Name,
                       Need_Offer_Responded_To__r.Posted_By__r.Organization_Account__r.Logo_URL__c,
                       Poster_Last_Viewed__c, Responder_Last_Viewed__c,
                       Poster_Archived__c, Responder_Archived__c,
                       CreatedDate
                FROM Response__c
                WHERE (
                    Contact__c = :myContactId
                    OR On_Behalf_Of_Contact__c = :myContactId
                    OR Need_Offer_Responded_To__r.Posted_By__c = :myContactId
                )
                AND Status__c NOT IN ('Declined', 'Cancelled', 'Expired')
                AND (
                    Need_Offer_Responded_To__r.Event_Type__c = NULL
                    OR Need_Offer_Responded_To__r.Event_Type__c = 'Gathering'
                    OR Last_Reply_Date__c != NULL
                )
                ORDER BY Last_Reply_Date__c DESC NULLS LAST, CreatedDate DESC
                LIMIT :responseThreadsLim
            ];

            Set<Id> respIds = new Set<Id>();
            for (Response__c r : responses) respIds.add(r.Id);
            Map<Id, Integer> respMsgCounts = new Map<Id, Integer>();
            if (!respIds.isEmpty()) {
                for (AggregateResult ar : [
                    SELECT Response__c respId, COUNT(Id) cnt
                    FROM Response_Message__c WHERE Response__c IN :respIds
                    GROUP BY Response__c
                ]) {
                    respMsgCounts.put((Id)ar.get('respId'), (Integer)ar.get('cnt'));
                }
            }

            for (Response__c resp : responses) {
                Boolean isPoster = (resp.Need_Offer_Responded_To__r?.Posted_By__c == myContactId);
                Boolean isArchived = isPoster
                    ? (resp.Poster_Archived__c == true)
                    : (resp.Responder_Archived__c == true);
                if (showArchived && !isArchived) continue;
                if (!showArchived && isArchived) continue;

                if (isPoster) {
                    if (isBlockedParticipant(
                        blockedContactIds,
                        resp.On_Behalf_Of_Contact__c,
                        resp.Contact__c
                    )) {
                        continue;
                    }
                } else if (isBlockedParticipant(
                    blockedContactIds,
                    resp.Need_Offer_Responded_To__r?.Posted_By__c,
                    resp.Need_Offer_Responded_To__r?.Contact__c
                )) {
                    continue;
                }

                Contact otherContact;
                if (isPoster) {
                    otherContact = resp.On_Behalf_Of_Contact__r?.Name != null
                        ? resp.On_Behalf_Of_Contact__r
                        : resp.Contact__r;
                } else {
                    otherContact = resp.Need_Offer_Responded_To__r?.Posted_By__r;
                }

                Boolean otherIsOrg = otherContact?.Is_Organization_Contact__c == true;
                String otherName;
                String otherImageUrl;
                String otherInitials;
                if (otherIsOrg) {
                    otherName = otherContact.Organization_Account__r?.Name;
                    otherImageUrl = otherContact.Organization_Account__r?.Logo_URL__c;
                    otherInitials = buildOrgInitials(otherName);
                } else {
                    otherName = otherContact?.Full_Name__c;
                    otherImageUrl = otherContact?.Display_Avatar_URL__c;
                    otherInitials = buildInitials(otherContact?.FirstName, otherContact?.LastName);
                }

                if (searchLower != null && (otherName == null || !otherName.toLowerCase().contains(searchLower))) {
                    continue;
                }

                String preview = String.isNotBlank(resp.Last_Reply__c) ? resp.Last_Reply__c : resp.Response__c;
                Datetime lastActivity = resp.Last_Reply_Date__c != null
                    ? Datetime.newInstance(resp.Last_Reply_Date__c, Time.newInstance(0, 0, 0, 0))
                    : resp.CreatedDate;

                Boolean isUnread = false;
                if (isPoster) {
                    isUnread = resp.Last_Reply_Date__c != null
                        && resp.Last_Reply_Contact_Lookup__c != myContactId
                        && (resp.Poster_Last_Viewed__c == null
                            || resp.Poster_Last_Viewed__c < lastActivity);
                } else {
                    isUnread = resp.Last_Reply_Date__c != null
                        && resp.Last_Reply_Contact_Lookup__c != myContactId
                        && (resp.Responder_Last_Viewed__c == null
                            || resp.Responder_Last_Viewed__c < lastActivity);
                }

                String parentRt = resp.Need_Offer_Responded_To__r?.RecordType?.DeveloperName;
                String parentType = resp.Need_Offer_Responded_To__r?.Type__c;
                String parentEventType = resp.Need_Offer_Responded_To__r?.Event_Type__c;
                String badgeSlug = postContextToBadgeSlug(parentRt, parentType, parentEventType);

                CommunicationThread t = new CommunicationThread();
                t.threadType = 'response';
                t.badgeType = badgeSlug;
                t.contextType = parentRt;
                t.isGroup = false;
                t.threadId = resp.Id;
                t.participantName = otherName;
                t.participantInitials = otherInitials;
                t.participantImageUrl = otherImageUrl;
                t.isOrgContact = otherIsOrg;
                t.contextLabel = resp.Need_Offer_Responded_To__r?.Name;
                t.lastMessagePreview = preview;
                t.lastActivityDate = lastActivity;
                t.isUnread = isUnread;
                t.unreadCount = isUnread ? 1 : 0;
                t.messageCount = (respMsgCounts.containsKey(resp.Id) ? respMsgCounts.get(resp.Id) : 0) + 1;
                t.statusBadge = resp.Status__c;
                t.actionUrl = FimbySettings.getUrl('Response_Reply', null, '?recordId=' + resp.Id);
                threads.add(t);
            }

            return threads;
        }

        private String buildInitials(String firstName, String lastName) {
            String initials = '';
            if (String.isNotBlank(firstName)) initials += firstName.substring(0, 1);
            if (String.isNotBlank(lastName)) initials += lastName.substring(0, 1);
            return initials.toUpperCase();
        }

        private String buildOrgInitials(String orgName) {
            if (String.isBlank(orgName)) return '?';
            List<String> words = orgName.split('\\s+');
            String initials = '';
            for (String w : words) {
                if (String.isNotBlank(w) && initials.length() < 2) {
                    initials += w.substring(0, 1);
                }
            }
            return initials.toUpperCase();
        }

        /**
         * @description Counts communication threads with unread activity for the current user.
         * Each DM conversation and each response thread contributes at most 1, regardless of
         * how many unread messages it contains.
         * @return Unread thread count
         */
        public Integer getUnifiedUnreadCountInternal() {
            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId)) return 0;

            Set<Id> blockedContactIds = FimbyBlockingHelper.getBidirectionalBlocks((Id) myContactId);

            Integer dmUnread = 0;
            for (Conversation__c conv : [
                SELECT Participant_1__c, Participant_2__c
                FROM Conversation__c
                WHERE Status__c != 'Blocked'
                AND (
                    (Participant_1__c = :myContactId
                        AND Participant_1_Archived__c = false
                        AND Participant_1_Unread_Count__c > 0)
                    OR (Participant_2__c = :myContactId
                        AND Participant_2_Archived__c = false
                        AND Participant_2_Unread_Count__c > 0)
                )
            ]) {
                Id otherId = conv.Participant_1__c == myContactId
                    ? conv.Participant_2__c
                    : conv.Participant_1__c;
                if (otherId != null && !blockedContactIds.contains(otherId)) {
                    dmUnread++;
                }
            }

            Integer responseUnread = 0;
            Integer unreadLim = FimbySettings.sharedContactsLimit();
            List<Response__c> responses = [
                SELECT Last_Reply_Date__c, Last_Reply_Contact_Lookup__c,
                       Contact__c, On_Behalf_Of_Contact__c,
                       Need_Offer_Responded_To__r.Posted_By__c,
                       Need_Offer_Responded_To__r.Contact__c,
                       Poster_Last_Viewed__c, Responder_Last_Viewed__c,
                       Poster_Archived__c, Responder_Archived__c
                FROM Response__c
                WHERE (
                    Contact__c = :myContactId
                    OR On_Behalf_Of_Contact__c = :myContactId
                    OR Need_Offer_Responded_To__r.Posted_By__c = :myContactId
                )
                AND Status__c NOT IN ('Declined', 'Cancelled', 'Expired')
                AND Last_Reply_Date__c != null
                AND Last_Reply_Contact_Lookup__c != :myContactId
                LIMIT :unreadLim
            ];

            for (Response__c resp : responses) {
                Boolean isPoster = (resp.Need_Offer_Responded_To__r?.Posted_By__c == myContactId);
                Boolean isArchived = isPoster
                    ? (resp.Poster_Archived__c == true)
                    : (resp.Responder_Archived__c == true);
                if (isArchived) {
                    continue;
                }

                if (isPoster) {
                    if (isBlockedParticipant(
                        blockedContactIds,
                        resp.On_Behalf_Of_Contact__c,
                        resp.Contact__c
                    )) {
                        continue;
                    }
                } else if (isBlockedParticipant(
                    blockedContactIds,
                    resp.Need_Offer_Responded_To__r?.Posted_By__c,
                    resp.Need_Offer_Responded_To__r?.Contact__c
                )) {
                    continue;
                }

                Datetime lastActivity = Datetime.newInstance(
                    resp.Last_Reply_Date__c, Time.newInstance(0, 0, 0, 0)
                );

                if (isPoster) {
                    if (resp.Poster_Last_Viewed__c == null || resp.Poster_Last_Viewed__c < lastActivity) {
                        responseUnread++;
                    }
                } else {
                    if (resp.Responder_Last_Viewed__c == null || resp.Responder_Last_Viewed__c < lastActivity) {
                        responseUnread++;
                    }
                }
            }

            Integer groupUnread = [
                SELECT COUNT()
                FROM Conversation_Member__c
                WHERE Contact__c = :myContactId
                AND Status__c = :FimbyConstants.MEMBER_ACTIVE
                AND Archived__c = false
                AND Unread_Count__c > 0
                AND Conversation__r.Is_Group__c = true
            ];

            return dmUnread + responseUnread + groupUnread;
        }

        /**
         * @description Marks a response thread as viewed; updates Poster_Last_Viewed__c or Responder_Last_Viewed__c.
         * @param responseId Id of the Response__c
         */
        public void markResponseViewedInternal(Id responseId) {
            markResponseReadInternal(responseId);
        }

        /**
         * @description Single choke point for marking a response thread read.
         * Both the inbox mark-read path (markThreadReadInternal response branch)
         * and the explicit markResponseViewed entry point funnel here, so the
         * hidden-notification read-sync (response replies + thanks) runs exactly
         * once per read regardless of which path the LWC used.
         * @param responseId Id of the Response__c
         */
        private void markResponseReadInternal(Id responseId) {
            if (responseId == null) return;

            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId)) return;

            Response__c resp = [
                SELECT Id, Contact__c, On_Behalf_Of_Contact__c,
                       Need_Offer_Responded_To__r.Posted_By__c
                FROM Response__c
                WHERE Id = :responseId
                LIMIT 1
            ];

            Boolean isPoster = (resp.Need_Offer_Responded_To__r?.Posted_By__c == myContactId);
            Boolean isResponder = (resp.Contact__c == myContactId || resp.On_Behalf_Of_Contact__c == myContactId);

            Response__c updateResp = new Response__c(Id = responseId);
            if (isPoster) {
                updateResp.Poster_Last_Viewed__c = Datetime.now();
            } else if (isResponder) {
                updateResp.Responder_Last_Viewed__c = Datetime.now();
            } else {
                return;
            }

            update updateResp;

            // Read-sync: clear this thread's hidden notifications (reply + thanks)
            // so the app-icon badge no longer counts them.
            FimbyNotificationService.markRelatedNotificationsRead(
                responseId, FimbyConstants.RESPONSE_HIDDEN_TYPES
            );
        }

        /**
         * @description Marks a thread as unread; for DM/library sets unread count to 1; for response clears last viewed.
         * @param threadType direct, library, or response
         * @param threadId Id of the Conversation__c or Response__c
         */
        public void markThreadUnreadInternal(String threadType, Id threadId) {
            if (String.isBlank(threadType) || threadId == null) return;

            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId)) return;

            String typeVal = threadType.toLowerCase();

            if (typeVal == 'response') {
                Response__c resp = [
                    SELECT Id, Contact__c, On_Behalf_Of_Contact__c,
                           Need_Offer_Responded_To__r.Posted_By__c
                    FROM Response__c WHERE Id = :threadId LIMIT 1
                ];
                Boolean isPoster = (resp.Need_Offer_Responded_To__r?.Posted_By__c == myContactId);
                Boolean isResponder = (resp.Contact__c == myContactId || resp.On_Behalf_Of_Contact__c == myContactId);
                Response__c upd = new Response__c(Id = threadId);
                if (isPoster) {
                    upd.Poster_Last_Viewed__c = null;
                } else if (isResponder) {
                    upd.Responder_Last_Viewed__c = null;
                } else {
                    return;
                }
                update upd;
                // Unread-sync: restore only the most recent hidden row so the
                // thread counts once on the app-icon badge.
                FimbyNotificationService.markLatestRelatedNotificationUnread(
                    threadId, FimbyConstants.RESPONSE_HIDDEN_TYPES
                );
            } else if (typeVal == 'group') {
                setGroupMemberUnread(threadId, myContactId, true);
                FimbyNotificationService.markLatestRelatedNotificationUnread(
                    threadId, FimbyConstants.CONVERSATION_HIDDEN_TYPES
                );
            } else {
                markConversationUnread(threadId, myContactId);
                FimbyNotificationService.markLatestRelatedNotificationUnread(
                    threadId, FimbyConstants.CONVERSATION_HIDDEN_TYPES
                );
            }
        }

        /**
         * @description Marks a thread as read; for DM/library sets unread count to 0; for response sets last viewed to now.
         * @param threadType direct, library, group, or response
         * @param threadId Id of the Conversation__c, Response__c, or group Conversation__c
         */
        public void markThreadReadInternal(String threadType, Id threadId) {
            if (String.isBlank(threadType) || threadId == null) return;

            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId)) return;

            String typeVal = threadType.toLowerCase();

            if (typeVal == 'response') {
                // Single response-read choke point (also wires hidden-notification sync).
                markResponseReadInternal(threadId);
            } else if (typeVal == 'group') {
                setGroupMemberRead(threadId, myContactId);
            } else {
                markConversationRead(threadId, myContactId);
            }
        }

        /**
         * @description Archives a thread for the current user; delegates to FimbyConversationController for DM/library, or sets Poster/Responder_Archived__c for response.
         * @param threadType direct, library, group, or response
         * @param threadId Id of the Conversation__c, Response__c, or group Conversation__c
         */
        public void archiveThreadInternal(String threadType, Id threadId) {
            if (String.isBlank(threadType) || threadId == null) return;

            String typeVal = threadType.toLowerCase();

            if (typeVal == 'response') {
                String myContactId = FimbyIdentityRepository.getActingAsContactId();
                if (String.isBlank(myContactId)) return;

                Response__c resp = [
                    SELECT Id, Contact__c, On_Behalf_Of_Contact__c,
                           Need_Offer_Responded_To__r.Posted_By__c
                    FROM Response__c WHERE Id = :threadId LIMIT 1
                ];
                Boolean isPoster = (resp.Need_Offer_Responded_To__r?.Posted_By__c == myContactId);
                Boolean isResponder = (resp.Contact__c == myContactId || resp.On_Behalf_Of_Contact__c == myContactId);
                Response__c upd = new Response__c(Id = threadId);
                if (isPoster) {
                    upd.Poster_Archived__c = true;
                } else if (isResponder) {
                    upd.Responder_Archived__c = true;
                } else {
                    return;
                }
                update upd;
            } else if (typeVal == 'group') {
                setGroupMemberArchived(threadId, FimbyIdentityRepository.getActingAsContactId(), true);
            } else {
                FimbyConversationController.archiveConversation(threadId);
            }
        }

        public Boolean isGroupConversationInternal(String conversationId) {
            List<Conversation__c> convs = [
                SELECT Is_Group__c FROM Conversation__c
                WHERE Id = :conversationId LIMIT 1
            ];
            return !convs.isEmpty() && convs[0].Is_Group__c;
        }

        public void unarchiveThreadInternal(String threadType, Id threadId) {
            if (String.isBlank(threadType) || threadId == null) return;

            String typeVal = threadType.toLowerCase();

            if (typeVal == 'response') {
                String myContactId = FimbyIdentityRepository.getActingAsContactId();
                if (String.isBlank(myContactId)) return;

                Response__c resp = [
                    SELECT Id, Contact__c, On_Behalf_Of_Contact__c,
                           Need_Offer_Responded_To__r.Posted_By__c
                    FROM Response__c WHERE Id = :threadId LIMIT 1
                ];
                Boolean isPoster = (resp.Need_Offer_Responded_To__r?.Posted_By__c == myContactId);
                Boolean isResponder = (resp.Contact__c == myContactId || resp.On_Behalf_Of_Contact__c == myContactId);
                Response__c upd = new Response__c(Id = threadId);
                if (isPoster) {
                    upd.Poster_Archived__c = false;
                } else if (isResponder) {
                    upd.Responder_Archived__c = false;
                } else {
                    return;
                }
                update upd;
            } else if (typeVal == 'group') {
                setGroupMemberArchived(threadId, FimbyIdentityRepository.getActingAsContactId(), false);
            } else {
                FimbyConversationController.unarchiveConversation(threadId);
            }
        }

        private void markConversationUnread(Id conversationId, String myContactId) {
            Conversation__c conv = [
                SELECT Id, Participant_1__c, Participant_2__c
                FROM Conversation__c WHERE Id = :conversationId LIMIT 1
            ];
            Conversation__c upd = new Conversation__c(Id = conversationId);
            if (conv.Participant_1__c == myContactId) {
                upd.Participant_1_Unread_Count__c = 1;
            } else if (conv.Participant_2__c == myContactId) {
                upd.Participant_2_Unread_Count__c = 1;
            } else {
                return;
            }
            update upd;
        }

        private void markConversationRead(Id conversationId, String myContactId) {
            Conversation__c conv = [
                SELECT Id, Participant_1__c, Participant_2__c
                FROM Conversation__c WHERE Id = :conversationId LIMIT 1
            ];
            Conversation__c upd = new Conversation__c(Id = conversationId);
            if (conv.Participant_1__c == myContactId) {
                upd.Participant_1_Unread_Count__c = 0;
            } else if (conv.Participant_2__c == myContactId) {
                upd.Participant_2_Unread_Count__c = 0;
            } else {
                return;
            }
            update upd;

            // Read-sync: clear this conversation's hidden message notifications.
            FimbyNotificationService.markRelatedNotificationsRead(
                conversationId, FimbyConstants.CONVERSATION_HIDDEN_TYPES
            );
        }

        private void setGroupMemberRead(Id conversationId, String myContactId) {
            List<Conversation_Member__c> members = [
                SELECT Id FROM Conversation_Member__c
                WHERE Conversation__c = :conversationId
                AND Contact__c = :myContactId
                AND Status__c = :FimbyConstants.MEMBER_ACTIVE
                LIMIT 1
            ];
            if (members.isEmpty()) return;
            members[0].Unread_Count__c = 0;
            members[0].Last_Read_Date__c = System.now();
            update members[0];

            // Read-sync: clear this group conversation's hidden message notifications.
            FimbyNotificationService.markRelatedNotificationsRead(
                conversationId, FimbyConstants.CONVERSATION_HIDDEN_TYPES
            );
        }

        private void setGroupMemberUnread(Id conversationId, String myContactId, Boolean asUnread) {
            List<Conversation_Member__c> members = [
                SELECT Id FROM Conversation_Member__c
                WHERE Conversation__c = :conversationId
                AND Contact__c = :myContactId
                AND Status__c = :FimbyConstants.MEMBER_ACTIVE
                LIMIT 1
            ];
            if (members.isEmpty()) return;
            if (asUnread) {
                members[0].Unread_Count__c = 1;
                members[0].Last_Read_Date__c = null;
            } else {
                members[0].Unread_Count__c = 0;
                members[0].Last_Read_Date__c = System.now();
            }
            update members[0];
        }

        private void setGroupMemberArchived(Id conversationId, String myContactId, Boolean archived) {
            if (String.isBlank(myContactId)) return;
            List<Conversation_Member__c> members = [
                SELECT Id FROM Conversation_Member__c
                WHERE Conversation__c = :conversationId
                AND Contact__c = :myContactId
                AND Status__c = :FimbyConstants.MEMBER_ACTIVE
                LIMIT 1
            ];
            if (members.isEmpty()) return;
            members[0].Archived__c = archived;
            update members[0];
        }
    }

    private static String contextToBadgeType(String contextType) {
        if (contextType == FimbyConstants.CTX_VOUCH_REQUEST) return 'vouch';
        if (contextType == FimbyConstants.CTX_LIBRARY_LENDING) return 'library';
        if (contextType == FimbyConstants.CTX_BULK_BUY) return 'bulkbuy';
        if (contextType == FimbyConstants.CTX_MISSED_PICKUP) return 'checkin';
        if (contextType == FimbyConstants.CTX_EVENT) return 'event';
        if (contextType == FimbyConstants.CTX_SKILL) return 'skill';
        return 'direct';
    }

    private static String eventTypeToBadgeSlug(String eventType) {
        if (eventType == 'Gathering') {
            return 'gathering';
        }
        if (eventType == 'Community_Event') {
            return 'community-event';
        }
        return 'event';
    }

    private static String postContextToBadgeSlug(
        String recordTypeDevName, String postType, String eventType
    ) {
        if (recordTypeDevName == FimbyConstants.RT_BULK_BUY) {
            return 'bulkbuy';
        }
        if (postType == 'Event') {
            return eventTypeToBadgeSlug(eventType);
        }
        return 'response';
    }

    private static Boolean isBlockedParticipant(Set<Id> blockedContactIds, Id contactA, Id contactB) {
        if (blockedContactIds == null || blockedContactIds.isEmpty()) {
            return false;
        }
        return (contactA != null && blockedContactIds.contains(contactA))
            || (contactB != null && blockedContactIds.contains(contactB));
    }

    // ================================================================
    // Wrapper classes
    // ================================================================

    public class ThreadListResult {
        @AuraEnabled public List<CommunicationThread> threads { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
    }

    public class CommunicationThread implements Comparable {
        @AuraEnabled public String threadType { get; set; }
        @AuraEnabled public String badgeType { get; set; }
        @AuraEnabled public String contextType { get; set; }
        @AuraEnabled public Boolean isGroup { get; set; }
        @AuraEnabled public Id threadId { get; set; }
        @AuraEnabled public String participantName { get; set; }
        @AuraEnabled public String participantInitials { get; set; }
        @AuraEnabled public String participantImageUrl { get; set; }
        @AuraEnabled public Boolean isOrgContact { get; set; }
        @AuraEnabled public String contextLabel { get; set; }
        @AuraEnabled public String lastMessagePreview { get; set; }
        @AuraEnabled public Datetime lastActivityDate { get; set; }
        @AuraEnabled public Boolean isUnread { get; set; }
        @AuraEnabled public Integer unreadCount { get; set; }
        @AuraEnabled public Integer messageCount { get; set; }
        @AuraEnabled public String statusBadge { get; set; }
        @AuraEnabled public String actionUrl { get; set; }

        public Integer compareTo(Object other) {
            CommunicationThread o = (CommunicationThread) other;
            if (this.lastActivityDate == null && o.lastActivityDate == null) return 0;
            if (this.lastActivityDate == null) return 1;
            if (o.lastActivityDate == null) return -1;
            // Descending: newer first
            if (this.lastActivityDate > o.lastActivityDate) return -1;
            if (this.lastActivityDate < o.lastActivityDate) return 1;
            return 0;
        }
    }
}
