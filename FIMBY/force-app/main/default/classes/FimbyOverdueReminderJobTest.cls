@IsTest
public class FimbyOverdueReminderJobTest {

    @TestSetup
    static void setupTestData() {
        FimbyTestDataFactory.createCompleteTestSetup();
    }

    private static Contact getTestContact() {
        return [
            SELECT Id, AccountId FROM Contact
            WHERE Id IN (SELECT ContactId FROM User WHERE Profile.Name = 'Customer Community User' AND IsActive = TRUE)
            LIMIT 1
        ];
    }

    /* ── execute() with no overdue loans is a clean no-op ────────────────── */

    @IsTest
    static void testExecute_NoOverdueLoans_IsNoOp() {
        Test.startTest();
        new FimbyOverdueReminderJob().execute(null);
        Test.stopTest();

        Integer notifCount = [
            SELECT COUNT() FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_OVERDUE_REMINDER
        ];
        System.assertEquals(0, notifCount, 'No overdue loans → no reminders');
    }

    /* ── Borrower gets nudged on a 3-day overdue loan ────────────────────── */

    @IsTest
    static void testExecute_BorrowerNudged_OnOverdueLoan() {
        Contact testContact = getTestContact();
        Library_Item__c item = [SELECT Id, Name, Owner_Contact__c FROM Library_Item__c LIMIT 1];

        Loaned_Item__c loan = new Loaned_Item__c(
            Name = 'Loan - ' + item.Name,
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Owned_By__c = item.Owner_Contact__c,
            Loan_Due_Date__c = Date.today().addDays(-3)
        );
        insert loan;

        Test.startTest();
        new FimbyOverdueReminderJob().execute(null);
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Id, Title__c, Body__c, Action_URL__c, Actor_Name__c, Contact__c, Type__c
            FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_OVERDUE_REMINDER
        ];
        System.assert(!notifs.isEmpty(), 'A borrower nudge should have been queued');
        Notification__c borrowerNote = notifs[0];
        System.assertEquals(testContact.Id, borrowerNote.Contact__c, 'Recipient is the borrower');
        System.assert(borrowerNote.Title__c.contains('overdue'), 'Title surfaces the overdue framing');
        System.assertEquals('FIMBY', borrowerNote.Actor_Name__c, 'System reminders are signed FIMBY');
        System.assert(String.isNotBlank(borrowerNote.Action_URL__c), 'Deep link is populated via FimbySettings.getUrl()');
    }

    /* ── Owner gets a parallel nudge at 21 days overdue ──────────────────── */
    /*
     * The Overdue_Reminder__c formula fires every 3 days past due
     * (MOD(daysOverdue, 3) = 0). The owner branch additionally requires
     * daysOverdue >= 7 AND MOD(daysOverdue, 7) = 0. 21 days hits both
     * cadences so we can exercise the owner-nudge code path.
     */
    @IsTest
    static void testExecute_OwnerAlsoNudged_AtTwentyOneDaysOverdue() {
        Contact testContact = getTestContact();
        Library_Item__c item = [SELECT Id, Name, Owner_Contact__c FROM Library_Item__c LIMIT 1];

        Loaned_Item__c loan = new Loaned_Item__c(
            Name = 'Loan - ' + item.Name,
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Owned_By__c = item.Owner_Contact__c,
            Loan_Due_Date__c = Date.today().addDays(-21)
        );
        insert loan;

        Test.startTest();
        new FimbyOverdueReminderJob().execute(null);
        Test.stopTest();

        Set<Id> recipientContactIds = new Set<Id>();
        for (Notification__c n : [
            SELECT Contact__c FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_OVERDUE_REMINDER
        ]) {
            recipientContactIds.add(n.Contact__c);
        }
        System.assert(recipientContactIds.contains(testContact.Id),
            'Borrower receives a nudge on the 21-day tick');
        System.assert(recipientContactIds.contains(item.Owner_Contact__c),
            'Owner also gets nudged once daysOverdue >= 7 and is a multiple of 7');
    }
}
