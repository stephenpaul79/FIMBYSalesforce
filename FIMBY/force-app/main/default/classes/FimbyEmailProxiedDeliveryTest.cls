/**
 * @description Covers email alerts for inboxes whose Contact has no login of their own.
 *
 * Before the fan-out these rows found no User at all and were quietly marked
 * Suppressed — the alert reached nobody. These tests pin the fix: the email goes to
 * every approved helper, each helper's outcome is tracked independently, and the
 * subject says whose inbox it is rather than an unqualified "your item".
 */
@IsTest
private class FimbyEmailProxiedDeliveryTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);

        Contact guardianOne = new Contact(
            FirstName = 'Sarah', LastName = 'GuardianOne', AccountId = nh.Id);
        Contact guardianTwo = new Contact(
            FirstName = 'Marcus', LastName = 'GuardianTwo', AccountId = nh.Id);
        Contact child = new Contact(
            FirstName = 'Maya', LastName = 'Proxied', AccountId = nh.Id);
        insert new List<Contact>{ guardianOne, guardianTwo, child };

        List<User> users = new List<User>{
            FimbyTestDataFactory.createCommunityUser(guardianOne.Id, null, false),
            FimbyTestDataFactory.createCommunityUser(guardianTwo.Id, null, false)
        };
        for (User u : users) {
            u.Email_Alerts_Enabled__c = true;
            u.Email_Alert_Messages__c = true;
            u.Include_Sundays__c = true;
        }
        insert users;

        // The child has no User. Only guardian one is approved at setup; the
        // two-guardian test adds the second relationship itself.
        insert new Support_Relationship__c(
            Contact__c = guardianOne.Id,
            Related_Contact__c = child.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id,
            Consent_Method__c = 'Written'
        );
    }

    private static Contact childContact() {
        return [SELECT Id, AccountId FROM Contact WHERE LastName = 'Proxied' LIMIT 1];
    }

    private static Contact guardian(String lastName) {
        return [SELECT Id FROM Contact WHERE LastName = :lastName LIMIT 1];
    }

    private static User userFor(Contact c) {
        return [SELECT Id, ContactId FROM User WHERE ContactId = :c.Id LIMIT 1];
    }

    private static Id seedAlert(Id inboxId) {
        Notification__c n = new Notification__c(
            Contact__c = inboxId,
            Type__c = FimbyConstants.NOTIF_MESSAGE,
            Title__c = 'sent a message',
            Body__c = 'Are you free Saturday?',
            Actor_Name__c = 'Aisha Bello',
            Email_Status__c = 'Pending',
            Push_Status__c = 'Sent'
        );
        Database.insert(n, AccessLevel.SYSTEM_MODE);
        return n.Id;
    }

    private static Notification__c reload(Id rowId) {
        return [
            SELECT Email_Status__c, Delivery_State__c
            FROM Notification__c WHERE Id = :rowId
            WITH SYSTEM_MODE
        ];
    }

    /**
     * The regression this whole change exists for: an alert on a login-less contact
     * used to be Suppressed because no User matched, so nobody was ever told.
     */
    @IsTest
    static void alertForALoginLessChildIsNoLongerSuppressed() {
        delete [SELECT Id FROM Notification__c];
        Id rowId = seedAlert(childContact().Id);
        FimbyEmailAlertQueueable.oweaCached = userFor(guardian('GuardianOne')).Id;

        Test.startTest();
        new FimbyEmailAlertBatchJob().execute(null);
        Test.stopTest();

        Notification__c after = reload(rowId);
        System.assertNotEquals('Suppressed', after.Email_Status__c,
            'An alert for a proxied child must reach its guardian, not be dropped');
        System.assertNotEquals('Pending', after.Email_Status__c,
            'The row must have been claimed and acted on');
    }

    /**
     * One approved helper needs no ledger — the plain channel status is enough, and
     * keeping it plain avoids writing delivery JSON on every ordinary row.
     */
    @IsTest
    static void aSingleRecipientIsClaimedWithoutALedger() {
        delete [SELECT Id FROM Notification__c];
        Id rowId = seedAlert(childContact().Id);
        FimbyEmailAlertQueueable.oweaCached = userFor(guardian('GuardianOne')).Id;

        Test.startTest();
        new FimbyEmailAlertBatchJob().execute(null);
        Test.stopTest();

        System.assertEquals(null, reload(rowId).Delivery_State__c,
            'A single-recipient row carries no per-recipient ledger');
    }

    /**
     * Two guardians, one inbox. Both must be claimed separately, and the single row
     * must survive two recipients being written in the same transaction — the case
     * that would previously have thrown a duplicate-Id DML error.
     */
    @IsTest
    static void bothGuardiansAreClaimedIndependentlyOnOneRow() {
        delete [SELECT Id FROM Notification__c];
        Contact child = childContact();
        Contact second = guardian('GuardianTwo');

        insert new Support_Relationship__c(
            Contact__c = second.Id,
            Related_Contact__c = child.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = child.AccountId,
            Consent_Method__c = 'Written'
        );

        Id rowId = seedAlert(child.Id);
        FimbyEmailAlertQueueable.oweaCached = userFor(guardian('GuardianOne')).Id;

        Test.startTest();
        new FimbyEmailAlertBatchJob().execute(null);
        Test.stopTest();

        Notification__c after = reload(rowId);
        FimbySupportedIdentityDelivery.Ledger ledger =
            FimbySupportedIdentityDelivery.parseLedger(after.Delivery_State__c);

        System.assertNotEquals(null, ledger,
            'Two recipients on one row require a per-recipient ledger');
        System.assertEquals(2, ledger.userIds().size(),
            'Both guardians must be tracked as distinct delivery claims');
        System.assertNotEquals('Suppressed', after.Email_Status__c,
            'A two-guardian row must not collapse to a single suppression');
    }

    /**
     * A guardian reading "Someone wants to borrow your item" about their child's
     * item has been told the wrong thing. The subject names the inbox instead.
     */
    @IsTest
    static void subjectNamesTheChildWhoseInboxItIs() {
        Contact child = childContact();
        Notification__c row = [
            SELECT Id FROM Notification__c WHERE Id = :seedAlert(child.Id)
        ];

        FimbyEmailAlertQueueable q = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>(),
            new Map<Id, Id>{ row.Id => child.Id },
            new Map<Id, String>{ child.Id => 'Maya' }
        );

        System.assertEquals('For Maya \u2014 Someone wants to borrow your item',
            q.applyInboxPrefix('Someone wants to borrow your item',
                new List<Notification__c>{ row }),
            'A proxied subject must name the child it concerns');
    }

    @IsTest
    static void subjectIsLeftAloneWhenAPrefixCouldMislead() {
        Contact child = childContact();
        Contact guardianOne = guardian('GuardianOne');
        Notification__c childRow = [
            SELECT Id FROM Notification__c WHERE Id = :seedAlert(child.Id)
        ];
        Notification__c ownRow = [
            SELECT Id FROM Notification__c WHERE Id = :seedAlert(guardianOne.Id)
        ];

        FimbyEmailAlertQueueable ownInbox = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>(), new Map<Id, Id>(), new Map<Id, String>());
        System.assertEquals('New message from a neighbour',
            ownInbox.applyInboxPrefix('New message from a neighbour',
                new List<Notification__c>{ ownRow }),
            'An ordinary inbox gets no prefix');

        FimbyEmailAlertQueueable noName = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>(),
            new Map<Id, Id>{ childRow.Id => child.Id },
            new Map<Id, String>()
        );
        System.assertEquals('New message from a neighbour',
            noName.applyInboxPrefix('New message from a neighbour',
                new List<Notification__c>{ childRow }),
            'A missing name is better than a malformed prefix');

        // One row proxied, one the guardian's own: no single name is truthful here.
        FimbyEmailAlertQueueable mixed = new FimbyEmailAlertQueueable(
            new Map<Id, List<Notification__c>>(),
            new Map<Id, Id>{ childRow.Id => child.Id },
            new Map<Id, String>{ child.Id => 'Maya' }
        );
        System.assertEquals('2 new messages',
            mixed.applyInboxPrefix('2 new messages',
                new List<Notification__c>{ childRow, ownRow }),
            'A batch spanning more than one inbox must not be labelled with just one');
    }
}
