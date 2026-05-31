/**
 * Unified context loader for the fimbyQuickResponseModal LWC.
 * Returns identity + type-specific data + existing-response checks in a single round-trip.
 */
public with sharing class FimbyQuickResponseController {

    private static final String CLASS_NAME = 'FimbyQuickResponseController';

    @AuraEnabled
    public static Map<String, Object> getQuickResponseContext(String recordId, String responseType) {
        try {
            if (String.isBlank(recordId) || String.isBlank(responseType)) {
                AuraHandledException ex = new AuraHandledException('Record ID and response type are required.');
                ex.setMessage('Record ID and response type are required.');
                throw ex;
            }

            Map<String, Object> result = new Map<String, Object>();

            Map<String, Object> identity = FimbyContactController.getActingAsContact();
            result.put('identity', identity);

            String contactId = (String) identity.get('contactId');
            String actingAsContactId = identity.get('actingAsContactId') != null
                ? (String) identity.get('actingAsContactId')
                : contactId;

            String viewState = 'form';

            if (responseType == 'story') {
                result.put('context', FimbyStoryCommentController.getStoryForComment(recordId));

            } else if (responseType == 'bulkBuy') {
                Map<String, Object> ctx = FimbyBulkBuyReservationController.getReservationContext(recordId);
                String rvState = (String) ctx.get('viewState');
                if (rvState == 'blocked') {
                    viewState = 'blocked';
                } else if (rvState == 'unavailable' || rvState == 'fullyReserved') {
                    viewState = 'unavailable';
                } else if (rvState == 'alreadyReserved') {
                    viewState = 'alreadyResponded';
                }
                result.put('context', ctx);

            } else if (responseType == 'library') {
                result.put('context', FimbyLibraryController.getLibraryItemForLending(recordId));
                Map<String, Object> existing = FimbyLibraryController.checkExistingLendingRequest(recordId, actingAsContactId);
                if (existing != null && (Boolean) existing.get('hasExistingRequest') == true) {
                    viewState = 'alreadyResponded';
                    result.put('existingRequest', existing.get('existingRequest'));
                }

            } else {
                // askOffer, gathering, openEvent
                result.put('context', getPostContext(recordId));
                if (responseType != 'openEvent') {
                    Map<String, Object> existing = FimbyResponseController.checkExistingResponse(recordId);
                    if ((Boolean) existing.get('hasExistingResponse') == true) {
                        viewState = 'alreadyResponded';
                        result.put('existingResponse', existing.get('existingResponse'));
                    }
                }
            }

            result.put('viewState', viewState);
            result.put('success', true);
            return result;

        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            FimbyLogger.error(CLASS_NAME, 'getQuickResponseContext', e);
            AuraHandledException ex = new AuraHandledException(e.getMessage());
            ex.setMessage(e.getMessage());
            throw ex;
        }
    }

    private static Map<String, Object> getPostContext(String recordId) {
        Needs_Offers__c post = [
            SELECT Id, Name, Details__c, Full_Details__c, Image_1_URL__c,
                   Total_Available__c, Total_Quantity__c, Per_Response_Limit__c,
                   Status__c, Type__c, RecordType.DeveloperName,
                   Posted_By__c, Posted_By__r.FirstName, Posted_By__r.LastName,
                   Event_Type__c, Event_Details__c, Location__c,
                   Expected_Attendance__c, Event_Link__c
            FROM Needs_Offers__c
            WHERE Id = :recordId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        String posterName = '';
        if (post.Posted_By__r != null) {
            String first = post.Posted_By__r.FirstName != null ? post.Posted_By__r.FirstName : '';
            String last = post.Posted_By__r.LastName != null ? post.Posted_By__r.LastName : '';
            posterName = (first + ' ' + last).trim();
        }

        return new Map<String, Object>{
            'id' => post.Id,
            'name' => post.Name,
            'details' => String.isNotBlank(post.Full_Details__c) ? post.Full_Details__c : post.Details__c,
            'imageUrl' => post.Image_1_URL__c,
            'type' => post.Type__c,
            'recordType' => post.RecordType?.DeveloperName,
            'totalAvailable' => post.Total_Available__c != null ? (Integer) post.Total_Available__c : 0,
            'totalQuantity' => post.Total_Quantity__c != null ? (Integer) post.Total_Quantity__c : 0,
            'perResponseLimit' => post.Per_Response_Limit__c != null ? (Integer) post.Per_Response_Limit__c : null,
            'status' => post.Status__c,
            'posterName' => posterName,
            'eventType' => post.Event_Type__c,
            'eventDetails' => post.Event_Details__c,
            'location' => post.Location__c,
            'expectedAttendance' => post.Expected_Attendance__c,
            'eventLink' => post.Event_Link__c
        };
    }
}
