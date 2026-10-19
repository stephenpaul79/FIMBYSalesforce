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
                   Last_Refreshed_Date__c, Last_Refresh_Reminder_Date__c, Last_Reply_Nudge_Date__c,
                   Contact__c, Posted_By__c, RecordType.DeveloperName
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

        List<Needs_Offers__c> due = new List<Needs_Offers__c>();
        for (Needs_Offers__c post : candidates) {
            if (post.Contact__c == null
                || post.Last_Reply_Nudge_Date__c == today
                || !isReminderDue(post, today, minAgeDays, leadDays)
                || !isEligibleForReminderCycle(post)) {
                continue;
            }
            due.add(post);
        }
        if (due.isEmpty()) {
            return;
        }

        List<Needs_Offers__c> unnudged = new List<Needs_Offers__c>();
        for (Needs_Offers__c post : due) {
            if (post.Last_Reply_Nudge_Date__c == null) {
                unnudged.add(post);
            }
        }
        Set<Id> nudgeEligible = FimbyReplyNudgeJob.eligibleResponsesByPost(unnudged, Datetime.now()).keySet();
        Map<Id, FimbyPostEngagementService.Summary> summaries =
            FimbyPostEngagementService.summarize(new Map<Id, Needs_Offers__c>(due).keySet(), null);

        List<FimbyNotificationService.NotificationRequest> requests = new List<FimbyNotificationService.NotificationRequest>();
        List<Needs_Offers__c> toUpdate = new List<Needs_Offers__c>();
        for (Needs_Offers__c post : due) {
            if (nudgeEligible.contains(post.Id)) {
                continue;
            }
            Boolean isNeed = post.RecordType.DeveloperName == FimbyConstants.RT_NEED;
            requests.add(new FimbyNotificationService.NotificationRequest(
                post.Contact__c,
                FimbyConstants.NOTIF_REFRESH_REMINDER,
                isNeed ? 'A quick check on your ask' : 'A quick check on your offer',
                reminderBody(isNeed, summaries.get(post.Id)),
                post.Id,
                'Needs_Offers__c',
                FimbySettings.getUrl('Asks_Offers', post.Id),
                'FIMBY'
            ));
            toUpdate.add(new Needs_Offers__c(Id = post.Id, Last_Refresh_Reminder_Date__c = today));
        }

        FimbyNotificationService.createNotificationsFromRequests(requests);
        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (Exception e) {
                FimbyLogger.error('FimbyRefreshReminderJob', 'updatePosts', e);
            }
        }
    }

    /**
     * @description Engaged posts auto-complete at end of life, so their reminder invites the
     * poster to mark the outcome instead of implying the post is about to vanish.
     */
    @TestVisible
    private static String reminderBody(Boolean isNeed, FimbyPostEngagementService.Summary s) {
        Boolean accepted = s != null && s.hasAcceptedResponse;
        Boolean conversation = s != null && s.hasPosterConversation;
        if (isNeed) {
            if (accepted) {
                return 'You’ve found someone to help. Mark your ask Answered, or refresh it if you still need help.';
            }
            if (conversation) {
                return 'You’ve heard from a neighbour about your ask. Mark it Answered if it’s sorted, or refresh it if you still need help.';
            }
            return 'Were you able to sort this out? Tap to let neighbours know — still needed, all sorted, or no longer needed.';
        }
        if (accepted) {
            return 'A neighbour is interested in your offer. If it’s been taken up, mark it Received; otherwise, refresh it.';
        }
        if (conversation) {
            return 'You’ve heard from a neighbour about your offer. If it’s been taken up, mark it Received; otherwise, refresh it.';
        }
        return 'Is this still available? Tap to let neighbours know — still available, all taken, or no longer available.';
    }

    public static Boolean isReminderDue(
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
