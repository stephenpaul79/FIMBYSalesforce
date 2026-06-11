/**
 * @description Nudges authors of open asks/offers near expiry to refresh or close.
 * Schedule daily:
 *   System.schedule('FIMBY Refresh Reminders', '0 0 8 * * ?', new FimbyRefreshReminderJob());
 */
global without sharing class FimbyRefreshReminderJob implements Schedulable {

    private static final Set<String> OPEN_STATUSES = new Set<String>{
        FimbyConstants.NEEDS_OFFERS_POSTED,
        FimbyConstants.NEEDS_OFFERS_REPLY_RECEIVED,
        FimbyConstants.NEEDS_OFFERS_REPLY_ACCEPTED
    };

    @TestVisible
    private static Integer testMaxRows;

    global void execute(SchedulableContext ctx) {
        Integer maxRows = testMaxRows != null ? testMaxRows : 200;
        Integer maxRefreshCount = FimbySettings.refreshMaxCount();
        Integer minAgeDays = FimbySettings.refreshReminderMinAgeDays();
        Integer leadDays = FimbySettings.refreshReminderLeadDays();
        Date today = Date.today();

        List<Needs_Offers__c> candidates = [
            SELECT Id, Name, CreatedDate, End_Date__c, Refresh_Count__c,
                   Last_Refreshed_Date__c, Last_Refresh_Reminder_Date__c,
                   Contact__c, RecordType.DeveloperName
            FROM Needs_Offers__c
            WHERE RecordType.DeveloperName IN ('Need', 'Offer')
              AND Type__c != 'Event'
              AND Status__c IN :OPEN_STATUSES
              AND End_Date__c != null
              AND (Refresh_Count__c = null OR Refresh_Count__c < :maxRefreshCount)
            ORDER BY End_Date__c ASC
            LIMIT :maxRows
        ];

        if (candidates.isEmpty()) {
            return;
        }

        List<Needs_Offers__c> toUpdate = new List<Needs_Offers__c>();

        for (Needs_Offers__c post : candidates) {
            if (!isReminderDue(post, today, minAgeDays, leadDays)) {
                continue;
            }
            if (!isEligibleForReminderCycle(post)) {
                continue;
            }

            Id recipientId = post.Contact__c;
            if (recipientId == null) {
                continue;
            }

            Boolean isNeed = post.RecordType.DeveloperName == FimbyConstants.RT_NEED;
            String title = isNeed
                ? 'A quick check on your ask'
                : 'A quick check on your offer';
            String body = isNeed
                ? 'Were you able to sort this out? Tap to let neighbours know — still needed, all sorted, or no longer needed.'
                : 'Is this still available? Tap to let neighbours know — still available, all taken, or no longer available.';
            String url = FimbySettings.getUrl('Asks_Offers', post.Id);

            FimbyNotificationService.createNotification(
                recipientId,
                FimbyConstants.NOTIF_REFRESH_REMINDER,
                title,
                body,
                post.Id,
                'Needs_Offers__c',
                url,
                'FIMBY'
            );

            post.Last_Refresh_Reminder_Date__c = today;
            toUpdate.add(post);
        }

        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (Exception e) {
                FimbyLogger.error('FimbyRefreshReminderJob', 'updatePosts', e);
            }
        }
    }

    @TestVisible
    private static Boolean isReminderDue(
        Needs_Offers__c post,
        Date today,
        Integer minAgeDays,
        Integer leadDays
    ) {
        Date minAgeDate = post.CreatedDate.date().addDays(minAgeDays);
        Date leadDate = post.End_Date__c.addDays(-leadDays);
        Date reminderDate = minAgeDate > leadDate ? minAgeDate : leadDate;
        return reminderDate <= today;
    }

    @TestVisible
    private static Boolean isEligibleForReminderCycle(Needs_Offers__c post) {
        if (post.Last_Refresh_Reminder_Date__c == null) {
            return true;
        }
        if (post.Last_Refreshed_Date__c == null) {
            return false;
        }
        return post.Last_Refresh_Reminder_Date__c < post.Last_Refreshed_Date__c;
    }
}
