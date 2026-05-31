/**
 * @description Scheduled Apex job that sends overdue-loan reminders.
 * Replaces the legacy Owner_Return_Reminder_Email + Item_Due_Reminder_Emails
 * flows. Schedule daily:
 *
 *   System.schedule('FIMBY Overdue Reminders', '0 0 8 * * ?', new FimbyOverdueReminderJob());
 *
 * Reminder cadence:
 *   - Borrower is nudged on every cadence tick (the Overdue_Reminder__c
 *     formula is true every 3 days after the due date).
 *   - Owner is nudged starting at day 7 overdue and every 7 days after, so
 *     the borrower has space to handle it without two-sided pressure on
 *     the first week.
 *
 * Tone is recovery-first per the FIMBY voice guide: "your loan is past due,
 * have you had a chance to return it?" — not punitive.
 */
global without sharing class FimbyOverdueReminderJob implements Schedulable {

    @TestVisible
    private static Integer testMaxRows;

    global void execute(SchedulableContext ctx) {
        Integer maxRows = testMaxRows != null ? testMaxRows : 500;

        List<Loaned_Item__c> overdueLoans = [
            SELECT Id, Library_Item__c, Library_Item__r.Name,
                   Loaned_To__c, Owned_By__c, Days_Overdue__c,
                   Item_Owner_s_First_Name__c, Requester_s_First_Name__c
            FROM Loaned_Item__c
            WHERE Overdue_Reminder__c = TRUE
              AND Returned_Date__c = NULL
              AND Loaned_To__c != NULL
            LIMIT :maxRows
        ];

        if (overdueLoans.isEmpty()) return;

        for (Loaned_Item__c loan : overdueLoans) {
            String itemName = loan.Library_Item__r?.Name != null
                ? loan.Library_Item__r.Name : 'a library item';
            String ownerFirst = String.isNotBlank(loan.Item_Owner_s_First_Name__c)
                ? loan.Item_Owner_s_First_Name__c : 'the owner';
            String borrowerFirst = String.isNotBlank(loan.Requester_s_First_Name__c)
                ? loan.Requester_s_First_Name__c : 'the borrower';
            Integer daysOverdue = loan.Days_Overdue__c != null ? (Integer) loan.Days_Overdue__c : 0;
            String itemUrl = FimbySettings.getUrl('Library_Item', String.valueOf(loan.Library_Item__c));

            // Borrower nudge — every cadence tick.
            FimbyNotificationService.createNotification(
                loan.Loaned_To__c,
                FimbyConstants.NOTIF_OVERDUE_REMINDER,
                itemName + ' is overdue',
                'Have you had a chance to return it to ' + ownerFirst + '? It\'s ' + daysOverdue + ' day(s) past due.',
                loan.Id,
                'Loaned_Item__c',
                itemUrl,
                'FIMBY'
            );

            // Owner nudge — only after the borrower has had a week, and then weekly.
            if (loan.Owned_By__c != null && daysOverdue >= 7 && Math.mod(daysOverdue, 7) == 0) {
                FimbyNotificationService.createNotification(
                    loan.Owned_By__c,
                    FimbyConstants.NOTIF_OVERDUE_REMINDER,
                    itemName + ' is ' + daysOverdue + ' days overdue',
                    'We\'ve also nudged ' + borrowerFirst + '. Let us know if you need help following up.',
                    loan.Id,
                    'Loaned_Item__c',
                    itemUrl,
                    'FIMBY'
                );
            }
        }
    }
}
