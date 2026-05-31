/**
 * @description Scheduled job (hourly) that expires Bulk Buy posts past their expiry date.
 * Sets Status to Expired, locks group chats, sends notifications. Does NOT cancel reservations.
 */
public without sharing class FimbyBulkBuyExpiryJob implements Schedulable {

    public void execute(SchedulableContext sc) {
        Id bulkBuyRtId = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get(FimbyConstants.RT_BULK_BUY)?.getRecordTypeId();

        List<Needs_Offers__c> expired = [
            SELECT Id, Name, Group_Conversation__c
            FROM Needs_Offers__c
            WHERE RecordTypeId = :bulkBuyRtId
            AND Availability_Rule__c = 'Expires_At_Date'
            AND Expiry_DateTime__c <= :System.now()
            AND Status__c = :FimbyConstants.NEEDS_OFFERS_AVAILABLE
            LIMIT 200
        ];

        for (Needs_Offers__c post : expired) {
            post.Status__c = FimbyConstants.NEEDS_OFFERS_EXPIRED;
        }

        if (!expired.isEmpty()) {
            update expired;
            for (Needs_Offers__c post : expired) {
                if (post.Group_Conversation__c != null) {
                    FimbyGroupConversationController.sendSystemMessage(
                        post.Group_Conversation__c,
                        'This bulk buy has expired.',
                        FimbyConstants.SYS_MSG_STATUS_CHANGE,
                        true
                    );
                    FimbyGroupConversationController.lockConversation(post.Group_Conversation__c);
                }
            }
        }
    }
}
