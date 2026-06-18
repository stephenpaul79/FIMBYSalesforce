/**
 * @description Controller for group conversations in Bulk Buy.
 * Manages multi-participant chat threads via Conversation_Member__c junction.
 */
public with sharing class FimbyGroupConversationController {

    private static final String CLASS_NAME = 'FimbyGroupConversationController';

    @AuraEnabled
    public static Id getOrCreateGroupConversation(Id postId) {
        Needs_Offers__c post = [
            SELECT Id, Group_Conversation__c, Name, Posted_By__c
            FROM Needs_Offers__c
            WHERE Id = :postId
            /* with sharing enforces record access */
            LIMIT 1
        ];

        if (post.Group_Conversation__c != null) {
            return post.Group_Conversation__c;
        }

        return new GroupChatHelper().createGroupConversation(post);
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getGroupMessages(Id conversationId, Integer pageSize, Integer offset) {
        try {
            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String contactId = (String) actingAs.get('contactId');

            Integer pSize = pageSize != null ? pageSize : 50;
            Integer pOffset = offset != null ? offset : 0;

            GroupChatHelper helper = new GroupChatHelper();
            List<Message__c> messages = helper.queryMessages(conversationId, pSize, pOffset);
            try {
                helper.markAsRead(conversationId, contactId);
            } catch (Exception markReadEx) {
                FimbyLogger.error(CLASS_NAME, 'getGroupMessages.markAsRead', markReadEx);
            }
            Integer total = helper.countMessages(conversationId);
            Conversation__c convMeta = helper.queryConversationMeta(conversationId);

            List<Map<String, Object>> messageList = new List<Map<String, Object>>();
            for (Message__c m : messages) {
                Boolean senderIsOrg = m.Sender__r?.Is_Organization_Contact__c == true;
                String senderDisplayName;
                String senderAvatarUrl;
                if (senderIsOrg) {
                    senderDisplayName = FimbyIdentityRepository.buildOrgDisplayName(
                        m.Sender__r.Organization_Account__r?.Name,
                        m.Sent_By__r?.FirstName
                    );
                    senderAvatarUrl = m.Sender__r.Organization_Account__r?.Logo_URL__c;
                } else {
                    senderDisplayName = null;
                    senderAvatarUrl = m.Sender__r?.Display_Avatar_URL__c;
                }

                messageList.add(new Map<String, Object>{
                    'id' => m.Id,
                    'body' => m.Body__c,
                    'senderId' => m.Sender__c,
                    'senderFirstName' => m.Sender__r?.FirstName,
                    'senderLastName' => m.Sender__r?.LastName,
                    'senderAvatarUrl' => senderAvatarUrl,
                    'senderIsOrg' => senderIsOrg,
                    'senderDisplayName' => senderDisplayName,
                    'sentByFirstName' => m.Sent_By__r?.FirstName,
                    'sentById' => m.Sent_By__c,
                    'sentDate' => m.Sent_Date__c,
                    'isSystem' => m.Is_System_Message__c,
                    'systemType' => m.System_Message_Type__c,
                    'isMine' => m.Sender__c == contactId
                });
            }

            return new Map<String, Object>{
                'messages' => messageList,
                'hasMore' => (pOffset + pSize) < total,
                'totalCount' => total,
                'groupName' => convMeta.Group_Name__c,
                'contextType' => convMeta.Context_Type__c
            };
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'getGroupMessages', e);
            throw buildAuraException('Error loading messages: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> sendGroupMessage(Id conversationId, String body) {
        try {
            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String contactId = (String) actingAs.get('contactId');
            String realContactId = (String) actingAs.get('realContactId');

            GroupChatHelper helper = new GroupChatHelper();
            Conversation__c conv = helper.queryConversation(conversationId);

            if (conv.Locked__c) {
                throw new AuraHandledException('This conversation is locked.');
            }

            return helper.doSendMessage(conversationId, contactId, realContactId, body);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'sendGroupMessage', e);
            throw buildAuraException('Error sending message: ' + e.getMessage());
        }
    }

    public static void sendSystemMessage(Id conversationId, String body, String messageType) {
        sendSystemMessage(conversationId, body, messageType, null);
    }

    /**
     * @param bumpConversationActivity When null, Bulk Buy reservation lines infer from fill state; otherwise explicit.
     *        Use true for organiser cancellation, pickup, completion, expiry, and full-lock reservation lines.
     */
    public static void sendSystemMessage(Id conversationId, String body, String messageType, Boolean bumpConversationActivity) {
        new GroupChatHelper().doSendSystemMessage(conversationId, body, messageType, bumpConversationActivity);
    }

    public static void addMember(Id conversationId, Id contactId) {
        new GroupChatHelper().doAddMember(conversationId, contactId);
    }

    public static void removeMember(Id conversationId, Id contactId) {
        new GroupChatHelper().doRemoveMember(conversationId, contactId);
    }

    public static void lockConversation(Id conversationId) {
        new GroupChatHelper().doLockConversation(conversationId);
    }

    @AuraEnabled
    public static Map<String, Object> toggleMute(Id conversationId) {
        try {
            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String contactId = (String) actingAs.get('contactId');

            return new GroupChatHelper().doToggleMute(conversationId, contactId);
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'toggleMute', e);
            throw buildAuraException('Error toggling mute: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getGroupMembers(Id conversationId) {
        try {
            List<Map<String, Object>> members = new List<Map<String, Object>>();
            List<Conversation_Member__c> cms = new GroupChatHelper().queryActiveMembers(conversationId);
            for (Conversation_Member__c cm : cms) {
                Boolean isOrg = cm.Contact__r?.Is_Organization_Contact__c == true;
                String displayName = isOrg ? cm.Contact__r.Organization_Account__r?.Name : null;
                String avatarUrl = isOrg
                    ? cm.Contact__r.Organization_Account__r?.Logo_URL__c
                    : cm.Contact__r?.Display_Avatar_URL__c;

                members.add(new Map<String, Object>{
                    'id' => cm.Id,
                    'contactId' => cm.Contact__c,
                    'firstName' => cm.Contact__r.FirstName,
                    'lastName' => cm.Contact__r.LastName,
                    'displayName' => displayName,
                    'avatarUrl' => avatarUrl,
                    'isOrgContact' => isOrg,
                    'role' => cm.Role__c,
                    'joinedDate' => cm.Joined_Date__c
                });
            }
            return members;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'getGroupMembers', e);
            throw buildAuraException('Error loading members: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getMyGroupConversations() {
        try {
            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String contactId = (String) actingAs.get('contactId');

            List<Map<String, Object>> results = new List<Map<String, Object>>();
            List<Conversation_Member__c> memberships = new GroupChatHelper().queryMyGroupMemberships(contactId);
            for (Conversation_Member__c cm : memberships) {
                results.add(new Map<String, Object>{
                    'conversationId' => cm.Conversation__c,
                    'groupName' => cm.Conversation__r.Group_Name__c,
                    'contextType' => cm.Conversation__r.Context_Type__c,
                    'lastMessage' => cm.Conversation__r.Last_Message_Preview__c,
                    'lastMessageDate' => cm.Conversation__r.Last_Message_Date__c,
                    'locked' => cm.Conversation__r.Locked__c,
                    'unreadCount' => cm.Unread_Count__c,
                    'muted' => cm.Muted__c
                });
            }
            return results;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'getMyGroupConversations', e);
            throw buildAuraException('Error loading conversations: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Id createEventGroupChat(Id eventId) {
        try {
            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String actingContactId = (String) actingAs.get('actingAsContactId');

            Needs_Offers__c post = [
                SELECT Id, Name, Posted_By__c, Posted_By__r.Full_Name__c,
                       Group_Conversation__c, Event_Type__c
                FROM Needs_Offers__c
                WHERE Id = :eventId
                LIMIT 1
            ];

            if (post.Posted_By__c != actingContactId) {
                throw new AuraHandledException('Only the event poster can create an event chat.');
            }
            if (post.Event_Type__c != 'Open_Event') {
                throw new AuraHandledException('Event chat is only available for Open Events.');
            }
            if (post.Group_Conversation__c != null) {
                return post.Group_Conversation__c;
            }

            return new EventChatHelper().createChat(post);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'createEventGroupChat', e);
            throw buildAuraException('Error creating event chat: ' + e.getMessage());
        }
    }

    public static void syncEventChatMember(Id eventId, Id contactId, String action) {
        List<Needs_Offers__c> posts = [
            SELECT Id, Group_Conversation__c, Group_Conversation__r.Group_Name__c
            FROM Needs_Offers__c
            WHERE Id = :eventId AND Group_Conversation__c != null
            LIMIT 1
        ];
        if (posts.isEmpty()) return;

        Id convId = posts[0].Group_Conversation__c;
        String convName = posts[0].Group_Conversation__r.Group_Name__c;
        GroupChatHelper helper = new GroupChatHelper();
        if (action == 'add') {
            helper.doAddMember(convId, contactId, convName);
        } else if (action == 'remove') {
            helper.doRemoveMember(convId, contactId);
        }
    }

    private static AuraHandledException buildAuraException(String msg) {
        AuraHandledException ex = new AuraHandledException(msg);
        ex.setMessage(msg);
        return ex;
    }

    private without sharing class GroupChatHelper {

        public Conversation__c queryConversation(Id conversationId) {
            return [
                SELECT Id, Locked__c FROM Conversation__c
                WHERE Id = :conversationId
                LIMIT 1
            ];
        }

        public Conversation__c queryConversationMeta(Id conversationId) {
            return [
                SELECT Id, Group_Name__c, Context_Type__c, Locked__c
                FROM Conversation__c
                WHERE Id = :conversationId
                LIMIT 1
            ];
        }

        public Id createGroupConversation(Needs_Offers__c post) {
            Conversation__c conv = new Conversation__c(
                Is_Group__c = true,
                Group_Name__c = post.Name,
                Context_Type__c = FimbyConstants.CTX_BULK_BUY,
                Related_Record_Id__c = post.Id,
                Status__c = FimbyConstants.CONVERSATION_ACTIVE
            );
            insert conv;

            post.Group_Conversation__c = conv.Id;
            update post;

            Conversation_Member__c ownerMember = new Conversation_Member__c(
                Conversation__c = conv.Id,
                Contact__c = post.Posted_By__c,
                Role__c = FimbyConstants.MEMBER_ROLE_OWNER,
                Status__c = FimbyConstants.MEMBER_ACTIVE,
                Joined_Date__c = System.now()
            );
            insert ownerMember;

            return conv.Id;
        }

        public Map<String, Object> doSendMessage(Id conversationId, Id contactId, Id realContactId, String body) {
            Message__c msg = new Message__c(
                Conversation__c = conversationId,
                Sender__c = contactId,
                Sent_By__c = realContactId != null ? realContactId : contactId,
                Body__c = body,
                Sent_Date__c = System.now(),
                Status__c = FimbyConstants.MESSAGE_SENT,
                Is_System_Message__c = false
            );
            insert msg;

            updateConversationSummary(conversationId, body);
            Set<Id> senderExcludeContactIds = buildSenderRecipientExclusionIds(contactId, realContactId);
            incrementUnreadForOthers(conversationId, senderExcludeContactIds);

            Conversation__c conv = [
                SELECT Id, Group_Name__c, Context_Type__c FROM Conversation__c
                WHERE Id = :conversationId LIMIT 1
            ];
            String groupName = conv.Group_Name__c != null ? conv.Group_Name__c : 'group chat';
            String notifType = notifTypeForContext(conv.Context_Type__c);

            List<Contact> senders = [
                SELECT Id, Full_Name__c, Is_Organization_Contact__c,
                       Organization_Account__r.Name
                FROM Contact WHERE Id = :contactId LIMIT 1
            ];
            String senderName;
            if (!senders.isEmpty() && senders[0].Is_Organization_Contact__c == true) {
                Contact realSender = realContactId != null && realContactId != contactId
                    ? [SELECT FirstName FROM Contact WHERE Id = :realContactId LIMIT 1]
                    : null;
                senderName = FimbyIdentityRepository.buildOrgDisplayName(
                    senders[0].Organization_Account__r?.Name,
                    realSender?.FirstName
                );
            } else {
                senderName = (!senders.isEmpty() && senders[0].Full_Name__c != null)
                    ? senders[0].Full_Name__c : 'FIMBY';
            }

            List<Conversation_Member__c> recipients = [
                SELECT Contact__c FROM Conversation_Member__c
                WHERE Conversation__c = :conversationId
                AND Contact__c NOT IN :senderExcludeContactIds
                AND Status__c = :FimbyConstants.MEMBER_ACTIVE
                AND Muted__c = false
            ];

            if (!recipients.isEmpty()) {
                String truncatedBody = body != null && body.length() > 140
                    ? body.substring(0, 137) + '...' : body;
                String convIdStr = String.valueOf(conversationId);
                String convUrl = FimbySettings.getUrl('Conversation', convIdStr);
                List<Notification__c> notifications = new List<Notification__c>();
                for (Conversation_Member__c cm : recipients) {
                    notifications.add(new Notification__c(
                        Contact__c = cm.Contact__c,
                        Type__c = notifType,
                        Title__c = senderName + ' in ' + groupName,
                        Body__c = truncatedBody,
                        Related_Record_Id__c = convIdStr,
                        Related_Record_Type__c = 'Conversation__c',
                        Action_URL__c = convUrl,
                        Actor_Name__c = senderName
                    ));
                }
                FimbyNotificationService.createNotifications(notifications);
            }

            return new Map<String, Object>{ 'success' => true, 'messageId' => msg.Id };
        }

        /**
         * @description Maps a conversation's context to the notification type so the in-app row,
         * email digest badge/CTA, and push category match the thread (a Bulk Buy chat must not
         * surface as "EVENT CHAT"). Event chats stay Event_Chat; everything else is a plain message.
         */
        private String notifTypeForContext(String contextType) {
            if (contextType == FimbyConstants.CTX_BULK_BUY) {
                return FimbyConstants.NOTIF_BULK_BUY_STATUS;
            }
            if (contextType == FimbyConstants.CTX_EVENT) {
                return FimbyConstants.NOTIF_EVENT_CHAT;
            }
            return FimbyConstants.NOTIF_MESSAGE;
        }

        public void doSendSystemMessage(Id conversationId, String body, String messageType, Boolean bumpConversationActivity) {
            Message__c msg = new Message__c(
                Conversation__c = conversationId,
                Body__c = body,
                Sent_Date__c = System.now(),
                Status__c = FimbyConstants.MESSAGE_SENT,
                Is_System_Message__c = true,
                System_Message_Type__c = messageType
            );
            insert msg;

            if (shouldBumpConversationSummary(conversationId, messageType, bumpConversationActivity)) {
                updateConversationSummary(conversationId, body);
            }
        }

        /**
         * @description Controls Last_Message_* updates (inbox ordering / preview). Bulk Buy reservation chatter
         * stays quiet until shares are fully locked, unless callers pass bump explicitly.
         */
        private Boolean shouldBumpConversationSummary(
            Id conversationId,
            String messageType,
            Boolean bumpConversationActivity
        ) {
            if (bumpConversationActivity != null) {
                return bumpConversationActivity;
            }
            Conversation__c c = [
                SELECT Context_Type__c, Related_Record_Id__c
                FROM Conversation__c
                WHERE Id = :conversationId
                LIMIT 1
            ];
            if (c.Context_Type__c != FimbyConstants.CTX_BULK_BUY) {
                return true;
            }
            if (c.Related_Record_Id__c == null) {
                return messageType != FimbyConstants.SYS_MSG_RESERVATION_CREATED
                    && messageType != FimbyConstants.SYS_MSG_RESERVATION_CANCELLED;
            }
            if (messageType == FimbyConstants.SYS_MSG_RESERVATION_CREATED) {
                return inferBulkBuyFullyReserved(c.Related_Record_Id__c);
            }
            if (messageType == FimbyConstants.SYS_MSG_RESERVATION_CANCELLED) {
                return false;
            }
            return true;
        }

        private Boolean inferBulkBuyFullyReserved(Id needsOffersId) {
            Needs_Offers__c post = [
                SELECT Total_Quantity__c, Owner_Shares__c
                FROM Needs_Offers__c
                WHERE Id = :needsOffersId
                LIMIT 1
            ];
            Decimal owner = post.Owner_Shares__c != null ? post.Owner_Shares__c : 0;
            List<AggregateResult> ar = [
                SELECT SUM(Amount_Requested__c) total
                FROM Response__c
                WHERE Need_Offer_Responded_To__c = :needsOffersId
                AND Status__c = :FimbyConstants.RESPONSE_RESERVED
            ];
            Decimal sumReserved = (!ar.isEmpty() && ar[0].get('total') != null)
                ? (Decimal) ar[0].get('total')
                : 0;
            Decimal available = post.Total_Quantity__c - owner - sumReserved;
            return available <= 0;
        }

        public void doAddMember(Id conversationId, Id contactId) {
            doAddMember(conversationId, contactId, null);
        }

        public void doAddMember(Id conversationId, Id contactId, String convName) {
            List<Conversation_Member__c> existing = [
                SELECT Id, Status__c FROM Conversation_Member__c
                WHERE Conversation__c = :conversationId AND Contact__c = :contactId
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                if (existing[0].Status__c != FimbyConstants.MEMBER_ACTIVE) {
                    existing[0].Status__c = FimbyConstants.MEMBER_ACTIVE;
                    existing[0].Joined_Date__c = System.now();
                    update existing[0];
                }
                return;
            }

            insert new Conversation_Member__c(
                Conversation__c = conversationId,
                Contact__c = contactId,
                Role__c = FimbyConstants.MEMBER_ROLE_MEMBER,
                Status__c = FimbyConstants.MEMBER_ACTIVE,
                Joined_Date__c = System.now()
            );

            if (convName != null) {
                FimbyNotificationService.createNotification(
                    contactId,
                    FimbyConstants.NOTIF_EVENT_CHAT,
                    'You\'ve been added to an event chat',
                    'You\'re now part of the event chat. Say hello.',
                    conversationId,
                    'Conversation__c',
                    FimbySettings.getUrl('Conversation', String.valueOf(conversationId)),
                    'Neighbourhood team'
                );
            }
        }

        public void doRemoveMember(Id conversationId, Id contactId) {
            List<Conversation_Member__c> members = [
                SELECT Id FROM Conversation_Member__c
                WHERE Conversation__c = :conversationId AND Contact__c = :contactId
                LIMIT 1
            ];
            if (!members.isEmpty()) {
                members[0].Status__c = FimbyConstants.MEMBER_REMOVED;
                update members[0];
            }
        }

        public void doLockConversation(Id conversationId) {
            Conversation__c conv = new Conversation__c(Id = conversationId, Locked__c = true);
            update conv;
        }

        public Map<String, Object> doToggleMute(Id conversationId, Id contactId) {
            List<Conversation_Member__c> members = [
                SELECT Id, Muted__c FROM Conversation_Member__c
                WHERE Conversation__c = :conversationId AND Contact__c = :contactId
                LIMIT 1
            ];
            if (members.isEmpty()) {
                throw new AuraHandledException('You are not a member of this conversation.');
            }
            members[0].Muted__c = !members[0].Muted__c;
            update members[0];
            return new Map<String, Object>{ 'success' => true, 'muted' => members[0].Muted__c };
        }

        public void markAsRead(Id conversationId, Id contactId) {
            List<Conversation_Member__c> members = [
                SELECT Id FROM Conversation_Member__c
                WHERE Conversation__c = :conversationId AND Contact__c = :contactId
                LIMIT 1
            ];
            if (!members.isEmpty()) {
                members[0].Last_Read_Date__c = System.now();
                members[0].Unread_Count__c = 0;
                update members[0];
            }

            // Read-sync: single choke point for group thread-open AND inbox, so
            // event-chat notifications clear from the app-icon badge once read.
            FimbyNotificationService.markRelatedNotificationsRead(
                conversationId, FimbyConstants.CONVERSATION_HIDDEN_TYPES
            );
        }

        private void updateConversationSummary(Id conversationId, String body) {
            String preview = body != null && body.length() > 100 ? body.substring(0, 97) + '...' : body;
            Conversation__c conv = new Conversation__c(
                Id = conversationId,
                Last_Message_Preview__c = preview,
                Last_Message_Date__c = System.now()
            );
            update conv;
        }

        public List<Message__c> queryMessages(Id conversationId, Integer pSize, Integer pOffset) {
            return [
                SELECT Id, Body__c, Sender__c, Sender__r.FirstName, Sender__r.LastName,
                       Sender__r.Image_URL__c, Sender__r.Display_Avatar_URL__c,
                       Sender__r.Is_Organization_Contact__c,
                       Sender__r.Organization_Account__r.Name,
                       Sender__r.Organization_Account__r.Logo_URL__c,
                       Sent_By__c, Sent_By__r.FirstName,
                       Sent_Date__c, Is_System_Message__c, System_Message_Type__c
                FROM Message__c
                WHERE Conversation__c = :conversationId
                ORDER BY Sent_Date__c ASC
                LIMIT :pSize
                OFFSET :pOffset
            ];
        }

        public Integer countMessages(Id conversationId) {
            return [SELECT COUNT() FROM Message__c WHERE Conversation__c = :conversationId];
        }

        public List<Conversation_Member__c> queryActiveMembers(Id conversationId) {
            return [
                SELECT Id, Contact__c, Contact__r.FirstName, Contact__r.LastName,
                       Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c,
                       Contact__r.Is_Organization_Contact__c,
                       Contact__r.Organization_Account__r.Name,
                       Contact__r.Organization_Account__r.Logo_URL__c,
                       Role__c, Status__c, Joined_Date__c
                FROM Conversation_Member__c
                WHERE Conversation__c = :conversationId
                AND Status__c = :FimbyConstants.MEMBER_ACTIVE
                ORDER BY Joined_Date__c ASC
            ];
        }

        public List<Conversation_Member__c> queryMyGroupMemberships(Id contactId) {
            return [
                SELECT Conversation__c, Conversation__r.Group_Name__c,
                       Conversation__r.Context_Type__c,
                       Conversation__r.Last_Message_Preview__c,
                       Conversation__r.Last_Message_Date__c,
                       Conversation__r.Locked__c, Unread_Count__c, Muted__c
                FROM Conversation_Member__c
                WHERE Contact__c = :contactId
                AND Status__c = :FimbyConstants.MEMBER_ACTIVE
                AND Conversation__r.Is_Group__c = true
                ORDER BY Conversation__r.Last_Message_Date__c DESC
                LIMIT 50
            ];
        }

        /**
         * Contact Ids that must not receive notifications or unread bumps for this send.
         * Includes represented + real author and org identities the user can act as (same User).
         */
        private Set<Id> buildSenderRecipientExclusionIds(Id actingAsContactId, Id sentByContactId) {
            Set<Id> excludeIds = new Set<Id>();
            if (actingAsContactId != null) {
                excludeIds.add(actingAsContactId);
            }
            Id sentBy = sentByContactId != null ? sentByContactId : actingAsContactId;
            if (sentBy != null) {
                excludeIds.add(sentBy);
            }

            Id realContactId = FimbyIdentityRepository.getCurrentUser()?.ContactId;
            if (realContactId == null) {
                return excludeIds;
            }
            excludeIds.add(realContactId);

            Set<Id> orgAccountIdsNeedingLookup = new Set<Id>();
            for (Support_Relationship__c rel : [
                SELECT Related_Organization__c, Related_Organization__r.Organization_Contact__c
                FROM Support_Relationship__c
                WHERE Contact__c = :realContactId
                  AND Status__c = 'Approved'
                  AND Relationship_Type__c = 'Community_Group_Rep'
                  AND Related_Organization__c != null
            ]) {
                if (rel.Related_Organization__r.Organization_Contact__c != null) {
                    excludeIds.add(rel.Related_Organization__r.Organization_Contact__c);
                } else {
                    orgAccountIdsNeedingLookup.add(rel.Related_Organization__c);
                }
            }
            if (!orgAccountIdsNeedingLookup.isEmpty()) {
                for (Contact orgContact : [
                    SELECT Id FROM Contact
                    WHERE Is_Organization_Contact__c = true
                      AND Organization_Account__c IN :orgAccountIdsNeedingLookup
                ]) {
                    excludeIds.add(orgContact.Id);
                }
            }
            return excludeIds;
        }

        private void incrementUnreadForOthers(Id conversationId, Set<Id> senderExcludeContactIds) {
            List<Conversation_Member__c> others = [
                SELECT Id, Unread_Count__c, Muted__c FROM Conversation_Member__c
                WHERE Conversation__c = :conversationId
                AND Contact__c NOT IN :senderExcludeContactIds
                AND Status__c = :FimbyConstants.MEMBER_ACTIVE
            ];
            for (Conversation_Member__c cm : others) {
                cm.Unread_Count__c = (cm.Unread_Count__c == null ? 0 : cm.Unread_Count__c) + 1;
            }
            if (!others.isEmpty()) {
                update others;
            }
        }
    }

    private without sharing class EventChatHelper {
        public Id createChat(Needs_Offers__c post) {
            Conversation__c conv = new Conversation__c(
                Is_Group__c = true,
                Group_Name__c = post.Name,
                Context_Type__c = FimbyConstants.CTX_EVENT,
                Related_Record_Id__c = post.Id,
                Status__c = FimbyConstants.CONVERSATION_ACTIVE
            );
            insert conv;

            post.Group_Conversation__c = conv.Id;
            update post;

            Conversation_Member__c ownerMember = new Conversation_Member__c(
                Conversation__c = conv.Id,
                Contact__c = post.Posted_By__c,
                Role__c = FimbyConstants.MEMBER_ROLE_OWNER,
                Status__c = FimbyConstants.MEMBER_ACTIVE,
                Joined_Date__c = System.now()
            );
            insert ownerMember;

            List<Response__c> activeAttendees = [
                SELECT On_Behalf_Of_Contact__c FROM Response__c
                WHERE Need_Offer_Responded_To__c = :post.Id
                AND Status__c IN ('New', 'Accepted')
                AND On_Behalf_Of_Contact__c != :post.Posted_By__c
            ];
            List<Conversation_Member__c> memberInserts = new List<Conversation_Member__c>();
            for (Response__c r : activeAttendees) {
                memberInserts.add(new Conversation_Member__c(
                    Conversation__c = conv.Id,
                    Contact__c = r.On_Behalf_Of_Contact__c,
                    Role__c = FimbyConstants.MEMBER_ROLE_MEMBER,
                    Status__c = FimbyConstants.MEMBER_ACTIVE,
                    Joined_Date__c = System.now()
                ));
            }
            if (!memberInserts.isEmpty()) {
                insert memberInserts;

                String posterName = post.Posted_By__r?.Full_Name__c != null
                    ? post.Posted_By__r.Full_Name__c : 'The event organiser';
                String convIdStr = String.valueOf(conv.Id);
                String convUrl = FimbySettings.getUrl('Conversation', convIdStr);
                List<Notification__c> notifications = new List<Notification__c>();
                for (Response__c r : activeAttendees) {
                    notifications.add(new Notification__c(
                        Contact__c = r.On_Behalf_Of_Contact__c,
                        Type__c = FimbyConstants.NOTIF_EVENT_CHAT,
                        Title__c = 'Event chat started',
                        Body__c = posterName + ' started an event chat for ' + post.Name,
                        Related_Record_Id__c = convIdStr,
                        Related_Record_Type__c = 'Conversation__c',
                        Action_URL__c = convUrl,
                        Actor_Name__c = posterName
                    ));
                }
                FimbyNotificationService.createNotifications(notifications);
            }

            FimbyGroupConversationController.sendSystemMessage(
                conv.Id,
                'Event chat is open',
                FimbyConstants.SYS_MSG_STATUS_CHANGE,
                true
            );

            return conv.Id;
        }
    }
}
