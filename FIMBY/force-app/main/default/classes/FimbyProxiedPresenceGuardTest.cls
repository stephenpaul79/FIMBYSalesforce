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

        // The factory seeds every Contact with an email. A real parent-managed profile
        // is created without one, and clearing it here is what makes the PII assertions
        // test the guard rather than the fixture.
        update new Contact(
            Id = peeps[2].Id,
            Is_Parent_Proxied__c = true,
            Email = null,
            Phone = null
        );

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

    /**
     * The label a thread shows is the whole point of this resolver: calling a supported
     * adult "parent-managed" would tell a neighbour with full agency that they are a
     * child. Both branches are asserted together so one can never drift into the other.
     */
    @IsTest
    static void proxyTypesDistinguishAManagedChildFromASupportedAdult() {
        Contact kid = child();
        Contact supportedAdult = neighbour();
        Contact grownUp = guardian();

        insert new Support_Relationship__c(
            Contact__c = grownUp.Id,
            Related_Contact__c = supportedAdult.Id,
            Relationship_Type__c = 'Support_Person',
            Neighbourhood__c = grownUp.AccountId,
            Status__c = 'Approved',
            Consent_Method__c = 'Verbal'
        );
        FimbyProxiedPresenceGuard.clearCache();

        Test.startTest();
        Map<Id, String> resolved = FimbyProxiedPresenceGuard.resolveProxyTypes(
            new Set<Id>{ kid.Id, supportedAdult.Id, grownUp.Id }
        );
        Test.stopTest();

        System.assertEquals(
            FimbyProxiedPresenceGuard.PROXY_TYPE_PARENT_MANAGED,
            resolved.get(kid.Id),
            'A parent-managed child must never be labelled as merely supported'
        );
        System.assertEquals(
            FimbyProxiedPresenceGuard.PROXY_TYPE_SUPPORTED,
            resolved.get(supportedAdult.Id),
            'An adult with an approved support person is supported, not parent-managed'
        );
        System.assertEquals(
            false,
            resolved.containsKey(grownUp.Id),
            'A neighbour nobody speaks for must be absent, so containsKey is a safe test'
        );
    }

    @IsTest
    static void parentManagedOutranksSupportedForTheSameChild() {
        Contact kid = child();
        // A child may also have a support person. They are still a child, and that is
        // the fact a reader needs — so the stronger label must win.
        insert new Support_Relationship__c(
            Contact__c = neighbour().Id,
            Related_Contact__c = kid.Id,
            Relationship_Type__c = 'Support_Person',
            Neighbourhood__c = kid.AccountId,
            Status__c = 'Approved',
            Consent_Method__c = 'Verbal'
        );
        FimbyProxiedPresenceGuard.clearCache();

        Test.startTest();
        Map<Id, String> resolved =
            FimbyProxiedPresenceGuard.resolveProxyTypes(new Set<Id>{ kid.Id });
        Test.stopTest();

        System.assertEquals(
            FimbyProxiedPresenceGuard.PROXY_TYPE_PARENT_MANAGED,
            resolved.get(kid.Id)
        );
    }

    @IsTest
    static void anUnapprovedSupportRelationshipDoesNotLabelAnyone() {
        Contact supportedAdult = neighbour();
        insert new Support_Relationship__c(
            Contact__c = guardian().Id,
            Related_Contact__c = supportedAdult.Id,
            Relationship_Type__c = 'Support_Person',
            Neighbourhood__c = supportedAdult.AccountId,
            Status__c = 'Pending Verification',
            Consent_Method__c = 'Verbal'
        );
        FimbyProxiedPresenceGuard.clearCache();

        Test.startTest();
        Map<Id, String> resolved =
            FimbyProxiedPresenceGuard.resolveProxyTypes(new Set<Id>{ supportedAdult.Id });
        Test.stopTest();

        System.assertEquals(
            false,
            resolved.containsKey(supportedAdult.Id),
            'A request nobody approved must not announce that someone speaks for them'
        );
    }

    @IsTest
    static void repeatedProxyTypeLookupsAreServedFromCache() {
        Contact kid = child();
        Contact grownUp = guardian();
        FimbyProxiedPresenceGuard.clearCache();

        Test.startTest();
        Integer before = Limits.getQueries();
        FimbyProxiedPresenceGuard.resolveProxyTypes(new Set<Id>{ kid.Id, grownUp.Id });
        Integer firstPass = Limits.getQueries() - before;
        FimbyProxiedPresenceGuard.resolveProxyTypes(new Set<Id>{ kid.Id, grownUp.Id });
        Integer afterCache = Limits.getQueries() - before;
        Test.stopTest();

        System.assertEquals(
            firstPass,
            afterCache,
            'A thread re-asking about the same senders on every page must cost nothing'
        );
        System.assertEquals(0, FimbyProxiedPresenceGuard.resolveProxyTypes(null).size());
        System.assertEquals(
            0,
            FimbyProxiedPresenceGuard.resolveProxyTypes(new Set<Id>()).size()
        );
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
    static void aProfileEditCannotPutContactDetailsOnAChild() {
        Contact kid = child();
        User guardianUser = [
            SELECT Id, ContactId FROM User WHERE ContactId = :guardian().Id AND IsActive = true LIMIT 1
        ];
        update new Contact(Id = guardian().Id, Logged_In_As_Contact__c = kid.Id);

        Boolean refused = false;
        Test.startTest();
        System.runAs(guardianUser) {
            FimbyIdentityRepository.clearCache();
            FimbyProxiedPresenceGuard.clearCache();
            try {
                FimbyProfileController.updateProfileSection(
                    new Map<String, String>{ 'Email' => 'maya@test.com' }
                );
            } catch (Exception e) {
                // The controller rewraps everything as AuraHandledException, whose
                // getMessage() is 'Script-thrown exception' in a test context, so the
                // message text cannot identify the cause. The control edit below is
                // what proves the refusal came from Is_Parent_Proxied__c.
                refused = true;
            }

            // A non-contact field stays editable, or a guardian could not maintain the
            // profile they are responsible for.
            FimbyProfileController.updateProfileSection(
                new Map<String, String>{ 'Pronouns__c' => 'she/her' }
            );
        }

        Contact midway = [SELECT Email FROM Contact WHERE Id = :kid.Id WITH SYSTEM_MODE];

        // Control: the identical edit succeeds the moment the profile is no longer
        // parent-managed. Without this, the test would only prove that something threw.
        update new Contact(Id = kid.Id, Is_Parent_Proxied__c = false);
        System.runAs(guardianUser) {
            FimbyIdentityRepository.clearCache();
            FimbyProxiedPresenceGuard.clearCache();
            FimbyProfileController.updateProfileSection(
                new Map<String, String>{ 'Email' => 'maya@test.com' }
            );
        }
        Test.stopTest();

        System.assertEquals(true, refused, 'A child profile must never hold a reachable email address');
        System.assertEquals(null, midway.Email, 'The refused edit must not have been written');

        Contact after = [SELECT Email, Pronouns__c FROM Contact WHERE Id = :kid.Id WITH SYSTEM_MODE];
        System.assertEquals('she/her', after.Pronouns__c, 'A non-contact field must stay editable');
        System.assertEquals(
            'maya@test.com',
            after.Email,
            'The control edit must succeed, isolating the refusal to Is_Parent_Proxied__c'
        );
    }

    @IsTest
    static void aChildIsNeverOfferedAsAVoucher() {
        Contact kid = child();
        Contact grownUp = neighbour();
        // Stamp the state that should be impossible. If the Track A attestation guard
        // ever regressed, the voucher list must still refuse to offer a child.
        update new List<Contact>{
            new Contact(Id = kid.Id, Vouched_Status__c = 'Vouched'),
            new Contact(Id = grownUp.Id, Vouched_Status__c = 'Vouched')
        };

        Contact kidNamed = [SELECT Id, Name FROM Contact WHERE Id = :kid.Id];
        Contact adultNamed = [SELECT Id, Name FROM Contact WHERE Id = :grownUp.Id];
        User guardianUser = [
            SELECT Id, ContactId FROM User WHERE ContactId = :guardian().Id AND IsActive = true LIMIT 1
        ];

        List<FimbyVouchController.VoucherOption> childHits;
        List<FimbyVouchController.VoucherOption> adultHits;
        Test.startTest();
        System.runAs(guardianUser) {
            FimbyIdentityRepository.clearCache();
            childHits = FimbyVouchController.searchVouchers(kidNamed.Name, 'peer');
            adultHits = FimbyVouchController.searchVouchers(adultNamed.Name, 'peer');
        }
        Test.stopTest();

        System.assertEquals(0, childHits.size(), 'A parent-managed child is never an eligible voucher');
        System.assertEquals(
            1,
            adultHits.size(),
            'An ordinary vouched neighbour must still be offered, or the filter is too broad'
        );
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

    private static String libraryItemPayload() {
        return JSON.serialize(new Map<String, Object>{
            'title' => 'Cordless drill',
            'description' => 'Charged, with a full bit set.',
            'category' => 'Tools',
            'maxLendingDays' => 7
        });
    }

    private static String skillPayload() {
        return JSON.serialize(new List<Map<String, Object>>{
            new Map<String, Object>{
                'category' => 'Yard & Outdoor Work',
                'title' => 'Raking leaves',
                'description' => 'Happy to help on weekends.'
            }
        });
    }

    /**
     * A listing is a standing invitation to strangers that outlives the moment, and its
     * coordination happens in a thread with no shared context. The guardian lists under
     * their own name instead — so the same payload must succeed for them and fail for
     * the child, which is what separates a real guard from a broken create path.
     */
    @IsTest
    static void aChildCannotListAnItemButTheirGuardianStillCan() {
        Contact kid = child();
        User guardianUser = [
            SELECT Id, ContactId FROM User WHERE ContactId = :guardian().Id AND IsActive = true LIMIT 1
        ];

        Map<String, Object> createdAsSelf;
        Boolean refusedAsChild = false;

        Test.startTest();
        System.runAs(guardianUser) {
            FimbyIdentityRepository.clearCache();
            FimbyProxiedPresenceGuard.clearCache();
            createdAsSelf = FimbyLibraryController.createLibraryItem(libraryItemPayload());
        }

        update new Contact(Id = guardian().Id, Logged_In_As_Contact__c = kid.Id);

        System.runAs(guardianUser) {
            FimbyIdentityRepository.clearCache();
            FimbyProxiedPresenceGuard.clearCache();
            try {
                FimbyLibraryController.createLibraryItem(libraryItemPayload());
            } catch (Exception e) {
                refusedAsChild = true;
            }
        }
        Test.stopTest();

        System.assertNotEquals(null, createdAsSelf, 'A guardian listing under their own name is ordinary use');
        System.assertEquals(true, refusedAsChild, 'A parent-managed child must not own a listing');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Library_Item__c WHERE Owner_Contact__c = :kid.Id],
            'The refused create must not have written a row owned by the child'
        );
    }

    @IsTest
    static void aChildCannotOfferASkillButTheirGuardianStillCan() {
        Contact kid = child();
        User guardianUser = [
            SELECT Id, ContactId FROM User WHERE ContactId = :guardian().Id AND IsActive = true LIMIT 1
        ];

        Boolean refusedAsChild = false;

        Test.startTest();
        System.runAs(guardianUser) {
            FimbyIdentityRepository.clearCache();
            FimbyProxiedPresenceGuard.clearCache();
            FimbySkillsController.saveSkillOffers(skillPayload());
        }

        update new Contact(Id = guardian().Id, Logged_In_As_Contact__c = kid.Id);

        System.runAs(guardianUser) {
            FimbyIdentityRepository.clearCache();
            FimbyProxiedPresenceGuard.clearCache();
            try {
                FimbySkillsController.saveSkillOffers(skillPayload());
            } catch (Exception e) {
                refusedAsChild = true;
            }
        }
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Skill_Offer__c WHERE Owner_Contact__c = :guardian().Id],
            'A guardian offering their own skill is ordinary use'
        );
        System.assertEquals(true, refusedAsChild, 'A parent-managed child must not offer a skill');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Skill_Offer__c WHERE Owner_Contact__c = :kid.Id],
            'The refused save must not have written a row owned by the child'
        );
    }

    /**
     * The regression this protects against is silent: reading Parent_Guardian through
     * the organization branch yields a null name and avatar, so the child would simply
     * be missing from Manage Identities with no error anywhere.
     */
    @IsTest
    static void aChildAppearsAsASwitchableIdentityWithTheirOwnName() {
        Contact kid = [SELECT Id, Full_Name__c FROM Contact WHERE Id = :child().Id];
        User guardianUser = [
            SELECT Id, ContactId FROM User WHERE ContactId = :guardian().Id AND IsActive = true LIMIT 1
        ];

        List<Map<String, Object>> identities;
        Test.startTest();
        System.runAs(guardianUser) {
            FimbyIdentityRepository.clearCache();
            identities = FimbySupportRelationshipController.getAvailableIdentities();
        }
        Test.stopTest();

        System.assertEquals(1, identities.size(), 'The guardian can act as exactly one child');
        System.assertEquals(
            kid.Id,
            identities[0].get('targetContactId'),
            'A contact-backed relationship must resolve to the related Contact, not an organization'
        );
        System.assertEquals(
            kid.Full_Name__c,
            identities[0].get('name'),
            'Reading a child through the organization branch leaves the name blank'
        );
    }
}
