/**
 * @description Handles all Response-related functionality. Extracted from FimbyLibraryController
 * for better maintainability. Used by fimbyQuickResponse, fimbyResponseReply, fimbyResponseStatusUpdate,
 * fimbyShareContent LWCs.
 */
public with sharing class FimbyResponseController {

    /**
     * Get Need/Offer details for the Response form
     * Matches New_Response.flow logic
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getNeedsOffersForResponse(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'noRecordId',
                    'message' => 'No Need or Offer selected.'
                };
            }

            Needs_Offers__c needOffer = new ResponseQueryHelper().queryNeedOfferForResponse(recordId);
            if (needOffer == null) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'noRecordId',
                    'message' => 'No Need or Offer selected.'
                };
            }

            Boolean isNeed = needOffer.RecordType?.DeveloperName == FimbyConstants.RT_NEED;
            if (!isNeed && needOffer.Total_Available__c <= 0) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'noneAvailable',
                    'message' => 'Oh No! This post has already been spoken for.'
                };
            }

            return new Map<String, Object>{
                'success' => true,
                'needOffer' => new Map<String, Object>{
                    'id' => needOffer.Id,
                    'name' => needOffer.Name,
                    'details' => String.isNotBlank(needOffer.Full_Details__c) ? needOffer.Full_Details__c : needOffer.Details__c,
                    'postingDetails' => needOffer.Posting_Details__c,
                    'imageUrl' => needOffer.Image_1_URL__c,
                    'type' => needOffer.Type__c,
                    'recordType' => needOffer.RecordType?.DeveloperName,
                    'totalAvailable' => needOffer.Total_Available__c,
                    'totalQuantity' => needOffer.Total_Quantity__c,
                    'perResponseLimit' => needOffer.Per_Response_Limit__c,
                    'autoAcceptResponses' => needOffer.Auto_Accept_Responses__c,
                    'neighbourhoodId' => needOffer.Neighbourhood__c,
                    'ownerId' => needOffer.OwnerId,
                    'postedById' => needOffer.Posted_By__c,
                    'postedByFirstName' => needOffer.Posted_By__r?.FirstName,
                    'postedByLastName' => needOffer.Posted_By__r?.LastName
                }
            };
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error getting Need/Offer: ' + e.getMessage());
            ex.setMessage('Error getting Need/Offer: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Check if user already has a response to this Need/Offer
     */
    @AuraEnabled
    public static Map<String, Object> checkExistingResponse(String needOfferId) {
        try {
            List<Response__c> existingResponses = [
                SELECT Id, Status__c, Name
                FROM Response__c
                WHERE Need_Offer_Responded_To__c = :needOfferId
                AND OwnerId = :UserInfo.getUserId()
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (!existingResponses.isEmpty()) {
                Response__c existing = existingResponses[0];
                String responseUrl = FimbySettings.getUrl('Response_Reply', null, '?recordId=' + existing.Id);
                return new Map<String, Object>{
                    'success' => true,
                    'hasExistingResponse' => true,
                    'existingResponse' => new Map<String, Object>{
                        'id' => existing.Id,
                        'status' => existing.Status__c,
                        'name' => existing.Name,
                        'responseUrl' => responseUrl
                    }
                };
            }

            return new Map<String, Object>{
                'success' => true,
                'hasExistingResponse' => false
            };
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error checking existing response: ' + e.getMessage());
            ex.setMessage('Error checking existing response: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Create a Response to a Need/Offer
     */
    @AuraEnabled
    public static Map<String, Object> createResponse(String responseData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(responseData);

            String needOfferId = (String) data.get('needOfferId');
            String subject = (String) data.get('subject');
            String responseDetails = (String) data.get('responseDetails');
            Boolean decline = data.get('decline') == true;

            Decimal amountRequested = 1;
            if (decline) {
                amountRequested = 0;
            } else if (data.get('amountRequested') != null) {
                amountRequested = Decimal.valueOf(String.valueOf(data.get('amountRequested')));
            }

            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String realContactId = (String) actingAs.get('realContactId');
            String actingAsContactId = (String) actingAs.get('actingAsContactId');

            Needs_Offers__c needOffer = [
                SELECT Id, Auto_Accept_Responses__c, Neighbourhood__c, Status__c,
                       Posted_By__c, Posted_By__r.FirstName, Posted_By__r.LastName,
                       RecordType.DeveloperName
                FROM Needs_Offers__c
                WHERE Id = :needOfferId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            Set<String> activeStatuses = new Set<String>{
                FimbyConstants.NEEDS_OFFERS_POSTED,
                FimbyConstants.NEEDS_OFFERS_AVAILABLE,
                'Reply Received', 'Reply Accepted'
            };
            if (!activeStatuses.contains(needOffer.Status__c)) {
                AuraHandledException ahe = new AuraHandledException('This post is no longer accepting responses.');
                ahe.setMessage('This post is no longer accepting responses.');
                throw ahe;
            }

            String status = FimbyConstants.RESPONSE_NEW;
            if (amountRequested == 0 || decline) {
                status = FimbyConstants.RESPONSE_DECLINED;
            } else if (needOffer.Auto_Accept_Responses__c == true) {
                status = FimbyConstants.RESPONSE_ACCEPTED;
            }

            Response__c newResponse = new Response__c(
                Name = subject,
                Contact__c = realContactId,
                Need_Offer_Responded_To__c = needOfferId,
                Response__c = responseDetails,
                Status__c = status,
                Amount_Requested__c = amountRequested,
                On_Behalf_Of_Contact__c = actingAsContactId,
                Neighbourhood__c = needOffer.Neighbourhood__c
            );

            new ResponseHelper().insertResponse(newResponse);

            if (status == FimbyConstants.RESPONSE_ACCEPTED) {
                FimbyResponseAutoShareHelper.tryAutoShareOnAccept(newResponse.Id);
            }

            FimbyCounterService.onResponseCreated(
                Id.valueOf(realContactId),
                needOffer.RecordType.DeveloperName,
                actingAsContactId != realContactId,
                status
            );

            Contact responder = [
                SELECT Id, FirstName, LastName
                FROM Contact
                WHERE Id = :actingAsContactId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (!Test.isRunningTest()) {
                ConnectApi.FeedItemInput feedItemInput = new ConnectApi.FeedItemInput();
                ConnectApi.MessageBodyInput messageBodyInput = new ConnectApi.MessageBodyInput();
                messageBodyInput.messageSegments = new List<ConnectApi.MessageSegmentInput>();

                ConnectApi.TextSegmentInput textSegment = new ConnectApi.TextSegmentInput();
                textSegment.text = 'Attn: ' + needOffer.Posted_By__r.FirstName + '\n\n'
                    + subject + '\n' + responseDetails + '\n\n'
                    + 'From: ' + responder.FirstName + ' ' + responder.LastName;
                messageBodyInput.messageSegments.add(textSegment);

                feedItemInput.body = messageBodyInput;
                feedItemInput.feedElementType = ConnectApi.FeedElementType.FeedItem;
                feedItemInput.subjectId = newResponse.Id;

                ConnectApi.ChatterFeeds.postFeedElement(Network.getNetworkId(), feedItemInput);
            }

            String responseUrl = FimbySettings.getUrl('Response_Reply', null, '?recordId=' + newResponse.Id);

            // Create in-app notification for post owner
            if (needOffer.Posted_By__c != null && needOffer.Posted_By__c != actingAsContactId) {
                String responderFullName = responder.FirstName + ' ' + responder.LastName;
                FimbyNotificationService.createNotification(
                    needOffer.Posted_By__c,
                    FimbyConstants.NOTIF_RESPONSE,
                    responderFullName + ' responded to your post',
                    subject,
                    newResponse.Id,
                    'Response__c',
                    FimbySettings.getUrl('Response_Reply', null, '?recordId=' + newResponse.Id),
                    responderFullName
                );
            }

            return new Map<String, Object>{
                'success' => true,
                'responseId' => newResponse.Id,
                'responseUrl' => responseUrl,
                'status' => status,
                'message' => 'Response submitted successfully'
            };

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            FimbyLogger.error('FimbyResponseController', 'createResponse', e);
            AuraHandledException ex = new AuraHandledException('Error creating response: ' + e.getMessage());
            ex.setMessage('Error creating response: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get Response details for the Reply form
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getResponseForReply(String recordId) {
        try {
            Response__c response = new ResponseQueryHelper().queryResponseForReply(recordId);

            if (response == null) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notFound',
                    'message' => 'Response not found.'
                };
            }

            String currentUserId = UserInfo.getUserId();
            Boolean isPoster = currentUserId.substring(0, 15) ==
                               String.valueOf(response.Need_Offer_Responded_To__r.OwnerId).substring(0, 15);
            Boolean isResponder = currentUserId.substring(0, 15) ==
                                 String.valueOf(response.OwnerId).substring(0, 15);

            if (!isPoster && !isResponder) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notAuthorized',
                    'message' => 'You are not able to reply as this is not your response or post.'
                };
            }

            String replyToName;
            if (isPoster) {
                replyToName = response.On_Behalf_Of_Contact__r?.Name != null
                    ? response.On_Behalf_Of_Contact__r.Name
                    : response.Contact__r?.Name;
            } else {
                replyToName = response.Reply_To_Contact__r?.Name != null
                    ? response.Reply_To_Contact__r.Name
                    : (response.Need_Offer_Responded_To__r.Posted_By__r?.FirstName + ' ' +
                       response.Need_Offer_Responded_To__r.Posted_By__r?.LastName);
            }

            return new Map<String, Object>{
                'success' => true,
                'response' => new Map<String, Object>{
                    'id' => response.Id,
                    'name' => response.Name,
                    'status' => response.Status__c,
                    'responseText' => response.Response__c,
                    'contactId' => response.Contact__c,
                    'contactName' => response.Contact__r?.Name,
                    'onBehalfOfId' => response.On_Behalf_Of_Contact__c,
                    'onBehalfOfName' => response.On_Behalf_Of_Contact__r?.Name,
                    'ownerId' => response.OwnerId,
                    'replyToContactId' => response.Reply_To_Contact__c
                },
                'needOffer' => new Map<String, Object>{
                    'id' => response.Need_Offer_Responded_To__c,
                    'name' => response.Need_Offer_Responded_To__r?.Name,
                    'ownerId' => response.Need_Offer_Responded_To__r?.OwnerId,
                    'postedById' => response.Need_Offer_Responded_To__r?.Posted_By__c,
                    'typeValue' => response.Need_Offer_Responded_To__r?.Type__c,
                    'eventType' => response.Need_Offer_Responded_To__r?.Event_Type__c
                },
                'isPoster' => isPoster,
                'replyToName' => replyToName
            };
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error getting response: ' + e.getMessage());
            ex.setMessage('Error getting response: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Submit a reply on a Response
     */
    @AuraEnabled
    public static Map<String, Object> submitResponseReply(String replyData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(replyData);

            String responseId = (String) data.get('responseId');
            String subject = (String) data.get('subject');
            String message = (String) data.get('message');
            String newStatus = (String) data.get('newStatus');
            Boolean shareContactInfo = data.get('shareContactInfo') == true;

            Response__c response = new ResponseQueryHelper().queryResponseForSubmitReply(responseId);

            String currentUserId = UserInfo.getUserId();
            Boolean isPoster = currentUserId.substring(0, 15) ==
                               String.valueOf(response.Need_Offer_Responded_To__r.OwnerId).substring(0, 15);

            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String replyingContactId = (String) actingAs.get('actingAsContactId');

            Contact replyingContact = [
                SELECT Id, FirstName, LastName
                FROM Contact
                WHERE Id = :replyingContactId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            String recipientUserId;
            String recipientContactId;
            if (isPoster) {
                recipientUserId = String.valueOf(response.OwnerId);
                recipientContactId = response.Contact__c;
            } else {
                recipientUserId = String.valueOf(response.Need_Offer_Responded_To__r.OwnerId);
                recipientContactId = response.Need_Offer_Responded_To__r.Posted_By__c;
            }

            String attentionName = isPoster
                ? (response.Contact__r?.FirstName + ' ' + response.Contact__r?.LastName)
                : (response.Need_Offer_Responded_To__r.Posted_By__r?.FirstName);

            if (!Test.isRunningTest()) {
                ConnectApi.FeedItemInput feedItemInput = new ConnectApi.FeedItemInput();
                ConnectApi.MessageBodyInput messageBodyInput = new ConnectApi.MessageBodyInput();
                messageBodyInput.messageSegments = new List<ConnectApi.MessageSegmentInput>();

                ConnectApi.MentionSegmentInput mentionSegment = new ConnectApi.MentionSegmentInput();
                mentionSegment.id = recipientUserId;
                messageBodyInput.messageSegments.add(mentionSegment);

                ConnectApi.TextSegmentInput textSegment = new ConnectApi.TextSegmentInput();
                textSegment.text = '  Attn: ' + attentionName + '\n' + subject + '\n' + message;
                messageBodyInput.messageSegments.add(textSegment);

                feedItemInput.body = messageBodyInput;
                feedItemInput.feedElementType = ConnectApi.FeedElementType.FeedItem;
                feedItemInput.subjectId = responseId;

                ConnectApi.ChatterFeeds.postFeedElement(Network.getNetworkId(), feedItemInput);
            }

            Response__c responseUpdate = new Response__c(
                Id = responseId,
                Last_Reply__c = message,
                Last_Reply_Date__c = Date.today(),
                Last_Reply_Contact_Lookup__c = recipientContactId
            );

            if (isPoster && String.isNotBlank(newStatus)) {
                responseUpdate.Status__c = newStatus;
            }

            new ResponseHelper().updateResponse(responseUpdate);

            String shareContactInfoUrl = null;
            if (shareContactInfo) {
                shareContactInfoUrl = '/flow/Share_Contact_Info?recordId=' + responseId;
            }

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Reply sent successfully',
                'newStatus' => isPoster ? newStatus : null,
                'shareContactInfoUrl' => shareContactInfoUrl
            };

        } catch (Exception e) {
            FimbyLogger.error('FimbyResponseController', 'submitResponseReply', e);
            AuraHandledException ex = new AuraHandledException('Error submitting reply: ' + e.getMessage());
            ex.setMessage('Error submitting reply: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get Response details for status update
     */
    @AuraEnabled
    public static Map<String, Object> getResponseForStatusUpdate(String recordId) {
        try {
            Response__c response = new ResponseQueryHelper().queryResponseForStatusUpdate(recordId);
            if (response == null) {
                AuraHandledException ex = new AuraHandledException('Error getting response: Record not found.');
                ex.setMessage('Error getting response: Record not found.');
                throw ex;
            }

            String currentUserId = UserInfo.getUserId();
            Boolean isResponseOwner = currentUserId == response.OwnerId;
            Boolean isNeedOfferOwner = currentUserId.substring(0, 15) ==
                                       String.valueOf(response.Need_Offer_Responded_To__r.OwnerId).substring(0, 15);
            Boolean hasAccess = isResponseOwner || isNeedOfferOwner;

            return new Map<String, Object>{
                'success' => true,
                'hasAccess' => hasAccess,
                'response' => new Map<String, Object>{
                    'id' => response.Id,
                    'name' => response.Name,
                    'status' => response.Status__c,
                    'ownerId' => response.OwnerId,
                    'needOfferOwnerId' => response.Need_Offer_Responded_To__r?.OwnerId
                }
            };
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error getting response: ' + e.getMessage());
            ex.setMessage('Error getting response: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Update Response status
     */
    @AuraEnabled
    public static Map<String, Object> updateResponseStatus(String responseId, String newStatus) {
        try {
            Map<String, Object> accessCheck = getResponseForStatusUpdate(responseId);
            if (!(Boolean) accessCheck.get('hasAccess')) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'noAccess',
                    'message' => 'You do not have the correct access level to update the status on this record.'
                };
            }

            Response__c responseUpdate = new Response__c(
                Id = responseId,
                Status__c = newStatus
            );

            new ResponseHelper().updateResponse(responseUpdate);

            if (newStatus == FimbyConstants.RESPONSE_ACCEPTED) {
                FimbyResponseAutoShareHelper.tryAutoShareOnAccept(responseId);
            }

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Status updated successfully',
                'newStatus' => newStatus
            };

        } catch (Exception e) {
            FimbyLogger.error('FimbyResponseController', 'updateResponseStatus', e);
            AuraHandledException ex = new AuraHandledException('Error updating status: ' + e.getMessage());
            ex.setMessage('Error updating status: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get Response and related data for the Share Contact Info form
     */
    @AuraEnabled
    public static Map<String, Object> getResponseForShareContactInfo(String recordId) {
        try {
            return new ShareContactInfoHelper().getResponseForShareContactInfoInternal(recordId);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error getting response data: ' + e.getMessage());
            ex.setMessage('Error getting response data: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Share contact info with another user
     */
    @AuraEnabled
    public static Map<String, Object> shareContactInfo(String shareData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(shareData);
            return new ShareContactInfoHelper().shareContactInfoInternal(data);
        } catch (Exception e) {
            FimbyLogger.error('FimbyResponseController', 'shareContactInfo', e);
            AuraHandledException ex = new AuraHandledException('Error sharing contact info: ' + e.getMessage());
            ex.setMessage('Error sharing contact info: ' + e.getMessage());
            throw ex;
        }
    }

    // ============================================
    // QUICK EVENT RESPONSE (Open Event / Community Event)
    // ============================================

    private static final Set<String> ACTIVE_RESPONSE_STATUSES = new Set<String>{
        FimbyConstants.RESPONSE_NEW,
        FimbyConstants.RESPONSE_ACCEPTED
    };

    /**
     * 1-click event response with full lifecycle: respond (idempotent), withdraw, guest count edit.
     * @param eventId The Needs_Offers__c record ID
     * @param action 'respond' | 'withdraw' | 'updateGuests'
     * @param guestCount Number of guests (including self); used for respond and updateGuests. Min 1.
     * @return Map with success, responseId, status, action, guestCount
     */
    @AuraEnabled
    public static Map<String, Object> quickEventResponse(String eventId, String action, Integer guestCount) {
        try {
            if (String.isBlank(eventId) || String.isBlank(action)) {
                throw newAuraException('Missing required parameters.');
            }

            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String actingAsContactId = (String) actingAs.get('actingAsContactId');
            String realContactId = (String) actingAs.get('realContactId');

            return new QuickEventResponseHelper().execute(eventId, action, guestCount, actingAsContactId, realContactId);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            FimbyLogger.error('FimbyResponseController', 'quickEventResponse', e);
            throw newAuraException('Error processing event response: ' + e.getMessage());
        }
    }

    /**
     * Find or create a 1:1 DM conversation between the acting user and the event poster,
     * scoped to a specific event via Related_Record_Id__c + Context_Type__c = 'Event'.
     * Only available after the user has an active response (intent-gated).
     * @param eventId The Needs_Offers__c record ID
     * @return Map with success, conversationId, isNew
     */
    @AuraEnabled
    public static Map<String, Object> getOrCreateEventConversation(String eventId, String targetContactId) {
        try {
            if (String.isBlank(eventId)) {
                throw newAuraException('Missing event ID.');
            }
            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String actingAsContactId = (String) actingAs.get('actingAsContactId');

            return new EventConversationHelper().getOrCreate(eventId, actingAsContactId, targetContactId);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            FimbyLogger.error('FimbyResponseController', 'getOrCreateEventConversation', e);
            throw newAuraException('Error opening conversation: ' + e.getMessage());
        }
    }

    private static AuraHandledException newAuraException(String msg) {
        AuraHandledException ex = new AuraHandledException(msg);
        ex.setMessage(msg);
        return ex;
    }

    // ============================================
    // HELPER CLASSES
    // ============================================

    /**
     * Without sharing helper for quick event response lifecycle.
     * Handles idempotent create, withdraw, rejoin, and guest count updates.
     */
    private without sharing class QuickEventResponseHelper {
        public Map<String, Object> execute(String eventId, String action, Integer guestCount, String actingAsContactId, String realContactId) {
            Needs_Offers__c evt = [
                SELECT Id, Status__c, Event_Type__c, Neighbourhood__c, Posted_By__c,
                       Posted_By__r.FirstName, Posted_By__r.LastName, Name
                FROM Needs_Offers__c
                WHERE Id = :eventId
                LIMIT 1
            ];

            Set<String> activePostStatuses = new Set<String>{
                FimbyConstants.NEEDS_OFFERS_POSTED,
                FimbyConstants.NEEDS_OFFERS_AVAILABLE,
                'Reply Received', 'Reply Accepted'
            };
            if (!activePostStatuses.contains(evt.Status__c)) {
                throw newAuraException('This event is no longer accepting responses.');
            }

            List<Response__c> existing = [
                SELECT Id, Status__c, Amount_Requested__c
                FROM Response__c
                WHERE Need_Offer_Responded_To__c = :eventId
                AND On_Behalf_Of_Contact__c = :actingAsContactId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            Map<String, Object> result;
            if (action == 'respond') {
                result = handleRespond(evt, existing, actingAsContactId, realContactId, guestCount);
                if (result.get('alreadyResponded') != true) {
                    FimbyGroupConversationController.syncEventChatMember(eventId, actingAsContactId, 'add');
                }
            } else if (action == 'withdraw') {
                result = handleWithdraw(evt, existing, actingAsContactId);
                if (result.get('alreadyWithdrawn') != true) {
                    FimbyGroupConversationController.syncEventChatMember(eventId, actingAsContactId, 'remove');
                }
            } else if (action == 'updateGuests') {
                result = handleUpdateGuests(existing, guestCount);
            } else {
                throw newAuraException('Invalid action: ' + action);
            }
            return result;
        }

        private Map<String, Object> handleRespond(Needs_Offers__c evt, List<Response__c> existing, String actingAsContactId, String realContactId, Integer guestCount) {
            Integer gc = (guestCount != null && guestCount >= 1) ? guestCount : 1;

            if (!existing.isEmpty() && ACTIVE_RESPONSE_STATUSES.contains(existing[0].Status__c)) {
                return new Map<String, Object>{
                    'success' => true,
                    'responseId' => existing[0].Id,
                    'status' => existing[0].Status__c,
                    'guestCount' => existing[0].Amount_Requested__c,
                    'action' => 'respond',
                    'alreadyResponded' => true
                };
            }

            Response__c newResp = new Response__c(
                Name = evt.Name,
                Contact__c = realContactId,
                On_Behalf_Of_Contact__c = actingAsContactId,
                Need_Offer_Responded_To__c = evt.Id,
                Response__c = 'Quick event response',
                Status__c = FimbyConstants.RESPONSE_ACCEPTED,
                Amount_Requested__c = gc,
                Neighbourhood__c = evt.Neighbourhood__c
            );
            insert newResp;

            FimbyCounterService.onResponseCreated(
                Id.valueOf(realContactId), FimbyConstants.RT_OFFER,
                actingAsContactId != realContactId,
                FimbyConstants.RESPONSE_ACCEPTED
            );

            if (evt.Posted_By__c != null && evt.Posted_By__c != actingAsContactId) {
                Contact responder = [SELECT Id, Full_Name__c FROM Contact WHERE Id = :actingAsContactId LIMIT 1];
                String responderName = responder.Full_Name__c;
                String evtType = evt.Event_Type__c;
                String notifBody = evtType == 'Community_Event'
                    ? responderName + ' is interested in ' + evt.Name
                    : responderName + ' is going to ' + evt.Name;
                FimbyNotificationService.createNotification(
                    evt.Posted_By__c,
                    FimbyConstants.NOTIF_RESPONSE,
                    responderName + (evtType == 'Community_Event' ? ' is interested' : ' is going'),
                    notifBody,
                    newResp.Id,
                    'Response__c',
                    FimbySettings.getUrl('Response_Reply', null, '?recordId=' + newResp.Id),
                    responderName
                );
            }

            return new Map<String, Object>{
                'success' => true,
                'responseId' => newResp.Id,
                'status' => FimbyConstants.RESPONSE_ACCEPTED,
                'guestCount' => gc,
                'action' => 'respond',
                'alreadyResponded' => false
            };
        }

        private Map<String, Object> handleWithdraw(Needs_Offers__c evt, List<Response__c> existing, String actingAsContactId) {
            if (existing.isEmpty() || !ACTIVE_RESPONSE_STATUSES.contains(existing[0].Status__c)) {
                return new Map<String, Object>{
                    'success' => true,
                    'action' => 'withdraw',
                    'alreadyWithdrawn' => true
                };
            }
            Response__c resp = existing[0];
            resp.Status__c = FimbyConstants.RESPONSE_CANCELLED;
            update resp;

            if (evt.Posted_By__c != null && evt.Posted_By__c != actingAsContactId) {
                Contact responder = [SELECT Id, Full_Name__c FROM Contact WHERE Id = :actingAsContactId LIMIT 1];
                String responderName = responder.Full_Name__c;
                String evtType = evt.Event_Type__c;
                String notifBody = evtType == 'Community_Event'
                    ? responderName + ' is no longer interested in ' + evt.Name
                    : responderName + ' is no longer going to ' + evt.Name;
                FimbyNotificationService.createNotification(
                    evt.Posted_By__c,
                    FimbyConstants.NOTIF_RESPONSE,
                    responderName + (evtType == 'Community_Event' ? ' is no longer interested' : ' is no longer going'),
                    notifBody,
                    resp.Id,
                    'Response__c',
                    FimbySettings.getUrl('Response_Reply', null, '?recordId=' + resp.Id),
                    responderName,
                    true
                );
            }

            return new Map<String, Object>{
                'success' => true,
                'responseId' => resp.Id,
                'status' => FimbyConstants.RESPONSE_CANCELLED,
                'action' => 'withdraw',
                'alreadyWithdrawn' => false
            };
        }

        private Map<String, Object> handleUpdateGuests(List<Response__c> existing, Integer guestCount) {
            if (existing.isEmpty() || !ACTIVE_RESPONSE_STATUSES.contains(existing[0].Status__c)) {
                throw newAuraException('You must respond to the event before updating guest count.');
            }
            Integer gc = (guestCount != null && guestCount >= 1) ? guestCount : 1;
            Response__c resp = existing[0];
            resp.Amount_Requested__c = gc;
            update resp;

            return new Map<String, Object>{
                'success' => true,
                'responseId' => resp.Id,
                'status' => resp.Status__c,
                'guestCount' => gc,
                'action' => 'updateGuests'
            };
        }
    }

    /**
     * Without sharing helper for event-scoped DM conversations.
     * Creates conversations scoped per event using Related_Record_Id__c + Context_Type__c = 'Event'.
     */
    private without sharing class EventConversationHelper {
        /**
         * Bidirectional event-scoped DM:
         *   targetContactId == null  → attendee messaging poster (existing flow, intent-gated)
         *   targetContactId != null  → poster messaging an attendee (poster-initiated)
         */
        public Map<String, Object> getOrCreate(String eventId, String actingAsContactId, String targetContactId) {
            Needs_Offers__c evt = [
                SELECT Id, Posted_By__c
                FROM Needs_Offers__c
                WHERE Id = :eventId
                LIMIT 1
            ];

            String posterContactId = evt.Posted_By__c;
            if (posterContactId == null) {
                throw newAuraException('Event has no poster.');
            }

            String otherContactId;
            if (String.isNotBlank(targetContactId)) {
                if (posterContactId != actingAsContactId) {
                    throw newAuraException('Only the event poster can message attendees.');
                }
                if (targetContactId == actingAsContactId) {
                    throw newAuraException('You cannot message yourself.');
                }
                List<Response__c> targetResp = [
                    SELECT Id FROM Response__c
                    WHERE Need_Offer_Responded_To__c = :eventId
                    AND On_Behalf_Of_Contact__c = :targetContactId
                    AND Status__c IN :ACTIVE_RESPONSE_STATUSES
                    LIMIT 1
                ];
                if (targetResp.isEmpty()) {
                    throw newAuraException('This person does not have an active response to the event.');
                }
                otherContactId = targetContactId;
            } else {
                if (posterContactId == actingAsContactId) {
                    throw newAuraException('You cannot message yourself.');
                }
                List<Response__c> activeResp = [
                    SELECT Id FROM Response__c
                    WHERE Need_Offer_Responded_To__c = :eventId
                    AND On_Behalf_Of_Contact__c = :actingAsContactId
                    AND Status__c IN :ACTIVE_RESPONSE_STATUSES
                    LIMIT 1
                ];
                if (activeResp.isEmpty()) {
                    throw newAuraException('You must respond to the event before messaging the poster.');
                }
                otherContactId = posterContactId;
            }

            Integer blockCount = [
                SELECT COUNT() FROM Blocked_Contact__c
                WHERE (Blocker__c = :actingAsContactId AND Blocked__c = :otherContactId)
                   OR (Blocker__c = :otherContactId AND Blocked__c = :actingAsContactId)
            ];
            if (blockCount > 0) {
                throw newAuraException('This contact is blocked.');
            }

            List<Conversation__c> existingConvs = [
                SELECT Id, Participant_1__c, Participant_1_Archived__c, Participant_2_Archived__c
                FROM Conversation__c
                WHERE Related_Record_Id__c = :eventId
                AND Context_Type__c = 'Event'
                AND ((Participant_1__c = :actingAsContactId AND Participant_2__c = :otherContactId)
                  OR (Participant_1__c = :otherContactId AND Participant_2__c = :actingAsContactId))
                LIMIT 1
            ];

            if (!existingConvs.isEmpty()) {
                Conversation__c conv = existingConvs[0];
                Boolean isP1 = (conv.Participant_1__c == actingAsContactId);
                if ((isP1 && conv.Participant_1_Archived__c) || (!isP1 && conv.Participant_2_Archived__c)) {
                    Conversation__c upd = new Conversation__c(Id = conv.Id);
                    if (isP1) upd.Participant_1_Archived__c = false;
                    else upd.Participant_2_Archived__c = false;
                    update upd;
                }
                return new Map<String, Object>{
                    'success' => true,
                    'conversationId' => conv.Id,
                    'isNew' => false
                };
            }

            Conversation__c newConv = new Conversation__c(
                Participant_1__c = actingAsContactId,
                Participant_2__c = otherContactId,
                Status__c = FimbyConstants.CONVERSATION_ACTIVE,
                Context_Type__c = 'Event',
                Related_Record_Id__c = eventId,
                Participant_1_Unread_Count__c = 0,
                Participant_2_Unread_Count__c = 0,
                Participant_1_Archived__c = false,
                Participant_2_Archived__c = false
            );
            insert newConv;

            return new Map<String, Object>{
                'success' => true,
                'conversationId' => newConv.Id,
                'isNew' => true
            };
        }
    }

    private without sharing class ResponseHelper {
        /**
         * @description Inserts a Response__c record without sharing enforcement.
         * @param response The Response__c record to insert
         */
        public void insertResponse(Response__c response) {
            insert response;
        }

        /**
         * @description Updates a Response__c record without sharing enforcement.
         * @param response The Response__c record to update
         */
        public void updateResponse(Response__c response) {
            update response;
        }
    }

    /**
     * Without sharing helper for querying Response__c records.
     * Community users may not have direct record access via sharing rules,
     * but auth checks in the calling methods enforce proper authorization.
     */
    private without sharing class ResponseQueryHelper {
        /**
         * @description Queries a Response__c record with all fields needed for the reply form.
         * @param recordId The Response__c record ID
         * @return The Response__c record or null if not found
         */
        public Response__c queryResponseForReply(String recordId) {
            List<Response__c> results = [
                SELECT Id, Name, Status__c, Response__c, Contact__c, Contact__r.Name,
                       On_Behalf_Of_Contact__c, On_Behalf_Of_Contact__r.Name,
                       OwnerId, Reply_To_Contact__c, Reply_To_Contact__r.Name,
                       Need_Offer_Responded_To__c, Need_Offer_Responded_To__r.Name,
                       Need_Offer_Responded_To__r.OwnerId, Need_Offer_Responded_To__r.Posted_By__c,
                       Need_Offer_Responded_To__r.Posted_By__r.FirstName,
                       Need_Offer_Responded_To__r.Posted_By__r.LastName,
                       Need_Offer_Responded_To__r.Type__c,
                       Need_Offer_Responded_To__r.Event_Type__c
                FROM Response__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            return results.isEmpty() ? null : results[0];
        }

        /**
         * @description Queries a Response__c record with fields needed for submitting a reply.
         * @param responseId The Response__c record ID
         * @return The Response__c record
         */
        public Response__c queryResponseForSubmitReply(String responseId) {
            return [
                SELECT Id, Name, OwnerId, Contact__c, Contact__r.FirstName, Contact__r.LastName,
                       On_Behalf_Of_Contact__c, On_Behalf_Of_Contact__r.FirstName, On_Behalf_Of_Contact__r.LastName,
                       Reply_To_Contact__c, Need_Offer_Responded_To__c, Need_Offer_Responded_To__r.OwnerId,
                       Need_Offer_Responded_To__r.Posted_By__c,
                       Need_Offer_Responded_To__r.Posted_By__r.FirstName
                FROM Response__c
                WHERE Id = :responseId
                LIMIT 1
            ];
        }

        /**
         * @description Queries a Response__c record for the status-update modal.
         * Posters must load responder-owned rows; sharing rules alone would return zero rows.
         * @param recordId The Response__c record ID
         * @return The Response__c record or null if not found
         */
        public Response__c queryResponseForStatusUpdate(String recordId) {
            List<Response__c> results = [
                SELECT Id, Name, Status__c, OwnerId,
                       Need_Offer_Responded_To__c, Need_Offer_Responded_To__r.OwnerId
                FROM Response__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            return results.isEmpty() ? null : results[0];
        }

        /**
         * @description Queries a Needs_Offers__c record for the response composer.
         * @param recordId The Needs_Offers__c record ID
         * @return The Needs_Offers__c record or null if not found
         */
        public Needs_Offers__c queryNeedOfferForResponse(String recordId) {
            List<Needs_Offers__c> results = [
                SELECT Id, Name, Details__c, Full_Details__c, Posting_Details__c, Image_1_URL__c,
                       Total_Available__c, Total_Quantity__c, Per_Response_Limit__c,
                       Auto_Accept_Responses__c, Neighbourhood__c,
                       OwnerId, Posted_By__c, Posted_By__r.FirstName, Posted_By__r.LastName,
                       RecordType.DeveloperName, Type__c
                FROM Needs_Offers__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            return results.isEmpty() ? null : results[0];
        }
    }

    private without sharing class ShareContactInfoHelper {

        /**
         * @description Loads response, recipient, and sharing contact data for the Share Contact Info flow.
         * @param recordId The Response__c record ID
         * @return Map containing success, response, needOffer, recipient, and sharingContact data
         */
        public Map<String, Object> getResponseForShareContactInfoInternal(String recordId) {
            Response__c response = [
                SELECT Id, Name, OwnerId, Contact__c, Contact__r.Name,
                       On_Behalf_Of_Contact__c, On_Behalf_Of_Contact__r.Name,
                       Reply_To_Contact__c, Reply_To_Contact__r.Name,
                       Need_Offer_Responded_To__c, Need_Offer_Responded_To__r.OwnerId,
                       Need_Offer_Responded_To__r.Posted_By__c,
                       Need_Offer_Responded_To__r.Name
                FROM Response__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            User currentUser = FimbyIdentityRepository.getCurrentUser();
            String currentUserId = UserInfo.getUserId();

            String postBy = String.valueOf(response.Need_Offer_Responded_To__r.OwnerId).substring(0, 15);
            String respondeeContact = String.valueOf(response.OwnerId).substring(0, 15);
            String currentUser15 = currentUserId.substring(0, 15);

            Boolean isPostedBy = (currentUser15 == postBy);
            Boolean isRespondee = (currentUser15 == respondeeContact);

            if (!isPostedBy && !isRespondee) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notAuthorized',
                    'message' => 'You are not the owner of this contact, post or response so you are not able to share contact information here.'
                };
            }

            String recipientContactId;
            if (isPostedBy) {
                recipientContactId = response.Contact__c;
            } else {
                recipientContactId = response.Reply_To_Contact__c;
            }

            Contact recipient = [
                SELECT Id, Name, FirstName, LastName
                FROM Contact
                WHERE Id = :recipientContactId
                LIMIT 1
            ];

            if (currentUser.ContactId == recipientContactId) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'selfShare',
                    'message' => 'You cannot share contact info with yourself.'
                };
            }

            String sharingContactId;
            if (isPostedBy) {
                sharingContactId = response.Reply_To_Contact__c;
            } else {
                sharingContactId = response.Contact__c;
            }

            Contact sharingContact = [
                SELECT Id, Name, FirstName, LastName, Email, Phone,
                       MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
                FROM Contact
                WHERE Id = :sharingContactId
                LIMIT 1
            ];

            return new Map<String, Object>{
                'success' => true,
                'isPostedBy' => isPostedBy,
                'response' => new Map<String, Object>{
                    'id' => response.Id,
                    'name' => response.Name
                },
                'needOffer' => new Map<String, Object>{
                    'name' => response.Need_Offer_Responded_To__r?.Name
                },
                'recipient' => new Map<String, Object>{
                    'id' => recipient.Id,
                    'name' => recipient.Name,
                    'firstName' => recipient.FirstName
                },
                'sharingContact' => new Map<String, Object>{
                    'id' => sharingContact.Id,
                    'name' => sharingContact.Name,
                    'email' => sharingContact.Email,
                    'phone' => sharingContact.Phone,
                    'street' => sharingContact.MailingStreet,
                    'city' => sharingContact.MailingCity,
                    'state' => sharingContact.MailingState,
                    'postalCode' => sharingContact.MailingPostalCode,
                    'country' => sharingContact.MailingCountry
                }
            };
        }

        /**
         * @description Shares contact info between participants on a response. Creates or updates
         * Shared_Contact_Info__c and optionally emails the recipient.
         * @param data Map with responseId, sharingContactId, recipientContactId, shareEmail, sharePhone,
         *            shareAddress, and optional address fields
         * @return Map with success, message, and sharedContactInfoId
         */
        public Map<String, Object> shareContactInfoInternal(Map<String, Object> data) {
            String responseId = (String) data.get('responseId');
            String sharingContactId = (String) data.get('sharingContactId');
            String recipientContactId = (String) data.get('recipientContactId');
            Boolean shareEmail = data.get('shareEmail') == true;
            Boolean sharePhone = data.get('sharePhone') == true;
            Boolean shareAddress = data.get('shareAddress') == true;

            String email = (String) data.get('email');
            String phone = (String) data.get('phone');
            String street = (String) data.get('street');
            String city = (String) data.get('city');
            String state = (String) data.get('state');
            String postalCode = (String) data.get('postalCode');
            String country = (String) data.get('country');

            Contact sharingContact = [
                SELECT Id, Name, FirstName, LastName, Email
                FROM Contact
                WHERE Id = :sharingContactId
                LIMIT 1
            ];

            Contact recipientContact = [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id = :recipientContactId
                LIMIT 1
            ];

            Response__c response = [
                SELECT Id, Need_Offer_Responded_To__r.Name
                FROM Response__c
                WHERE Id = :responseId
                LIMIT 1
            ];

            List<Shared_Contact_Info__c> existingRecords = [
                SELECT Id, Email__c, Phone__c, Street__c, City__c, Province_State__c,
                       Postal_Code__c, Country__c, Additional_Info__c
                FROM Shared_Contact_Info__c
                WHERE Contact__c = :sharingContactId
                  AND Shared_To__c = :recipientContactId
                LIMIT 1
            ];

            Shared_Contact_Info__c sharedInfo;
            Boolean isNew = existingRecords.isEmpty();
            Shared_Contact_Info__c beforeShare = isNew
                ? null
                : existingRecords[0].clone(false, false, false, false);

            Boolean shouldSendEmail = isNew || FimbySharedContactInfoHelper.hasExpandedContactShare(
                beforeShare,
                FimbySharedContactInfoHelper.buildAfterStateMerge(
                    beforeShare,
                    shareEmail,
                    sharePhone,
                    shareAddress,
                    email,
                    phone,
                    street,
                    city,
                    state,
                    postalCode,
                    country,
                    null
                )
            );

            if (isNew) {
                sharedInfo = new Shared_Contact_Info__c(
                    Contact__c = sharingContactId,
                    Shared_To__c = recipientContactId,
                    Response__c = responseId,
                    Origin__c = 'Response'
                );
            } else {
                sharedInfo = existingRecords[0];
                sharedInfo.Response__c = responseId;
                sharedInfo.Origin__c = 'Response';
            }

            if (shareEmail && String.isNotBlank(email)) {
                sharedInfo.Email__c = email;
            }
            if (sharePhone && String.isNotBlank(phone)) {
                sharedInfo.Phone__c = phone;
            }
            if (shareAddress) {
                sharedInfo.Street__c = street;
                sharedInfo.City__c = city;
                sharedInfo.Province_State__c = state;
                sharedInfo.Postal_Code__c = postalCode;
                sharedInfo.Country__c = country;
            }

            new SharedContactInfoDmlHelper().upsertSharedContactInfo(sharedInfo, isNew);

            if (shouldSendEmail) {
                List<User> recipientUsers = [
                    SELECT Id FROM User
                    WHERE ContactId = :recipientContact.Id AND IsActive = true
                    LIMIT 1
                ];
                if (!recipientUsers.isEmpty()) {
                    String senderName = sharingContact.FirstName + ' ' + sharingContact.LastName;
                    String contextLabel = response.Need_Offer_Responded_To__r?.Name;
                    String emailVal = (shareEmail && String.isNotBlank(email)) ? email : null;
                    String phoneVal = (sharePhone && String.isNotBlank(phone)) ? phone : null;
                    String streetVal = shareAddress ? (street + ', ' + city + ', ' + state + ' ' + postalCode) : null;

                    String cardHtml = FimbyEmailHtmlBuilder.buildContactShareCard(
                        senderName, emailVal, phoneVal, streetVal, null, contextLabel
                    );

                    FimbyTransactionalEmailService.TransactionalEmailRequest emailReq =
                        new FimbyTransactionalEmailService.TransactionalEmailRequest();
                    emailReq.recipientUserId = recipientUsers[0].Id;
                    emailReq.subject = 'Contact info shared — ' + (contextLabel != null ? contextLabel : 'your post');
                    emailReq.cardHtml = cardHtml;
                    emailReq.skipSubjectBlock = true;
                    emailReq.replyToEmail = sharingContact.Email;
                    emailReq.ctaUrl = FimbySettings.getUrl('Response_Reply', null, '?recordId=' + responseId);

                    FimbyTransactionalEmailService.send(emailReq);
                }
            }

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Contact information shared successfully',
                'sharedContactInfoId' => sharedInfo.Id
            };
        }
    }

    private without sharing class SharedContactInfoDmlHelper {
        /**
         * @description Inserts or updates a Shared_Contact_Info__c record based on isNew flag.
         * @param record The Shared_Contact_Info__c record to upsert
         * @param isNew True to insert, false to update
         */
        public void upsertSharedContactInfo(Shared_Contact_Info__c record, Boolean isNew) {
            if (isNew) {
                insert record;
            } else {
                update record;
            }
        }
    }
}