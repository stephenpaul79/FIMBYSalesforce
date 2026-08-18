@IsTest
private class FimbySCIDirectionalMigrationBatchTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 3, true);
    }

    private static List<Contact> getContacts() {
        return [SELECT Id, AccountId FROM Contact WHERE AccountId != null ORDER BY CreatedDate ASC];
    }

    @IsTest
    static void preflightCountsRun() {
        Test.startTest();
        Map<String, Integer> counts = FimbySCIDirectionalMigrationBatch.preflightCounts();
        Test.stopTest();
        System.assert(counts.containsKey('duplicateOpenPairs'));
        System.assert(counts.containsKey('sciActive'));
        System.assertEquals(0, FimbySCIDirectionalMigrationBatch.countDuplicateOpenPairs());
    }

    @IsTest
    static void passAClosesDuplicateOpenPairsAndBackfills() {
        List<Contact> peeps = getContacts();
        FimbySharedContactService.skipTrigger = true;
        Shared_Contact_Info__c older = new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'older@test.com',
            Status__c = 'Active'
        );
        insert older;
        Shared_Contact_Info__c newer = new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'newer@test.com',
            Status__c = null
        );
        insert newer;
        FimbySharedContactService.skipTrigger = false;

        System.assert(FimbySCIDirectionalMigrationBatch.countDuplicateOpenPairs() >= 1);

        Test.startTest();
        Database.executeBatch(new FimbySCIDirectionalMigrationBatch(
            FimbySCIDirectionalMigrationBatch.Phase.PASS_A, false
        ), 200);
        Test.stopTest();

        System.assertEquals(0, FimbySCIDirectionalMigrationBatch.countDuplicateOpenPairs());
        Shared_Contact_Info__c current = [
            SELECT Status__c, Email__c, Active_Pair_Key__c, Contact_Neighbourhood__c
            FROM Shared_Contact_Info__c
            WHERE Contact__c = :peeps[0].Id AND Shared_To__c = :peeps[1].Id
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ];
        System.assertEquals('Active', current.Status__c);
        System.assertEquals('newer@test.com', current.Email__c);
        System.assertEquals(
            FimbySharedContactService.buildPairKey(peeps[0].Id, peeps[1].Id),
            current.Active_Pair_Key__c
        );
        System.assertEquals(peeps[0].AccountId, current.Contact_Neighbourhood__c);
        Shared_Contact_Info__c closed = [
            SELECT Status__c, Active_Pair_Key__c, Consent_Closed_Date__c
            FROM Shared_Contact_Info__c WHERE Id = :older.Id
        ];
        System.assertEquals('Revoked', closed.Status__c);
        System.assertEquals(null, closed.Active_Pair_Key__c);
        System.assertNotEquals(null, closed.Consent_Closed_Date__c);

        FimbySharedContactService.ShareRequest request = new FimbySharedContactService.ShareRequest();
        request.sharerContactId = peeps[0].Id;
        request.recipientContactId = peeps[1].Id;
        request.shareEmail = true;
        request.email = 'after-migration@test.com';
        FimbySharedContactService.ShareResult saved = FimbySharedContactService.saveActiveEpisode(request);
        System.assertEquals(false, saved.createdNewEpisode, 'Save after Pass A must update, not collide');
        System.assertEquals(current.Id, saved.sharedContactInfoId);
    }

    @IsTest
    static void dryRunPassADoesNotMutate() {
        List<Contact> peeps = getContacts();
        FimbySharedContactService.skipTrigger = true;
        insert new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'dry@test.com',
            Status__c = 'Active'
        );
        FimbySharedContactService.skipTrigger = false;

        Test.startTest();
        Database.executeBatch(new FimbySCIDirectionalMigrationBatch(
            FimbySCIDirectionalMigrationBatch.Phase.PASS_A, true
        ), 200);
        Test.stopTest();

        Shared_Contact_Info__c row = [
            SELECT Active_Pair_Key__c, Contact_Neighbourhood__c FROM Shared_Contact_Info__c LIMIT 1
        ];
        System.assertEquals(null, row.Active_Pair_Key__c, 'Dry run must not populate the pair key');
        System.assertEquals(null, row.Contact_Neighbourhood__c, 'Dry run must not backfill neighbourhoods');
    }

    @IsTest
    static void passBBindsCreatorAlignedAndLocksTheRest() {
        List<Contact> peeps = getContacts();
        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = peeps[0].Id,
            Shared_To__c = peeps[1].Id,
            Email__c = 'bind@test.com',
            Status__c = 'Active'
        );
        insert sci;

        Conversation__c aligned = new Conversation__c(
            Participant_1__c = peeps[1].Id,
            Participant_2__c = peeps[0].Id,
            Context_Type__c = FimbyConstants.CTX_DIRECT,
            Status__c = 'Active'
        );
        Conversation__c unauthorized = new Conversation__c(
            Participant_1__c = peeps[0].Id,
            Participant_2__c = peeps[1].Id,
            Context_Type__c = FimbyConstants.CTX_DIRECT,
            Status__c = 'Active'
        );
        Conversation__c emptyUnauthorized = new Conversation__c(
            Participant_1__c = peeps[2].Id,
            Participant_2__c = peeps[0].Id,
            Context_Type__c = FimbyConstants.CTX_DIRECT,
            Status__c = 'Active'
        );
        insert new List<Conversation__c>{ aligned, unauthorized, emptyUnauthorized };
        insert new Message__c(
            Conversation__c = unauthorized.Id,
            Body__c = 'Historical hello',
            Status__c = FimbyConstants.MESSAGE_SENT,
            Sent_Date__c = System.now()
        );

        Test.startTest();
        Database.executeBatch(new FimbySCIDirectionalMigrationBatch(
            FimbySCIDirectionalMigrationBatch.Phase.PASS_B, false
        ), 200);
        Test.stopTest();

        aligned = [
            SELECT Authorizing_Shared_Contact_Info__c, Locked__c
            FROM Conversation__c WHERE Id = :aligned.Id
        ];
        System.assertEquals(sci.Id, aligned.Authorizing_Shared_Contact_Info__c);
        System.assertEquals(false, aligned.Locked__c);

        unauthorized = [
            SELECT Locked__c, Authorizing_Shared_Contact_Info__c
            FROM Conversation__c WHERE Id = :unauthorized.Id
        ];
        System.assertEquals(true, unauthorized.Locked__c);
        System.assertEquals(null, unauthorized.Authorizing_Shared_Contact_Info__c);
        System.assertEquals(
            1,
            [
                SELECT COUNT() FROM Message__c
                WHERE Conversation__c = :unauthorized.Id
                AND System_Message_Type__c = 'Contact_Sharing_Revoked'
            ]
        );

        emptyUnauthorized = [
            SELECT Locked__c FROM Conversation__c WHERE Id = :emptyUnauthorized.Id
        ];
        System.assertEquals(true, emptyUnauthorized.Locked__c);
        System.assertEquals(
            0,
            [
                SELECT COUNT() FROM Message__c
                WHERE Conversation__c = :emptyUnauthorized.Id
                AND System_Message_Type__c = 'Contact_Sharing_Revoked'
            ],
            'Empty historical threads must not be resurfaced with a bubble'
        );
    }
}
