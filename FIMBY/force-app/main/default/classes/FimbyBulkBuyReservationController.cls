/**
 * @description Concurrency-safe reservation controller for Bulk Buy shares.
 * Uses FOR UPDATE row locking to prevent oversubscription.
 */
public with sharing class FimbyBulkBuyReservationController {

    private static final String CLASS_NAME = 'FimbyBulkBuyReservationController';

    @AuraEnabled
    public static Map<String, Object> createReservation(String postId, Integer amount) {
        try {
            Id realContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();

            // Block check evaluates the represented identity (who is making the reservation)
            Contact c = [SELECT Id, Is_Bulk_Buy_Blocked__c FROM Contact WHERE Id = :actingAsContactId LIMIT 1];
            if (c.Is_Bulk_Buy_Blocked__c) {
                return new Map<String, Object>{
                    'success' => false,
                    'blocked' => true,
                    'message' => 'A few shares in a row weren\'t completed. Your neighbours are counting on you -- let\'s chat about how to get back on track.'
                };
            }

            return new ReservationHelper().doCreateReservation(postId, realContactId, actingAsContactId, amount);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'createReservation', e);
            throw buildAuraException('Error creating reservation: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> cancelReservation(String responseId) {
        try {
            Id realContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();

            ReservationHelper helper = new ReservationHelper();
            List<Response__c> rows = helper.getResponseById(responseId);
            if (rows.isEmpty()) {
                throw new AuraHandledException('Reservation not found.');
            }
            Response__c resp = rows[0];

            // Dual-check: allow cancel if the user is the real submitter OR the represented identity
            Boolean isAuthor = (resp.Contact__c == realContactId);
            Boolean isRepresented = (resp.On_Behalf_Of_Contact__c == actingAsContactId)
                || (resp.On_Behalf_Of_Contact__c == null && resp.Contact__c == actingAsContactId);
            if (!isAuthor && !isRepresented) {
                throw new AuraHandledException('You can only cancel your own reservation.');
            }
            if (resp.Status__c != FimbyConstants.RESPONSE_RESERVED) {
                throw new AuraHandledException('This reservation cannot be cancelled.');
            }

            Id postId = resp.Need_Offer_Responded_To__c;
            Boolean wasFullyReservedBeforeCancel = helper.isBulkBuyFullyReserved(postId);

            resp.Status__c = FimbyConstants.RESPONSE_CANCELLED;
            resp.Amount_Requested__c = 0;
            helper.updateResponse(resp);

            String displayFirstName = resp.On_Behalf_Of_Contact__r != null
                ? resp.On_Behalf_Of_Contact__r.FirstName
                : resp.Contact__r.FirstName;

            if (resp.Need_Offer_Responded_To__r.Group_Conversation__c != null) {
                FimbyGroupConversationController.sendSystemMessage(
                    resp.Need_Offer_Responded_To__r.Group_Conversation__c,
                    displayFirstName + ' cancelled their reservation',
                    FimbyConstants.SYS_MSG_RESERVATION_CANCELLED,
                    wasFullyReservedBeforeCancel
                );
            }

            FimbyNotificationService.createNotification(
                helper.getPostedByContactId(resp.Need_Offer_Responded_To__c),
                FimbyConstants.NOTIF_BULK_BUY_RESERVATION,
                displayFirstName + ' cancelled their reservation',
                '',
                resp.Need_Offer_Responded_To__c,
                'Needs_Offers__c',
                FimbySettings.getUrl('Asks_Offers', String.valueOf(resp.Need_Offer_Responded_To__c)),
                displayFirstName
            );

            return new Map<String, Object>{ 'success' => true };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'cancelReservation', e);
            throw buildAuraException('Error cancelling: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> revokeReservation(String responseId) {
        try {
            Id realContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();

            ReservationHelper helper = new ReservationHelper();
            List<Response__c> rows = helper.getResponseById(responseId);
            if (rows.isEmpty()) {
                throw new AuraHandledException('Reservation not found.');
            }
            Response__c resp = rows[0];

            Boolean isOrganiser =
                (resp.Need_Offer_Responded_To__r.Posted_By__c == realContactId) ||
                (resp.Need_Offer_Responded_To__r.Contact__c == actingAsContactId);
            if (!isOrganiser) {
                throw new AuraHandledException('Only the organiser can revoke reservations.');
            }

            resp.Status__c = FimbyConstants.RESPONSE_CANCELLED;
            resp.Amount_Requested__c = 0;
            helper.updateResponse(resp);

            String displayFirstName = resp.On_Behalf_Of_Contact__r != null
                ? resp.On_Behalf_Of_Contact__r.FirstName
                : resp.Contact__r.FirstName;

            if (resp.Need_Offer_Responded_To__r.Group_Conversation__c != null) {
                FimbyGroupConversationController.sendSystemMessage(
                    resp.Need_Offer_Responded_To__r.Group_Conversation__c,
                    displayFirstName + '\'s reservation was removed by the organiser',
                    FimbyConstants.SYS_MSG_RESERVATION_CANCELLED,
                    true
                );
            }

            return new Map<String, Object>{ 'success' => true };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'revokeReservation', e);
            throw buildAuraException('Error revoking: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> updateReservationAmount(String responseId, Integer newAmount) {
        try {
            Id realContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();

            return new ReservationHelper().doUpdateAmount(responseId, realContactId, actingAsContactId, newAmount);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'updateReservationAmount', e);
            throw buildAuraException('Error updating reservation: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getReservationContext(String postId) {
        try {
            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();

            // Block evaluation is based on the represented identity (whose history matters)
            Contact c = [SELECT Id, Is_Bulk_Buy_Blocked__c FROM Contact WHERE Id = :actingAsContactId LIMIT 1];

            Needs_Offers__c post = [
                SELECT Id, Name, Status__c, Display_Status__c, Total_Quantity__c, Total_Reserved__c,
                       Total_Available__c, Owner_Shares__c, Per_Response_Limit__c, Allocation_Unit_Label__c,
                       Total_Estimated_Cost__c, Estimated_Cost_Per_Share__c,
                       Image_1_URL__c, Posted_By__c, Contact__c,
                       Posted_By__r.FirstName, Posted_By__r.LastName,
                       Posted_By__r.Full_Name__c, Posted_By__r.Image_URL__c,
                       Posted_By__r.Display_Avatar_URL__c
                FROM Needs_Offers__c
                WHERE Id = :postId
                /* with sharing enforces record access */
                LIMIT 1
            ];

            // Existing reservation lookup: prefer match on represented identity (On_Behalf_Of_Contact__c)
            // falling back to Contact__c for legacy records created before dual-stamping.
            List<Response__c> existing = [
                SELECT Id, Amount_Requested__c, Status__c
                FROM Response__c
                WHERE Need_Offer_Responded_To__c = :postId
                AND (On_Behalf_Of_Contact__c = :actingAsContactId
                     OR (On_Behalf_Of_Contact__c = NULL AND Contact__c = :actingAsContactId))
                AND Status__c = :FimbyConstants.RESPONSE_RESERVED
                /* with sharing enforces record access */
                LIMIT 1
            ];

            // Post owner (Contact__c) is the represented identity on the card — not Posted_By__c
            // (real author). Support users who typed on behalf of an org must still reserve.
            Boolean isOwnPost = (post.Contact__c == actingAsContactId);

            String viewState;
            if (c.Is_Bulk_Buy_Blocked__c) {
                viewState = 'blocked';
            } else if (isOwnPost) {
                viewState = 'unavailable';
            } else if (!existing.isEmpty()) {
                viewState = 'alreadyReserved';
            } else if (post.Status__c != FimbyConstants.NEEDS_OFFERS_AVAILABLE) {
                viewState = 'unavailable';
            } else if (getAvailableShareCount(post) <= 0) {
                viewState = 'fullyReserved';
            } else {
                viewState = 'form';
            }

            return new Map<String, Object>{
                'success' => true,
                'viewState' => viewState,
                'post' => post,
                'existingReservation' => existing.isEmpty() ? null : existing[0],
                'isBlocked' => c.Is_Bulk_Buy_Blocked__c,
                'contactId' => actingAsContactId
            };
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'getReservationContext', e);
            throw buildAuraException('Error loading: ' + e.getMessage());
        }
    }

    private static AuraHandledException buildAuraException(String msg) {
        AuraHandledException ex = new AuraHandledException(msg);
        ex.setMessage(msg);
        return ex;
    }

    /** Sum of reserved responses equals or exceeds buy capacity (no shares left). */
    private static Decimal sumReservedShares(Needs_Offers__c post) {
        List<AggregateResult> ar = [
            SELECT SUM(Amount_Requested__c) total
            FROM Response__c
            WHERE Need_Offer_Responded_To__c = :post.Id
            AND Status__c = :FimbyConstants.RESPONSE_RESERVED
        ];
        return (!ar.isEmpty() && ar[0].get('total') != null) ? (Decimal) ar[0].get('total') : 0;
    }

    private static Decimal getAvailableShareCount(Needs_Offers__c post) {
        Decimal ownerShares = post.Owner_Shares__c != null ? post.Owner_Shares__c : 0;
        return post.Total_Quantity__c - ownerShares - sumReservedShares(post);
    }

    private static Boolean isBulkBuyFullyReserved(Id postId) {
        Needs_Offers__c post = [
            SELECT Total_Quantity__c, Owner_Shares__c
            FROM Needs_Offers__c
            WHERE Id = :postId
            LIMIT 1
        ];
        Decimal owner = post.Owner_Shares__c != null ? post.Owner_Shares__c : 0;
        List<AggregateResult> ar = [
            SELECT SUM(Amount_Requested__c) total
            FROM Response__c
            WHERE Need_Offer_Responded_To__c = :postId
            AND Status__c = :FimbyConstants.RESPONSE_RESERVED
        ];
        Decimal sumReserved = (!ar.isEmpty() && ar[0].get('total') != null)
            ? (Decimal) ar[0].get('total')
            : 0;
        return post.Total_Quantity__c - owner - sumReserved <= 0;
    }

    /**
     * @description Without sharing helper for DML operations with row locking.
     */
    private without sharing class ReservationHelper {

        public List<Response__c> getResponseById(Id responseId) {
            return [
                SELECT Id, Contact__c, On_Behalf_Of_Contact__c, Status__c, Need_Offer_Responded_To__c,
                       Need_Offer_Responded_To__r.Posted_By__c,
                       Need_Offer_Responded_To__r.Contact__c,
                       Need_Offer_Responded_To__r.Group_Conversation__c,
                       Need_Offer_Responded_To__r.Name,
                       Contact__r.FirstName, On_Behalf_Of_Contact__r.FirstName
                FROM Response__c
                WHERE Id = :responseId
                LIMIT 1
            ];
        }

        public Id getPostedByContactId(Id postId) {
            Needs_Offers__c post = [
                SELECT Posted_By__c FROM Needs_Offers__c WHERE Id = :postId LIMIT 1
            ];
            return post.Posted_By__c;
        }

        public Boolean isBulkBuyFullyReserved(Id postId) {
            Needs_Offers__c post = [
                SELECT Total_Quantity__c, Owner_Shares__c
                FROM Needs_Offers__c
                WHERE Id = :postId
                LIMIT 1
            ];
            Decimal owner = post.Owner_Shares__c != null ? post.Owner_Shares__c : 0;
            List<AggregateResult> ar = [
                SELECT SUM(Amount_Requested__c) total
                FROM Response__c
                WHERE Need_Offer_Responded_To__c = :postId
                AND Status__c = :FimbyConstants.RESPONSE_RESERVED
            ];
            Decimal sumReserved = (!ar.isEmpty() && ar[0].get('total') != null)
                ? (Decimal) ar[0].get('total')
                : 0;
            return post.Total_Quantity__c - owner - sumReserved <= 0;
        }

        public Map<String, Object> doCreateReservation(Id postId, Id realContactId, Id actingAsContactId, Integer amount) {
            Needs_Offers__c post = [
                SELECT Id, Total_Quantity__c, Total_Reserved__c, Total_Available__c, Owner_Shares__c,
                       Per_Response_Limit__c, Group_Conversation__c, Posted_By__c, Name, Status__c
                FROM Needs_Offers__c
                WHERE Id = :postId
                FOR UPDATE
            ];

            if (post.Status__c != FimbyConstants.NEEDS_OFFERS_AVAILABLE) {
                throw new AuraHandledException('This bulk buy is no longer accepting reservations.');
            }

            Decimal available = getAvailableShareCount(post);
            if (amount > available) {
                throw new AuraHandledException('Only ' + available.intValue() + ' shares available.');
            }
            if (post.Per_Response_Limit__c != null && amount > post.Per_Response_Limit__c) {
                throw new AuraHandledException('Maximum ' + post.Per_Response_Limit__c.intValue() + ' shares per person.');
            }

            // Existing-reservation check evaluates the represented identity (legacy fallback to Contact__c)
            List<Response__c> existing = [
                SELECT Id FROM Response__c
                WHERE Need_Offer_Responded_To__c = :postId
                AND (On_Behalf_Of_Contact__c = :actingAsContactId
                     OR (On_Behalf_Of_Contact__c = NULL AND Contact__c = :actingAsContactId))
                AND Status__c = :FimbyConstants.RESPONSE_RESERVED
            ];
            if (!existing.isEmpty()) {
                throw new AuraHandledException('You already have a reservation.');
            }

            // Dual-stamp: Contact__c = real (who clicked), On_Behalf_Of_Contact__c = represented identity
            Response__c resp = new Response__c(
                Need_Offer_Responded_To__c = postId,
                Contact__c = realContactId,
                On_Behalf_Of_Contact__c = actingAsContactId,
                Amount_Requested__c = amount,
                Status__c = FimbyConstants.RESPONSE_NEW
            );
            insert resp;
            resp.Status__c = FimbyConstants.RESPONSE_RESERVED;
            update resp;

            Id groupConvId = post.Group_Conversation__c;
            if (groupConvId == null) {
                groupConvId = FimbyGroupConversationController.getOrCreateGroupConversation(postId);
            }

            // Group conversation membership represents the identity (so neighbours see the org/individual)
            Contact reserver = [SELECT FirstName FROM Contact WHERE Id = :actingAsContactId LIMIT 1];

            FimbyGroupConversationController.addMember(groupConvId, actingAsContactId);

            FimbyGroupConversationController.sendSystemMessage(
                groupConvId,
                reserver.FirstName + ' reserved ' + amount + ' share' + (amount > 1 ? 's' : ''),
                FimbyConstants.SYS_MSG_RESERVATION_CREATED
            );

            String shareLabel = amount + ' share' + (amount > 1 ? 's' : '');
            FimbyNotificationService.createNotification(
                post.Posted_By__c,
                FimbyConstants.NOTIF_BULK_BUY_RESERVATION,
                reserver.FirstName + ' reserved ' + shareLabel,
                post.Name,
                postId,
                'Needs_Offers__c',
                FimbySettings.getUrl('Asks_Offers', String.valueOf(postId)),
                reserver.FirstName
            );

            return new Map<String, Object>{
                'success' => true,
                'responseId' => resp.Id,
                'groupConversationId' => groupConvId
            };
        }

        public Map<String, Object> doUpdateAmount(Id responseId, Id realContactId, Id actingAsContactId, Integer newAmount) {
            Response__c resp = [
                SELECT Id, Contact__c, On_Behalf_Of_Contact__c, Amount_Requested__c, Need_Offer_Responded_To__c
                FROM Response__c
                WHERE Id = :responseId
                FOR UPDATE
            ];

            // Dual-check: real submitter OR represented identity may modify
            Boolean isAuthor = (resp.Contact__c == realContactId);
            Boolean isRepresented = (resp.On_Behalf_Of_Contact__c == actingAsContactId)
                || (resp.On_Behalf_Of_Contact__c == null && resp.Contact__c == actingAsContactId);
            if (!isAuthor && !isRepresented) {
                throw new AuraHandledException('You can only modify your own reservation.');
            }

            Needs_Offers__c post = [
                SELECT Id, Total_Quantity__c, Total_Reserved__c, Owner_Shares__c, Per_Response_Limit__c
                FROM Needs_Offers__c
                WHERE Id = :resp.Need_Offer_Responded_To__c
                FOR UPDATE
            ];

            Decimal currentAmount = resp.Amount_Requested__c;
            Decimal available = getAvailableShareCount(post) + currentAmount;

            if (newAmount > available) {
                throw new AuraHandledException('Only ' + available.intValue() + ' shares available.');
            }
            if (post.Per_Response_Limit__c != null && newAmount > post.Per_Response_Limit__c) {
                throw new AuraHandledException('Maximum ' + post.Per_Response_Limit__c.intValue() + ' shares per person.');
            }

            resp.Amount_Requested__c = newAmount;
            update resp;

            return new Map<String, Object>{ 'success' => true };
        }

        public void updateResponse(Response__c resp) { update resp; }
    }
}
