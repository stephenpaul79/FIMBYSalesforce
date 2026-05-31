/**
 * @description Handles the response thread conversation page: message CRUD, response status lifecycle,
 * contact sharing, and unread tracking. Used by fimbyResponseThread LWC.
 */
public with sharing class FimbyResponseThreadController {

    /**
     * @description LWC-callable method that loads the full response thread: response, post, messages,
     * identity, and contact sharing status. Verifies user is poster or responder.
     * @param responseId The Response__c record ID
     * @return Map with success, response, post, messages, isPoster, isResponder, and contactShared
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getThread(String responseId) {
        try {
            if (String.isBlank(responseId)) {
                return errorResult('noRecordId', 'No response selected.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            if (identity == null) {
                return errorResult('noIdentity', 'Unable to determine your identity.');
            }

            String myContactId = identity.actingAsContactId;
            ThreadHelper helper = new ThreadHelper();
            Response__c resp = helper.queryThread(responseId);

            if (resp == null) {
                return errorResult('notFound', 'Response not found.');
            }

            Boolean isPoster = (resp.Need_Offer_Responded_To__r?.Posted_By__c == myContactId);
            Boolean isResponder = (resp.Contact__c == myContactId || resp.On_Behalf_Of_Contact__c == myContactId);

            if (!isPoster && !isResponder) {
                return errorResult('notAuthorized', 'You do not have access to this conversation.');
            }

            helper.markRead(resp, myContactId, isPoster);

            Needs_Offers__c post = resp.Need_Offer_Responded_To__r;

            List<Map<String, Object>> messages = helper.queryMessages(responseId, FimbySettings.responseMessagesPageSize(), 0);

            String otherParticipantId = isPoster
                ? (resp.On_Behalf_Of_Contact__c != null ? resp.On_Behalf_Of_Contact__c : resp.Contact__c)
                : post.Posted_By__c;
            Boolean contactShared = helper.hasSharedContactInfo(myContactId, otherParticipantId);

            return new Map<String, Object>{
                'success' => true,
                'response' => buildResponseMap(resp),
                'post' => buildPostMap(post),
                'messages' => messages,
                'isPoster' => isPoster,
                'isResponder' => isResponder,
                'myContactId' => myContactId,
                'myContactName' => identity.orgDisplayName,
                'myContactImageUrl' => identity.orgAvatarUrl,
                'contactShared' => contactShared
            };
        } catch (Exception e) {
            return throwAura('Error loading thread: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that loads paginated messages for a response thread.
     * Marks messages as read for the current user.
     * @param responseId The Response__c record ID
     * @param pageSize Number of messages per page (defaults to settings)
     * @param offset Pagination offset (defaults to 0)
     * @return Map with success and messages list
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getMessages(String responseId, Integer pageSize, Integer offset) {
        try {
            if (String.isBlank(responseId)) {
                return errorResult('noRecordId', 'No response selected.');
            }

            String myContactId = FimbyIdentityRepository.getActingAsContactId();
            if (String.isBlank(myContactId)) {
                return errorResult('noIdentity', 'Unable to determine your identity.');
            }

            ThreadHelper helper = new ThreadHelper();

            Response__c resp = helper.queryThreadMinimal(responseId);
            if (resp == null) {
                return errorResult('notFound', 'Response not found.');
            }

            Boolean isPoster = (resp.Need_Offer_Responded_To__r?.Posted_By__c == myContactId);
            helper.markRead(resp, myContactId, isPoster);

            Integer limitSize = (pageSize != null && pageSize > 0) ? pageSize : FimbySettings.responseMessagesPageSize();
            Integer offsetVal = (offset != null && offset >= 0) ? offset : 0;

            List<Map<String, Object>> messages = helper.queryMessages(responseId, limitSize, offsetVal);

            return new Map<String, Object>{
                'success' => true,
                'messages' => messages
            };
        } catch (Exception e) {
            return throwAura('Error loading messages: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that sends a new message in the response thread.
     * Creates Response_Message__c, updates unread counts, and triggers notification.
     * @param responseId The Response__c record ID
     * @param body The message body text (max 5000 chars)
     * @return Map with success, messageId, and sentDate
     */
    @AuraEnabled
    public static Map<String, Object> sendMessage(String responseId, String body) {
        try {
            if (String.isBlank(responseId) || String.isBlank(body)) {
                return errorResult('invalidInput', 'Response ID and message body are required.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            if (identity == null) {
                return errorResult('noIdentity', 'Unable to determine your identity.');
            }

            String myContactId = identity.actingAsContactId;
            String realContactId = identity.currentUser.ContactId;
            String myName = identity.orgDisplayName;
            ThreadHelper helper = new ThreadHelper();

            Response__c resp = helper.queryThreadMinimal(responseId);
            if (resp == null) {
                return errorResult('notFound', 'Response not found.');
            }

            Boolean isPoster = (resp.Need_Offer_Responded_To__r?.Posted_By__c == myContactId);
            Boolean isResponder = (resp.Contact__c == myContactId || resp.On_Behalf_Of_Contact__c == myContactId);
            if (!isPoster && !isResponder) {
                return errorResult('notAuthorized', 'You do not have access to this conversation.');
            }

            if (isTerminalStatus(resp.Status__c) && resp.Status__c != FimbyConstants.RESPONSE_COMPLETED) {
                return errorResult('threadClosed', 'This conversation is no longer active.');
            }

            Response_Message__c msg = new Response_Message__c(
                Response__c = responseId,
                Body__c = body.left(5000),
                Sender__c = myContactId,
                Sent_By__c = realContactId,
                Sent_Date__c = Datetime.now(),
                Is_System_Message__c = false
            );
            helper.insertMessage(msg);

            Response__c upd = new Response__c(
                Id = responseId,
                Last_Reply__c = body.left(255),
                Last_Reply_Date__c = Date.today(),
                Last_Reply_Contact_Lookup__c = myContactId
            );
            if (isPoster) {
                upd.Responder_Unread_Count__c = (resp.Responder_Unread_Count__c != null ? resp.Responder_Unread_Count__c : 0) + 1;
                upd.Responder_Archived__c = false;
            } else {
                upd.Poster_Unread_Count__c = (resp.Poster_Unread_Count__c != null ? resp.Poster_Unread_Count__c : 0) + 1;
                upd.Poster_Archived__c = false;
            }
            helper.updateResponse(upd);

            String recipientContactId = isPoster
                ? (resp.On_Behalf_Of_Contact__c != null ? resp.On_Behalf_Of_Contact__c : resp.Contact__c)
                : resp.Need_Offer_Responded_To__r?.Posted_By__c;

            if (recipientContactId != null && recipientContactId != myContactId) {
                String postName = resp.Need_Offer_Responded_To__r?.Name;
                String snippet = body.length() > 100 ? body.substring(0, 100) + '...' : body;
                FimbyNotificationService.createNotification(
                    recipientContactId,
                    FimbyConstants.NOTIF_RESPONSE,
                    myName + ' replied',
                    'On "' + postName + '": "' + snippet + '"',
                    Id.valueOf(responseId),
                    'Response__c',
                    FimbySettings.getUrl('Response_Reply', null, '?recordId=' + responseId),
                    myName
                );
            }

            return new Map<String, Object>{
                'success' => true,
                'messageId' => msg.Id,
                'sentDate' => msg.Sent_Date__c
            };
        } catch (Exception e) {
            return throwAura('Error sending message: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that updates the amount requested on a response.
     * Only the responder can update. Validates against post availability and per-response limit.
     * @param responseId The Response__c record ID
     * @param newAmount The new amount to request (must be at least 1)
     * @return Map with success, newAmount, and message
     */
    @AuraEnabled
    public static Map<String, Object> updateResponseAmount(String responseId, Decimal newAmount) {
        try {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            if (identity == null) {
                return errorResult('noIdentity', 'Unable to determine your identity.');
            }

            String myContactId = identity.actingAsContactId;
            String myName = identity.orgDisplayName;
            ThreadHelper helper = new ThreadHelper();

            Response__c resp = helper.queryThreadForAmountUpdate(responseId);
            if (resp == null) {
                return errorResult('notFound', 'Response not found.');
            }

            Boolean isResponder = (resp.Contact__c == myContactId || resp.On_Behalf_Of_Contact__c == myContactId);
            if (!isResponder) {
                return errorResult('notAuthorized', 'Only the respondee can update the amount.');
            }

            if (resp.Status__c != FimbyConstants.RESPONSE_NEW && resp.Status__c != FimbyConstants.RESPONSE_ACCEPTED) {
                return errorResult('invalidStatus', 'Amount can only be updated for New or Accepted responses.');
            }

            if (newAmount == null || newAmount < 1) {
                return errorResult('invalidAmount', 'Amount must be at least 1.');
            }

            Needs_Offers__c post = resp.Need_Offer_Responded_To__r;
            Decimal currentReservation = resp.Amount_Requested__c != null ? resp.Amount_Requested__c : 0;
            Decimal totalAvailable = (post.Total_Available__c != null ? post.Total_Available__c : 0) + currentReservation;
            Decimal perLimit = post.Per_Response_Limit__c;

            if (newAmount > totalAvailable) {
                return errorResult('quantityExceeded', 'Only ' + totalAvailable.intValue() + ' available. Please choose a smaller amount.');
            }
            if (perLimit != null && perLimit > 0 && newAmount > perLimit) {
                return errorResult('limitExceeded', 'Maximum per response is ' + perLimit.intValue() + '.');
            }

            Decimal oldAmount = resp.Amount_Requested__c;

            Response__c upd = new Response__c(
                Id = responseId,
                Amount_Requested__c = newAmount,
                Poster_Unread_Count__c = (resp.Poster_Unread_Count__c != null ? resp.Poster_Unread_Count__c : 0) + 1
            );
            helper.updateResponse(upd);

            String sysBody = myName + ' updated their request from ' + oldAmount.intValue() + ' to ' + newAmount.intValue();
            helper.createSystemMessage(responseId, myContactId, sysBody, 'Amount_Change');

            String posterContactId = post.Posted_By__c;
            if (posterContactId != null && posterContactId != myContactId) {
                FimbyNotificationService.createNotification(
                    posterContactId,
                    FimbyConstants.NOTIF_RESPONSE,
                    myName + ' updated their request to ' + newAmount.intValue(),
                    sysBody,
                    Id.valueOf(responseId),
                    'Response__c',
                    FimbySettings.getUrl('Response_Reply', null, '?recordId=' + responseId),
                    myName
                );
            }

            return new Map<String, Object>{
                'success' => true,
                'newAmount' => newAmount,
                'message' => 'Amount updated successfully'
            };
        } catch (Exception e) {
            return throwAura('Error updating amount: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that cancels a response. Only the responder can cancel.
     * @param responseId The Response__c record ID
     * @return Map with success, newStatus, and message
     */
    @AuraEnabled
    public static Map<String, Object> cancelResponse(String responseId) {
        try {
            return changeStatus(responseId, FimbyConstants.RESPONSE_CANCELLED, true);
        } catch (Exception e) {
            return throwAura('Error cancelling response: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that accepts a response. Only the poster can accept.
     * @param responseId The Response__c record ID
     * @return Map with success, newStatus, and message
     */
    @AuraEnabled
    public static Map<String, Object> acceptResponse(String responseId) {
        try {
            return changeStatus(responseId, FimbyConstants.RESPONSE_ACCEPTED, false);
        } catch (Exception e) {
            return throwAura('Error accepting response: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that declines a response. Only the poster can decline.
     * @param responseId The Response__c record ID
     * @return Map with success, newStatus, and message
     */
    @AuraEnabled
    public static Map<String, Object> declineResponse(String responseId) {
        try {
            return changeStatus(responseId, FimbyConstants.RESPONSE_DECLINED, false);
        } catch (Exception e) {
            return throwAura('Error declining response: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that marks a response as complete. Only the poster can complete.
     * @param responseId The Response__c record ID
     * @return Map with success, newStatus, and message
     */
    @AuraEnabled
    public static Map<String, Object> completeResponse(String responseId) {
        try {
            return changeStatus(responseId, FimbyConstants.RESPONSE_COMPLETED, false);
        } catch (Exception e) {
            return throwAura('Error completing response: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that shares contact info between response participants.
     * Delegates to FimbyResponseController.shareContactInfo.
     * @param shareData JSON string with responseId, sharingContactId, recipientContactId, and share options
     * @return Map with success and message
     */
    @AuraEnabled
    public static Map<String, Object> shareContactInfo(String shareData) {
        try {
            return FimbyResponseController.shareContactInfo(shareData);
        } catch (Exception e) {
            return throwAura('Error sharing contact info: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that loads response and contact data needed for the Share Contact Info flow.
     * Delegates to FimbyResponseController.getResponseForShareContactInfo.
     * @param responseId The Response__c record ID
     * @return Map with success, response, needOffer, recipient, and sharingContact
     */
    @AuraEnabled
    public static Map<String, Object> getShareContactInfoData(String responseId) {
        try {
            return FimbyResponseController.getResponseForShareContactInfo(responseId);
        } catch (Exception e) {
            return throwAura('Error getting contact info data: ' + e.getMessage());
        }
    }

    // ============================================
    // PRIVATE HELPERS
    // ============================================

    private static Map<String, Object> changeStatus(String responseId, String newStatus, Boolean responderAction) {
        FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
        if (identity == null) {
            return errorResult('noIdentity', 'Unable to determine your identity.');
        }

        String myContactId = identity.actingAsContactId;
        Id myRealContactId = identity.contact?.Id;
        String myName = identity.orgDisplayName;
        ThreadHelper helper = new ThreadHelper();

        Response__c resp = helper.queryThreadMinimal(responseId);
        if (resp == null) {
            return errorResult('notFound', 'Response not found.');
        }

        Id postOwnerId = resp.Need_Offer_Responded_To__r?.Contact__c;
        Id postSubmittedBy = resp.Need_Offer_Responded_To__r?.Posted_By__c;
        Boolean isPoster = postSubmittedBy == myRealContactId || postOwnerId == myContactId;
        Boolean isResponder = (resp.Contact__c == myContactId || resp.On_Behalf_Of_Contact__c == myContactId);

        if (responderAction && !isResponder) {
            return errorResult('notAuthorized', 'Only the respondee can perform this action.');
        }
        if (!responderAction && !isPoster) {
            return errorResult('notAuthorized', 'Only the poster can perform this action.');
        }

        Set<String> validFrom = new Set<String>();
        if (newStatus == FimbyConstants.RESPONSE_ACCEPTED) validFrom.addAll(new List<String>{FimbyConstants.RESPONSE_NEW});
        else if (newStatus == FimbyConstants.RESPONSE_DECLINED) validFrom.addAll(new List<String>{FimbyConstants.RESPONSE_NEW});
        else if (newStatus == FimbyConstants.RESPONSE_CANCELLED) validFrom.addAll(new List<String>{FimbyConstants.RESPONSE_NEW, FimbyConstants.RESPONSE_ACCEPTED});
        else if (newStatus == FimbyConstants.RESPONSE_COMPLETED) validFrom.addAll(new List<String>{FimbyConstants.RESPONSE_ACCEPTED});

        if (!validFrom.contains(resp.Status__c)) {
            return errorResult('invalidTransition', 'Cannot change from ' + resp.Status__c + ' to ' + newStatus + '.');
        }

        Response__c upd = new Response__c(Id = responseId, Status__c = newStatus);
        if (newStatus == FimbyConstants.RESPONSE_COMPLETED) {
            upd.Completed_Date__c = DateTime.now();
        }
        if (isPoster) {
            upd.Responder_Unread_Count__c = (resp.Responder_Unread_Count__c != null ? resp.Responder_Unread_Count__c : 0) + 1;
        } else {
            upd.Poster_Unread_Count__c = (resp.Poster_Unread_Count__c != null ? resp.Poster_Unread_Count__c : 0) + 1;
        }
        helper.updateResponse(upd);

        Id responderContactId = resp.Contact__c;
        String parentRtName = resp.Need_Offer_Responded_To__r?.RecordType?.DeveloperName;
        Boolean isActingAsOther = resp.On_Behalf_Of_Contact__c != null
            && resp.On_Behalf_Of_Contact__c != resp.Contact__c;

        if (newStatus == FimbyConstants.RESPONSE_CANCELLED) {
            FimbyCounterService.onResponseCancelled(responderContactId, parentRtName, isActingAsOther, resp.Status__c);
        } else {
            FimbyCounterService.onResponseStatusChanged(responderContactId, parentRtName, isActingAsOther, resp.Status__c, newStatus);
        }

        String sysBody;
        if (newStatus == FimbyConstants.RESPONSE_ACCEPTED) sysBody = 'Response accepted';
        else if (newStatus == FimbyConstants.RESPONSE_DECLINED) sysBody = 'Response declined';
        else if (newStatus == FimbyConstants.RESPONSE_CANCELLED) sysBody = myName + ' cancelled their response';
        else if (newStatus == FimbyConstants.RESPONSE_COMPLETED) sysBody = 'Response marked as complete';
        else sysBody = 'Status changed to ' + newStatus;

        helper.createSystemMessage(responseId, myContactId, sysBody, 'Status_Change');

        String recipientContactId;
        if (isPoster) {
            recipientContactId = resp.On_Behalf_Of_Contact__c != null ? resp.On_Behalf_Of_Contact__c : resp.Contact__c;
        } else {
            recipientContactId = resp.Need_Offer_Responded_To__r?.Posted_By__c;
        }

        if (recipientContactId != null && recipientContactId != myContactId) {
            String notifTitle;
            if (newStatus == FimbyConstants.RESPONSE_ACCEPTED) notifTitle = 'Your response was accepted';
            else if (newStatus == FimbyConstants.RESPONSE_DECLINED) notifTitle = 'Your response was declined';
            else if (newStatus == FimbyConstants.RESPONSE_CANCELLED) notifTitle = myName + ' cancelled their response';
            else if (newStatus == FimbyConstants.RESPONSE_COMPLETED) notifTitle = 'Response marked as complete';
            else notifTitle = 'Response status updated';

            FimbyNotificationService.createNotification(
                recipientContactId,
                FimbyConstants.NOTIF_RESPONSE,
                notifTitle,
                sysBody,
                Id.valueOf(responseId),
                'Response__c',
                FimbySettings.getUrl('Response_Reply', null, '?recordId=' + responseId),
                myName
            );
        }

        if (newStatus == FimbyConstants.RESPONSE_ACCEPTED && isPoster) {
            FimbyResponseAutoShareHelper.tryAutoShareOnAccept(resp.Id);
        }

        return new Map<String, Object>{
            'success' => true,
            'newStatus' => newStatus,
            'message' => sysBody
        };
    }

    private static Boolean isTerminalStatus(String status) {
        return status == FimbyConstants.RESPONSE_DECLINED || status == FimbyConstants.RESPONSE_CANCELLED || status == FimbyConstants.RESPONSE_EXPIRED;
    }

    private static Map<String, Object> buildResponseMap(Response__c resp) {
        Contact responder = resp.On_Behalf_Of_Contact__r?.Name != null
            ? resp.On_Behalf_Of_Contact__r
            : resp.Contact__r;
        Boolean responderIsOrg = responder?.Is_Organization_Contact__c == true;

        String responderName;
        String responderImageUrl;
        if (responderIsOrg) {
            responderName = responder.Organization_Account__r?.Name;
            responderImageUrl = responder.Organization_Account__r?.Logo_URL__c;
        } else {
            responderName = responder?.Name;
            responderImageUrl = responder?.Image_URL__c;
        }

        return new Map<String, Object>{
            'id' => resp.Id,
            'name' => resp.Name,
            'status' => resp.Status__c,
            'responseText' => resp.Response__c,
            'amountRequested' => resp.Amount_Requested__c,
            'contactId' => resp.Contact__c,
            'contactName' => resp.Contact__r?.Name,
            'onBehalfOfId' => resp.On_Behalf_Of_Contact__c,
            'onBehalfOfName' => resp.On_Behalf_Of_Contact__r?.Name,
            'responderName' => responderName,
            'responderImageUrl' => responderImageUrl,
            'responderIsOrg' => responderIsOrg,
            'createdDate' => resp.CreatedDate,
            'lastReplyDate' => resp.Last_Reply_Date__c,
            'completedDate' => resp.Completed_Date__c,
            'posterUnreadCount' => resp.Poster_Unread_Count__c,
            'responderUnreadCount' => resp.Responder_Unread_Count__c
        };
    }

    private static Map<String, Object> buildPostMap(Needs_Offers__c post) {
        if (post == null) return new Map<String, Object>();

        Boolean posterIsOrg = post.Posted_By__r?.Is_Organization_Contact__c == true;
        String postedByName = posterIsOrg
            ? post.Posted_By__r.Organization_Account__r?.Name
            : post.Posted_By__r?.Name;
        String postedByImageUrl = posterIsOrg
            ? post.Posted_By__r.Organization_Account__r?.Logo_URL__c
            : post.Posted_By__r?.Image_URL__c;

        return new Map<String, Object>{
            'id' => post.Id,
            'name' => post.Name,
            'details' => post.Full_Details__c != null ? post.Full_Details__c : post.Details__c,
            'imageUrl' => post.Image_1_URL__c,
            'type' => post.Type__c,
            'eventType' => post.Event_Type__c,
            'recordType' => post.RecordType?.DeveloperName,
            'status' => post.Status__c,
            'totalQuantity' => post.Total_Quantity__c,
            'totalAvailable' => post.Total_Available__c,
            'totalReserved' => post.Total_Reserved__c,
            'perResponseLimit' => post.Per_Response_Limit__c,
            'postedById' => post.Posted_By__c,
            'postedByName' => postedByName,
            'postedByImageUrl' => postedByImageUrl,
            'postedByIsOrg' => posterIsOrg,
            'endDate' => post.End_Date__c
        };
    }

    private static Map<String, Object> errorResult(String error, String message) {
        return new Map<String, Object>{
            'success' => false,
            'error' => error,
            'message' => message
        };
    }

    private static Map<String, Object> throwAura(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        throw ex;
    }

    // ============================================
    // WITHOUT SHARING HELPER
    // ============================================

    private without sharing class ThreadHelper {

        /**
         * @description Queries a Response__c with full post and contact details for thread display.
         * @param responseId The Response__c record ID
         * @return The Response__c record or null if not found
         */
        public Response__c queryThread(String responseId) {
            List<Response__c> results = [
                SELECT Id, Name, Status__c, Response__c, Amount_Requested__c,
                       Contact__c, Contact__r.Name, Contact__r.FirstName, Contact__r.LastName,
                       Contact__r.Image_URL__c,
                       Contact__r.Is_Organization_Contact__c,
                       Contact__r.Organization_Account__r.Name,
                       Contact__r.Organization_Account__r.Logo_URL__c,
                       On_Behalf_Of_Contact__c, On_Behalf_Of_Contact__r.Name,
                       On_Behalf_Of_Contact__r.FirstName, On_Behalf_Of_Contact__r.LastName,
                       On_Behalf_Of_Contact__r.Image_URL__c,
                       On_Behalf_Of_Contact__r.Is_Organization_Contact__c,
                       On_Behalf_Of_Contact__r.Organization_Account__r.Name,
                       On_Behalf_Of_Contact__r.Organization_Account__r.Logo_URL__c,
                       OwnerId, CreatedDate, Last_Reply_Date__c, Completed_Date__c,
                       Poster_Unread_Count__c, Responder_Unread_Count__c,
                       Poster_Last_Viewed__c, Responder_Last_Viewed__c,
                       Need_Offer_Responded_To__c,
                       Need_Offer_Responded_To__r.Id,
                       Need_Offer_Responded_To__r.Name,
                       Need_Offer_Responded_To__r.Details__c,
                       Need_Offer_Responded_To__r.Full_Details__c,
                       Need_Offer_Responded_To__r.Image_1_URL__c,
                       Need_Offer_Responded_To__r.Type__c,
                       Need_Offer_Responded_To__r.Event_Type__c,
                       Need_Offer_Responded_To__r.RecordType.DeveloperName,
                       Need_Offer_Responded_To__r.Status__c,
                       Need_Offer_Responded_To__r.Total_Quantity__c,
                       Need_Offer_Responded_To__r.Total_Available__c,
                       Need_Offer_Responded_To__r.Total_Reserved__c,
                       Need_Offer_Responded_To__r.Per_Response_Limit__c,
                       Need_Offer_Responded_To__r.Posted_By__c,
                       Need_Offer_Responded_To__r.Posted_By__r.Name,
                       Need_Offer_Responded_To__r.Posted_By__r.FirstName,
                       Need_Offer_Responded_To__r.Posted_By__r.LastName,
                       Need_Offer_Responded_To__r.Posted_By__r.Image_URL__c,
                       Need_Offer_Responded_To__r.Posted_By__r.Is_Organization_Contact__c,
                       Need_Offer_Responded_To__r.Posted_By__r.Organization_Account__r.Name,
                       Need_Offer_Responded_To__r.Posted_By__r.Organization_Account__r.Logo_URL__c,
                       Need_Offer_Responded_To__r.End_Date__c,
                       Need_Offer_Responded_To__r.OwnerId
                FROM Response__c
                WHERE Id = :responseId
                LIMIT 1
            ];
            return results.isEmpty() ? null : results[0];
        }

        /**
         * @description Queries a minimal Response__c for access checks and status updates.
         * @param responseId The Response__c record ID
         * @return The Response__c record or null if not found
         */
        public Response__c queryThreadMinimal(String responseId) {
            List<Response__c> results = [
                SELECT Id, Name, Status__c, OwnerId,
                       Contact__c, On_Behalf_Of_Contact__c,
                       Poster_Unread_Count__c, Responder_Unread_Count__c,
                       Poster_Last_Viewed__c, Responder_Last_Viewed__c,
                       Need_Offer_Responded_To__c,
                       Need_Offer_Responded_To__r.Name,
                       Need_Offer_Responded_To__r.Posted_By__c,
                       Need_Offer_Responded_To__r.Contact__c,
                       Need_Offer_Responded_To__r.OwnerId,
                       Need_Offer_Responded_To__r.RecordType.DeveloperName
                FROM Response__c
                WHERE Id = :responseId
                LIMIT 1
            ];
            return results.isEmpty() ? null : results[0];
        }

        /**
         * @description Queries Response__c with post availability fields needed for amount update.
         * @param responseId The Response__c record ID
         * @return The Response__c record or null if not found
         */
        public Response__c queryThreadForAmountUpdate(String responseId) {
            List<Response__c> results = [
                SELECT Id, Name, Status__c, Amount_Requested__c,
                       Contact__c, On_Behalf_Of_Contact__c, OwnerId,
                       Poster_Unread_Count__c, Responder_Unread_Count__c,
                       Need_Offer_Responded_To__c,
                       Need_Offer_Responded_To__r.Total_Available__c,
                       Need_Offer_Responded_To__r.Per_Response_Limit__c,
                       Need_Offer_Responded_To__r.Posted_By__c,
                       Need_Offer_Responded_To__r.Name
                FROM Response__c
                WHERE Id = :responseId
                LIMIT 1
            ];
            return results.isEmpty() ? null : results[0];
        }

        /**
         * @description Queries Response_Message__c records for a response, ordered by sent date.
         * @param responseId The Response__c record ID
         * @param limitSize Maximum number of messages to return
         * @param offsetVal Pagination offset
         * @return List of message maps with id, body, senderId, senderName, etc.
         */
        public List<Map<String, Object>> queryMessages(String responseId, Integer limitSize, Integer offsetVal) {
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            List<Response_Message__c> msgs = [
                SELECT Id, Body__c, Sender__c, Sender__r.Name, Sender__r.FirstName, Sender__r.LastName,
                       Sender__r.Image_URL__c,
                       Sender__r.Is_Organization_Contact__c,
                       Sender__r.Organization_Account__r.Name,
                       Sender__r.Organization_Account__r.Logo_URL__c,
                       Sent_By__c, Sent_By__r.FirstName,
                       Sent_Date__c, Read_Date__c,
                       Is_System_Message__c, System_Message_Type__c
                FROM Response_Message__c
                WHERE Response__c = :responseId
                ORDER BY Sent_Date__c ASC
                LIMIT :limitSize
                OFFSET :offsetVal
            ];
            for (Response_Message__c m : msgs) {
                Boolean senderIsOrg = m.Sender__r?.Is_Organization_Contact__c == true;
                String senderName;
                String senderImageUrl;
                if (senderIsOrg) {
                    senderName = FimbyIdentityRepository.buildOrgDisplayName(
                        m.Sender__r.Organization_Account__r?.Name,
                        m.Sent_By__r?.FirstName
                    );
                    senderImageUrl = m.Sender__r.Organization_Account__r?.Logo_URL__c;
                } else {
                    senderName = m.Sender__r?.Name;
                    senderImageUrl = m.Sender__r?.Image_URL__c;
                }

                result.add(new Map<String, Object>{
                    'id' => m.Id,
                    'body' => m.Body__c,
                    'senderId' => m.Sender__c,
                    'senderName' => senderName,
                    'senderImageUrl' => senderImageUrl,
                    'senderIsOrg' => senderIsOrg,
                    'sentDate' => m.Sent_Date__c,
                    'readDate' => m.Read_Date__c,
                    'isSystemMessage' => m.Is_System_Message__c,
                    'systemMessageType' => m.System_Message_Type__c
                });
            }
            return result;
        }

        /**
         * @description Marks a response thread as read for the current participant. Resets unread count
         * and updates last viewed timestamp. Marks individual messages as read.
         * @param resp The Response__c record
         * @param myContactId The current user's acting-as contact ID
         * @param isPoster True if current user is the post owner
         */
        public void markRead(Response__c resp, String myContactId, Boolean isPoster) {
            Response__c upd = new Response__c(Id = resp.Id);
            if (isPoster) {
                upd.Poster_Unread_Count__c = 0;
                upd.Poster_Last_Viewed__c = Datetime.now();
            } else {
                upd.Responder_Unread_Count__c = 0;
                upd.Responder_Last_Viewed__c = Datetime.now();
            }
            update upd;

            List<Response_Message__c> unread = [
                SELECT Id
                FROM Response_Message__c
                WHERE Response__c = :resp.Id
                  AND Read_Date__c = null
                  AND Sender__c != :myContactId
            ];
            if (!unread.isEmpty()) {
                for (Response_Message__c m : unread) {
                    m.Read_Date__c = Datetime.now();
                }
                update unread;
            }
        }

        /**
         * @description Inserts a Response_Message__c record.
         * @param msg The message record to insert
         */
        public void insertMessage(Response_Message__c msg) {
            insert msg;
        }

        /**
         * @description Updates a Response__c record.
         * @param resp The response record to update
         */
        public void updateResponse(Response__c resp) {
            update resp;
        }

        public void createSystemMessage(String responseId, String senderContactId, String body, String msgType) {
            Response_Message__c sysMsg = new Response_Message__c(
                Response__c = responseId,
                Body__c = body,
                Sender__c = senderContactId,
                Sent_Date__c = Datetime.now(),
                Is_System_Message__c = true,
                System_Message_Type__c = msgType
            );
            insert sysMsg;
        }

        /**
         * @description Checks if the current user has shared contact info with the other participant.
         * @param myContactId The current user's acting-as contact ID
         * @param otherParticipantId The other participant's contact ID
         * @return True if an active Shared_Contact_Info__c exists between the contacts
         */
        public Boolean hasSharedContactInfo(String myContactId, String otherParticipantId) {
            if (String.isBlank(otherParticipantId)) return false;
            List<Shared_Contact_Info__c> existing = [
                SELECT Id FROM Shared_Contact_Info__c
                WHERE Contact__c = :myContactId
                  AND Shared_To__c = :otherParticipantId
                  AND (Status__c = 'Active' OR Status__c = null)
                LIMIT 1
            ];
            return !existing.isEmpty();
        }
    }
}
