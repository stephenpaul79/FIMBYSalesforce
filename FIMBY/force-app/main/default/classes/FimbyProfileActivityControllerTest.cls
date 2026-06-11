@IsTest
private class FimbyProfileActivityControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(neighbourhood.Id, 2, true);
        Contact owner = contacts[0];
        Contact viewer = contacts[1];
        FimbyTestDataFactory.createCommunityUser(viewer.Id, 'Customer Community User - Mobile App', true);

        FimbyTestDataFactory.createStories(neighbourhood.Id, owner.Id, 2, true);
        FimbyTestDataFactory.createAskOfferItems(neighbourhood.Id, owner.Id, 2, true);
        FimbyTestDataFactory.createLibraryItems(neighbourhood.Id, owner.Id, 1, true);
    }

    private static User getCommunityUser() {
        Account nh = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        List<User> users = [
            SELECT Id, ContactId
            FROM User
            WHERE IsActive = true
              AND ContactId IN (SELECT Id FROM Contact WHERE AccountId = :nh.Id)
            LIMIT 1
        ];
        System.assert(!users.isEmpty(), 'Test setup must create a community user.');
        return users[0];
    }

    private static Contact getOwnerContact() {
        Account nh = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        List<Contact> contacts = [
            SELECT Id FROM Contact
            WHERE AccountId = :nh.Id
            ORDER BY CreatedDate ASC
        ];
        System.assert(!contacts.isEmpty(), 'Test setup must create owner contact.');
        return contacts[0];
    }

    @IsTest
    static void testGetProfileActivity_sameNeighbourhood() {
        Contact owner = getOwnerContact();
        User viewerUser = getCommunityUser();

        Test.startTest();
        System.runAs(viewerUser) {
            FimbyProfileActivityController.ProfileActivityResult result =
                FimbyProfileActivityController.getProfileActivity(owner.Id, 0, 20);

            System.assertNotEquals(null, result);
            System.assert(result.totalCount >= 5, 'Should include stories, asks/offers, and library');
            System.assert(result.items.size() > 0, 'Should return at least one row');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetProfileActivity_deniedCrossNeighbourhood() {
        Account otherNeighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        otherNeighbourhood.Name = 'Other Neighbourhood';
        update otherNeighbourhood;

        Contact remoteOwner = FimbyTestDataFactory.createNeighbourhoodContact(otherNeighbourhood.Id, true);
        FimbyTestDataFactory.createStories(otherNeighbourhood.Id, remoteOwner.Id, 1, true);

        User viewerUser = getCommunityUser();

        Test.startTest();
        System.runAs(viewerUser) {
            FimbyProfileActivityController.ProfileActivityResult result =
                FimbyProfileActivityController.getProfileActivity(remoteOwner.Id, 0, 20);

            System.assertEquals(0, result.totalCount, 'Cross-neighbourhood contact without shared link is denied');
            System.assertEquals(true, result.items.isEmpty());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetProfileActivity_pagination() {
        Contact owner = getOwnerContact();
        User viewerUser = getCommunityUser();

        Test.startTest();
        System.runAs(viewerUser) {
            FimbyProfileActivityController.ProfileActivityResult page1 =
                FimbyProfileActivityController.getProfileActivity(owner.Id, 0, 2);
            FimbyProfileActivityController.ProfileActivityResult page2 =
                FimbyProfileActivityController.getProfileActivity(owner.Id, 2, 2);

            System.assertEquals(2, page1.items.size());
            System.assert(page1.hasMore, 'More items should remain');
            System.assert(page2.items.size() > 0, 'Second page should return rows');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetProfileActivity_excludesModeratedAndInactive() {
        Contact owner = getOwnerContact();
        Account nh = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];

        Story__c hiddenStory = new Story__c(
            Name = 'Hidden Story',
            Message__c = 'Hidden',
            Type__c = 'Bio',
            Neighbourhood__c = nh.Id,
            Posted_By__c = owner.Id,
            Moderation_Status__c = 'Hidden_By_Moderator'
        );
        insert hiddenStory;

        Needs_Offers__c expiredPost = new Needs_Offers__c(
            Name = 'Expired Post',
            Details__c = 'Expired',
            Type__c = 'Goods - Unperishable',
            Status__c = 'Expired',
            Neighbourhood__c = nh.Id,
            Posted_By__c = owner.Id,
            Contact__c = owner.Id
        );
        insert expiredPost;

        User viewerUser = getCommunityUser();

        Test.startTest();
        System.runAs(viewerUser) {
            FimbyProfileActivityController.ProfileActivityResult result =
                FimbyProfileActivityController.getProfileActivity(owner.Id, 0, 50);

            for (FimbyFeedItem item : result.items) {
                System.assertNotEquals(hiddenStory.Id, item.recordId);
                System.assertNotEquals(expiredPost.Id, item.recordId);
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetProfileActivity_blockedContactEmpty() {
        Contact owner = getOwnerContact();
        User viewerUser = getCommunityUser();
        Id viewerContactId = viewerUser.ContactId;

        insert new Blocked_Contact__c(
            Blocker__c = viewerContactId,
            Blocked__c = owner.Id
        );

        Test.startTest();
        System.runAs(viewerUser) {
            FimbyProfileActivityController.ProfileActivityResult result =
                FimbyProfileActivityController.getProfileActivity(owner.Id, 0, 20);

            System.assertEquals(0, result.totalCount);
        }
        Test.stopTest();
    }

    @IsTest
    static void testContactVisibility_canViewSameNeighbourhood() {
        Contact owner = getOwnerContact();
        User viewerUser = getCommunityUser();

        Test.startTest();
        System.runAs(viewerUser) {
            System.assertEquals(
                true,
                FimbyContactVisibility.canView(viewerUser.ContactId, owner.Id),
                'Same-neighbourhood contacts should be visible'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testContactVisibility_selfNullAndOrgContact() {
        User viewerUser = getCommunityUser();
        Account nh = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];

        Account org;
        Contact orgContact;
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        org = new Account(
            Name = 'C4 Activity Org',
            RecordTypeId = orgRtId,
            Is_Approved_Community_Group__c = true,
            Type = 'Community Group'
        );
        insert org;

        orgContact = new Contact(
            LastName = 'Org Voice',
            AccountId = nh.Id,
            Is_Organization_Contact__c = true,
            Organization_Account__c = org.Id
        );
        insert orgContact;
        update new Account(Id = org.Id, Organization_Contact__c = orgContact.Id);

        insert new Community_Group_Neighbourhood__c(
            Organization__c = org.Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Active'
        );

        Test.startTest();
        System.runAs(viewerUser) {
            System.assertEquals(false, FimbyContactVisibility.canView(null, viewerUser.ContactId));
            System.assertEquals(true, FimbyContactVisibility.canView(viewerUser.ContactId, viewerUser.ContactId));
            System.assertEquals(
                true,
                FimbyContactVisibility.canView(viewerUser.ContactId, orgContact.Id),
                'Org contact linked to viewer neighbourhood should be visible'
            );
        }
        Test.stopTest();
    }
}
