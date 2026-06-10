/**
 * @description Handles Needs & Offers (Ask & Offer) functionality.
 * Extracted from FimbyLibraryController for better maintainability.
 * Used by fimbyAskOfferComposer LWC.
 */
public with sharing class FimbyAskOfferController {

    /**
     * Get picklist values for Needs_Offers__c.Type__c
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getNeedsOffersTypePicklist() {
        List<Map<String, String>> options = new List<Map<String, String>>();

        Schema.DescribeFieldResult fieldResult = Needs_Offers__c.Type__c.getDescribe();
        List<Schema.PicklistEntry> entries = fieldResult.getPicklistValues();

        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                options.add(new Map<String, String>{
                    'label' => entry.getLabel(),
                    'value' => entry.getValue()
                });
            }
        }

        return options;
    }

    /**
     * Create a new Needs_Offers__c record (Need or Offer)
     * Matches Post_A_Need.flow and Post_an_Offer.flow logic
     */
    @AuraEnabled
    public static Map<String, Object> createNeedsOffersPost(String postData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(postData);

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;
            Id neighbourhoodId = identity.neighbourhoodId;

            String postType = (String) data.get('postType');

            List<RecordType> rtList = [
                SELECT Id
                FROM RecordType
                WHERE SobjectType = 'Needs_Offers__c'
                AND DeveloperName = :postType
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (rtList.isEmpty()) {
                throw new AuraHandledException('Record type not found: ' + postType);
            }
            Id recordTypeId = rtList[0].Id;

            String title = (String) data.get('title');
            String description = (String) data.get('description');
            String typeValue = (String) data.get('type');

            // Quantity: Ask defaults to 1; null means unlimited (Open/Community Events)
            Decimal quantity = (postType == FimbyConstants.RT_NEED)
                ? 1
                : (data.get('quantity') != null ? Decimal.valueOf(String.valueOf(data.get('quantity'))) : null);
            Decimal perResponseLimit = data.get('perResponseLimit') != null
                ? Decimal.valueOf(String.valueOf(data.get('perResponseLimit')))
                : 1;

            // End date (start date no longer sent for Ask/Offer)
            String endDateStr = (String) data.get('endDate');
            Date endDate = String.isNotBlank(endDateStr) ? Date.valueOf(endDateStr) : Date.today().addDays(postType == FimbyConstants.RT_NEED ? FimbySettings.needDefaultEndDays() : FimbySettings.offerDefaultEndDays());

            // Event datetime-local fields: parse ISO strings like '2026-03-20T09:00'
            String eventStartStr = (String) data.get('eventStart');
            String eventEndStr = (String) data.get('eventEnd');
            Date startDate = null;
            String startTime = null;
            Time startTimeValue = null;
            Date endDateFromEvent = null;
            String endTime = null;
            Time endTimeValue = null;
            String location = (String) data.get('location');

            if (String.isNotBlank(eventStartStr) && eventStartStr.contains('T')) {
                List<String> parts = eventStartStr.split('T');
                startDate = Date.valueOf(parts[0]);
                startTime = formatTimeFromIso(parts[1]);
                List<String> hm = parts[1].split(':');
                startTimeValue = Time.newInstance(Integer.valueOf(hm[0]), Integer.valueOf(hm[1]), 0, 0);
            }
            if (String.isNotBlank(eventEndStr) && eventEndStr.contains('T')) {
                List<String> parts = eventEndStr.split('T');
                endDateFromEvent = Date.valueOf(parts[0]);
                endTime = formatTimeFromIso(parts[1]);
                endDate = endDateFromEvent;
                List<String> hm = parts[1].split(':');
                endTimeValue = Time.newInstance(Integer.valueOf(hm[0]), Integer.valueOf(hm[1]), 0, 0);
            }

            validateEventDatetimeOrder(startDate, startTimeValue, endDateFromEvent, endTimeValue);

            // Settings
            Boolean autoAccept = data.get('autoAcceptResponses') == true;
            Boolean autoShare = data.get('autoShareContactInfo') == true;

            // Create Details__c (truncated to 255 chars, matching flow formula)
            String details = description.length() <= 255 ? description : description.substring(0, 252) + '...';

            Needs_Offers__c newPost = new Needs_Offers__c(
                RecordTypeId = recordTypeId,
                Name = title,
                Details__c = details,
                Full_Details__c = description,
                Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
                Contact__c = actingAsContactId,
                Posted_By__c = realContactId,
                Neighbourhood__c = neighbourhoodId,
                Giver_Recipient_Type__c = FimbyConstants.VIS_SELF,
                Total_Quantity__c = quantity,
                Per_Response_Limit__c = perResponseLimit,
                Start_Date__c = startDate,
                End_Date__c = endDate,
                Start_Time__c = startTimeValue,
                Start_Time_Text__c = startTime,
                End_Time__c = endTimeValue,
                End_Time_Text__c = endTime,
                Location__c = location,
                Auto_Accept_Responses__c = autoAccept,
                Auto_Share_Contact_Info__c = autoShare
            );

            if (String.isNotBlank(typeValue)) {
                newPost.Type__c = typeValue;
            }

            if (data.get('isUrgent') == true) {
                newPost.Is_Urgent__c = true;
            }

            String eventTypeValue = (String) data.get('eventType');
            if (String.isNotBlank(eventTypeValue)) {
                newPost.Event_Type__c = eventTypeValue;
                if (eventTypeValue == 'Open_Event') {
                    newPost.Auto_Accept_Responses__c = true;
                }
            }
            if (data.get('expectedAttendance') != null) {
                newPost.Expected_Attendance__c = Decimal.valueOf(String.valueOf(data.get('expectedAttendance')));
            }
            String eventNotes = (String) data.get('eventNotes');
            if (String.isNotBlank(eventNotes)) {
                newPost.Event_Notes__c = eventNotes;
            }
            String eventLink = (String) data.get('eventLink');
            if (String.isNotBlank(eventLink)) {
                newPost.Event_Link__c = eventLink;
            }

            // Set visibility scope based on content type
            String rtName = '';
            if (newPost.RecordTypeId != null) {
                rtName = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosById().get(newPost.RecordTypeId)?.getDeveloperName();
            }
            if (rtName == FimbyConstants.RT_BULK_BUY) {
                newPost.Visibility_Scope__c = 'Adjacent';
            } else if (rtName == FimbyConstants.RT_OFFER && newPost.Event_Type__c == null) {
                newPost.Visibility_Scope__c = 'Adjacent';
            } else if (newPost.Is_Urgent__c == true) {
                newPost.Visibility_Scope__c = 'Adjacent';
            } else if (newPost.Event_Type__c == 'Gathering') {
                newPost.Visibility_Scope__c = 'Neighbourhood';
            } else if (newPost.Event_Type__c != null) {
                newPost.Visibility_Scope__c = 'Regional';
            } else {
                newPost.Visibility_Scope__c = 'Neighbourhood';
            }

            FimbyRecurrenceService.applyRecurrenceOnCreate(newPost, data);

            new NeedsOffersHelper().insertPost(newPost);

            FimbyRecurrenceService.finalizeSeriesParentAfterInsert(newPost);

            FimbyCounterService.onPostCreated(
                realContactId, postType, actingAsContactId != realContactId
            );

            String postUrl = FimbySettings.getUrl('Needs_Offers', newPost.Id);

            return new Map<String, Object>{
                'success' => true,
                'recordId' => newPost.Id,
                'postUrl' => postUrl,
                'message' => postType + ' posted successfully'
            };

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error('FimbyAskOfferController', 'createNeedsOffersPost', e);
            AuraHandledException ex = new AuraHandledException('Error creating post: ' + e.getMessage());
            ex.setMessage('Error creating post: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Update an existing Needs_Offers__c post (Ask, Offer, or Event).
     * Mirrors createNeedsOffersPost field mapping; does not accept Type__c, Status__c, or Category__c.
     */
    @AuraEnabled
    public static Map<String, Object> updateNeedsOffersPost(String postData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(postData);
            String recordId = (String) data.get('recordId');
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Needs_Offers__c post = [
                SELECT Id, Posted_By__c, Contact__c, RecordType.DeveloperName,
                       Type__c, Event_Type__c, Is_Urgent__c,
                       Start_Date__c, Start_Time__c, End_Date__c, End_Time__c,
                       Series_Parent__c, Recurrence_Frequency__c, Recurrence_Interval__c,
                       Recurrence_End_Mode__c, Recurrence_End_Date__c, Recurrence_Max_Occurrences__c,
                       Reinvite_Prior_Attendees__c, Series_Ended__c, Current_Occurrence__c,
                       Name, Details__c, Full_Details__c, Location__c, Event_Link__c, Event_Notes__c,
                       Total_Quantity__c, Per_Response_Limit__c, Expected_Attendance__c,
                       Auto_Accept_Responses__c, Auto_Share_Contact_Info__c,
                       Image_1_URL__c, Image_1_Ratio__c, Image_2_URL__c, Image_2_Ratio__c,
                       Image_3_URL__c, Image_3_Ratio__c, Image_4_URL__c, Image_4_Ratio__c
                FROM Needs_Offers__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            if (post.Posted_By__c != realContactId && post.Contact__c != actingAsContactId) {
                throw new AuraHandledException('You can only edit posts you created.');
            }

            if (data.containsKey('title')) {
                post.Name = (String) data.get('title');
            }
            if (data.containsKey('description')) {
                String description = (String) data.get('description');
                post.Full_Details__c = description;
                post.Details__c = description != null && description.length() > 255
                    ? description.substring(0, 252) + '...' : description;
            }

            String endDateStr = (String) data.get('endDate');
            if (String.isNotBlank(endDateStr)) {
                post.End_Date__c = Date.valueOf(endDateStr);
            }

            if (data.containsKey('quantity')) {
                post.Total_Quantity__c = data.get('quantity') != null
                    ? Decimal.valueOf(String.valueOf(data.get('quantity'))) : null;
            }
            if (data.containsKey('perResponseLimit')) {
                post.Per_Response_Limit__c = data.get('perResponseLimit') != null
                    ? Decimal.valueOf(String.valueOf(data.get('perResponseLimit'))) : null;
            }

            String eventStartStr = (String) data.get('eventStart');
            String eventEndStr = (String) data.get('eventEnd');
            if (String.isNotBlank(eventStartStr) && eventStartStr.contains('T')) {
                List<String> parts = eventStartStr.split('T');
                post.Start_Date__c = Date.valueOf(parts[0]);
                post.Start_Time_Text__c = formatTimeFromIso(parts[1]);
                List<String> hm = parts[1].split(':');
                post.Start_Time__c = Time.newInstance(Integer.valueOf(hm[0]), Integer.valueOf(hm[1]), 0, 0);
            }
            if (eventEndStr != null) {
                if (String.isNotBlank(eventEndStr) && eventEndStr.contains('T')) {
                    List<String> parts = eventEndStr.split('T');
                    post.End_Date__c = Date.valueOf(parts[0]);
                    post.End_Time_Text__c = formatTimeFromIso(parts[1]);
                    List<String> hm = parts[1].split(':');
                    post.End_Time__c = Time.newInstance(Integer.valueOf(hm[0]), Integer.valueOf(hm[1]), 0, 0);
                } else if (String.isBlank(eventEndStr)) {
                    post.End_Time__c = null;
                    post.End_Time_Text__c = null;
                }
            }
            if (data.containsKey('location')) {
                post.Location__c = (String) data.get('location');
            }

            if (data.containsKey('isUrgent')) {
                post.Is_Urgent__c = data.get('isUrgent') == true;
            }
            if (data.containsKey('autoAcceptResponses')) {
                post.Auto_Accept_Responses__c = data.get('autoAcceptResponses') == true;
            }
            if (data.containsKey('autoShareContactInfo')) {
                post.Auto_Share_Contact_Info__c = data.get('autoShareContactInfo') == true;
            }
            if (data.containsKey('expectedAttendance')) {
                post.Expected_Attendance__c = data.get('expectedAttendance') != null
                    ? Decimal.valueOf(String.valueOf(data.get('expectedAttendance'))) : null;
            }
            if (data.containsKey('eventNotes')) {
                post.Event_Notes__c = (String) data.get('eventNotes');
            }
            if (data.containsKey('eventLink')) {
                post.Event_Link__c = (String) data.get('eventLink');
            }

            // Recompute visibility scope when urgency changes
            String rtName = post.RecordType?.DeveloperName;
            if (rtName == FimbyConstants.RT_BULK_BUY) {
                post.Visibility_Scope__c = 'Adjacent';
            } else if (rtName == FimbyConstants.RT_OFFER && post.Event_Type__c == null) {
                post.Visibility_Scope__c = 'Adjacent';
            } else if (post.Is_Urgent__c == true) {
                post.Visibility_Scope__c = 'Adjacent';
            } else if (post.Event_Type__c == 'Gathering') {
                post.Visibility_Scope__c = 'Neighbourhood';
            } else if (post.Event_Type__c != null) {
                post.Visibility_Scope__c = 'Regional';
            } else {
                post.Visibility_Scope__c = 'Neighbourhood';
            }

            if (post.Event_Type__c == 'Open_Event') {
                post.Auto_Accept_Responses__c = true;
            }

            if (post.Type__c == 'Event') {
                validateEventDatetimeOrder(
                    post.Start_Date__c,
                    post.Start_Time__c,
                    post.End_Date__c,
                    post.End_Time__c
                );
            }

            Id parentId = FimbyRecurrenceService.resolveSeriesParentId(post);
            Needs_Offers__c parent = null;
            if (parentId != post.Id) {
                parent = loadSeriesParent(parentId);
            } else if (String.isNotBlank(post.Recurrence_Frequency__c)) {
                parent = post;
            }

            String recurrenceScope = (String) data.get('recurrenceScope');
            FimbyRecurrenceService.applyRecurrenceOnUpdate(post, parent, data, recurrenceScope);

            NeedsOffersHelper helper = new NeedsOffersHelper();
            helper.updatePost(post);
            if (parent != null && parent.Id != post.Id) {
                helper.updatePost(parent);
            }

            return new Map<String, Object>{
                'success' => true,
                'recordId' => post.Id,
                'message' => 'Post updated successfully'
            };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error('FimbyAskOfferController', 'updateNeedsOffersPost', e);
            AuraHandledException ex = new AuraHandledException('Error updating post: ' + e.getMessage());
            ex.setMessage('Error updating post: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get responses for a specific Need/Offer record (for detail page related list).
     * Returns enhanced data for poster triage: amount, last message preview,
     * last activity time, unread count, and response owner for auth checks.
     * Posters receive all responses; other viewers receive only their own.
     */
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getResponsesForNeedOffer(String needOfferId) {
        if (String.isBlank(needOfferId)) {
            return new List<Map<String, Object>>();
        }

        FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
        Id realContactId = identity.currentUser.ContactId;
        Id actingAsContactId = identity.actingAsContactId;

        ResponseListHelper helper = new ResponseListHelper();
        Needs_Offers__c post = helper.queryPost(needOfferId);
        if (post == null) {
            return new List<Map<String, Object>>();
        }

        Boolean isPoster = post.Posted_By__c == realContactId || post.Contact__c == actingAsContactId;
        List<Response__c> responses = isPoster
            ? helper.queryAllResponses(needOfferId)
            : helper.queryResponsesForViewer(needOfferId, realContactId, actingAsContactId);

        return mapResponsesForDetail(responses);
    }

    private static List<Map<String, Object>> mapResponsesForDetail(List<Response__c> responses) {
        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (Response__c resp : responses) {
            Datetime lastActivity = resp.Last_Reply_Date__c != null
                ? Datetime.newInstance(resp.Last_Reply_Date__c, Time.newInstance(0, 0, 0, 0))
                : resp.CreatedDate;
            Integer unreadCount = resp.Poster_Unread_Count__c != null
                ? resp.Poster_Unread_Count__c.intValue() : 0;

            results.add(new Map<String, Object>{
                'id' => resp.Id,
                'name' => resp.Name,
                'responderName' => resp.Responding_Contact_Text__c,
                'status' => resp.Status__c,
                'createdDate' => resp.CreatedDate,
                'amountRequested' => resp.Amount_Requested__c,
                'lastMessagePreview' => resp.Last_Reply__c,
                'lastActivityDate' => lastActivity,
                'unreadCount' => unreadCount,
                'ownerId' => resp.OwnerId,
                'contactId' => resp.On_Behalf_Of_Contact__c,
                'avatarUrl' => resp.On_Behalf_Of_Contact__r?.Image_URL__c,
                'posterThanked' => resp.Poster_Thanked__c,
                'responderThanked' => resp.Responder_Thanked__c
            });
        }
        return results;
    }

    /**
     * Delete a Needs_Offers__c record (with ownership check)
     */
    @AuraEnabled
    public static Map<String, Object> deleteNeedsOffersPost(String recordId, String seriesDeleteScope) {
        try {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Needs_Offers__c post = [
                SELECT Id, Name, Posted_By__c, Contact__c, OwnerId, RecordType.DeveloperName,
                       Series_Parent__c, Recurrence_Frequency__c
                FROM Needs_Offers__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (post.Posted_By__c != realContactId && post.Contact__c != actingAsContactId) {
                throw new AuraHandledException('You can only delete posts you have created.');
            }

            notifyPendingRespondersOnDelete(identity.orgDisplayName, post);

            FimbyCounterService.onPostDeleted(
                post.Posted_By__c,
                post.RecordType.DeveloperName,
                post.Posted_By__c != post.Contact__c
            );

            if (FimbyRecurrenceService.isSeriesMember(post)) {
                FimbyRecurrenceService.deleteSeriesMember(recordId, seriesDeleteScope);
            } else {
                new NeedsOffersHelper().deletePost(post);
            }

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Post deleted successfully'
            };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error deleting post: ' + e.getMessage());
            ex.setMessage('Error deleting post: ' + e.getMessage());
            throw ex;
        }
    }

    private static void notifyPendingRespondersOnDelete(String actorName, Needs_Offers__c post) {
        List<Response__c> pendingResponses = new ResponseListHelper().queryPendingResponses(post.Id);
        Set<Id> notifiedContacts = new Set<Id>();
        for (Response__c resp : pendingResponses) {
            Id recipientId = resp.On_Behalf_Of_Contact__c != null
                ? resp.On_Behalf_Of_Contact__c
                : resp.Contact__c;
            if (recipientId == null || notifiedContacts.contains(recipientId)) {
                continue;
            }
            notifiedContacts.add(recipientId);
            FimbyNotificationService.createNotification(
                recipientId,
                FimbyConstants.NOTIF_RESPONSE,
                actorName + ' removed a post you responded to',
                '"' + post.Name + '" is no longer available.',
                resp.Id,
                'Response__c',
                FimbySettings.getUrl('Home'),
                actorName
            );
        }
    }

    private static Needs_Offers__c loadSeriesParent(Id parentId) {
        List<Needs_Offers__c> rows = [
            SELECT Id, Recurrence_Frequency__c, Recurrence_Interval__c,
                   Recurrence_End_Mode__c, Recurrence_End_Date__c, Recurrence_Max_Occurrences__c,
                   Reinvite_Prior_Attendees__c, Next_Occurrence_Date__c, Current_Occurrence__c,
                   Series_Ended__c, Name, Details__c, Full_Details__c, Location__c, Event_Link__c,
                   Event_Notes__c, Total_Quantity__c, Per_Response_Limit__c, Expected_Attendance__c,
                   Auto_Accept_Responses__c, Auto_Share_Contact_Info__c,
                   Image_1_URL__c, Image_1_Ratio__c, Image_2_URL__c, Image_2_Ratio__c,
                   Image_3_URL__c, Image_3_Ratio__c, Image_4_URL__c, Image_4_Ratio__c
            FROM Needs_Offers__c
            WHERE Id = :parentId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static void validateEventDatetimeOrder(
        Date startDate,
        Time startTime,
        Date endDate,
        Time endTime
    ) {
        if (startDate == null || startTime == null || endDate == null || endTime == null) {
            return;
        }
        Datetime startDt = Datetime.newInstance(startDate, startTime);
        Datetime endDt = Datetime.newInstance(endDate, endTime);
        if (endDt <= startDt) {
            AuraHandledException ex = new AuraHandledException(
                'The end time needs to come after the start time.'
            );
            ex.setMessage('The end time needs to come after the start time.');
            throw ex;
        }
    }

    /**
     * Converts an ISO time fragment like '09:00' or '14:30' to '9:00 am' / '2:30 pm'.
     */
    private static String formatTimeFromIso(String isoTime) {
        if (String.isBlank(isoTime)) return null;
        List<String> hm = isoTime.split(':');
        Integer hour = Integer.valueOf(hm[0]);
        String minutes = hm[1].left(2);
        String amPm = hour >= 12 ? 'pm' : 'am';
        if (hour == 0) hour = 12;
        else if (hour > 12) hour -= 12;
        return hour + ':' + minutes + ' ' + amPm;
    }

    /**
     * @description Visibility check for a single Needs_Offers__c record. Returns
     * { visible: true } when the record is visible to the running user (moderation
     * + neighbourhood/scope filters mirror listAsksAndOffers). Otherwise returns
     * { removed: true, message: 'This post is no longer available.' } so detail
     * LWCs can render a "no longer available" state instead of leaking the
     * record via UI API getRecord (which ignores Moderation_Status__c).
     *
     * Owner-of-record sees the same removed state in MVP — a future enhancement
     * could surface a "Hidden by moderator" label for the author specifically.
     */
    @AuraEnabled(cacheable=true)
    public static VisibilityResult getNeedOfferVisibility(Id recordId) {
        if (recordId == null) {
            return new VisibilityResult(false, true, 'This post is no longer available.');
        }

        try {
            String neighbourhoodAccountId = FimbyIdentityRepository.getNeighbourhoodId();
            Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
            Set<Id> sharedContactIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();

            Needs_Offers__c row = new NeedsOffersHelper().queryVisiblePost(
                recordId,
                neighbourhoodAccountId,
                adjacentIds,
                sharedContactIds
            );

            return row == null
                ? new VisibilityResult(false, true, 'This post is no longer available.')
                : new VisibilityResult(true, false, null, row.Group_Conversation__c);

        } catch (Exception e) {
            FimbyLogger.error('FimbyAskOfferController', 'getNeedOfferVisibility', e);
            return new VisibilityResult(false, true, 'This post is no longer available.');
        }
    }

    /**
     * Non-cacheable lookup for event/bulk-buy group chat id. Used imperatively because
     * community FLS hides Group_Conversation__c from uiRecordApi and cacheable visibility
     * wire can serve a stale null groupConversationId after chat creation.
     */
    @AuraEnabled
    public static Id getGroupConversationIdForPost(Id recordId) {
        if (recordId == null) {
            return null;
        }
        try {
            return new NeedsOffersHelper().queryGroupConversationId(recordId);
        } catch (Exception e) {
            FimbyLogger.error('FimbyAskOfferController', 'getGroupConversationIdForPost', e);
            return null;
        }
    }

    public class VisibilityResult {
        @AuraEnabled public Boolean visible { get; set; }
        @AuraEnabled public Boolean removed { get; set; }
        @AuraEnabled public String message { get; set; }
        /** Event/Bulk Buy group chat — resolved server-side because community FLS may hide the lookup from uiRecordApi. */
        @AuraEnabled public Id groupConversationId { get; set; }

        public VisibilityResult(Boolean visible, Boolean removed, String message) {
            this(visible, removed, message, null);
        }

        public VisibilityResult(Boolean visible, Boolean removed, String message, Id groupConversationId) {
            this.visible = visible;
            this.removed = removed;
            this.message = message;
            this.groupConversationId = groupConversationId;
        }
    }

    /**
     * @description Without sharing helper for Response__c list queries on the detail page.
     * Community posters cannot see responder-owned rows via sharing rules alone.
     */
    private without sharing class ResponseListHelper {
        public Needs_Offers__c queryPost(String needOfferId) {
            List<Needs_Offers__c> posts = [
                SELECT Id, Posted_By__c, Contact__c
                FROM Needs_Offers__c
                WHERE Id = :needOfferId
                LIMIT 1
            ];
            return posts.isEmpty() ? null : posts[0];
        }

        public List<Response__c> queryAllResponses(String needOfferId) {
            return [
                SELECT Id, Name, Responding_Contact_Text__c, Status__c, CreatedDate,
                       Amount_Requested__c, Last_Reply__c, Last_Reply_Date__c,
                       Poster_Unread_Count__c, OwnerId,
                       On_Behalf_Of_Contact__c,
                       On_Behalf_Of_Contact__r.Image_URL__c,
                       Poster_Thanked__c, Responder_Thanked__c
                FROM Response__c
                WHERE Need_Offer_Responded_To__c = :needOfferId
                AND (Moderation_Status__c = null OR Moderation_Status__c = 'Visible')
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
        }

        public List<Response__c> queryResponsesForViewer(
            String needOfferId,
            Id realContactId,
            Id actingAsContactId
        ) {
            return [
                SELECT Id, Name, Responding_Contact_Text__c, Status__c, CreatedDate,
                       Amount_Requested__c, Last_Reply__c, Last_Reply_Date__c,
                       Poster_Unread_Count__c, OwnerId,
                       On_Behalf_Of_Contact__c,
                       On_Behalf_Of_Contact__r.Image_URL__c,
                       Poster_Thanked__c, Responder_Thanked__c
                FROM Response__c
                WHERE Need_Offer_Responded_To__c = :needOfferId
                AND (Moderation_Status__c = null OR Moderation_Status__c = 'Visible')
                AND (Contact__c = :realContactId
                     OR On_Behalf_Of_Contact__c = :actingAsContactId
                     OR OwnerId = :UserInfo.getUserId())
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
        }

        /**
         * @description Pending responses on a post — used when poster deletes and must notify responders.
         * @param needOfferId The Needs_Offers__c record ID
         * @return Active Response__c rows for notification fan-out
         */
        public List<Response__c> queryPendingResponses(String needOfferId) {
            return [
                SELECT Id, Contact__c, On_Behalf_Of_Contact__c
                FROM Response__c
                WHERE Need_Offer_Responded_To__c = :needOfferId
                  AND Status__c IN (:FimbyConstants.RESPONSE_NEW, :FimbyConstants.RESPONSE_ACCEPTED)
            ];
        }
    }

    /**
     * @description Helper class for without sharing DML operations on Needs_Offers__c.
     */
    private without sharing class NeedsOffersHelper {
        /**
         * @description Inserts a Needs_Offers__c record without sharing.
         * @param post The Needs_Offers__c record to insert
         */
        public void insertPost(Needs_Offers__c post) {
            insert post;
        }

        /**
         * @description Updates a Needs_Offers__c record without sharing.
         * @param post The Needs_Offers__c record to update
         */
        public void updatePost(Needs_Offers__c post) {
            update post;
        }

        /**
         * @description Deletes a Needs_Offers__c record without sharing.
         * @param post The Needs_Offers__c record to delete
         */
        public void deletePost(Needs_Offers__c post) {
            delete post;
        }

        /**
         * @description Visibility-scoped Needs_Offers__c read for detail pages.
         */
        public Needs_Offers__c queryVisiblePost(
            Id recordId,
            String neighbourhoodAccountId,
            Set<Id> adjacentIds,
            Set<Id> sharedContactIds
        ) {
            String query = 'SELECT Id, Group_Conversation__c FROM Needs_Offers__c WHERE Id = :recordId '
                + 'AND (Moderation_Status__c = null OR Moderation_Status__c = \'Visible\')';

            if (String.isNotBlank(neighbourhoodAccountId)) {
                query += ' AND (Neighbourhood__c = :neighbourhoodAccountId'
                    + ' OR (Neighbourhood__c IN :adjacentIds AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))'
                    + ' OR (Neighbourhood__c IN :adjacentIds AND Posted_By__c IN :sharedContactIds))';
            }

            query += ' LIMIT 1';

            List<Needs_Offers__c> rows = Database.query(query);
            return rows.isEmpty() ? null : rows[0];
        }

        /**
         * @description Group chat lookup — community FLS may hide Group_Conversation__c from uiRecordApi.
         */
        public Id queryGroupConversationId(Id recordId) {
            List<Needs_Offers__c> rows = [
                SELECT Group_Conversation__c
                FROM Needs_Offers__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0].Group_Conversation__c;
        }
    }
}