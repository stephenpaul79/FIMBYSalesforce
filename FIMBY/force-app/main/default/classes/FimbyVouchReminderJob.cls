/**
 * @description Scheduled Apex job that nudges pending vouches.
 * Schedule daily:
 *
 *   System.schedule('FIMBY Vouch Reminders', '0 0 9 * * ?', new FimbyVouchReminderJob());
 *
 * Behaviour:
 *   - Each pending Vouch_Record__c older than 3 days gets one reminder
 *     notification to the reference (the person being asked to vouch).
 *     The job stamps Last_Reminder_Sent_Date__c so we only nudge every 3
 *     days, not daily.
 *   - When a pending vouch is older than the configured
 *     Vouch_Pending_Moderator_Alert_Days (default 7), a Moderator_Task__c
 *     is opened so a moderator can reach out and either help close the
 *     loop or expire the request.
 *
 * Voice: gentle, dignity-first per the FIMBY voice guide. "Just a nudge."
 */
global without sharing class FimbyVouchReminderJob implements Schedulable {

    private static final Integer REMINDER_GRACE_DAYS = 3;

    @TestVisible
    private static Integer testMaxRows;

    global void execute(SchedulableContext ctx) {
        Integer maxRows = testMaxRows != null ? testMaxRows : 200;
        Integer moderatorThresholdDays = FimbySettings.vouchPendingModeratorAlertDays();

        Datetime reminderCutoff = Datetime.now().addDays(-REMINDER_GRACE_DAYS);
        Datetime moderatorCutoff = Datetime.now().addDays(-moderatorThresholdDays);

        List<Vouch_Record__c> pending = [
            SELECT Id, Requester_Contact__c, Reference_Contact__c, Conversation__c,
                   Neighbourhood__c, CreatedDate, Last_Reminder_Sent_Date__c,
                   Moderator_Alert_Opened__c,
                   Requester_Contact__r.FirstName, Requester_Contact__r.LastName,
                   Reference_Contact__r.FirstName, Reference_Contact__r.LastName
            FROM Vouch_Record__c
            WHERE Status__c = 'Pending'
              AND CreatedDate < :reminderCutoff
            ORDER BY CreatedDate ASC
            LIMIT :maxRows
        ];

        if (pending.isEmpty()) return;

        List<Vouch_Record__c> toUpdate = new List<Vouch_Record__c>();
        List<Moderator_Task__c> tasksToCreate = new List<Moderator_Task__c>();

        for (Vouch_Record__c vr : pending) {
            Boolean dueForReminder = (vr.Last_Reminder_Sent_Date__c == null)
                || (vr.Last_Reminder_Sent_Date__c < Datetime.now().addDays(-REMINDER_GRACE_DAYS));

            if (dueForReminder && vr.Reference_Contact__c != null) {
                String requesterName = displayName(
                    vr.Requester_Contact__r?.FirstName,
                    vr.Requester_Contact__r?.LastName
                );
                String url = vr.Conversation__c != null
                    ? FimbySettings.getUrl('Conversation', String.valueOf(vr.Conversation__c))
                    : FimbySettings.getUrl('Notifications');

                FimbyNotificationService.createNotification(
                    vr.Reference_Contact__c,
                    FimbyConstants.NOTIF_VOUCH_REQUEST_REMINDER,
                    'Just a nudge: ' + requesterName + ' is still waiting',
                    'Whenever you have a moment, your reply opens up the library so they can borrow.',
                    vr.Id,
                    'Vouch_Record__c',
                    url,
                    requesterName
                );
                vr.Last_Reminder_Sent_Date__c = Datetime.now();
                toUpdate.add(vr);
            }

            Boolean shouldOpenModeratorTask = (vr.Moderator_Alert_Opened__c != true)
                && vr.CreatedDate < moderatorCutoff;
            if (shouldOpenModeratorTask) {
                String requesterName = displayName(
                    vr.Requester_Contact__r?.FirstName,
                    vr.Requester_Contact__r?.LastName
                );
                String referenceName = displayName(
                    vr.Reference_Contact__r?.FirstName,
                    vr.Reference_Contact__r?.LastName
                );
                tasksToCreate.add(new Moderator_Task__c(
                    Category__c = 'Vouch_Pending',
                    Summary__c = requesterName + ' has been waiting for ' + referenceName
                        + ' to vouch for ' + moderatorThresholdDays + ' days.',
                    Related_Record_Id__c = vr.Id,
                    Neighbourhood__c = vr.Neighbourhood__c
                ));
                vr.Moderator_Alert_Opened__c = true;
                if (!toUpdate.contains(vr)) {
                    toUpdate.add(vr);
                }
            }
        }

        if (!tasksToCreate.isEmpty()) {
            try {
                insert tasksToCreate;
            } catch (Exception e) {
                FimbyLogger.error('FimbyVouchReminderJob', 'createModeratorTasks', e);
            }
        }
        if (!toUpdate.isEmpty()) {
            try {
                update toUpdate;
            } catch (Exception e) {
                FimbyLogger.error('FimbyVouchReminderJob', 'updateVouchRecords', e);
            }
        }
    }

    private static String displayName(String firstName, String lastName) {
        if (String.isBlank(firstName) && String.isBlank(lastName)) return 'A neighbour';
        if (String.isBlank(lastName)) return firstName;
        if (String.isBlank(firstName)) return lastName;
        return firstName + ' ' + lastName;
    }
}
