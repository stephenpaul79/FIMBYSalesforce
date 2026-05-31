/**
 * @description Auto-shares poster contact info with responder when a response is accepted
 * and the parent post has Auto_Share_Contact_Info__c enabled.
 */
public without sharing class FimbyResponseAutoShareHelper {

    /**
     * @description Creates Shared_Contact_Info__c when auto-share is enabled on the parent post.
     * Safe to call from any accept path (thread, status modal, auto-accept on create).
     * @param responseId The accepted Response__c record ID
     */
    public static void tryAutoShareOnAccept(Id responseId) {
        if (responseId == null) {
            return;
        }
        try {
            List<Response__c> responses = [
                SELECT Id, Contact__c, On_Behalf_Of_Contact__c, Need_Offer_Responded_To__c
                FROM Response__c
                WHERE Id = :responseId
                LIMIT 1
            ];
            if (responses.isEmpty()) {
                return;
            }
            Response__c resp = responses[0];

            Needs_Offers__c post = [
                SELECT Auto_Share_Contact_Info__c, Contact__c, Posted_By__c
                FROM Needs_Offers__c
                WHERE Id = :resp.Need_Offer_Responded_To__c
                LIMIT 1
            ];
            if (post.Auto_Share_Contact_Info__c != true) {
                return;
            }

            Id sharingContactId = post.Contact__c != null ? post.Contact__c : post.Posted_By__c;
            if (sharingContactId == null) {
                return;
            }

            Id responderContactId = resp.On_Behalf_Of_Contact__c != null
                ? resp.On_Behalf_Of_Contact__c
                : resp.Contact__c;
            if (responderContactId == null || responderContactId == sharingContactId) {
                return;
            }

            List<Shared_Contact_Info__c> existing = [
                SELECT Id
                FROM Shared_Contact_Info__c
                WHERE Contact__c = :sharingContactId
                  AND Shared_To__c = :responderContactId
                  AND Response__c = :resp.Id
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                return;
            }

            Contact poster = [
                SELECT Email, Phone, MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
                FROM Contact
                WHERE Id = :sharingContactId
                LIMIT 1
            ];

            Boolean shareEmail = String.isNotBlank(poster.Email);
            Boolean sharePhone = String.isNotBlank(poster.Phone);
            Boolean shareAddress = String.isNotBlank(poster.MailingStreet);
            if (!shareEmail && !sharePhone && !shareAddress) {
                return;
            }

            Map<String, Object> shareMap = new Map<String, Object>{
                'responseId' => resp.Id,
                'sharingContactId' => sharingContactId,
                'recipientContactId' => responderContactId,
                'shareEmail' => shareEmail,
                'sharePhone' => sharePhone,
                'shareAddress' => shareAddress,
                'email' => poster.Email != null ? poster.Email : '',
                'phone' => poster.Phone != null ? poster.Phone : '',
                'street' => poster.MailingStreet != null ? poster.MailingStreet : '',
                'city' => poster.MailingCity != null ? poster.MailingCity : '',
                'state' => poster.MailingState != null ? poster.MailingState : '',
                'postalCode' => poster.MailingPostalCode != null ? poster.MailingPostalCode : '',
                'country' => poster.MailingCountry != null ? poster.MailingCountry : ''
            };
            Map<String, Object> result = FimbyResponseController.shareContactInfo(JSON.serialize(shareMap));
            if (result == null || result.get('success') != true) {
                FimbyLogger.warn(
                    'FimbyResponseAutoShareHelper',
                    'tryAutoShareOnAccept',
                    'Auto-share returned unsuccessful for response ' + responseId
                );
            }
        } catch (Exception e) {
            FimbyLogger.error('FimbyResponseAutoShareHelper', 'tryAutoShareOnAccept', e);
        }
    }
}
