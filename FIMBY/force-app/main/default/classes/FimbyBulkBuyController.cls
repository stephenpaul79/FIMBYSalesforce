/**
 * @description Controller for Bulk Buy post lifecycle: create, update, detail, pickup, complete, cancel.
 * Follow-up-aware completion blocks manual complete when Pending/Escalated follow-ups exist.
 */
public with sharing class FimbyBulkBuyController {

    private static final String CLASS_NAME = 'FimbyBulkBuyController';

    @AuraEnabled
    public static Map<String, Object> createBulkBuyPost(String postData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(postData);
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;
            Id neighbourhoodId = identity.neighbourhoodId;

            Id recordTypeId = getRecordTypeId(FimbyConstants.RT_BULK_BUY);

            String title = (String) data.get('title');
            String description = (String) data.get('description');
            Decimal totalQuantity = toDecimal(data.get('totalQuantity'), 1);
            Decimal ownerShares = toDecimal(data.get('ownerShares'), 0);
            Decimal perResponseLimit = toDecimal(data.get('perResponseLimit'), null);
            String unitLabel = (String) data.get('unitLabel');
            String availabilityRule = (String) data.get('availabilityRule');
            String expiryDateStr = (String) data.get('expiryDateTime');
            Decimal totalEstimatedCost = toDecimal(data.get('totalEstimatedCost'), null);
            String autoLockDays = (String) data.get('autoLockDays');

            String details = description != null && description.length() > 255
                ? description.substring(0, 252) + '...' : description;

            Needs_Offers__c post = new Needs_Offers__c(
                RecordTypeId = recordTypeId,
                Name = title,
                Details__c = details,
                Full_Details__c = description,
                Status__c = FimbyConstants.NEEDS_OFFERS_AVAILABLE,
                Contact__c = actingAsContactId,
                Posted_By__c = realContactId,
                Neighbourhood__c = neighbourhoodId,
                Giver_Recipient_Type__c = FimbyConstants.VIS_SELF,
                Total_Quantity__c = totalQuantity,
                Owner_Shares__c = ownerShares,
                Per_Response_Limit__c = perResponseLimit,
                Allocation_Unit_Label__c = unitLabel,
                Availability_Rule__c = availabilityRule,
                Auto_Accept_Responses__c = true,
                Auto_Lock_Days__c = String.isNotBlank(autoLockDays) ? autoLockDays : '7'
            );

            if (totalEstimatedCost != null) {
                post.Total_Estimated_Cost__c = totalEstimatedCost;
            }
            if (String.isNotBlank(expiryDateStr) && availabilityRule == 'Expires_At_Date') {
                post.Expiry_DateTime__c = Datetime.valueOf(expiryDateStr.replace('T', ' '));
            }

            new BulkBuyHelper().insertRecord(post);

            return new Map<String, Object>{
                'success' => true,
                'recordId' => post.Id,
                'postUrl' => FimbySettings.getUrl('Asks_Offers', post.Id),
                'message' => 'Bulk buy posted successfully'
            };
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'createBulkBuyPost', e);
            throw buildAuraException('Error creating bulk buy: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> updateBulkBuyPost(String postData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(postData);
            String recordId = (String) data.get('recordId');

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Needs_Offers__c post = [
                SELECT Id, Posted_By__c, Contact__c, Total_Reserved__c, Owner_Shares__c
                FROM Needs_Offers__c
                WHERE Id = :recordId
                /* with sharing enforces record access */
                LIMIT 1
            ];

            if (post.Posted_By__c != realContactId && post.Contact__c != actingAsContactId) {
                throw new AuraHandledException('You can only edit posts you created.');
            }

            Decimal newQuantity = toDecimal(data.get('totalQuantity'), null);
            Decimal newOwnerShares = data.containsKey('ownerShares') ? toDecimal(data.get('ownerShares'), 0) : post.Owner_Shares__c;
            Decimal effectiveOwner = newOwnerShares != null ? newOwnerShares : 0;
            Decimal committed = post.Total_Reserved__c + effectiveOwner;
            if (newQuantity != null && newQuantity < committed) {
                throw new AuraHandledException('Total shares cannot be less than reserved + owner shares (' + committed.intValue() + ').');
            }

            if (newQuantity != null) { post.Total_Quantity__c = newQuantity; }
            if (data.containsKey('title')) { post.Name = (String) data.get('title'); }
            if (data.containsKey('description')) {
                String descText = (String) data.get('description');
                post.Full_Details__c = descText;
                post.Details__c = descText != null && descText.length() > 255 ? descText.substring(0, 252) + '...' : descText;
            }
            if (data.containsKey('ownerShares')) { post.Owner_Shares__c = toDecimal(data.get('ownerShares'), 0); }
            if (data.containsKey('unitLabel')) { post.Allocation_Unit_Label__c = (String) data.get('unitLabel'); }
            if (data.containsKey('perResponseLimit')) { post.Per_Response_Limit__c = toDecimal(data.get('perResponseLimit'), null); }
            if (data.containsKey('totalEstimatedCost')) { post.Total_Estimated_Cost__c = toDecimal(data.get('totalEstimatedCost'), null); }

            new BulkBuyHelper().updateRecord(post);

            return new Map<String, Object>{ 'success' => true, 'message' => 'Updated' };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'updateBulkBuyPost', e);
            throw buildAuraException('Error updating: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> getBulkBuyDetail(String recordId) {
        try {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Needs_Offers__c post = [
                SELECT Id, Name, Full_Details__c, Details__c, Status__c, Display_Status__c,
                       Total_Quantity__c, Total_Reserved__c, Total_Available__c, Owner_Shares__c,
                       Per_Response_Limit__c, Allocation_Unit_Label__c, Availability_Rule__c, Expiry_DateTime__c,
                       Total_Estimated_Cost__c, Estimated_Cost_Per_Share__c,
                       Pickup_Notified__c, Pickup_Notified_Date__c, Receipt_Image_URL__c,
                       Auto_Lock_Days__c, Group_Conversation__c, Active_Reserver_Ids__c,
                       Posted_By__c, Contact__c,
                       Image_1_URL__c, Image_2_URL__c, Image_3_URL__c, Image_4_URL__c,
                       CreatedDate, Posted_By__r.FirstName, Posted_By__r.LastName,
                       Neighbourhood__c
                FROM Needs_Offers__c
                WHERE Id = :recordId
                /* with sharing enforces record access */
                LIMIT 1
            ];

            Boolean isOrganiser = (post.Posted_By__c == realContactId || post.Contact__c == actingAsContactId);

            List<Map<String, Object>> reservations = new BulkBuyHelper().getReservations(recordId);

            return new Map<String, Object>{
                'success' => true,
                'post' => post,
                'isOrganiser' => isOrganiser,
                'reservations' => reservations,
                'contactId' => actingAsContactId
            };
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'getBulkBuyDetail', e);
            throw buildAuraException('Error loading detail: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> notifyForPickup(String postId, String message, String receiptImageUrl) {
        try {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Needs_Offers__c post = [
                SELECT Id, Posted_By__c, Contact__c, Status__c, Group_Conversation__c, Name
                FROM Needs_Offers__c
                WHERE Id = :postId
                /* with sharing enforces record access */
                LIMIT 1
            ];

            if (post.Posted_By__c != realContactId && post.Contact__c != actingAsContactId) {
                throw new AuraHandledException('Only the organiser can notify for pickup.');
            }

            post.Pickup_Notified__c = true;
            post.Pickup_Notified_Date__c = System.now();
            post.Status__c = FimbyConstants.NEEDS_OFFERS_PICKUP_READY;
            if (String.isNotBlank(receiptImageUrl)) {
                post.Receipt_Image_URL__c = receiptImageUrl;
            }

            new BulkBuyHelper().updateRecord(post);

            if (post.Group_Conversation__c != null) {
                FimbyGroupConversationController.sendSystemMessage(
                    post.Group_Conversation__c,
                    'Pickup is ready!',
                    FimbyConstants.SYS_MSG_PICKUP_READY,
                    true
                );
                if (String.isNotBlank(message)) {
                    FimbyGroupConversationController.sendGroupMessage(
                        post.Group_Conversation__c, message
                    );
                }
            }

            notifyAllReservers(postId, FimbyConstants.NOTIF_BULK_BUY_PICKUP,
                'Pickup is ready', post.Name);

            return new Map<String, Object>{ 'success' => true };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'notifyForPickup', e);
            throw buildAuraException('Error notifying: ' + e.getMessage());
        }
    }

    /**
     * @description Manual completion by organiser. Blocked while Pending/Escalated follow-ups exist.
     */
    @AuraEnabled
    public static Map<String, Object> completeBulkBuy(String postId) {
        try {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Needs_Offers__c post = [
                SELECT Id, Posted_By__c, Contact__c, Group_Conversation__c, Name
                FROM Needs_Offers__c
                WHERE Id = :postId
                /* with sharing enforces record access */
                LIMIT 1
            ];

            if (post.Posted_By__c != realContactId && post.Contact__c != actingAsContactId) {
                throw new AuraHandledException('Only the organiser can complete this bulk buy.');
            }

            List<Bulk_Buy_Follow_Up__c> activeFollowUps = [
                SELECT Id FROM Bulk_Buy_Follow_Up__c
                WHERE Bulk_Buy__c = :postId
                AND Status__c IN (:FimbyConstants.FOLLOWUP_PENDING, :FimbyConstants.FOLLOWUP_ESCALATED)
                /* with sharing enforces record access */
                LIMIT 1
            ];

            if (!activeFollowUps.isEmpty()) {
                throw new AuraHandledException('Resolve open check-ins before completing.');
            }

            completePost(post);

            return new Map<String, Object>{ 'success' => true };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'completeBulkBuy', e);
            throw buildAuraException('Error completing: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> cancelBulkBuy(String postId) {
        try {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Needs_Offers__c post = [
                SELECT Id, Posted_By__c, Contact__c, Group_Conversation__c, Name
                FROM Needs_Offers__c
                WHERE Id = :postId
                /* with sharing enforces record access */
                LIMIT 1
            ];

            if (post.Posted_By__c != realContactId && post.Contact__c != actingAsContactId) {
                throw new AuraHandledException('Only the organiser can cancel this bulk buy.');
            }

            post.Status__c = FimbyConstants.NEEDS_OFFERS_CANCELLED;
            new BulkBuyHelper().updateRecord(post);

            // Notify while reservations are still Reserved (notifyAllReservers filters by status).
            notifyAllReservers(postId, FimbyConstants.NOTIF_BULK_BUY_STATUS,
                post.Name + ' has been cancelled', '');

            List<Response__c> responses = new BulkBuyHelper().getReservedResponsesForCancel(postId);
            for (Response__c r : responses) {
                r.Status__c = FimbyConstants.RESPONSE_CANCELLED;
                r.Amount_Requested__c = 0;
            }
            if (!responses.isEmpty()) {
                new BulkBuyHelper().updateResponses(responses);
            }

            if (post.Group_Conversation__c != null) {
                FimbyGroupConversationController.sendSystemMessage(
                    post.Group_Conversation__c,
                    'This bulk buy has been cancelled.',
                    FimbyConstants.SYS_MSG_STATUS_CHANGE
                );
                FimbyGroupConversationController.lockConversation(post.Group_Conversation__c);
            }

            return new Map<String, Object>{ 'success' => true };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'cancelBulkBuy', e);
            throw buildAuraException('Error cancelling: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getMyBulkBuys() {
        try {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Id bulkBuyRtId = getRecordTypeId(FimbyConstants.RT_BULK_BUY);

            Set<Id> postIds = new Set<Id>();
            List<Map<String, Object>> results = new List<Map<String, Object>>();

            List<Needs_Offers__c> organised = [
                SELECT Id, Name, Display_Status__c, Total_Quantity__c, Total_Reserved__c, Owner_Shares__c,
                       Allocation_Unit_Label__c, CreatedDate, Image_1_URL__c
                FROM Needs_Offers__c
                WHERE (Contact__c = :actingAsContactId OR Posted_By__c = :realContactId)
                  AND RecordTypeId = :bulkBuyRtId
                /* with sharing enforces record access */
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
            for (Needs_Offers__c p : organised) {
                postIds.add(p.Id);
                results.add(new Map<String, Object>{
                    'id' => p.Id, 'name' => p.Name, 'displayStatus' => p.Display_Status__c,
                    'totalQuantity' => p.Total_Quantity__c, 'totalReserved' => p.Total_Reserved__c,
                    'unitLabel' => p.Allocation_Unit_Label__c, 'createdDate' => p.CreatedDate,
                    'imageUrl' => p.Image_1_URL__c, 'role' => 'organiser'
                });
            }

            List<Response__c> joined = [
                SELECT Need_Offer_Responded_To__c, Need_Offer_Responded_To__r.Name,
                       Need_Offer_Responded_To__r.Display_Status__c,
                       Need_Offer_Responded_To__r.Total_Quantity__c,
                       Need_Offer_Responded_To__r.Total_Reserved__c,
                       Need_Offer_Responded_To__r.Allocation_Unit_Label__c,
                       Need_Offer_Responded_To__r.CreatedDate,
                       Need_Offer_Responded_To__r.Image_1_URL__c,
                       Amount_Requested__c, Status__c
                FROM Response__c
                WHERE Contact__c = :actingAsContactId
                AND Need_Offer_Responded_To__r.RecordTypeId = :bulkBuyRtId
                AND Status__c != :FimbyConstants.RESPONSE_CANCELLED
                /* with sharing enforces record access */
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
            for (Response__c r : joined) {
                if (!postIds.contains(r.Need_Offer_Responded_To__c)) {
                    results.add(new Map<String, Object>{
                        'id' => r.Need_Offer_Responded_To__c,
                        'name' => r.Need_Offer_Responded_To__r.Name,
                        'displayStatus' => r.Need_Offer_Responded_To__r.Display_Status__c,
                        'totalQuantity' => r.Need_Offer_Responded_To__r.Total_Quantity__c,
                        'totalReserved' => r.Need_Offer_Responded_To__r.Total_Reserved__c,
                        'unitLabel' => r.Need_Offer_Responded_To__r.Allocation_Unit_Label__c,
                        'createdDate' => r.Need_Offer_Responded_To__r.CreatedDate,
                        'imageUrl' => r.Need_Offer_Responded_To__r.Image_1_URL__c,
                        'role' => 'reserver', 'myShares' => r.Amount_Requested__c
                    });
                }
            }

            return results;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'getMyBulkBuys', e);
            throw buildAuraException('Error loading bulk buys: ' + e.getMessage());
        }
    }

    /**
     * @description Shared completion logic used by both manual complete and auto-lock job.
     */
    public static void completePost(Needs_Offers__c post) {
        post.Status__c = FimbyConstants.NEEDS_OFFERS_COMPLETED;
        new BulkBuyHelper().updateRecord(post);

        List<Response__c> responses = new BulkBuyHelper().getResponsesForCompletion(post.Id);

        Set<Id> completedContactIds = new Set<Id>();
        List<Response__c> toUpdate = new List<Response__c>();

        for (Response__c r : responses) {
            if (r.Status__c == FimbyConstants.RESPONSE_NO_FOLLOW_THROUGH) {
                continue;
            }

            Boolean hasEscalated = false;
            Boolean hasNegativeOutcome = false;
            for (Bulk_Buy_Follow_Up__c fu : r.Follow_Ups__r) {
                if (fu.Status__c == FimbyConstants.FOLLOWUP_ESCALATED) {
                    hasEscalated = true;
                }
                if (fu.Status__c == FimbyConstants.FOLLOWUP_NO_RESPONSE ||
                    fu.Status__c == FimbyConstants.FOLLOWUP_ADMIN_CONFIRMED) {
                    hasNegativeOutcome = true;
                }
            }

            if (hasEscalated) {
                // Response stays Reserved -- admin resolves later
                continue;
            }
            if (hasNegativeOutcome) {
                r.Status__c = FimbyConstants.RESPONSE_NO_FOLLOW_THROUGH;
            } else {
                r.Status__c = FimbyConstants.RESPONSE_COMPLETED;
                completedContactIds.add(r.Contact__c);
            }
            toUpdate.add(r);
        }

        if (!toUpdate.isEmpty()) {
            new BulkBuyHelper().updateResponses(toUpdate);
        }

        if (!completedContactIds.isEmpty()) {
            incrementCompletedBulkBuys(completedContactIds);
        }
        incrementCompletedBulkBuys(new Set<Id>{ [SELECT Posted_By__c FROM Needs_Offers__c WHERE Id = :post.Id].Posted_By__c });

        recalculateBlockedFlags(responses);

        if (post.Group_Conversation__c != null) {
            FimbyGroupConversationController.sendSystemMessage(
                post.Group_Conversation__c,
                'This bulk buy has been completed -- thanks everyone!',
                FimbyConstants.SYS_MSG_STATUS_CHANGE,
                true
            );
            FimbyGroupConversationController.lockConversation(post.Group_Conversation__c);
        }
    }

    public static void incrementCompletedBulkBuys(Set<Id> contactIds) {
        if (contactIds.isEmpty()) { return; }
        List<Contact> contacts = [
            SELECT Id, Completed_Bulk_Buys__c FROM Contact WHERE Id IN :contactIds
        ];
        for (Contact c : contacts) {
            c.Completed_Bulk_Buys__c = (c.Completed_Bulk_Buys__c == null ? 0 : c.Completed_Bulk_Buys__c) + 1;
        }
        new BulkBuyHelper().updateContacts(contacts);
    }

    public static void recalculateBlockedFlags(List<Response__c> responses) {
        Set<Id> contactIds = new Set<Id>();
        for (Response__c r : responses) {
            if (r.Contact__c != null) { contactIds.add(r.Contact__c); }
        }
        recalculateBlockedFlagsForContacts(contactIds);
    }

    public static void recalculateBlockedFlagsForContacts(Set<Id> contactIds) {
        if (contactIds.isEmpty()) { return; }

        Id bulkBuyRtId = getRecordTypeId(FimbyConstants.RT_BULK_BUY);
        Id restorationRtId = Schema.SObjectType.Bulk_Buy_Follow_Up__c
            .getRecordTypeInfosByDeveloperName().get(FimbyConstants.RT_RESTORATION)?.getRecordTypeId();

        Map<Id, Bulk_Buy_Follow_Up__c> latestRestorationByContact = new Map<Id, Bulk_Buy_Follow_Up__c>();
        if (restorationRtId != null) {
            for (Bulk_Buy_Follow_Up__c fu : [
                SELECT Id, Reported_User__c, Resolution_Date__c
                FROM Bulk_Buy_Follow_Up__c
                WHERE Reported_User__c IN :contactIds
                  AND RecordTypeId = :restorationRtId
                  AND Status__c = :FimbyConstants.FOLLOWUP_PROBATIONARY_RESTORED
                ORDER BY Resolution_Date__c DESC
            ]) {
                if (!latestRestorationByContact.containsKey(fu.Reported_User__c)) {
                    latestRestorationByContact.put(fu.Reported_User__c, fu);
                }
            }
        }

        List<Response__c> allOutcomes = [
            SELECT Id, Contact__c, Status__c, CreatedDate
            FROM Response__c
            WHERE Contact__c IN :contactIds
              AND Need_Offer_Responded_To__r.RecordTypeId = :bulkBuyRtId
              AND Status__c IN (:FimbyConstants.RESPONSE_COMPLETED, :FimbyConstants.RESPONSE_NO_FOLLOW_THROUGH)
            ORDER BY CreatedDate DESC
        ];

        Map<Id, List<Response__c>> outcomesByContact = new Map<Id, List<Response__c>>();
        for (Response__c r : allOutcomes) {
            if (!outcomesByContact.containsKey(r.Contact__c)) {
                outcomesByContact.put(r.Contact__c, new List<Response__c>());
            }
            outcomesByContact.get(r.Contact__c).add(r);
        }

        List<Contact> toUpdate = new List<Contact>();
        for (Id cId : contactIds) {
            Boolean hasActiveRestoration = false;
            Bulk_Buy_Follow_Up__c restoration = latestRestorationByContact.get(cId);
            if (restoration != null) {
                Boolean hasNewerOutcome = false;
                for (Response__c r : outcomesByContact.containsKey(cId) ? outcomesByContact.get(cId) : new List<Response__c>()) {
                    if (r.CreatedDate > restoration.Resolution_Date__c) {
                        hasNewerOutcome = true;
                        break;
                    }
                }
                hasActiveRestoration = !hasNewerOutcome;
            }

            Boolean blocked = false;
            if (!hasActiveRestoration) {
                List<Response__c> outcomes = outcomesByContact.containsKey(cId) ? outcomesByContact.get(cId) : new List<Response__c>();
                if (outcomes.size() >= 3) {
                    blocked = true;
                    for (Integer i = 0; i < 3; i++) {
                        if (outcomes[i].Status__c != FimbyConstants.RESPONSE_NO_FOLLOW_THROUGH) {
                            blocked = false;
                            break;
                        }
                    }
                }
            }

            toUpdate.add(new Contact(Id = cId, Is_Bulk_Buy_Blocked__c = blocked));
        }
        if (!toUpdate.isEmpty()) {
            new BulkBuyHelper().updateContacts(toUpdate);
        }
    }

    private static void notifyAllReservers(Id postId, String notifType, String title, String body) {
        List<Response__c> reservers = new BulkBuyHelper().getReserversForNotification(postId);
        String url = FimbySettings.getUrl('Asks_Offers', String.valueOf(postId));
        List<FimbyNotificationService.NotificationRequest> requests =
            new List<FimbyNotificationService.NotificationRequest>();
        for (Response__c r : reservers) {
            requests.add(new FimbyNotificationService.NotificationRequest(
                r.Contact__c, notifType,
                title, body, postId, 'Needs_Offers__c',
                url, 'FIMBY'
            ));
        }
        FimbyNotificationService.createNotificationsFromRequests(requests);
    }

    private static Id getRecordTypeId(String devName) {
        return Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get(devName)?.getRecordTypeId();
    }

    private static Decimal toDecimal(Object val, Decimal fallback) {
        if (val == null) { return fallback; }
        return Decimal.valueOf(String.valueOf(val));
    }

    private static AuraHandledException buildAuraException(String msg) {
        AuraHandledException ex = new AuraHandledException(msg);
        ex.setMessage(msg);
        return ex;
    }

    private without sharing class BulkBuyHelper {
        public void insertRecord(Needs_Offers__c record) { insert record; }
        public void updateRecord(Needs_Offers__c record) { update record; }
        public void updateResponses(List<Response__c> records) { update records; }
        public void updateContacts(List<Contact> records) { update records; }

        public List<Response__c> getReserversForNotification(Id postId) {
            return [
                SELECT Contact__c FROM Response__c
                WHERE Need_Offer_Responded_To__c = :postId
                AND Status__c IN (:FimbyConstants.RESPONSE_RESERVED, :FimbyConstants.RESPONSE_COMPLETED)
            ];
        }

        public List<Response__c> getReservedResponsesForCancel(Id postId) {
            return [
                SELECT Id, Status__c
                FROM Response__c
                WHERE Need_Offer_Responded_To__c = :postId
                AND Status__c = :FimbyConstants.RESPONSE_RESERVED
            ];
        }

        public List<Response__c> getResponsesForCompletion(Id postId) {
            return [
                SELECT Id, Status__c, Contact__c,
                    (SELECT Id, Status__c FROM Follow_Ups__r
                     WHERE Status__c IN (:FimbyConstants.FOLLOWUP_NO_RESPONSE, :FimbyConstants.FOLLOWUP_ADMIN_CONFIRMED,
                                          :FimbyConstants.FOLLOWUP_ESCALATED)
                     LIMIT 1)
                FROM Response__c
                WHERE Need_Offer_Responded_To__c = :postId
                AND Status__c IN (:FimbyConstants.RESPONSE_RESERVED, :FimbyConstants.RESPONSE_NO_FOLLOW_THROUGH)
            ];
        }

        public List<Map<String, Object>> getReservations(Id postId) {
            List<Map<String, Object>> results = new List<Map<String, Object>>();
            List<Response__c> responses = [
                SELECT Id, Contact__c, Contact__r.FirstName, Contact__r.LastName,
                       On_Behalf_Of_Contact__c,
                       On_Behalf_Of_Contact__r.FirstName, On_Behalf_Of_Contact__r.LastName,
                       Amount_Requested__c, Status__c, CreatedDate
                FROM Response__c
                WHERE Need_Offer_Responded_To__c = :postId
                AND Status__c != :FimbyConstants.RESPONSE_CANCELLED
                ORDER BY CreatedDate ASC
            ];
            for (Response__c r : responses) {
                Id representedId = r.On_Behalf_Of_Contact__c != null
                    ? r.On_Behalf_Of_Contact__c
                    : r.Contact__c;
                String firstName = r.On_Behalf_Of_Contact__c != null
                    ? r.On_Behalf_Of_Contact__r.FirstName
                    : r.Contact__r.FirstName;
                String lastName = r.On_Behalf_Of_Contact__c != null
                    ? r.On_Behalf_Of_Contact__r.LastName
                    : r.Contact__r.LastName;
                results.add(new Map<String, Object>{
                    'id' => r.Id,
                    'contactId' => representedId,
                    'realContactId' => r.Contact__c,
                    'onBehalfOfContactId' => r.On_Behalf_Of_Contact__c,
                    'firstName' => firstName,
                    'lastName' => lastName,
                    'amount' => r.Amount_Requested__c,
                    'status' => r.Status__c,
                    'createdDate' => r.CreatedDate
                });
            }
            return results;
        }
    }
}
