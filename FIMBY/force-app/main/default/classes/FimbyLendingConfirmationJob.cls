/**
 * @description Scheduled Apex job that auto-expires stale Requesting Confirmation
 * lending requests and promotes the next waitlisted person.
 * Schedule: System.schedule('FIMBY Lending Confirmation Expiry', '0 0 7 * * ?', new FimbyLendingConfirmationJob());
 */
global without sharing class FimbyLendingConfirmationJob implements Schedulable {

    @TestVisible
    private static Datetime testCutoffOverride;

    global void execute(SchedulableContext ctx) {
        Integer expiryDays = FimbySettings.lendingConfirmationExpiryDays();
        Datetime cutoff = testCutoffOverride != null ? testCutoffOverride : Datetime.now().addDays(-expiryDays);

        List<Lending_Request__c> staleRequests = [
            SELECT Id, Status__c, Requested_By__c,
                   Library_Item__c, Library_Item__r.Name
            FROM Lending_Request__c
            WHERE Status__c = :FimbyConstants.LENDING_REQUESTING_CONFIRMATION
            AND LastModifiedDate < :cutoff
            LIMIT 200
        ];

        if (staleRequests.isEmpty()) return;

        // Expire all stale requests
        for (Lending_Request__c req : staleRequests) {
            req.Status__c = FimbyConstants.LENDING_CANCELLED;
        }
        update staleRequests;

        // Notify borrowers and promote next waitlisted per item
        Set<Id> processedItems = new Set<Id>();
        for (Lending_Request__c req : staleRequests) {
            String itemName = req.Library_Item__r?.Name != null
                ? req.Library_Item__r.Name : 'a library item';

            if (req.Requested_By__c != null) {
                FimbyNotificationService.createNotification(
                    req.Requested_By__c,
                    FimbyConstants.NOTIF_LENDING_REQUEST,
                    'Your confirmation window has expired',
                    'You did not confirm in time for ' + itemName + '.',
                    req.Id, 'Lending_Request__c',
                    FimbySettings.getUrl('Library_Item', String.valueOf(req.Library_Item__c)),
                    'FIMBY'
                );
            }

            // Promote next waitlisted (once per item)
            if (!processedItems.contains(req.Library_Item__c)) {
                processedItems.add(req.Library_Item__c);
                promoteNextWaitlisted(req.Library_Item__c);
            }
        }
    }

    private void promoteNextWaitlisted(Id libraryItemId) {
        List<Lending_Request__c> nextUp = [
            SELECT Id, Status__c, Requested_By__c, Library_Item__r.Name
            FROM Lending_Request__c
            WHERE Library_Item__c = :libraryItemId
            AND Status__c = :FimbyConstants.LENDING_WAITLISTED
            AND Waitlist_Position__c = 1
            LIMIT 1
        ];

        if (nextUp.isEmpty()) return;

        nextUp[0].Status__c = FimbyConstants.LENDING_REQUESTING_CONFIRMATION;
        update nextUp[0];

        if (nextUp[0].Requested_By__c != null) {
            String itemName = nextUp[0].Library_Item__r?.Name != null
                ? nextUp[0].Library_Item__r.Name : 'a library item';
            FimbyNotificationService.createNotification(
                nextUp[0].Requested_By__c,
                FimbyConstants.NOTIF_LENDING_REQUEST,
                itemName + ' is available, confirm to borrow',
                'Confirm your interest within ' + FimbySettings.lendingConfirmationExpiryDays() + ' days.',
                nextUp[0].Id, 'Lending_Request__c',
                FimbySettings.getUrl('Library_Item', String.valueOf(libraryItemId)),
                'FIMBY'
            );
        }
    }
}
