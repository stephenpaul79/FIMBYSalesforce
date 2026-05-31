/**
 * @description Invocable action for creating system messages when Response status changes to Expired
 * or Cancelled via flows or scheduled processes. Used by Response Status Change System Message flow.
 */
public without sharing class FimbyResponseStatusChangeAction {

    /**
     * @description Input for the Invocable method. Contains Response ID and new status.
     */
    public class StatusChangeInput {
        @InvocableVariable(required=true label='Response ID')
        public Id responseId;

        @InvocableVariable(required=true label='New Status')
        public String newStatus;
    }

    /**
     * @description InvocableMethod that creates system messages on response threads when status changes
     * to Expired or Cancelled. Called from flows or scheduled processes. Creates Response_Message__c
     * records and increments responder unread count.
     * @param inputs List of StatusChangeInput with responseId and newStatus
     */
    @InvocableMethod(label='Create Response Status System Message'
                     description='Creates a system message on the response thread when status changes to Expired/Cancelled')
    public static void createStatusSystemMessages(List<StatusChangeInput> inputs) {
        try {
        List<Response_Message__c> messagesToInsert = new List<Response_Message__c>();

        Set<Id> responseIds = new Set<Id>();
        for (StatusChangeInput input : inputs) {
            responseIds.add(input.responseId);
        }

        Map<Id, Response__c> responseMap = new Map<Id, Response__c>([
            SELECT Id, Contact__c, On_Behalf_Of_Contact__c,
                   Responder_Unread_Count__c, Poster_Unread_Count__c,
                   Need_Offer_Responded_To__r.Posted_By__c
            FROM Response__c
            WHERE Id IN :responseIds
        ]);

        List<Response__c> responsesToUpdate = new List<Response__c>();

        for (StatusChangeInput input : inputs) {
            Response__c resp = responseMap.get(input.responseId);
            if (resp == null) continue;

            String body;
            String msgType;
            if (input.newStatus == FimbyConstants.RESPONSE_EXPIRED) {
                body = 'This post has expired';
                msgType = 'Post_Expired';
            } else if (input.newStatus == FimbyConstants.RESPONSE_CANCELLED) {
                body = 'This post was removed by the author';
                msgType = 'Post_Cancelled';
            } else {
                body = 'Status changed to ' + input.newStatus;
                msgType = 'Status_Change';
            }

            messagesToInsert.add(new Response_Message__c(
                Response__c = input.responseId,
                Body__c = body,
                Sent_Date__c = Datetime.now(),
                Is_System_Message__c = true,
                System_Message_Type__c = msgType
            ));

            Response__c upd = new Response__c(Id = input.responseId);
            upd.Responder_Unread_Count__c = (resp.Responder_Unread_Count__c != null ? resp.Responder_Unread_Count__c : 0) + 1;
            responsesToUpdate.add(upd);
        }

        if (!messagesToInsert.isEmpty()) {
            Database.insert(messagesToInsert, true);
        }
        if (!responsesToUpdate.isEmpty()) {
            Database.update(responsesToUpdate, true);
        }
        } catch (Exception e) {
            FimbyLogger.error('FimbyResponseStatusChangeAction', 'createStatusSystemMessages', e);
        }
    }
}
