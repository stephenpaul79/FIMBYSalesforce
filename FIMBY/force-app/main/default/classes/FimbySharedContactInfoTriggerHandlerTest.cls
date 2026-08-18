@IsTest
private class FimbySharedContactInfoTriggerHandlerTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 3, true);
    }

    private static List<Contact> getContacts() {
        return [SELECT Id, AccountId FROM Contact WHERE AccountId != null ORDER BY CreatedDate ASC];
    }

    @IsTest
    static void insertStampsKeyAndNeighbourhoods() {
        List<Contact> peeps = getContacts();
        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'stamp@test.com'
        );
        insert sci;

        sci = [
            SELECT Status__c, Active_Pair_Key__c, Contact_Neighbourhood__c, Shared_To_Neighbourhood__c
            FROM Shared_Contact_Info__c WHERE Id = :sci.Id
        ];
        System.assertEquals('Active', sci.Status__c);
        System.assertEquals(
            FimbySharedContactService.buildPairKey(peeps[0].Id, peeps[1].Id),
            sci.Active_Pair_Key__c
        );
        System.assertEquals(peeps[0].AccountId, sci.Contact_Neighbourhood__c);
        System.assertEquals(peeps[1].AccountId, sci.Shared_To_Neighbourhood__c);
    }

    @IsTest
    static void partiesAreImmutable() {
        List<Contact> peeps = getContacts();
        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'party@test.com'
        );
        insert sci;
        sci.Shared_To__c = peeps[2].Id;
        Boolean threw = false;
        try {
            update sci;
        } catch (DmlException e) {
            threw = true;
            System.assert(e.getMessage().contains('cannot be reassigned'), e.getMessage());
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void revokedCannotReopenOrEditSnapshot() {
        List<Contact> peeps = getContacts();
        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'closed@test.com',
            Status__c = 'Active'
        );
        insert sci;
        sci.Status__c = 'Revoked';
        update sci;

        Shared_Contact_Info__c reopen = new Shared_Contact_Info__c(Id = sci.Id, Status__c = 'Active');
        Boolean reopenThrew = false;
        try {
            update reopen;
        } catch (DmlException e) {
            reopenThrew = true;
        }
        System.assertEquals(true, reopenThrew, 'Revoked to Active must be refused');

        Shared_Contact_Info__c edit = new Shared_Contact_Info__c(Id = sci.Id, Email__c = 'tamper@test.com');
        Boolean editThrew = false;
        try {
            update edit;
        } catch (DmlException e) {
            editThrew = true;
        }
        System.assertEquals(true, editThrew, 'Revoked snapshot must be frozen');
    }

    @IsTest
    static void neighbourhoodRestampAndDeleteAllowedOnRevoked() {
        List<Contact> peeps = getContacts();
        Account otherNh = FimbyTestDataFactory.createNeighbourhood(true);
        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'history@test.com',
            Status__c = 'Revoked'
        );
        insert sci;

        sci.Contact_Neighbourhood__c = otherNh.Id;
        update sci;
        System.assertEquals(
            peeps[0].AccountId,
            [SELECT Contact_Neighbourhood__c FROM Shared_Contact_Info__c WHERE Id = :sci.Id]
                .Contact_Neighbourhood__c,
            'Trigger restamps neighbourhood from the current Contact account'
        );

        delete sci;
        System.assertEquals(0, [SELECT COUNT() FROM Shared_Contact_Info__c WHERE Id = :sci.Id]);
    }

    @IsTest
    static void revokeLocksBoundThreadOnce() {
        List<Contact> peeps = getContacts();
        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'lock@test.com',
            Status__c = 'Active'
        );
        insert sci;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = peeps[1].Id,
            Participant_2__c = peeps[0].Id,
            Context_Type__c = FimbyConstants.CTX_DIRECT,
            Status__c = 'Active',
            Authorizing_Shared_Contact_Info__c = sci.Id
        );
        insert conv;
        insert new Message__c(
            Conversation__c = conv.Id,
            Body__c = 'Hello',
            Is_System_Message__c = false,
            Status__c = FimbyConstants.MESSAGE_SENT,
            Sent_Date__c = System.now()
        );

        Test.startTest();
        sci.Status__c = 'Revoked';
        update sci;
        FimbySharedContactInfoTriggerHandler.lockAuthorizedConversations(new Set<Id>{ sci.Id });
        Test.stopTest();

        Conversation__c locked = [SELECT Locked__c FROM Conversation__c WHERE Id = :conv.Id];
        System.assertEquals(true, locked.Locked__c);
        System.assertEquals(
            1,
            [
                SELECT COUNT() FROM Message__c
                WHERE Conversation__c = :conv.Id
                AND Is_System_Message__c = true
                AND System_Message_Type__c = 'Contact_Sharing_Revoked'
            ]
        );
    }

    @IsTest
    static void duplicateOpenPairIsRejected() {
        List<Contact> peeps = getContacts();
        insert new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'one@test.com',
            Status__c = 'Active'
        );
        Boolean threw = false;
        try {
            insert new Shared_Contact_Info__c(
                Contact__c = peeps[0].Id,
                Shared_To__c = peeps[1].Id,
                Email__c = 'two@test.com',
                Status__c = 'Active'
            );
        } catch (DmlException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Unique pair key must reject a second Active episode');
    }
}
