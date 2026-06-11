/**
 * @description Manages 1:1 conversation threads for the FIMBY messaging system. Identity resolution delegated to FimbyIdentityRepository. Uses a without sharing inner class for community user access.
 */
public with sharing class FimbyConversationController {

    private static Integer MAX_NEW_CONVERSATIONS_PER_DAY = FimbySettings.maxNewConversationsPerDay();

    /**
     * Get paginated conversation threads for the current user.
     * Returns newest-message-first. Supports filter (all, unread, archived)
     * and free-text search against the other participant's name.
     */
    @AuraEnabled(cacheable=false)
    public static ConversationListResult getConversations(
        Integer pageSize, Integer offset, String filter, String searchTerm
    ) {
        return new ConversationHelper().getConversationsInternal(pageSize, offset, filter, searchTerm);
    }

    /**
     * Find an existing conversation with the target contact, or create one.
     * Validates shared contact info exists and no block is active.
     * Rate-limited: max 5 new conversations per day.
     */
    @AuraEnabled
    public static Map<String, Object> getOrCreateConversation(String targetContactId) {
        return new ConversationHelper().getOrCreateConversationInternal(targetContactId);
    }

    /**
     * Validate messaging eligibility and return draft header info without creating a record.
     * If a Direct conversation already exists, returns its id for redirect.
     */
    @AuraEnabled
    public static DraftConversationResult prepareDirectConversation(String targetContactId) {
        return new ConversationHelper().prepareDirectConversationInternal(targetContactId);
    }

    /**
     * Find or create a Direct conversation, then send the first (or next) message.
     * Rate limit applies only when a new conversation is created.
     */
    @AuraEnabled
    public static Map<String, Object> sendDirectMessage(String targetContactId, String body) {
        return new ConversationHelper().sendDirectMessageInternal(targetContactId, body);
    }

    /**
     * Archive a conversation for the current user (per-user flag).
     */
    @AuraEnabled
    public static void archiveConversation(Id conversationId) {
        new ConversationHelper().archiveConversationInternal(conversationId);
    }

    /**
     * Unarchive a conversation for the current user.
     */
    @AuraEnabled
    public static void unarchiveConversation(Id conversationId) {
        new ConversationHelper().unarchiveConversationInternal(conversationId);
    }

    /**
     * Get total unread message count across all conversations (for tab badge).
     */
    @AuraEnabled(cacheable=false)
    public static Integer getUnreadMessageCount() {
        return new ConversationHelper().getUnreadMessageCountInternal();
    }

    /**
     * Block a contact. Creates Blocked_Contact__c and sets conversation to Blocked.
     */
    @AuraEnabled
    public static Map<String, Object> blockContact(
        String blockedContactId, String reason, Boolean isReport, String reportDetails
    ) {
        return new ConversationHelper().blockContactInternal(blockedContactId, reason, isReport, reportDetails);
    }

    /**
     * Unblock a contact. Removes Blocked_Contact__c and reactivates conversation.
     */
    @AuraEnabled
    public static void unblockContact(String blockedContactId) {
        new ConversationHelper().unblockContactInternal(blockedContactId);
    }

    /**
     * Get the list of contacts blocked by the current user.
     */
    @AuraEnabled(cacheable=false)
    public static List<BlockedContactWrapper> getBlockedContacts() {
        return new ConversationHelper().getBlockedContactsInternal();
    }

    /**
     * Search neighbourhood contacts to block (same Account, excluding self and already blocked).
     */
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> searchNeighboursForBlock(String searchTerm) {
        return new ConversationHelper().searchNeighboursForBlockInternal(searchTerm);
    }

    /**
     * Get the list of shared contacts available for starting new conversations.
     * Returns contacts from Shared_Contact_Info__c (either direction).
     */
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getMessageableContacts(String searchTerm) {
        return new ConversationHelper().getMessageableContactsInternal(searchTerm);
    }

    /**
     * Check if a conversation's shared contact info has been revoked.
     * Returns true if no Active SCI records exist between the participants.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean isConversationRevoked(Id conversationId) {
        return new ConversationHelper().isConversationRevokedInternal(conversationId);
    }

    /**
     * @description Without sharing helper for community user access to Contact, Conversation__c, Shared_Contact_Info__c, Blocked_Contact__c.
     */
    private without sharing class ConversationHelper {

        private Boolean eitherIsOrgContact(Id contactId1, Id contactId2) {
            return [
                SELECT COUNT() FROM Contact
                WHERE Id IN (:contactId1, :contactId2)
                  AND Is_Organization_Contact__c = true
            ] > 0;
        }

        private Boolean isModeratorForContact(Id moderatorContactId, Id targetContactId) {
            List<Contact> targets = [
                SELECT AccountId FROM Contact WHERE Id = :targetContactId LIMIT 1
            ];
            if (targets.isEmpty() || targets[0].AccountId == null) {
                return false;
            }
            return [
                SELECT COUNT() FROM Moderator_Assignment__c
                WHERE Contact__c = :moderatorContactId
                  AND Neighbourhood__c = :targets[0].AccountId
                  AND Status__c = 'Active'
            ] > 0;
        }

        private Set<Id> getBlockedContactIds(String myContactId) {
            return FimbyBlockingHelper.getBidirectionalBlocks((Id) myContactId);
        }

        /**
         * Determines which participant slot (1 or 2) the current user occupies.
         * Returns 1, 2, or 0 if not a participant.
         */
        private Integer getParticipantSlot(Conversation__c conv, String contactId) {
            if (conv.Participant_1__c == contactId) return 1;
            if (conv.Participant_2__c == contactId) return 2;
            return 0;
        }

        /**
         * @description Fetches paginated conversations with filter (all/unread/archived) and search.
         * @param pageSize Number of items per page
         * @param offset Pagination offset
         * @param filter all, unread, or archived
         * @param searchTerm Free-text search against other participant's name
         * @return ConversationListResult with conversations and totalCount
         */
        public ConversationListResult getConversationsInternal(
            Integer pageSize, Integer offset, String filter, String searchTerm
        ) {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            ConversationListResult result = new ConversationListResult();
            result.conversations = new List<ConversationWrapper>();

            if (identity == null) {
                result.totalCount = 0;
                return result;
            }

            String myContactId = identity.actingAsContactId;
            Set<Id> blockedIds = getBlockedContactIds(myContactId);

            Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : FimbySettings.messagesPageSize();
            Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;
            String filterVal = String.isNotBlank(filter) ? filter.toLowerCase() : 'all';

            // Build dynamic query
            String baseCondition = '(Participant_1__c = :myContactId OR Participant_2__c = :myContactId)';
            String statusCondition = ' AND Status__c != \'Blocked\'';

            String filterCondition = '';
            if (filterVal == 'unread') {
                filterCondition = ' AND ((Participant_1__c = :myContactId AND Participant_1_Unread_Count__c > 0)'
                    + ' OR (Participant_2__c = :myContactId AND Participant_2_Unread_Count__c > 0))';
            } else if (filterVal == 'archived') {
                filterCondition = ' AND ((Participant_1__c = :myContactId AND Participant_1_Archived__c = true)'
                    + ' OR (Participant_2__c = :myContactId AND Participant_2_Archived__c = true))';
            } else {
                // 'all' — exclude archived
                filterCondition = ' AND ((Participant_1__c = :myContactId AND Participant_1_Archived__c = false)'
                    + ' OR (Participant_2__c = :myContactId AND Participant_2_Archived__c = false))';
            }

            String whereClause = baseCondition + statusCondition + filterCondition;

            // Count
            String countQuery = 'SELECT COUNT() FROM Conversation__c WHERE ' + whereClause;
            result.totalCount = Database.countQuery(countQuery);

            // Main query
            String mainQuery = 'SELECT Id, Participant_1__c, Participant_2__c,'
                + ' Participant_1__r.Name, Participant_1__r.FirstName, Participant_1__r.LastName,'
                + ' Participant_2__r.Name, Participant_2__r.FirstName, Participant_2__r.LastName,'
                + ' Last_Message_Preview__c, Last_Message_Date__c, Last_Message_Sender__c,'
                + ' Participant_1_Unread_Count__c, Participant_2_Unread_Count__c,'
                + ' Participant_1_Archived__c, Participant_2_Archived__c, Status__c'
                + ' FROM Conversation__c WHERE ' + whereClause
                + ' ORDER BY Last_Message_Date__c DESC NULLS LAST'
                + ' LIMIT :limitSize OFFSET :offsetVal';

            List<Conversation__c> conversations = Database.query(mainQuery);

            for (Conversation__c conv : conversations) {
                // Determine other participant
                Boolean isP1 = (conv.Participant_1__c == myContactId);
                String otherName = isP1 ? conv.Participant_2__r?.Name : conv.Participant_1__r?.Name;
                String otherFirstName = isP1 ? conv.Participant_2__r?.FirstName : conv.Participant_1__r?.FirstName;
                String otherId = isP1 ? conv.Participant_2__c : conv.Participant_1__c;

                // Skip blocked contacts
                if (blockedIds.contains(otherId)) continue;

                // Apply search filter on other participant's name
                if (String.isNotBlank(searchTerm)) {
                    String term = searchTerm.toLowerCase();
                    if (otherName == null || !otherName.toLowerCase().contains(term)) {
                        continue;
                    }
                }

                ConversationWrapper w = new ConversationWrapper();
                w.conversationId = conv.Id;
                w.participantName = otherName;
                w.participantFirstName = otherFirstName;
                w.participantId = otherId;
                w.lastMessage = conv.Last_Message_Preview__c;
                w.lastMessageDate = conv.Last_Message_Date__c;
                w.unreadCount = isP1
                    ? (conv.Participant_1_Unread_Count__c != null ? conv.Participant_1_Unread_Count__c.intValue() : 0)
                    : (conv.Participant_2_Unread_Count__c != null ? conv.Participant_2_Unread_Count__c.intValue() : 0);
                w.isArchived = isP1 ? conv.Participant_1_Archived__c : conv.Participant_2_Archived__c;
                w.isActingAsSelf = (identity.currentUser.ContactId == identity.actingAsContactId);
                w.actingAsContactName = identity.orgDisplayName;
                result.conversations.add(w);
            }

            return result;
        }

        private String resolveActingAsContactId() {
            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId)) {
                throw new AuraHandledException('Unable to resolve current user identity.');
            }
            return myContactId;
        }

        private void validateCanMessage(String myContactId, String targetContactId) {
            if (myContactId == targetContactId) {
                throw new AuraHandledException('You cannot start a conversation with yourself.');
            }

            if (!eitherIsOrgContact(myContactId, targetContactId)
                && !isModeratorForContact(myContactId, targetContactId)) {
                Integer sharedCount = [
                    SELECT COUNT() FROM Shared_Contact_Info__c
                    WHERE ((Contact__c = :myContactId AND Shared_To__c = :targetContactId)
                       OR (Contact__c = :targetContactId AND Shared_To__c = :myContactId))
                      AND (Status__c = 'Active' OR Status__c = null)
                ];
                if (sharedCount == 0) {
                    throw new AuraHandledException('Contact info sharing has been revoked. You cannot start new conversations.');
                }
            }

            Integer blockCount = [
                SELECT COUNT() FROM Blocked_Contact__c
                WHERE (Blocker__c = :myContactId AND Blocked__c = :targetContactId)
                   OR (Blocker__c = :targetContactId AND Blocked__c = :myContactId)
            ];
            if (blockCount > 0) {
                throw new AuraHandledException('This contact is blocked.');
            }
        }

        private Conversation__c findDirectConversation(String myContactId, String targetContactId) {
            List<Conversation__c> existing = [
                SELECT Id, Status__c,
                       Participant_1__c, Participant_2__c,
                       Participant_1_Archived__c, Participant_2_Archived__c
                FROM Conversation__c
                WHERE ((Participant_1__c = :myContactId AND Participant_2__c = :targetContactId)
                    OR (Participant_1__c = :targetContactId AND Participant_2__c = :myContactId))
                  AND (Context_Type__c = null OR Context_Type__c = :FimbyConstants.CTX_DIRECT)
                LIMIT 1
            ];

            if (existing.isEmpty()) {
                return null;
            }

            Conversation__c conv = existing[0];
            Boolean isP1 = (conv.Participant_1__c == myContactId);
            if ((isP1 && conv.Participant_1_Archived__c) ||
                (!isP1 && conv.Participant_2_Archived__c)) {
                Conversation__c upd = new Conversation__c(Id = conv.Id);
                if (isP1) {
                    upd.Participant_1_Archived__c = false;
                } else {
                    upd.Participant_2_Archived__c = false;
                }
                update upd;
            }
            return conv;
        }

        private Conversation__c createDirectConversation(String myContactId, String targetContactId) {
            Date today = Date.today();
            Datetime startOfDay = Datetime.newInstance(today.year(), today.month(), today.day(), 0, 0, 0);
            Integer todayCount = [
                SELECT COUNT() FROM Conversation__c
                WHERE Participant_1__c = :myContactId
                  AND CreatedDate >= :startOfDay
            ];
            if (todayCount >= MAX_NEW_CONVERSATIONS_PER_DAY) {
                throw new AuraHandledException(
                    'You\'ve reached the daily limit of ' + MAX_NEW_CONVERSATIONS_PER_DAY
                    + ' new conversations. Please try again tomorrow.'
                );
            }

            Conversation__c newConv = new Conversation__c(
                Participant_1__c = myContactId,
                Participant_2__c = targetContactId,
                Context_Type__c = FimbyConstants.CTX_DIRECT,
                Status__c = FimbyConstants.CONVERSATION_ACTIVE,
                Participant_1_Unread_Count__c = 0,
                Participant_2_Unread_Count__c = 0,
                Participant_1_Archived__c = false,
                Participant_2_Archived__c = false
            );
            insert newConv;
            return newConv;
        }

        private DraftConversationResult buildDraftResult(
            FimbyIdentityRepository.Identity identity,
            String myContactId,
            String targetContactId,
            Conversation__c existingConv
        ) {
            List<Contact> targets = [
                SELECT Id, Name, FirstName, Image_URL__c,
                       Is_Organization_Contact__c,
                       Organization_Account__r.Name,
                       Organization_Account__r.Logo_URL__c
                FROM Contact
                WHERE Id = :targetContactId
                LIMIT 1
            ];
            if (targets.isEmpty()) {
                throw new AuraHandledException('Contact not found.');
            }

            Contact other = targets[0];
            Boolean otherIsOrg = other.Is_Organization_Contact__c == true;

            DraftConversationResult result = new DraftConversationResult();
            result.conversationId = existingConv != null ? existingConv.Id : null;
            result.isExisting = existingConv != null;
            result.otherParticipantId = other.Id;
            result.otherParticipantName = otherIsOrg
                ? other.Organization_Account__r?.Name
                : other.Name;
            result.otherParticipantFirstName = other.FirstName;
            result.otherParticipantImageUrl = otherIsOrg
                ? other.Organization_Account__r?.Logo_URL__c
                : other.Image_URL__c;
            result.isOtherParticipantOrg = otherIsOrg;
            result.myContactId = myContactId;
            result.myContactImageUrl = identity.orgAvatarUrl;
            result.isActingAsSelf = (identity.currentUser.ContactId == identity.actingAsContactId);
            result.actingAsContactName = identity.orgDisplayName;
            return result;
        }

        /**
         * @description Finds or creates a conversation with the target contact; validates shared contact info and blocks.
         * @param targetContactId Contact Id to start conversation with
         * @return Map with success, conversationId, and isNew flag
         */
        public Map<String, Object> getOrCreateConversationInternal(String targetContactId) {
            String myContactId = resolveActingAsContactId();
            validateCanMessage(myContactId, targetContactId);

            Conversation__c existing = findDirectConversation(myContactId, targetContactId);
            if (existing != null) {
                return new Map<String, Object>{
                    'success' => true,
                    'conversationId' => existing.Id,
                    'isNew' => false
                };
            }

            Conversation__c newConv = createDirectConversation(myContactId, targetContactId);
            return new Map<String, Object>{
                'success' => true,
                'conversationId' => newConv.Id,
                'isNew' => true
            };
        }

        /**
         * @description Validates messaging eligibility and returns draft header info without inserting a record.
         */
        public DraftConversationResult prepareDirectConversationInternal(String targetContactId) {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            if (identity == null) {
                throw new AuraHandledException('Unable to resolve current user identity.');
            }

            String myContactId = identity.actingAsContactId;
            validateCanMessage(myContactId, targetContactId);
            Conversation__c existing = findDirectConversation(myContactId, targetContactId);
            return buildDraftResult(identity, myContactId, targetContactId, existing);
        }

        /**
         * @description Finds or creates a Direct conversation, then sends the message via FimbyMessageController.
         */
        public Map<String, Object> sendDirectMessageInternal(String targetContactId, String body) {
            String myContactId = resolveActingAsContactId();
            validateCanMessage(myContactId, targetContactId);

            Conversation__c conv = findDirectConversation(myContactId, targetContactId);
            Boolean isNew = false;
            if (conv == null) {
                conv = createDirectConversation(myContactId, targetContactId);
                isNew = true;
            }

            Map<String, Object> sendResult = FimbyMessageController.sendMessage(conv.Id, body);
            sendResult.put('conversationId', conv.Id);
            sendResult.put('isNew', isNew);
            return sendResult;
        }

        /**
         * @description Archives a conversation for the current user (sets Participant_X_Archived__c).
         * @param conversationId Id of the Conversation__c
         */
        public void archiveConversationInternal(Id conversationId) {
            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId) || conversationId == null) return;

            Conversation__c conv = [
                SELECT Id, Participant_1__c, Participant_2__c,
                       Participant_1_Archived__c, Participant_2_Archived__c
                FROM Conversation__c WHERE Id = :conversationId LIMIT 1
            ];

            Integer slot = getParticipantSlot(conv, myContactId);
            if (slot == 1) conv.Participant_1_Archived__c = true;
            else if (slot == 2) conv.Participant_2_Archived__c = true;
            else throw new AuraHandledException('You are not a participant in this conversation.');

            update conv;
        }

        public void unarchiveConversationInternal(Id conversationId) {
            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId) || conversationId == null) return;

            Conversation__c conv = [
                SELECT Id, Participant_1__c, Participant_2__c,
                       Participant_1_Archived__c, Participant_2_Archived__c
                FROM Conversation__c WHERE Id = :conversationId LIMIT 1
            ];

            Integer slot = getParticipantSlot(conv, myContactId);
            if (slot == 1) conv.Participant_1_Archived__c = false;
            else if (slot == 2) conv.Participant_2_Archived__c = false;
            else throw new AuraHandledException('You are not a participant in this conversation.');

            update conv;
        }

        /**
         * @description Counts DM conversations with unread messages for the current user.
         * Each conversation contributes at most 1, regardless of unread message count.
         * @return Unread conversation count
         */
        public Integer getUnreadMessageCountInternal() {
            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId)) return 0;

            Set<Id> blockedContactIds = FimbyBlockingHelper.getBidirectionalBlocks((Id) myContactId);
            Integer total = 0;
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
                    total++;
                }
            }
            return total;
        }

        /**
         * @description Blocks a contact; creates Blocked_Contact__c and sets conversation(s) to Blocked.
         * @param blockedContactId Contact Id to block
         * @param reason Block reason
         * @param isReport Whether this is a report
         * @param reportDetails Optional report details
         * @return Map with success and alreadyBlocked flag
         */
        public Map<String, Object> blockContactInternal(
            String blockedContactId, String reason, Boolean isReport, String reportDetails
        ) {
            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId)) {
                throw new AuraHandledException('Unable to resolve current user identity.');
            }

            // Check if already blocked
            List<Blocked_Contact__c> existing = [
                SELECT Id FROM Blocked_Contact__c
                WHERE Blocker__c = :myContactId AND Blocked__c = :blockedContactId
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return new Map<String, Object>{ 'success' => true, 'alreadyBlocked' => true };
            }

            Blocked_Contact__c block = new Blocked_Contact__c(
                Blocker__c = myContactId,
                Blocked__c = blockedContactId,
                Reason__c = reason,
                Reported__c = (isReport == true),
                Report_Details__c = reportDetails
            );
            insert block;

            // Set conversation status to Blocked
            List<Conversation__c> convs = [
                SELECT Id, Status__c FROM Conversation__c
                WHERE (Participant_1__c = :myContactId AND Participant_2__c = :blockedContactId)
                   OR (Participant_1__c = :blockedContactId AND Participant_2__c = :myContactId)
            ];
            for (Conversation__c conv : convs) {
                conv.Status__c = FimbyConstants.CONVERSATION_BLOCKED;
            }
            if (!convs.isEmpty()) update convs;

            return new Map<String, Object>{ 'success' => true, 'alreadyBlocked' => false };
        }

        /**
         * @description Unblocks a contact; removes Blocked_Contact__c and reactivates conversation if no reverse block.
         * @param blockedContactId Contact Id to unblock
         */
        public void unblockContactInternal(String blockedContactId) {
            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId)) return;

            List<Blocked_Contact__c> blocks = [
                SELECT Id FROM Blocked_Contact__c
                WHERE Blocker__c = :myContactId AND Blocked__c = :blockedContactId
            ];
            if (!blocks.isEmpty()) delete blocks;

            // Reactivate conversation if no reverse block exists
            Integer reverseBlockCount = [
                SELECT COUNT() FROM Blocked_Contact__c
                WHERE Blocker__c = :blockedContactId AND Blocked__c = :myContactId
            ];
            if (reverseBlockCount == 0) {
                List<Conversation__c> convs = [
                    SELECT Id, Status__c FROM Conversation__c
                    WHERE (Participant_1__c = :myContactId AND Participant_2__c = :blockedContactId)
                       OR (Participant_1__c = :blockedContactId AND Participant_2__c = :myContactId)
                ];
                for (Conversation__c conv : convs) {
                    conv.Status__c = FimbyConstants.CONVERSATION_ACTIVE;
                }
                if (!convs.isEmpty()) update convs;
            }
        }

        /**
         * @description Returns the list of contacts blocked by the current user.
         * @return List of BlockedContactWrapper
         */
        public List<BlockedContactWrapper> getBlockedContactsInternal() {
            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            List<BlockedContactWrapper> result = new List<BlockedContactWrapper>();
            if (String.isBlank(myContactId)) return result;

            for (Blocked_Contact__c bc : [
                SELECT Id, Blocked__c, Blocked__r.Name, Blocked__r.FirstName,
                       Reason__c, Reported__c, CreatedDate
                FROM Blocked_Contact__c
                WHERE Blocker__c = :myContactId
                ORDER BY CreatedDate DESC
            ]) {
                BlockedContactWrapper w = new BlockedContactWrapper();
                w.id = bc.Id;
                w.contactId = bc.Blocked__c;
                w.contactName = bc.Blocked__r?.Name;
                w.contactFirstName = bc.Blocked__r?.FirstName;
                w.reason = bc.Reason__c;
                w.isReported = bc.Reported__c;
                w.blockedDate = bc.CreatedDate;
                result.add(w);
            }
            return result;
        }

        /**
         * @description Searches contacts in the same neighbourhood who can be blocked.
         * @param searchTerm Name or email fragment (min 2 chars)
         * @return List of maps with contactId, contactName, firstName, email
         */
        public List<Map<String, Object>> searchNeighboursForBlockInternal(String searchTerm) {
            List<Map<String, Object>> results = new List<Map<String, Object>>();
            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId)) {
                return results;
            }

            Contact me = [SELECT Id, AccountId FROM Contact WHERE Id = :myContactId LIMIT 1];
            if (me.AccountId == null) {
                return results;
            }

            Set<Id> excludeIds = new Set<Id>{ me.Id };
            for (Blocked_Contact__c bc : [
                SELECT Blocked__c FROM Blocked_Contact__c WHERE Blocker__c = :myContactId
            ]) {
                if (bc.Blocked__c != null) {
                    excludeIds.add(bc.Blocked__c);
                }
            }

            if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
                return results;
            }

            String term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            for (Contact c : [
                SELECT Id, Name, FirstName, LastName, Full_Name__c, Email
                FROM Contact
                WHERE AccountId = :me.AccountId
                  AND Id NOT IN :excludeIds
                  AND Is_Organization_Contact__c = false
                  AND (Name LIKE :term OR Email LIKE :term OR FirstName LIKE :term
                       OR LastName LIKE :term OR Full_Name__c LIKE :term)
                ORDER BY Name
                LIMIT 20
            ]) {
                String displayName = String.isNotBlank(c.Full_Name__c) ? c.Full_Name__c : c.Name;
                results.add(new Map<String, Object>{
                    'contactId' => c.Id,
                    'contactName' => displayName,
                    'firstName' => c.FirstName,
                    'email' => c.Email
                });
            }
            return results;
        }

        /**
         * @description Returns contacts who have shared contact info (either direction) and are not blocked.
         * @param searchTerm Optional filter by name
         * @return List of maps with contactId, contactName, contactFirstName
         */
        public List<Map<String, Object>> getMessageableContactsInternal(String searchTerm) {
            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            if (String.isBlank(myContactId)) return result;

            Set<Id> blockedIds = getBlockedContactIds(myContactId);
            Id neighbourhoodId = FimbyIdentityRepository.getNeighbourhoodId();

            // Get all contacts who have shared info with me or I've shared with (Active only)
            Integer contactsLimit = FimbySettings.messageableContactsLimit();
            List<Shared_Contact_Info__c> shared = [
                SELECT Contact__c, Contact__r.Name, Contact__r.FirstName, Contact__r.Image_URL__c,
                       Shared_To__c, Shared_To__r.Name, Shared_To__r.FirstName, Shared_To__r.Image_URL__c
                FROM Shared_Contact_Info__c
                WHERE (Contact__c = :myContactId OR Shared_To__c = :myContactId)
                  AND (Status__c = 'Active' OR Status__c = null)
                ORDER BY CreatedDate DESC
                LIMIT :contactsLimit
            ];

            Set<Id> seen = new Set<Id>();
            String term = String.isNotBlank(searchTerm) ? searchTerm.toLowerCase() : null;

            for (Shared_Contact_Info__c sci : shared) {
                Id otherId = (sci.Contact__c == myContactId) ? sci.Shared_To__c : sci.Contact__c;
                String otherName = (sci.Contact__c == myContactId)
                    ? sci.Shared_To__r?.Name : sci.Contact__r?.Name;
                String otherFirstName = (sci.Contact__c == myContactId)
                    ? sci.Shared_To__r?.FirstName : sci.Contact__r?.FirstName;

                String otherImageUrl = (sci.Contact__c == myContactId)
                    ? sci.Shared_To__r?.Image_URL__c : sci.Contact__r?.Image_URL__c;

                if (otherId == null || seen.contains(otherId) || blockedIds.contains(otherId)) continue;
                seen.add(otherId);

                if (term != null && (otherName == null || !otherName.toLowerCase().contains(term))) continue;

                result.add(new Map<String, Object>{
                    'contactId' => otherId,
                    'contactName' => otherName,
                    'contactFirstName' => otherFirstName,
                    'isOrgContact' => false,
                    'avatarUrl' => otherImageUrl
                });
            }

            // Org contacts in the same neighbourhood are messageable without SCI
            List<Contact> orgContacts = [
                SELECT Id, Name, Organization_Account__c,
                       Organization_Account__r.Name, Organization_Account__r.Logo_URL__c
                FROM Contact
                WHERE Is_Organization_Contact__c = true
                  AND AccountId = :neighbourhoodId
                  AND Id != :myContactId
                  AND Id NOT IN :blockedIds
                ORDER BY Organization_Account__r.Name
                LIMIT 20
            ];
            for (Contact oc : orgContacts) {
                if (seen.contains(oc.Id)) continue;
                seen.add(oc.Id);
                String orgName = oc.Organization_Account__r?.Name;
                if (term != null && (orgName == null || !orgName.toLowerCase().contains(term))) continue;

                result.add(new Map<String, Object>{
                    'contactId' => oc.Id,
                    'contactName' => orgName != null ? orgName : oc.Name,
                    'contactFirstName' => orgName,
                    'isOrgContact' => true,
                    'avatarUrl' => oc.Organization_Account__r?.Logo_URL__c
                });
            }

            // Moderators can message all contacts in their assigned neighbourhoods
            Set<Id> modNeighbourhoodIds = new Set<Id>();
            for (Moderator_Assignment__c ma : [
                SELECT Neighbourhood__c FROM Moderator_Assignment__c
                WHERE Contact__c = :myContactId AND Status__c = 'Active'
            ]) {
                modNeighbourhoodIds.add(ma.Neighbourhood__c);
            }
            if (!modNeighbourhoodIds.isEmpty()) {
                List<Contact> nhContacts = [
                    SELECT Id, Name, FirstName, Image_URL__c
                    FROM Contact
                    WHERE AccountId IN :modNeighbourhoodIds
                      AND Id != :myContactId
                      AND Id NOT IN :blockedIds
                      AND Id NOT IN :seen
                    ORDER BY Name
                    LIMIT :contactsLimit
                ];
                for (Contact c : nhContacts) {
                    if (seen.contains(c.Id)) continue;
                    seen.add(c.Id);
                    if (term != null && (c.Name == null || !c.Name.toLowerCase().contains(term))) continue;
                    result.add(new Map<String, Object>{
                        'contactId' => c.Id,
                        'contactName' => c.Name,
                        'contactFirstName' => c.FirstName,
                        'isOrgContact' => false,
                        'avatarUrl' => c.Image_URL__c
                    });
                }
            }

            return result;
        }

        /**
         * @description Checks if shared contact info between conversation participants has been revoked.
         * @param conversationId Id of the Conversation__c
         * @return true if no Active Shared_Contact_Info__c exists between participants
         */
        public Boolean isConversationRevokedInternal(Id conversationId) {
            Conversation__c convo = [
                SELECT Participant_1__c, Participant_2__c, Context_Type__c
                FROM Conversation__c
                WHERE Id = :conversationId LIMIT 1
            ];

            if (convo.Context_Type__c == FimbyConstants.CTX_VOUCH_REQUEST) {
                return false;
            }

            Id p1 = convo.Participant_1__c;
            Id p2 = convo.Participant_2__c;

            if (eitherIsOrgContact(p1, p2)) {
                return false;
            }

            if (isModeratorForContact(p1, p2) || isModeratorForContact(p2, p1)) {
                return false;
            }

            Integer activeCount = [
                SELECT COUNT() FROM Shared_Contact_Info__c
                WHERE ((Contact__c = :p1 AND Shared_To__c = :p2)
                    OR (Contact__c = :p2 AND Shared_To__c = :p1))
                  AND (Status__c = 'Active' OR Status__c = null)
            ];
            return (activeCount == 0);
        }
    }

    /* ---------------------------------------------------------------
     * Wrapper classes
     * --------------------------------------------------------------- */
    public class ConversationListResult {
        @AuraEnabled public List<ConversationWrapper> conversations { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
    }

    public class ConversationWrapper {
        @AuraEnabled public Id conversationId { get; set; }
        @AuraEnabled public String participantName { get; set; }
        @AuraEnabled public String participantFirstName { get; set; }
        @AuraEnabled public Id participantId { get; set; }
        @AuraEnabled public String lastMessage { get; set; }
        @AuraEnabled public Datetime lastMessageDate { get; set; }
        @AuraEnabled public Integer unreadCount { get; set; }
        @AuraEnabled public Boolean isArchived { get; set; }
        @AuraEnabled public Boolean isActingAsSelf { get; set; }
        @AuraEnabled public String actingAsContactName { get; set; }
    }

    public class BlockedContactWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Id contactId { get; set; }
        @AuraEnabled public String contactName { get; set; }
        @AuraEnabled public String contactFirstName { get; set; }
        @AuraEnabled public String reason { get; set; }
        @AuraEnabled public Boolean isReported { get; set; }
        @AuraEnabled public Datetime blockedDate { get; set; }
    }

    public class DraftConversationResult {
        @AuraEnabled public Id conversationId { get; set; }
        @AuraEnabled public Boolean isExisting { get; set; }
        @AuraEnabled public String otherParticipantName { get; set; }
        @AuraEnabled public String otherParticipantFirstName { get; set; }
        @AuraEnabled public Id otherParticipantId { get; set; }
        @AuraEnabled public String otherParticipantImageUrl { get; set; }
        @AuraEnabled public Boolean isOtherParticipantOrg { get; set; }
        @AuraEnabled public String myContactId { get; set; }
        @AuraEnabled public String myContactImageUrl { get; set; }
        @AuraEnabled public Boolean isActingAsSelf { get; set; }
        @AuraEnabled public String actingAsContactName { get; set; }
    }
}