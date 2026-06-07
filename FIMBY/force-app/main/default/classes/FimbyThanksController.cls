/**
 * @description Handles sending thank you messages to responders. When someone responds to a Need/Offer,
 * the poster can send a private thank you message to the responder.
 */
public with sharing class FimbyThanksController {

    /**
     * Send a thank you message to a responder
     * @param thanksData JSON string containing: recipientId (Contact), message, relatedRecordId (Response)
     * @return Map with success status and message
     */
    @AuraEnabled
    public static Map<String, Object> sendThanks(String thanksData) {
        try {
            return new ThanksHelper().sendThanksInternal(thanksData);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error sending thanks: ' + e.getMessage());
            ex.setMessage('Error sending thanks: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * @description Helper class for thank-you operations without sharing.
     */
    private without sharing class ThanksHelper {
        /**
         * @description Parses thanks JSON, posts Chatter message to recipient, and optionally sends email.
         * @param thanksDataJson JSON with recipientId (Contact), message, and optional relatedRecordId (Response)
         * @return Map with success and message
         */
        public Map<String, Object> sendThanksInternal(String thanksDataJson) {
            Map<String, Object> thanksData = (Map<String, Object>) JSON.deserializeUntyped(thanksDataJson);

            String recipientId = (String) thanksData.get('recipientId');
            String message = (String) thanksData.get('message');
            String relatedRecordId = (String) thanksData.get('relatedRecordId');

            Contact senderContact = FimbyIdentityRepository.getCurrentContact();
            String senderName = senderContact != null ? senderContact.Name : UserInfo.getName();

            Contact recipient = [SELECT Id, Name, Email FROM Contact WHERE Id = :recipientId LIMIT 1];

            String postTitle = '';
            Response__c response = null;
            if (String.isNotBlank(relatedRecordId)) {
                try {
                    response = [
                        SELECT Id, Name, Contact__c, On_Behalf_Of_Contact__c,
                               Need_Offer_Responded_To__c,
                               Need_Offer_Responded_To__r.Name,
                               Need_Offer_Responded_To__r.Contact__c,
                               Poster_Thanked__c, Responder_Thanked__c
                        FROM Response__c
                        WHERE Id = :relatedRecordId
                        LIMIT 1
                    ];
                    if (response.Need_Offer_Responded_To__r != null) {
                        postTitle = response.Need_Offer_Responded_To__r.Name;
                    }
                } catch (Exception e) {
                    FimbyLogger.warn('FimbyThanksController', 'sendThankYou', 'Response lookup failed: ' + e.getMessage());
                }
            }

            sendThankYouEmail(recipient, senderName, message, postTitle, relatedRecordId);

            String direction = '';
            if (response != null) {
                Id responderId = response.On_Behalf_Of_Contact__c != null
                    ? response.On_Behalf_Of_Contact__c
                    : response.Contact__c;
                Boolean isPosterThanking = (recipientId == responderId);
                if (isPosterThanking) {
                    response.Poster_Thanked__c = true;
                    direction = 'posterToResponder';
                } else {
                    response.Responder_Thanked__c = true;
                    direction = 'responderToPoster';
                }
                update response;

                Response_Message__c thankMsg = new Response_Message__c(
                    Response__c = relatedRecordId,
                    Body__c = message,
                    Sender__c = senderContact != null ? senderContact.Id : null,
                    Sent_Date__c = Datetime.now(),
                    Is_System_Message__c = true,
                    System_Message_Type__c = 'Thanks_Sent'
                );
                insert thankMsg;

                createThanksNotification(recipientId, senderName, message, relatedRecordId);
            }

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Thank you message sent successfully!',
                'direction' => direction
            };
        }

        private void createThanksNotification(Id recipientId, String senderName, String message, String relatedRecordId) {
            try {
                String actionUrl = String.isNotBlank(relatedRecordId)
                    ? FimbySettings.getUrl('Response_Reply', null, '?recordId=' + relatedRecordId)
                    : FimbySettings.getUrl('Notifications');
                FimbyNotificationService.createNotification(
                    recipientId,
                    FimbyConstants.NOTIF_THANKS_RECEIVED,
                    senderName + ' thanked you',
                    message,
                    relatedRecordId != null ? (Id) relatedRecordId : null,
                    'Response__c',
                    actionUrl,
                    senderName
                );
            } catch (Exception e) {
                FimbyLogger.warn('FimbyThanksController', 'createThanksNotification', e.getMessage());
            }
        }

        private void sendThankYouEmail(Contact recipient, String senderName, String message, String postTitle, String relatedRecordId) {
            try {
                List<User> users = [
                    SELECT Id FROM User
                    WHERE ContactId = :recipient.Id AND IsActive = true
                    LIMIT 1
                ];
                if (users.isEmpty()) return;

                Id recipientUserId = users[0].Id;
                String ctaUrl = String.isNotBlank(relatedRecordId)
                    ? FimbySettings.getUrl('Response_Reply', null, '?recordId=' + relatedRecordId)
                    : null;
                String cardHtml = FimbyEmailHtmlBuilder.buildThankYouCard(
                    FimbyTransactionalEmailService.lookupRecipientFirstName(recipientUserId),
                    senderName, message, postTitle,
                    ctaUrl, 'View Conversation', 'reply.png'
                );

                FimbyTransactionalEmailService.TransactionalEmailRequest req =
                    new FimbyTransactionalEmailService.TransactionalEmailRequest();
                req.recipientUserId = recipientUserId;
                req.subject = 'Thank you from ' + senderName;
                req.cardHtml = cardHtml;
                req.skipSubjectBlock = true;

                FimbyTransactionalEmailService.send(req);
            } catch (Exception e) {
                FimbyLogger.warn('FimbyThanksController', 'sendThankYouEmail', 'Failed to send thank you email: ' + e.getMessage());
            }
        }
    }
}