@IsTest
public class FimbyVouchReminderJobTest {

    private static Account makeNeighbourhood(String name) {
        Account a = new Account(Name = name, Active__c = 'Yes');
        insert a;
        return a;
    }

    private static Contact makeContact(String first, String last, String email, Id accountId) {
        Contact c = new Contact(
            FirstName = first,
            LastName  = last,
            Email     = email,
            AccountId = accountId,
            Vouched_Status__c = 'Vouched'
        );
        insert c;
        return c;
    }

    private static Vouch_Record__c makeVouch(Id requesterId, Id referenceId, Id neighbourhoodId) {
        Vouch_Record__c vr = new Vouch_Record__c(
            Requester_Contact__c = requesterId,
            Reference_Contact__c = referenceId,
            Neighbourhood__c     = neighbourhoodId,
            Status__c            = 'Pending',
            Source__c            = 'Peer',
            Requested_Date__c    = System.now()
        );
        insert vr;
        return vr;
    }

    /* ── execute() with no pending vouches is a clean no-op ──────────────── */

    @IsTest
    static void testExecute_NoPending_IsNoOp() {
        Test.startTest();
        new FimbyVouchReminderJob().execute(null);
        Test.stopTest();

        Integer notifCount = [
            SELECT COUNT() FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_VOUCH_REQUEST_REMINDER
        ];
        System.assertEquals(0, notifCount, 'No pending vouches → no reminders');
    }

    /* ── A vouch >3 days old nudges the reference and stamps the date ────── */

    @IsTest
    static void testExecute_PendingVouch_NudgesReference() {
        Account hood = makeNeighbourhood('VouchReminderHood');
        Contact requester = makeContact('Riley', 'Requester', 'riley@example.com', hood.Id);
        Contact reference = makeContact('Reggie', 'Reference', 'reggie@example.com', hood.Id);

        Vouch_Record__c vr = makeVouch(requester.Id, reference.Id, hood.Id);
        Test.setCreatedDate(vr.Id, Datetime.now().addDays(-5));

        Test.startTest();
        new FimbyVouchReminderJob().execute(null);
        Test.stopTest();

        List<Notification__c> notes = [
            SELECT Id, Contact__c, Type__c, Title__c, Actor_Name__c, Actor_Contact__c, Action_URL__c
            FROM Notification__c
            WHERE Type__c = :FimbyConstants.NOTIF_VOUCH_REQUEST_REMINDER
        ];
        System.assertEquals(1, notes.size(), 'Reference gets one nudge');
        System.assertEquals(reference.Id, notes[0].Contact__c, 'Recipient is the reference');
        // Title is now a de-actored verb phrase; the requester identity lives on
        // Actor_Name__c / Actor_Contact__c (the LWC prepends the bold name).
        System.assert(notes[0].Actor_Name__c.contains('Riley'), 'Requester name surfaces as the actor');
        System.assertEquals(requester.Id, notes[0].Actor_Contact__c, 'Actor Contact stamped to the requester');
        System.assert(notes[0].Title__c.contains('still waiting'), 'Title carries the verb phrase');
        System.assert(String.isNotBlank(notes[0].Action_URL__c), 'Deep link populated');

        Vouch_Record__c refreshed = [
            SELECT Last_Reminder_Sent_Date__c FROM Vouch_Record__c WHERE Id = :vr.Id
        ];
        System.assertNotEquals(null, refreshed.Last_Reminder_Sent_Date__c,
            'Reminder timestamp stamped so we throttle the next cadence tick');
    }

    /* ── A vouch >7 days old opens a moderator task ──────────────────────── */

    @IsTest
    static void testExecute_StuckVouch_OpensModeratorTask() {
        Account hood = makeNeighbourhood('StuckVouchHood');
        Contact requester = makeContact('Sam', 'Stuck', 'sam-stuck@example.com', hood.Id);
        Contact reference = makeContact('Pat', 'Pending', 'pat-pending@example.com', hood.Id);

        Vouch_Record__c vr = makeVouch(requester.Id, reference.Id, hood.Id);
        Test.setCreatedDate(vr.Id, Datetime.now().addDays(-30));

        Test.startTest();
        new FimbyVouchReminderJob().execute(null);
        Test.stopTest();

        List<Moderator_Task__c> tasks = [
            SELECT Id, Category__c, Related_Record_Id__c
            FROM Moderator_Task__c
            WHERE Related_Record_Id__c = :vr.Id
        ];
        System.assertEquals(1, tasks.size(), 'Stuck vouch opens exactly one moderator task');
        System.assertEquals('Vouch_Pending', tasks[0].Category__c, 'Tagged as Vouch_Pending');

        Vouch_Record__c refreshed = [
            SELECT Moderator_Alert_Opened__c FROM Vouch_Record__c WHERE Id = :vr.Id
        ];
        System.assertEquals(true, refreshed.Moderator_Alert_Opened__c,
            'Idempotency flag set so we never double-open a moderator task');
    }
}
