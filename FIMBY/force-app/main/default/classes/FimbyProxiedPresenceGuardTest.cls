@IsTest
private class FimbyProxiedPresenceGuardTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> peeps = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 3, true);

        // peeps[0] is the guardian and the only one with a login. peeps[2] becomes the
        // parent-managed child, which is exactly the point: a child never gets a User.
        FimbyTestDataFactory.createCommunityUser(peeps[0].Id, null, true);
        FimbyTestDataFactory.createCommunityUser(peeps[1].Id, null, true);

        update new Contact(Id = peeps[2].Id, Is_Parent_Proxied__c = true);

        insert new Support_Relationship__c(
            Contact__c = peeps[0].Id,
            Related_Contact__c = peeps[2].Id,
            Relationship_Type__c = 'Parent_Guardian',
            Neighbourhood__c = nh.Id,
            Status__c = 'Approved',
            Consent_Method__c = 'Guardian'
        );
    }

    private static List<Contact> getContacts() {
        return [
            SELECT Id, AccountId, Is_Parent_Proxied__c
            FROM Contact
            WHERE AccountId != null
            ORDER BY CreatedDate ASC
        ];
    }

    private static Contact guardian() {
        return getContacts()[0];
    }

    private static Contact neighbour() {
        return getContacts()[1];
    }

    private static Contact child() {
        return getContacts()[2];
    }

    private static FimbySharedContactService.ShareRequest shareRequest(Id sharerId, Id recipientId) {
        FimbySharedContactService.ShareRequest request = new FimbySharedContactService.ShareRequest();
        request.sharerContactId = sharerId;
        request.recipientContactId = recipientId;
        request.origin = 'My Neighbours';
        request.writeMode = FimbySharedContactService.MODE_REPLACE;
        request.shareEmail = true;
        request.email = 'grown.up@test.com';
        return request;
    }

    @IsTest
    static void aChildIsAPersonNotAnOrganization() {
        System.assertEquals(
            true,
            FimbyProxiedPresenceGuard.isContactBackedRelationship('Parent_Guardian'),
            'A parent-managed child is a contact-backed supportee, like an elder neighbour'
        );
        System.assertEquals(
            true,
            FimbyProxiedPresenceGuard.isContactBackedRelationship('Support_Person')
        );
        System.assertEquals(
            false,
            FimbyProxiedPresenceGuard.isOrganizationBackedRelationship('Parent_Guardian'),
            'Falling into the organization branch would hand a child an organization\'s capabilities'
        );
        System.assertEquals(
            true,
            FimbyProxiedPresenceGuard.isOrganizationBackedRelationship('Community_Group_Rep')
        );
    }

    @IsTest
    static void anUnknownRelationshipTypeFailsClosedOnBothSides() {
        System.assertEquals(
            false,
            FimbyProxiedPresenceGuard.isContactBackedRelationship('Some_Future_Type')
        );
        System.assertEquals(
            false,
            FimbyProxiedPresenceGuard.isOrganizationBackedRelationship('Some_Future_Type'),
            'An unrecognised type must not inherit organization behaviour by default'
        );
        System.assertEquals(false, FimbyProxiedPresenceGuard.isContactBackedRelationship(null));
        System.assertEquals(false, FimbyProxiedPresenceGuard.isOrganizationBackedRelationship(null));
    }

    @IsTest
    static void proxiedContactsAreResolvedInOneQueryAndAdultsAreNot() {
        // Resolved before the measured window, or the helpers' own SOQL is counted.
        Contact kid = child();
        Contact grownUp = guardian();
        Contact other = neighbour();

        Test.startTest();
        Integer before = Limits.getQueries();
        Set<Id> proxied = FimbyProxiedPresenceGuard.proxiedAmong(
            new Set<Id>{ kid.Id, grownUp.Id, other.Id }
        );
        Integer used = Limits.getQueries() - before;
        // A second ask must be free, or a trigger over 200 rows would pay repeatedly.
        FimbyProxiedPresenceGuard.proxiedAmong(new Set<Id>{ kid.Id, grownUp.Id });
        Integer usedAfterCache = Limits.getQueries() - before;
        Test.stopTest();

        System.assertEquals(1, proxied.size(), 'Only the child is parent-managed');
        System.assert(proxied.contains(kid.Id));
        System.assertEquals(1, used, 'Three contacts must cost exactly one query');
        System.assertEquals(1, usedAfterCache, 'A repeat check must be served from cache');

        System.assertEquals(true, FimbyProxiedPresenceGuard.isProxied(kid.Id));
        System.assertEquals(false, FimbyProxiedPresenceGuard.isProxied(grownUp.Id));
        System.assertEquals(false, FimbyProxiedPresenceGuard.isProxied(null));
        System.assertEquals(0, FimbyProxiedPresenceGuard.proxiedAmong(null).size());
    }

    @IsTest
    static void theServiceRefusesAChildAsTheSharer() {
        String message;
        Test.startTest();
        try {
            FimbySharedContactService.saveActiveEpisode(shareRequest(child().Id, neighbour().Id));
            System.assert(false, 'A parent-managed child must never disclose contact details outward');
        } catch (FimbySharedContactService.SharedContactException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        System.assertEquals(FimbyProxiedPresenceGuard.OUTBOUND_SHARE_REFUSAL, message);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Shared_Contact_Info__c WHERE Contact__c = :child().Id],
            'The refusal must happen before any row is written'
        );
    }

    @IsTest
    static void anAdultMayStillShareTheirOwnDetailsWithAChild() {
        Test.startTest();
        FimbySharedContactService.ShareResult saved =
            FimbySharedContactService.saveActiveEpisode(shareRequest(neighbour().Id, child().Id));
        Test.stopTest();

        System.assertNotEquals(null, saved.sharedContactInfoId);
        System.assertEquals(true, saved.createdNewEpisode);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Shared_Contact_Info__c
                WHERE Shared_To__c = :child().Id AND Status__c = 'Active'
            ],
            'Receiving an adult\'s grant is the one direction that stays open to a child'
        );
    }

    @IsTest
    static void theTriggerRefusesAChildSharerThatBypassedTheService() {
        String message;
        Test.startTest();
        try {
            // System mode still fires triggers, so this proves the invariant rather
            // than accidentally testing the running user's field permissions.
            Database.insert(
                new Shared_Contact_Info__c(
                    Contact__c = child().Id,
                    Shared_To__c = neighbour().Id,
                    Email__c = 'should.not.exist@test.com',
                    Status__c = 'Active'
                ),
                AccessLevel.SYSTEM_MODE
            );
            System.assert(false, 'The object-level invariant must catch a direct write');
        } catch (DmlException e) {
            message = e.getDmlMessage(0);
        }
        Test.stopTest();

        System.assertEquals(FimbyProxiedPresenceGuard.OUTBOUND_SHARE_INVARIANT, message);
    }

    @IsTest
    static void aChildSharerRowThatSlippedThroughCanStillBeRevoked() {
        // Seed the row the invariant is meant to prevent, as a historical import would.
        FimbySharedContactService.skipTrigger = true;
        Shared_Contact_Info__c legacy = new Shared_Contact_Info__c(
            Contact__c = child().Id,
            Shared_To__c = neighbour().Id,
            Email__c = 'legacy@test.com',
            Status__c = 'Active'
        );
        Database.insert(legacy, AccessLevel.SYSTEM_MODE);
        FimbySharedContactService.skipTrigger = false;

        Test.startTest();
        Database.update(
            new Shared_Contact_Info__c(Id = legacy.Id, Status__c = 'Revoked'),
            AccessLevel.SYSTEM_MODE
        );
        Test.stopTest();

        Shared_Contact_Info__c after = [
            SELECT Status__c, Consent_Closed_Date__c
            FROM Shared_Contact_Info__c
            WHERE Id = :legacy.Id
            WITH SYSTEM_MODE
        ];
        System.assertEquals(
            'Revoked',
            after.Status__c,
            'Blocking every save would trap a bad row open, which is worse than the row itself'
        );
        System.assertNotEquals(null, after.Consent_Closed_Date__c);
    }

    @IsTest
    static void contactDetailsAreProhibitedButANameAndPhotoAreNot() {
        System.assertEquals(
            true,
            FimbyProxiedPresenceGuard.hasProhibitedChildPii(new Contact(Email = 'maya@test.com'))
        );
        System.assertEquals(
            true,
            FimbyProxiedPresenceGuard.hasProhibitedChildPii(new Contact(MobilePhone = '0400111222'))
        );
        System.assertEquals(
            true,
            FimbyProxiedPresenceGuard.hasProhibitedChildPii(new Contact(MailingCity = 'Vancouver'))
        );
        System.assertEquals(
            false,
            FimbyProxiedPresenceGuard.hasProhibitedChildPii(
                new Contact(FirstName = 'Maya', Image_URL__c = 'https://example.com/maya.png')
            ),
            'A first name and a photo are the whole point of a child profile'
        );
        System.assertEquals(
            false,
            FimbyProxiedPresenceGuard.hasProhibitedChildPii(new Contact(Email = '   ')),
            'Whitespace is not contact information'
        );
        System.assertEquals(false, FimbyProxiedPresenceGuard.hasProhibitedChildPii(null));
    }

    @IsTest
    static void actingAsAChildIsDetectedAndActingAsYourselfIsNot() {
        Contact kid = child();
        User guardianUser = [
            SELECT Id, ContactId FROM User WHERE ContactId = :guardian().Id AND IsActive = true LIMIT 1
        ];

        Test.startTest();
        System.runAs(guardianUser) {
            FimbyIdentityRepository.clearCache();
            FimbyProxiedPresenceGuard.clearCache();
            System.assertEquals(
                false,
                FimbyProxiedPresenceGuard.isActingAsProxiedChild(),
                'A guardian acting as themselves keeps every ordinary capability'
            );
        }

        // Applied as the admin rather than inside runAs: production performs the switch
        // through a privileged helper, so making the test depend on the community
        // profile's field permissions would be testing the wrong thing.
        update new Contact(Id = guardian().Id, Logged_In_As_Contact__c = kid.Id);

        System.runAs(guardianUser) {
            FimbyIdentityRepository.clearCache();
            FimbyProxiedPresenceGuard.clearCache();
            System.assertEquals(
                true,
                FimbyProxiedPresenceGuard.isActingAsProxiedChild(),
                'Switched into the child, outbound share surfaces must be refused'
            );
        }
        Test.stopTest();
    }
}
