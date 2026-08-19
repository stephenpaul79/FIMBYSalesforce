@IsTest
private class FimbySharedContactServiceTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> peeps = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 3, true);
        FimbyTestDataFactory.createCommunityUser(peeps[0].Id, null, true);
        // The recipient needs a User for the email lane to have anywhere to send.
        FimbyTestDataFactory.createCommunityUser(peeps[1].Id, null, true);
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
    static void newEpisodeNotifiesRecipientButPlainEditDoesNot() {
        List<Contact> peeps = getContacts();

        Test.startTest();
        FimbySharedContactService.saveActiveEpisode(baseRequest(peeps[0].Id, peeps[1].Id));

        // Correcting an already-shared email is an edit to what the recipient can
        // already see, so it must not announce itself a second time.
        FimbySharedContactService.ShareRequest typoFix = baseRequest(peeps[0].Id, peeps[1].Id);
        typoFix.email = 'corrected@test.com';
        FimbySharedContactService.saveActiveEpisode(typoFix);
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Type__c, Title__c, Body__c, Actor_Name__c, Actor_Contact__c,
                   Action_URL__c, Related_Record_Id__c, Related_Record_Type__c
            FROM Notification__c
            WHERE Contact__c = :peeps[1].Id
              AND Type__c = :FimbyConstants.NOTIF_CONTACT_INFO_SHARED
        ];
        System.assertEquals(1, notifs.size(), 'A typo fix must not re-notify the recipient');
        System.assertEquals('shared their contact info with you', notifs[0].Title__c);
        System.assertEquals('You can now see their email address.', notifs[0].Body__c);
        System.assertEquals(peeps[0].Id, notifs[0].Actor_Contact__c, 'Actor is the sharer');
        System.assertNotEquals(null, notifs[0].Actor_Name__c, 'Actor name is never null or blank');
        System.assertNotEquals('', notifs[0].Actor_Name__c, 'Actor name is never null or blank');
        System.assertEquals('Shared_Contact_Info__c', notifs[0].Related_Record_Type__c);
        System.assert(
            notifs[0].Action_URL__c.contains('/neighbour?id=' + peeps[0].Id),
            'Action URL should deep-link to the sharer profile, got: ' + notifs[0].Action_URL__c
        );
    }

    @IsTest
    static void expandingDisclosureNotifiesAgainAndSuppressionIsHonoured() {
        List<Contact> peeps = getContacts();
        FimbySharedContactService.saveActiveEpisode(baseRequest(peeps[0].Id, peeps[1].Id));

        Test.startTest();
        FimbySharedContactService.ShareRequest addPhone = baseRequest(peeps[0].Id, peeps[1].Id);
        addPhone.sharePhone = true;
        addPhone.phone = '0400111222';
        FimbySharedContactService.saveActiveEpisode(addPhone);

        FimbySharedContactService.ShareRequest addAddress = baseRequest(peeps[0].Id, peeps[1].Id);
        addAddress.sharePhone = true;
        addAddress.phone = '0400111222';
        addAddress.shareAddress = true;
        addAddress.street = '12 Maple Lane';
        addAddress.city = 'Vancouver';
        FimbySharedContactService.saveActiveEpisode(addAddress);

        FimbySharedContactService.ShareRequest silentToOther = baseRequest(peeps[0].Id, peeps[2].Id);
        silentToOther.suppressNotification = true;
        FimbySharedContactService.saveActiveEpisode(silentToOther);
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Body__c FROM Notification__c
            WHERE Contact__c = :peeps[1].Id
              AND Type__c = :FimbyConstants.NOTIF_CONTACT_INFO_SHARED
            ORDER BY CreatedDate ASC
        ];
        System.assertEquals(3, notifs.size(), 'Each newly visible field should notify again');
        System.assertEquals(
            'You can now see their email address and phone number.',
            notifs[1].Body__c
        );
        System.assertEquals(
            'You can now see their email address, phone number, and address.',
            notifs[2].Body__c
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT() FROM Notification__c
                WHERE Contact__c = :peeps[2].Id
                  AND Type__c = :FimbyConstants.NOTIF_CONTACT_INFO_SHARED
            ],
            'Suppressed shares must stay silent so migrations do not replay consent'
        );
    }

    @IsTest
    static void emailReachesRecipientUnlessTheyOptedOut() {
        List<Contact> peeps = getContacts();
        User recipientUser = [
            SELECT Id, Email_Alerts_Enabled__c FROM User
            WHERE ContactId = :peeps[1].Id AND IsActive = true LIMIT 1
        ];

        Test.startTest();
        FimbyTransactionalEmailService.testSendInvocationCount = 0;
        FimbySharedContactService.saveActiveEpisode(baseRequest(peeps[0].Id, peeps[1].Id));
        Integer afterFirstShare = FimbyTransactionalEmailService.testSendInvocationCount;

        // runAs isolates the setup-object DML from the Shared_Contact_Info__c writes.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            recipientUser.Email_Alerts_Enabled__c = false;
            update recipientUser;
        }

        FimbySharedContactService.ShareRequest addPhone = baseRequest(peeps[0].Id, peeps[1].Id);
        addPhone.sharePhone = true;
        addPhone.phone = '0400111222';
        FimbySharedContactService.saveActiveEpisode(addPhone);
        Test.stopTest();

        System.assertEquals(1, afterFirstShare, 'A new episode should email the recipient');
        System.assertEquals(
            1,
            FimbyTransactionalEmailService.testSendInvocationCount,
            'A recipient who turned email alerts off must not be emailed'
        );
        System.assertEquals(
            2,
            [
                SELECT COUNT() FROM Notification__c
                WHERE Contact__c = :peeps[1].Id
                  AND Type__c = :FimbyConstants.NOTIF_CONTACT_INFO_SHARED
            ],
            'Opting out of email must not silence the in-app bell'
        );
    }

    @IsTest
    static void emailCarriesSurfaceContextAndAddress() {
        List<Contact> peeps = getContacts();

        Test.startTest();
        FimbyTransactionalEmailService.testSendInvocationCount = 0;
        FimbySharedContactService.ShareRequest request = baseRequest(peeps[0].Id, peeps[1].Id);
        request.shareAddress = true;
        request.street = '12 Maple Lane';
        request.city = 'Vancouver';
        request.provinceState = 'BC';
        request.postalCode = 'V5K 0A1';
        request.emailContextLabel = 'Lending item';
        FimbySharedContactService.saveActiveEpisode(request);
        Test.stopTest();

        System.assertEquals(1, FimbyTransactionalEmailService.testSendInvocationCount);
        String card = FimbyTransactionalEmailService.testLastCardHtml;
        System.assert(card.contains('Lending item'), 'Card should carry the surface context');
        System.assert(
            card.contains('12 Maple Lane, Vancouver, BC, V5K 0A1'),
            'Card should show the full shared address on one line, got: ' + card
        );
        System.assert(
            FimbyTransactionalEmailService.testLastSubject.endsWith('shared their contact info with you'),
            'Subject should name the sharer, got: ' + FimbyTransactionalEmailService.testLastSubject
        );
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
