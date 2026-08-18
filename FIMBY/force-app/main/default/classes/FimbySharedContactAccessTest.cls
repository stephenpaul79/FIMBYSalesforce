@IsTest
private class FimbySharedContactAccessTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 3, true);
    }

    private static List<Contact> getContacts() {
        return [SELECT Id, AccountId FROM Contact WHERE AccountId != null ORDER BY CreatedDate ASC];
    }

    @IsTest
    static void newestRevokedWinsOverOlderActive() {
        List<Contact> peeps = getContacts();
        insert new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'old-active@test.com',
            Status__c = 'Active'
        );
        insert new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'newer-revoked@test.com',
            Status__c = 'Revoked'
        );

        Test.startTest();
        Shared_Contact_Info__c current =
            FimbySharedContactAccess.findCurrentEpisode(peeps[0].Id, peeps[1].Id);
        Shared_Contact_Info__c active =
            FimbySharedContactAccess.findActiveEpisode(peeps[0].Id, peeps[1].Id);
        Shared_Contact_Info__c snapshot =
            FimbySharedContactAccess.getActiveInboundSnapshot(peeps[0].Id, peeps[1].Id);
        Test.stopTest();

        System.assertEquals('Revoked', current.Status__c, 'Current episode is the newest row');
        System.assertEquals(null, active, 'A newer Revoked row must not fall back to older Active');
        System.assertEquals(null, snapshot, 'Revoked inbound must not expose a snapshot');
        System.assertEquals(false, FimbySharedContactAccess.hasActiveEpisode(peeps[0].Id, peeps[1].Id));
    }

    @IsTest
    static void inboundOnlyIncomingSharers() {
        List<Contact> peeps = getContacts();
        insert new List<Shared_Contact_Info__c>{
            new Shared_Contact_Info__c(
                Contact__c = peeps[0].Id,
                Shared_To__c = peeps[1].Id,
                Email__c = 'inbound@test.com',
                Status__c = 'Active'
            ),
            new Shared_Contact_Info__c(
                Contact__c = peeps[1].Id,
                Shared_To__c = peeps[2].Id,
                Email__c = 'outbound-only@test.com',
                Status__c = 'Active'
            )
        };

        Test.startTest();
        Set<Id> incoming = FimbySharedContactAccess.getActiveIncomingSharerIds(peeps[1].Id);
        Test.stopTest();

        System.assert(incoming.contains(peeps[0].Id), 'Inbound Active sharer is included');
        System.assert(!incoming.contains(peeps[2].Id), 'Outbound-only share must not expand the recipient');
        System.assertEquals(1, incoming.size());
    }

    @IsTest
    static void filterAndStatusHelpers() {
        List<Contact> peeps = getContacts();
        Shared_Contact_Info__c openRow = new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'open@test.com',
            Status__c = 'Active'
        );
        insert openRow;
        Shared_Contact_Info__c closedRow = new Shared_Contact_Info__c(
            Contact__c = peeps[2].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'closed@test.com',
            Status__c = 'Revoked'
        );
        insert closedRow;

        Test.startTest();
        Set<Id> filtered = FimbySharedContactAccess.filterToActiveIncomingSharers(
            peeps[1].Id,
            new Set<Id>{ peeps[0].Id, peeps[2].Id, peeps[1].Id }
        );
        System.assert(FimbySharedContactAccess.isEpisodeActive(openRow.Id));
        System.assert(!FimbySharedContactAccess.isEpisodeActive(closedRow.Id));
        System.assert(!FimbySharedContactAccess.isEpisodeActive(null));
        Shared_Contact_Info__c locked = FimbySharedContactAccess.lockEpisode(openRow.Id);
        Set<Id> openIds = FimbySharedContactAccess.filterActiveEpisodeIds(
            new Set<Id>{ openRow.Id, closedRow.Id }
        );
        Test.stopTest();

        System.assertEquals(new Set<Id>{ peeps[0].Id }, filtered);
        System.assertEquals(openRow.Id, locked.Id);
        System.assertEquals(new Set<Id>{ openRow.Id }, openIds);
        System.assertEquals(null, FimbySharedContactAccess.findCurrentEpisode(null, peeps[1].Id));
        System.assertEquals(0, FimbySharedContactAccess.getActiveIncomingSharerIds(null).size());
    }
}
