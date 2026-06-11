/**
 * @description Handles individual message CRUD within conversation threads. Supports dual-identity
 * pattern (Sender__c / Sent_By__c). Creates in-app Notification__c records for new messages; the
 * creation-time gate check in FimbyNotificationService decides push eligibility.
 */
public with sharing class FimbyMessageController {

    /**
     * Get paginated messages for a conversation.
     * Marks retrieved messages as read for the current participant.
     * Returns oldest-first (newest at bottom, like iMessage).
     */
    @AuraEnabled(cacheable=false)
    public static MessageListResult getMessages(Id conversationId, Integer pageSize, Integer offset) {
        return new MessageHelper().getMessagesInternal(conversationId, pageSize, offset);
    }

    /**
     * Send a message in a conversation.
     * Creates Message__c with dual-identity fields, updates Conversation__c summary,
     * and fires a push notification (respecting quiet hours and user preferences).
     */
    @AuraEnabled
    public static Map<String, Object> sendMessage(Id conversationId, String body) {
        return new MessageHelper().sendMessageInternal(conversationId, body);
    }

    /* ---------------------------------------------------------------
     * Without sharing helper — community users need elevated access
     * to query Conversation__c, Message__c, Contact, and User records.
     * --------------------------------------------------------------- */
    private without sharing class MessageHelper {

        /**
         * @description Fetches paginated messages for a conversation and marks them as read for the current participant.
         * @param conversationId Id of the Conversation__c
         * @param pageSize Number of messages per page
         * @param offset Pagination offset
         * @return MessageListResult with messages, totalCount, participant info
         */
        public MessageListResult getMessagesInternal(Id conversationId, Integer pageSize, Integer offset) {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            MessageListResult result = new MessageListResult();
            result.messages = new List<MessageWrapper>();

            if (identity == null || conversationId == null) {
                result.totalCount = 0;
                return result;
            }

            String myContactId = identity.actingAsContactId;

            Conversation__c conv = [
                SELECT Id, Participant_1__c, Participant_2__c,
                       Context_Type__c, Related_Record_Id__c, Locked__c,
                       Participant_1__r.Name, Participant_1__r.FirstName,
                       Participant_1__r.Image_URL__c,
                       Participant_1__r.Is_Organization_Contact__c,
                       Participant_1__r.Organization_Account__r.Name,
                       Participant_1__r.Organization_Account__r.Logo_URL__c,
                       Participant_2__r.Name, Participant_2__r.FirstName,
                       Participant_2__r.Image_URL__c,
                       Participant_2__r.Is_Organization_Contact__c,
                       Participant_2__r.Organization_Account__r.Name,
                       Participant_2__r.Organization_Account__r.Logo_URL__c,
                       Participant_1_Unread_Count__c, Participant_2_Unread_Count__c
                FROM Conversation__c
                WHERE Id = :conversationId LIMIT 1
            ];

            Boolean isP1 = (conv.Participant_1__c == myContactId);
            Boolean isP2 = (conv.Participant_2__c == myContactId);
            if (!isP1 && !isP2) {
                throw new AuraHandledException('You are not a participant in this conversation.');
            }

            Contact otherParticipant = isP1 ? conv.Participant_2__r : conv.Participant_1__r;
            Boolean otherIsOrg = otherParticipant?.Is_Organization_Contact__c == true;
            result.otherParticipantName = otherIsOrg
                ? otherParticipant.Organization_Account__r?.Name
                : otherParticipant?.Name;
            result.otherParticipantFirstName = otherParticipant?.FirstName;
            result.otherParticipantId = isP1 ? conv.Participant_2__c : conv.Participant_1__c;
            result.otherParticipantImageUrl = otherIsOrg
                ? otherParticipant.Organization_Account__r?.Logo_URL__c
                : otherParticipant?.Image_URL__c;
            result.isOtherParticipantOrg = otherIsOrg;
            result.isActingAsSelf = (identity.currentUser.ContactId == identity.actingAsContactId);
            result.actingAsContactName = identity.orgDisplayName;
            result.myContactImageUrl = identity.orgAvatarUrl;
            result.myContactId = myContactId;
            result.contextType = conv.Context_Type__c;
            result.relatedRecordId = conv.Related_Record_Id__c;
            result.relatedRecordTitle = resolveRelatedRecordTitle(conv.Context_Type__c, conv.Related_Record_Id__c);
            result.isLocked = (conv.Locked__c == true);

            Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : 50;
            Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;

            result.totalCount = [SELECT COUNT() FROM Message__c WHERE Conversation__c = :conversationId];

            List<Message__c> messages = [
                SELECT Id, Body__c, Sender__c, Sender__r.Name, Sender__r.FirstName,
                       Sender__r.Image_URL__c,
                       Sender__r.Is_Organization_Contact__c,
                       Sender__r.Organization_Account__r.Name,
                       Sender__r.Organization_Account__r.Logo_URL__c,
                       Sent_By__c, Sent_By__r.Name, Sent_By__r.FirstName,
                       Sent_Date__c, Status__c, Read_Date__c,
                       Is_System_Message__c, System_Message_Type__c
                FROM Message__c
                WHERE Conversation__c = :conversationId
                ORDER BY Sent_Date__c ASC
                LIMIT :limitSize
                OFFSET :offsetVal
            ];

            // Collect unread messages from the other participant to mark as read
            List<Message__c> toMarkRead = new List<Message__c>();
            Datetime now = Datetime.now();

            for (Message__c msg : messages) {
                MessageWrapper w = new MessageWrapper();
                w.id = msg.Id;
                w.body = msg.Body__c;
                w.senderContactId = msg.Sender__c;

                Boolean senderIsOrg = msg.Sender__r?.Is_Organization_Contact__c == true;
                w.senderIsOrg = senderIsOrg;
                if (senderIsOrg) {
                    w.senderName = FimbyIdentityRepository.buildOrgDisplayName(
                        msg.Sender__r.Organization_Account__r?.Name,
                        msg.Sent_By__r?.FirstName
                    );
                    w.senderImageUrl = msg.Sender__r.Organization_Account__r?.Logo_URL__c;
                } else {
                    w.senderName = msg.Sender__r?.Name;
                    w.senderImageUrl = msg.Sender__r?.Image_URL__c;
                }
                w.senderFirstName = msg.Sender__r?.FirstName;
                w.sentByContactId = msg.Sent_By__c;
                w.sentByName = msg.Sent_By__r?.Name;
                w.sentByFirstName = msg.Sent_By__r?.FirstName;
                w.isOnBehalfOf = (msg.Sender__c != msg.Sent_By__c);
                w.sentDate = msg.Sent_Date__c;
                w.status = msg.Status__c;
                w.isRead = (msg.Read_Date__c != null);
                w.isMine = (msg.Sender__c == myContactId);
                w.isSystemMessage = (msg.Is_System_Message__c == true);
                w.systemMessageType = msg.System_Message_Type__c;
                result.messages.add(w);

                // Mark messages from the other person as read
                if (msg.Sender__c != myContactId && msg.Read_Date__c == null) {
                    msg.Read_Date__c = now;
                    toMarkRead.add(msg);
                }
            }

            // Batch update read dates
            if (!toMarkRead.isEmpty()) {
                update toMarkRead;

                // Reset unread count for this participant
                if (isP1) {
                    conv.Participant_1_Unread_Count__c = 0;
                } else {
                    conv.Participant_2_Unread_Count__c = 0;
                }
                update conv;
            }

            return result;
        }

        /**
         * @description Resolves the display title for a conversation's related record.
         * Library_Lending is skipped — the LWC uses lendingContext.itemName instead.
         * For Bulk_Buy, Missed_Pickup, and Event, queries Needs_Offers__c.Name.
         */
        private String resolveRelatedRecordTitle(String contextType, String relatedRecordId) {
            if (String.isBlank(contextType) || String.isBlank(relatedRecordId)
                || contextType == 'Direct' || contextType == 'Library_Lending') {
                return null;
            }
            try {
                Id recordId = Id.valueOf(relatedRecordId);
                String sObjectType = recordId.getSObjectType().getDescribe().getName();
                if (sObjectType == 'Needs_Offers__c') {
                    List<Needs_Offers__c> records = [
                        SELECT Name FROM Needs_Offers__c WHERE Id = :recordId LIMIT 1
                    ];
                    return records.isEmpty() ? null : records[0].Name;
                }
                if (sObjectType == 'Skill_Offer__c') {
                    List<Skill_Offer__c> records = [
                        SELECT Name FROM Skill_Offer__c WHERE Id = :recordId LIMIT 1
                    ];
                    return records.isEmpty() ? null : records[0].Name;
                }
            } catch (Exception e) {
                return null;
            }
            return null;
        }

        /**
         * @description Sends a message in a conversation; creates Message__c, updates Conversation__c summary, fires push notification.
         * @param conversationId Id of the Conversation__c
         * @param body Message body text (max 5000 chars)
         * @return Map with success, messageId, sentDate
         */
        public Map<String, Object> sendMessageInternal(Id conversationId, String body) {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            if (identity == null) {
                throw new AuraHandledException('Unable to resolve current user identity.');
            }

            if (String.isBlank(body) || body.trim().length() == 0) {
                throw new AuraHandledException('Message cannot be empty.');
            }

            if (body.length() > 5000) {
                throw new AuraHandledException('Message is too long. Maximum 5000 characters.');
            }

            String realContactId = identity.currentUser.ContactId;
            String actingAsContactId = identity.actingAsContactId;
            String actingAsContactName = identity.orgDisplayName;

            // Verify participation and check for blocks
            Conversation__c conv = [
                SELECT Id, Participant_1__c, Participant_2__c, Status__c, Locked__c,
                       Participant_1_Unread_Count__c, Participant_2_Unread_Count__c
                FROM Conversation__c
                WHERE Id = :conversationId LIMIT 1
            ];

            if (conv.Status__c == FimbyConstants.CONVERSATION_BLOCKED) {
                throw new AuraHandledException('This conversation has been blocked.');
            }

            if (conv.Locked__c == true) {
                throw new AuraHandledException('This conversation is read-only.');
            }

            Boolean isP1 = (conv.Participant_1__c == actingAsContactId);
            Boolean isP2 = (conv.Participant_2__c == actingAsContactId);
            if (!isP1 && !isP2) {
                throw new AuraHandledException('You are not a participant in this conversation.');
            }

            // Bypass SCI check when either participant is an org contact
            Id p1 = conv.Participant_1__c;
            Id p2 = conv.Participant_2__c;
            Boolean eitherIsOrg = identity.isOrgContact;
            if (!eitherIsOrg) {
                Id otherParticipantId = isP1 ? p2 : p1;
                eitherIsOrg = [
                    SELECT COUNT() FROM Contact
                    WHERE Id = :otherParticipantId AND Is_Organization_Contact__c = true
                ] > 0;
            }
            if (!eitherIsOrg) {
                Integer activeSciCount = [
                    SELECT COUNT() FROM Shared_Contact_Info__c
                    WHERE ((Contact__c = :p1 AND Shared_To__c = :p2)
                        OR (Contact__c = :p2 AND Shared_To__c = :p1))
                      AND (Status__c = 'Active' OR Status__c = null)
                ];
                if (activeSciCount == 0) {
                    throw new AuraHandledException('You are no longer connected to this contact.');
                }
            }

            String recipientContactId = isP1 ? conv.Participant_2__c : conv.Participant_1__c;

            // Create the message
            String cleanBody = body.trim();
            Datetime now = Datetime.now();

            Message__c newMsg = new Message__c(
                Conversation__c = conversationId,
                Sender__c = actingAsContactId,
                Sent_By__c = realContactId,
                Body__c = cleanBody,
                Sent_Date__c = now,
                Status__c = FimbyConstants.MESSAGE_SENT
            );

            try {
                insert newMsg;
            } catch (Exception e) {
                throw new AuraHandledException('Failed to send message: ' + e.getMessage());
            }

            // Update conversation summary
            String preview = cleanBody.length() > 255 ? cleanBody.substring(0, 252) + '...' : cleanBody;
            conv.Last_Message_Preview__c = preview;
            conv.Last_Message_Date__c = now;
            conv.Last_Message_Sender__c = actingAsContactId;

            // Increment unread count for the recipient
            if (isP1) {
                conv.Participant_2_Unread_Count__c = (conv.Participant_2_Unread_Count__c != null
                    ? conv.Participant_2_Unread_Count__c : 0) + 1;
                // Un-archive for recipient if they archived it
                conv.Participant_2_Archived__c = false;
            } else {
                conv.Participant_1_Unread_Count__c = (conv.Participant_1_Unread_Count__c != null
                    ? conv.Participant_1_Unread_Count__c : 0) + 1;
                conv.Participant_1_Archived__c = false;
            }
            update conv;

            String msgSnippet = cleanBody.length() > 140 ? cleanBody.substring(0, 137) + '...' : cleanBody;
            FimbyNotificationService.createNotification(
                recipientContactId,
                FimbyConstants.NOTIF_MESSAGE,
                actingAsContactName,
                msgSnippet,
                conversationId,
                'Conversation__c',
                FimbySettings.getUrl('Conversation', conversationId),
                actingAsContactName
            );

            return new Map<String, Object>{
                'success' => true,
                'messageId' => newMsg.Id,
                'sentDate' => now
            };
        }

    }

    /* ---------------------------------------------------------------
     * Wrapper classes
     * --------------------------------------------------------------- */
    public class MessageListResult {
        @AuraEnabled public List<MessageWrapper> messages { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public String otherParticipantName { get; set; }
        @AuraEnabled public String otherParticipantFirstName { get; set; }
        @AuraEnabled public Id otherParticipantId { get; set; }
        @AuraEnabled public String otherParticipantImageUrl { get; set; }
        @AuraEnabled public Boolean isOtherParticipantOrg { get; set; }
        @AuraEnabled public Boolean isActingAsSelf { get; set; }
        @AuraEnabled public String actingAsContactName { get; set; }
        @AuraEnabled public String myContactImageUrl { get; set; }
        @AuraEnabled public String myContactId { get; set; }
        @AuraEnabled public String contextType { get; set; }
        @AuraEnabled public String relatedRecordId { get; set; }
        @AuraEnabled public String relatedRecordTitle { get; set; }
        @AuraEnabled public Boolean isLocked { get; set; }
    }

    public class MessageWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String body { get; set; }
        @AuraEnabled public Id senderContactId { get; set; }
        @AuraEnabled public String senderName { get; set; }
        @AuraEnabled public String senderFirstName { get; set; }
        @AuraEnabled public String senderImageUrl { get; set; }
        @AuraEnabled public Boolean senderIsOrg { get; set; }
        @AuraEnabled public Id sentByContactId { get; set; }
        @AuraEnabled public String sentByName { get; set; }
        @AuraEnabled public String sentByFirstName { get; set; }
        @AuraEnabled public Boolean isOnBehalfOf { get; set; }
        @AuraEnabled public Datetime sentDate { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Boolean isRead { get; set; }
        @AuraEnabled public Boolean isMine { get; set; }
        @AuraEnabled public Boolean isSystemMessage { get; set; }
        @AuraEnabled public String systemMessageType { get; set; }
    }

}