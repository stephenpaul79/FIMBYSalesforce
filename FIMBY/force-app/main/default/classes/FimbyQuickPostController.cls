/**
 * @deprecated Dead code — no LWC imports this class. The fimbyQuickPost component is a
 * navigation launcher only (routes to /s/ask-or-offer-post, /s/story-composer, /s/add-library-item).
 * Record creation is handled by FimbyAskOfferController, FimbyStoriesController, and FimbyLibraryController.
 * Retained temporarily to avoid test class deployment issues. Safe to delete when convenient.
 */
public with sharing class FimbyQuickPostController {

    /**
     * @description LWC-callable method that creates a new Needs_Offers__c (Need or Offer) from minimal form data.
     * @param itemData JSON string with name, description, type, category, location, imageUrl, needOrOffer, and optional event date/time
     * @return Map with success, Id, and message
     */
    @AuraEnabled
    public static Map<String, Object> createNeedsOffer(String itemData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(itemData);

            Needs_Offers__c newItem = new Needs_Offers__c();
            newItem.Name = (String) data.get('name');
            newItem.Details__c = (String) data.get('description');
            newItem.Type__c = (String) data.get('type');
            newItem.Category__c = (String) data.get('category');
            newItem.Location__c = (String) data.get('location');
            newItem.Image_1_URL__c = (String) data.get('imageUrl');

            // Set the Record Type based on needOrOffer parameter
            String needOrOffer = (String) data.get('needOrOffer');
            Schema.SObjectType targetType = Schema.getGlobalDescribe().get('Needs_Offers__c');
            Schema.DescribeSObjectResult objResult = targetType.getDescribe();
            Map<String,Schema.RecordTypeInfo> rtMapByName = objResult.getRecordTypeInfosByName();

            if (needOrOffer != null && needOrOffer.equalsIgnoreCase('need')) {
                newItem.RecordTypeId = rtMapByName.get(FimbyConstants.RT_NEED).getRecordTypeId();
            } else if (needOrOffer != null && needOrOffer.equalsIgnoreCase('offer')) {
                newItem.RecordTypeId = rtMapByName.get(FimbyConstants.RT_OFFER).getRecordTypeId();
            } else {
                // Default to Need if not specified
                newItem.RecordTypeId = rtMapByName.get(FimbyConstants.RT_NEED).getRecordTypeId();
            }

            FimbyIdentityRepository.Identity identity;
            try {
                identity = FimbyIdentityRepository.getIdentity();
            } catch (Exception identityException) {
                FimbyLogger.error('FimbyQuickPostController', 'createNeedsOffer', identityException);
                throw new AuraHandledException('Unable to resolve identity. Please try again.');
            }

            if (identity.currentUser.ContactId != null) {
                newItem.Contact__c = identity.actingAsContactId;
                newItem.Posted_By__c = identity.currentUser.ContactId;
                if (identity.neighbourhoodId != null) {
                    newItem.Neighbourhood__c = identity.neighbourhoodId;
                }
            } else {
                throw new AuraHandledException('User must have an associated Contact to create posts.');
            }

            // Set Giver_Recipient_Type__c to "Self" (default) to satisfy validation rule
            // "Recipient_Details_Required"
            newItem.Giver_Recipient_Type__c = FimbyConstants.VIS_SELF;

            // Set Status__c explicitly (has default but being explicit)
            newItem.Status__c = FimbyConstants.NEEDS_OFFERS_POSTED;

            // Handle event-specific fields
            if (data.containsKey('eventDate')) {
                String eventDateStr = (String) data.get('eventDate');
                if (String.isNotBlank(eventDateStr)) {
                    newItem.Start_Date__c = Date.valueOf(eventDateStr);
                }
            }

            if (data.containsKey('eventTime')) {
                String timeStr = (String) data.get('eventTime');
                if (String.isNotBlank(timeStr)) {
                    // Convert time string (HH:mm) to Time
                    List<String> timeParts = timeStr.split(':');
                    if (timeParts.size() == 2) {
                        Integer hours = Integer.valueOf(timeParts[0]);
                        Integer minutes = Integer.valueOf(timeParts[1]);
                        newItem.Start_Time__c = Time.newInstance(hours, minutes, 0, 0);
                    }
                }
            }

            insert newItem;

            String rtName = (needOrOffer != null && needOrOffer.equalsIgnoreCase('offer'))
                ? FimbyConstants.RT_OFFER : FimbyConstants.RT_NEED;
            FimbyCounterService.onPostCreated(
                identity.currentUser.ContactId, rtName,
                identity.actingAsContactId != identity.currentUser.ContactId
            );

            return new Map<String, Object>{
                'success' => true,
                'Id' => newItem.Id,
                'message' => 'Item created successfully'
            };

        } catch (DmlException dmlEx) {
            FimbyLogger.error('FimbyQuickPostController', 'createNeedsOffer', dmlEx);
            throw new AuraHandledException('Database error: ' + dmlEx.getDmlMessage(0));
        } catch (Exception e) {
            FimbyLogger.error('FimbyQuickPostController', 'createNeedsOffer', e);
            throw new AuraHandledException('Error creating marketplace item: ' + e.getMessage());
        }
    }
}