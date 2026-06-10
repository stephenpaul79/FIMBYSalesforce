/**
 * @description Opt-in re-invite to prior-occurrence attendees when a new event occurrence spawns.
 */
public with sharing class FimbyRecurrenceReinviteService {

    private static final Set<String> ATTENDEE_STATUSES = new Set<String>{
        'Accepted', 'Interested', 'New', 'Completed'
    };

    public static void sendReinvites(
        Needs_Offers__c seriesParent,
        Needs_Offers__c priorOccurrence,
        Needs_Offers__c newOccurrence
    ) {
        if (seriesParent == null || priorOccurrence == null || newOccurrence == null) {
            return;
        }

        Id viewerNeighbourhood = seriesParent.Neighbourhood__c;
        Set<Id> blocked = FimbyBlockingHelper.getBidirectionalBlocks(seriesParent.Contact__c);

        List<Response__c> priorResponses = [
            SELECT Id, On_Behalf_Of_Contact__c, Contact__c
            FROM Response__c
            WHERE Need_Offer_Responded_To__c = :priorOccurrence.Id
              AND Status__c IN :ATTENDEE_STATUSES
        ];

        String eventTitle = newOccurrence.Name != null ? newOccurrence.Name : 'the event';
        String actionUrl = FimbySettings.getUrl('Needs_Offers', newOccurrence.Id);
        Set<Id> notified = new Set<Id>();

        for (Response__c resp : priorResponses) {
            Id recipientId = resp.On_Behalf_Of_Contact__c != null
                ? resp.On_Behalf_Of_Contact__c
                : resp.Contact__c;
            if (recipientId == null || notified.contains(recipientId) || blocked.contains(recipientId)) {
                continue;
            }
            notified.add(recipientId);

            FimbyNotificationService.createNotification(
                recipientId,
                FimbyConstants.NOTIF_EVENT_SERIES_NEW_OCCURRENCE,
                eventTitle + ' is back on the calendar',
                'If you would like to come along again, take a look at the updated details.',
                newOccurrence.Id,
                'Needs_Offers__c',
                actionUrl,
                'FIMBY'
            );
        }
    }
}
