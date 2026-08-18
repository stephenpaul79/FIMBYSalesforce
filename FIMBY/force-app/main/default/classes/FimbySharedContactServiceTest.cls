@IsTest
private class FimbySharedContactServiceTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> peeps = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 3, true);
        FimbyTestDataFactory.createCommunityUser(peeps[0].Id, null, true);
    }

    private static List<Contact> getContacts() {
        return [SELECT Id, AccountId, Email FROM Contact WHERE AccountId != null ORDER BY CreatedDate ASC];
    }

    private static User getSharerUser() {
        List<Contact> peeps = getContacts();
        return [SELECT Id, ContactId FROM User WHERE ContactId = :peeps[0].Id AND IsActive = true LIMIT 1];
    }

    private static FimbySharedContactService.ShareRequest baseRequest(Id sharerId, Id recipientId) {
        FimbySharedContactService.ShareRequest request = new FimbySharedContactService.ShareRequest();
        request.sharerContactId = sharerId;
        request.recipientContactId = recipientId;
        request.origin = 'My Neighbours';
        request.writeMode = FimbySharedContactService.MODE_REPLACE;
        request.shareEmail = true;
        request.email = 'first@test.com';
        return request;
    }

    @IsTest
    static void saveInsertsThenUpdatesOpenEpisode() {
        List<Contact> peeps = getContacts();

        Test.startTest();
        FimbySharedContactService.ShareResult created =
            FimbySharedContactService.saveActiveEpisode(baseRequest(peeps[0].Id, peeps[1].Id));
        FimbySharedContactService.ShareRequest edit = baseRequest(peeps[0].Id, peeps[1].Id);
        edit.email = 'updated@test.com';
        edit.sharePhone = true;
        edit.phone = '0400111222';
        FimbySharedContactService.ShareResult updated =
            FimbySharedContactService.saveActiveEpisode(edit);
        Test.stopTest();

        System.assertEquals(true, created.createdNewEpisode);
        System.assertEquals(false, updated.createdNewEpisode);
        System.assertEquals(created.sharedContactInfoId, updated.sharedContactInfoId);
        Shared_Contact_Info__c row = [
            SELECT Email__c, Phone__c, Status__c, Active_Pair_Key__c,
                   Contact_Neighbourhood__c, Shared_To_Neighbourhood__c
            FROM Shared_Contact_Info__c WHERE Id = :created.sharedContactInfoId
        ];
        System.assertEquals('updated@test.com', row.Email__c);
        System.assertEquals('0400111222', row.Phone__c);
        System.assertEquals('Active', row.Status__c);
        System.assertEquals(
            FimbySharedContactService.buildPairKey(peeps[0].Id, peeps[1].Id),
            row.Active_Pair_Key__c
        );
        System.assertEquals(peeps[0].AccountId, row.Contact_Neighbourhood__c);
        System.assertEquals(peeps[1].AccountId, row.Shared_To_Neighbourhood__c);
    }

    @IsTest
    static void replaceClearsUncheckedFieldsMergeKeepsThem() {
        List<Contact> peeps = getContacts();
        FimbySharedContactService.ShareRequest first = baseRequest(peeps[0].Id, peeps[1].Id);
        first.sharePhone = true;
        first.phone = '0400111222';
        FimbySharedContactService.saveActiveEpisode(first);

        Test.startTest();
        FimbySharedContactService.ShareRequest replaceOnlyEmail = baseRequest(peeps[0].Id, peeps[1].Id);
        replaceOnlyEmail.writeMode = FimbySharedContactService.MODE_REPLACE;
        FimbySharedContactService.saveActiveEpisode(replaceOnlyEmail);
        Shared_Contact_Info__c afterReplace = [
            SELECT Phone__c FROM Shared_Contact_Info__c
            WHERE Contact__c = :peeps[0].Id AND Shared_To__c = :peeps[1].Id
        ];

        FimbySharedContactService.ShareRequest restorePhone = baseRequest(peeps[0].Id, peeps[1].Id);
        restorePhone.sharePhone = true;
        restorePhone.phone = '0400111222';
        FimbySharedContactService.saveActiveEpisode(restorePhone);

        FimbySharedContactService.ShareRequest mergeEmailOnly = baseRequest(peeps[0].Id, peeps[1].Id);
        mergeEmailOnly.writeMode = FimbySharedContactService.MODE_MERGE;
        mergeEmailOnly.sharePhone = false;
        FimbySharedContactService.saveActiveEpisode(mergeEmailOnly);
        Test.stopTest();

        System.assertEquals(null, afterReplace.Phone__c, 'REPLACE must clear an unchecked phone');
        Shared_Contact_Info__c afterMerge = [
            SELECT Phone__c FROM Shared_Contact_Info__c
            WHERE Contact__c = :peeps[0].Id AND Shared_To__c = :peeps[1].Id
        ];
        System.assertEquals('0400111222', afterMerge.Phone__c, 'MERGE must keep an unchecked phone');
    }

    @IsTest
    static void reshareAfterRevokeInsertsNewEpisode() {
        List<Contact> peeps = getContacts();
        User sharerUser = getSharerUser();
        FimbySharedContactService.ShareResult first =
            FimbySharedContactService.saveActiveEpisode(baseRequest(peeps[0].Id, peeps[1].Id));

        Test.startTest();
        System.runAs(sharerUser) {
            FimbySharedContactService.revokeEpisode(peeps[0].Id, first.sharedContactInfoId);
        }
        FimbySharedContactService.ShareRequest again = baseRequest(peeps[0].Id, peeps[1].Id);
        again.email = 'again@test.com';
        FimbySharedContactService.ShareResult second =
            FimbySharedContactService.saveActiveEpisode(again);
        Test.stopTest();

        System.assertEquals(true, second.createdNewEpisode);
        System.assertNotEquals(first.sharedContactInfoId, second.sharedContactInfoId);
        Shared_Contact_Info__c oldRow = [
            SELECT Status__c, Email__c, Active_Pair_Key__c, Consent_Closed_Date__c
            FROM Shared_Contact_Info__c WHERE Id = :first.sharedContactInfoId
        ];
        System.assertEquals('Revoked', oldRow.Status__c);
        System.assertEquals('first@test.com', oldRow.Email__c);
        System.assertEquals(null, oldRow.Active_Pair_Key__c);
        System.assertNotEquals(null, oldRow.Consent_Closed_Date__c);
    }

    @IsTest
    static void revokeRejectsNonSharerAndIsIdempotent() {
        List<Contact> peeps = getContacts();
        FimbySharedContactService.ShareResult first =
            FimbySharedContactService.saveActiveEpisode(baseRequest(peeps[0].Id, peeps[1].Id));

        Boolean threw = false;
        try {
            FimbySharedContactService.revokeEpisode(peeps[1].Id, first.sharedContactInfoId);
        } catch (FimbySharedContactService.SharedContactException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Only the sharer may revoke');

        FimbySharedContactService.revokeEpisode(peeps[0].Id, first.sharedContactInfoId);
        FimbySharedContactService.revokeEpisode(peeps[0].Id, first.sharedContactInfoId);
        System.assertEquals(
            'Revoked',
            [SELECT Status__c FROM Shared_Contact_Info__c WHERE Id = :first.sharedContactInfoId].Status__c
        );
    }

    @IsTest
    static void assertRecipientAllowedSameNeighbourhood() {
        List<Contact> peeps = getContacts();
        User sharerUser = getSharerUser();

        Test.startTest();
        System.runAs(sharerUser) {
            FimbySharedContactService.assertRecipientAllowed(peeps[0].Id, peeps[1].Id);
            Boolean threw = false;
            try {
                FimbySharedContactService.assertRecipientAllowed(peeps[0].Id, peeps[0].Id);
            } catch (FimbySharedContactService.SharedContactException e) {
                threw = true;
            }
            System.assertEquals(true, threw, 'Cannot share with yourself');
        }
        Test.stopTest();
    }

    @IsTest
    static void pairKeyAndNeighbourhoodHelpers() {
        List<Contact> peeps = getContacts();
        System.assertEquals(null, FimbySharedContactService.buildPairKey(null, peeps[1].Id));
        Map<Id, Id> neighbourhoods = FimbySharedContactService.neighbourhoodsFor(
            new Set<Id>{ peeps[0].Id, peeps[1].Id }
        );
        System.assertEquals(peeps[0].AccountId, neighbourhoods.get(peeps[0].Id));
        System.assertEquals(0, FimbySharedContactService.neighbourhoodsFor(new Set<Id>()).size());
    }
}
