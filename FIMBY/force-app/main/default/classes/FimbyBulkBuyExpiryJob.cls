/**
 * @description Scheduled job that closes the reservation window on dated Bulk Buys whose
 * Expiry_DateTime__c has passed. Cadence is set by the live CronTrigger, not by this class.
 *
 * - With one or more Reserved responses: stamps Reservations_Closed_Date__c, keeps the post
 *   Available and its group chat unlocked, posts nothing to chat, and notifies only the
 *   represented organiser.
 * - With no Reserved responses: sets Expired / Closed_By Auto, notifies nobody, and quietly
 *   locks any leftover group chat.
 *
 * Idempotent: candidates require Reservations_Closed_Date__c = NULL, so a closed post is never
 * selected or notified twice. Candidate rows are locked FOR UPDATE, matching the lock taken when
 * a reservation is created, so a new reservation cannot race a zero-reservation expiry.
 */
public without sharing class FimbyBulkBuyExpiryJob implements Schedulable {

    private static final Integer BATCH_LIMIT = 200;
    private static final String NOTIF_TITLE = 'Reservations closed';

    public void execute(SchedulableContext sc) {
        run();
    }

    /**
     * @description Processes up to BATCH_LIMIT expired-window candidates. Public for tests and
     * manual runs from anonymous Apex.
     */
    public static void run() {
        Id bulkBuyRtId = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName().get(FimbyConstants.RT_BULK_BUY)?.getRecordTypeId();
        Datetime now = System.now();

        Set<Id> candidateIds = new Map<Id, Needs_Offers__c>([
            SELECT Id
            FROM Needs_Offers__c
            WHERE RecordTypeId = :bulkBuyRtId
            AND Availability_Rule__c = 'Expires_At_Date'
            AND Expiry_DateTime__c <= :now
            AND Status__c = :FimbyConstants.NEEDS_OFFERS_AVAILABLE
            AND Reservations_Closed_Date__c = NULL
            WITH SYSTEM_MODE
            ORDER BY Expiry_DateTime__c ASC
            LIMIT :BATCH_LIMIT
        ]).keySet();
        if (candidateIds.isEmpty()) {
            return;
        }

        List<Needs_Offers__c> locked = [
            SELECT Id, Name, Contact__c, Group_Conversation__c
            FROM Needs_Offers__c
            WHERE Id IN :candidateIds
            AND Status__c = :FimbyConstants.NEEDS_OFFERS_AVAILABLE
            AND Reservations_Closed_Date__c = NULL
            WITH SYSTEM_MODE
            FOR UPDATE
        ];
        if (locked.isEmpty()) {
            return;
        }

        Map<Id, Integer> reservationCounts = new Map<Id, Integer>();
        Map<Id, Decimal> shareSums = new Map<Id, Decimal>();
        tallyReservedResponses(new Map<Id, Needs_Offers__c>(locked).keySet(), reservationCounts, shareSums);

        List<Needs_Offers__c> toUpdate = new List<Needs_Offers__c>();
        List<FimbyNotificationService.NotificationRequest> notices =
            new List<FimbyNotificationService.NotificationRequest>();
        List<Conversation__c> chatsToLock = new List<Conversation__c>();

        for (Needs_Offers__c post : locked) {
            Integer reservers = reservationCounts.get(post.Id);
            if (reservers != null && reservers > 0) {
                toUpdate.add(new Needs_Offers__c(Id = post.Id, Reservations_Closed_Date__c = now));
                FimbyNotificationService.NotificationRequest notice =
                    buildOrganiserNotice(post, shareSums.get(post.Id), reservers);
                if (notice != null) {
                    notices.add(notice);
                }
            } else {
                toUpdate.add(new Needs_Offers__c(
                    Id = post.Id,
                    Status__c = FimbyConstants.NEEDS_OFFERS_EXPIRED,
                    Closed_By__c = FimbyConstants.CLOSED_BY_AUTO
                ));
                if (post.Group_Conversation__c != null) {
                    chatsToLock.add(new Conversation__c(Id = post.Group_Conversation__c, Locked__c = true));
                }
            }
        }

        Database.update(toUpdate, AccessLevel.SYSTEM_MODE);
        if (!chatsToLock.isEmpty()) {
            Database.update(chatsToLock, AccessLevel.SYSTEM_MODE);
        }
        FimbyNotificationService.createNotificationsFromRequests(notices);
    }

    private static void tallyReservedResponses(
        Set<Id> postIds, Map<Id, Integer> counts, Map<Id, Decimal> shares
    ) {
        for (Response__c r : [
            SELECT Need_Offer_Responded_To__c, Amount_Requested__c
            FROM Response__c
            WHERE Need_Offer_Responded_To__c IN :postIds
            AND Status__c = :FimbyConstants.RESPONSE_RESERVED
            WITH SYSTEM_MODE
        ]) {
            Id postId = r.Need_Offer_Responded_To__c;
            counts.put(postId, (counts.containsKey(postId) ? counts.get(postId) : 0) + 1);
            Decimal amount = r.Amount_Requested__c != null ? r.Amount_Requested__c : 0;
            shares.put(postId, (shares.containsKey(postId) ? shares.get(postId) : 0) + amount);
        }
    }

    @TestVisible
    private static FimbyNotificationService.NotificationRequest buildOrganiserNotice(
        Needs_Offers__c post, Decimal shareSum, Integer reserverCount
    ) {
        if (post.Contact__c == null) {
            return null;
        }
        Integer shareCount = shareSum != null ? shareSum.intValue() : 0;
        String body = shareCount + (shareCount == 1 ? ' share is' : ' shares are')
            + ' reserved by ' + reserverCount + (reserverCount == 1 ? ' neighbour' : ' neighbours')
            + '. Buy when ready, then notify everyone for pickup, or cancel.';
        return new FimbyNotificationService.NotificationRequest(
            post.Contact__c,
            FimbyConstants.NOTIF_BULK_BUY_STATUS,
            NOTIF_TITLE,
            body,
            post.Id,
            'Needs_Offers__c',
            FimbySettings.getUrl('Asks_Offers', String.valueOf(post.Id)),
            'FIMBY'
        );
    }
}
