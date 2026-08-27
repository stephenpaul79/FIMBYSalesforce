@IsTest
private class FimbyParentGuardianServiceTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> peeps = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        FimbyTestDataFactory.createCommunityUser(peeps[0].Id, null, true);
    }

    private static Contact guardian() {
        return [SELECT Id, Name, LastName, AccountId FROM Contact WHERE AccountId != null LIMIT 1];
    }

    private static User guardianUser() {
        return [SELECT Id, ContactId FROM User WHERE ContactId = :guardian().Id AND IsActive = true LIMIT 1];
    }

    private static FimbyParentGuardianService.FamilyMemberInput input(String name, Date dob, Boolean attested) {
        FimbyParentGuardianService.FamilyMemberInput req = new FimbyParentGuardianService.FamilyMemberInput();
        req.firstName = name;
        req.birthdate = dob;
        req.attested = attested;
        return req;
    }

    private static String refusalFor(FimbyParentGuardianService.FamilyMemberInput req) {
        try {
            FimbyParentGuardianService.createFamilyMember(req);
            return null;
        } catch (Exception e) {
            return e.getMessage();
        }
    }

    /**
     * The whole point of the record is that it proves what was agreed to. A profile
     * created without the attestation, its version, and the guardian's own Id on it is
     * a profile with no legal basis, so this asserts the stamps and not merely the row.
     */
    @IsTest
    static void creatingAFamilyMemberStampsTheAttestationAndApprovesImmediately() {
        Contact parent = guardian();
        Date twelveYearsAgo = Date.today().addYears(-12);

        FimbyParentGuardianService.FamilyMemberResult result;
        Test.startTest();
        System.runAs(guardianUser()) {
            FimbyIdentityRepository.clearCache();
            result = FimbyParentGuardianService.createFamilyMember(
                input('Maya', twelveYearsAgo, true)
            );
        }
        Test.stopTest();

        Contact child = [
            SELECT Id, FirstName, LastName, Birthdate, Email, Phone,
                   Is_Parent_Proxied__c, Is_Minor__c, Proxied_By_Contact__c
            FROM Contact WHERE Id = :result.contactId
        ];
        System.assertEquals('Maya', child.FirstName);
        System.assertEquals(parent.LastName, child.LastName, 'A child carries the family name, not a bare first name');
        System.assertEquals(true, child.Is_Parent_Proxied__c);
        System.assertEquals(true, child.Is_Minor__c);
        System.assertEquals(parent.Id, child.Proxied_By_Contact__c);
        System.assertEquals(null, child.Email, 'A parent-managed profile is created with no reachable contact details');
        System.assertEquals(null, child.Phone);

        Support_Relationship__c rel = [
            SELECT Id, Relationship_Type__c, Status__c, Consent_Method__c, Contact__c,
                   Related_Contact__c, Approved_By__c, Guardian_Attested__c,
                   Guardian_Attested_By_Contact__c, Guardian_Attestation_Version__c,
                   Guardian_Echo_Confirmed__c
            FROM Support_Relationship__c WHERE Id = :result.relationshipId
        ];
        System.assertEquals('Parent_Guardian', rel.Relationship_Type__c);
        System.assertEquals('Approved', rel.Status__c, 'Nobody waits in a queue to be a parent');
        System.assertEquals('Guardian', rel.Consent_Method__c);
        System.assertEquals(parent.Id, rel.Contact__c);
        System.assertEquals(child.Id, rel.Related_Contact__c);
        System.assertEquals(true, rel.Guardian_Attested__c);
        System.assertEquals(parent.Id, rel.Guardian_Attested_By_Contact__c);
        System.assertEquals(
            FimbySettings.guardianAttestationVersion(),
            rel.Guardian_Attestation_Version__c,
            'Without the version the record proves only that something was agreed to'
        );
        System.assertEquals(false, rel.Guardian_Echo_Confirmed__c, 'The echo is confirmed by the guardian, not by us');
    }

    /**
     * Silently gaining a second identity is what a compromised account would want. The
     * receipt is what makes it loud, and the passive task is what guarantees a human
     * eventually sees the profile without anyone being blocked.
     */
    @IsTest
    static void creatingAFamilyMemberLeavesAReceiptAndAPassiveReview() {
        Contact parent = guardian();

        Test.startTest();
        System.runAs(guardianUser()) {
            FimbyIdentityRepository.clearCache();
            FimbyParentGuardianService.createFamilyMember(input('Maya', Date.today().addYears(-9), true));
        }
        Test.stopTest();

        List<Notification__c> receipts = [
            SELECT Id, Title__c, Body__c, Action_URL__c
            FROM Notification__c
            WHERE Contact__c = :parent.Id
        ];
        System.assertEquals(1, receipts.size(), 'The guardian must be told a new identity now exists');
        System.assertEquals(true, receipts[0].Title__c.contains('Maya'), 'The receipt names the child');
        System.assertEquals(
            true,
            receipts[0].Body__c.contains('didn\'t do this'),
            'A receipt that does not tell you what to do when it was not you is not a security receipt'
        );

        List<Moderator_Task__c> tasks = [
            SELECT Id, Category__c, Subject_Contact__c, Secondary_Contact__c, Status__c
            FROM Moderator_Task__c
            WHERE Category__c = 'Parent_Managed_Profile'
        ];
        System.assertEquals(1, tasks.size(), 'A profile is never created without a human eventually seeing it');
        System.assertEquals(parent.Id, tasks[0].Subject_Contact__c);
    }

    @IsTest
    static void aGuardianCanConfirmTheirOwnProfileButNobodyElseCan() {
        Contact parent = guardian();
        Account nh = [SELECT Id FROM Account WHERE Id = :parent.AccountId];
        List<Contact> others = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        User stranger = FimbyTestDataFactory.createCommunityUser(others[0].Id, null, true);

        FimbyParentGuardianService.FamilyMemberResult result;
        System.runAs(guardianUser()) {
            FimbyIdentityRepository.clearCache();
            result = FimbyParentGuardianService.createFamilyMember(input('Maya', Date.today().addYears(-14), true));
        }

        Boolean strangerRefused = false;
        Test.startTest();
        System.runAs(stranger) {
            FimbyIdentityRepository.clearCache();
            try {
                FimbyParentGuardianService.confirmGuardianEcho(result.relationshipId);
            } catch (Exception e) {
                strangerRefused = true;
            }
        }

        System.runAs(guardianUser()) {
            FimbyIdentityRepository.clearCache();
            FimbyParentGuardianService.confirmGuardianEcho(result.relationshipId);
            // Confirming twice is what a double-tap looks like; it must not throw.
            FimbyParentGuardianService.confirmGuardianEcho(result.relationshipId);
        }
        Test.stopTest();

        System.assertEquals(true, strangerRefused, 'Only the guardian on the relationship may confirm it');
        Support_Relationship__c rel = [
            SELECT Guardian_Echo_Confirmed__c, Guardian_Echo_Confirmed_Date__c
            FROM Support_Relationship__c WHERE Id = :result.relationshipId
        ];
        System.assertEquals(true, rel.Guardian_Echo_Confirmed__c);
        System.assertNotEquals(null, rel.Guardian_Echo_Confirmed_Date__c);
    }

    /**
     * Each refusal is asserted through its own message rather than "something threw",
     * because these four inputs fail for four different reasons and a guard that
     * collapses them would still pass a weaker test.
     */
    @IsTest
    static void theProfileIsRefusedWhenTheBasisForItIsMissing() {
        Date childDob = Date.today().addYears(-10);

        Test.startTest();
        System.runAs(guardianUser()) {
            FimbyIdentityRepository.clearCache();

            System.assertEquals(
                true,
                refusalFor(input('', childDob, true)).contains('first name'),
                'A profile with no name is not a presence'
            );
            System.assertEquals(
                true,
                refusalFor(input('Maya', null, true)).contains('date of birth'),
                'Without a birthdate we cannot know this is a young person'
            );
            System.assertEquals(
                true,
                refusalFor(input('Maya', childDob, false)).contains('parent or guardian'),
                'The attestation is the entire legal basis; it cannot be optional'
            );
            System.assertEquals(
                true,
                refusalFor(input('Maya', Date.today().addYears(1), true)).contains('future'),
                'A birthdate in the future is a typo'
            );
        }
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Contact WHERE Is_Parent_Proxied__c = true],
            'No refused attempt may leave a partial profile behind'
        );
    }

    /**
     * The dangerous case: this path creates a durable, silent login-as over another
     * person. Allowing it for an adult would hand one neighbour that power over
     * another with no consent record anywhere.
     */
    @IsTest
    static void anAdultCannotBeTurnedIntoAParentManagedProfile() {
        String refusal;
        Test.startTest();
        System.runAs(guardianUser()) {
            FimbyIdentityRepository.clearCache();
            refusal = refusalFor(input('Grandma', Date.today().addYears(-72), true));
        }
        Test.stopTest();

        System.assertNotEquals(null, refusal, 'An adult must never be created as parent-managed');
        System.assertEquals(
            true,
            refusal.contains('support relationship'),
            'The refusal has to name the path that does fit, or the guardian is just stuck'
        );
        System.assertEquals(0, [SELECT COUNT() FROM Contact WHERE Is_Parent_Proxied__c = true]);
    }

    /** Exactly 19 today is an adult. The boundary is where this guard is worth testing. */
    @IsTest
    static void theAdultBoundaryIsCheckedOnTheDayItIsCrossed() {
        Test.startTest();
        System.runAs(guardianUser()) {
            FimbyIdentityRepository.clearCache();
            System.assertNotEquals(
                null,
                refusalFor(input('Just19', Date.today().addYears(-19), true)),
                'Someone who turns 19 today sets up their own profile'
            );
            System.assertEquals(
                null,
                refusalFor(input('Almost19', Date.today().addYears(-19).addDays(1), true)),
                'One day short of 19 is still a young person'
            );
        }
        Test.stopTest();
    }

    @isTest
    static void anyOneGuardianCanRemoveTheProfileAndTheOtherIsTold() {
        Contact parent = guardian();
        Account nh = [SELECT Id FROM Account WHERE Id = :parent.AccountId];
        List<Contact> others = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        Contact secondGuardian = others[0];

        FimbyParentGuardianService.FamilyMemberResult created;
        System.runAs(guardianUser()) {
            FimbyIdentityRepository.clearCache();
            created = FimbyParentGuardianService.createFamilyMember(
                input('Maya', Date.today().addYears(-11), true)
            );
        }

        // The second adult in the household holds the same mandate.
        insert new Support_Relationship__c(
            Relationship_Type__c = 'Parent_Guardian',
            Contact__c = secondGuardian.Id,
            Related_Contact__c = created.contactId,
            Neighbourhood__c = nh.Id,
            Status__c = 'Approved',
            Consent_Method__c = 'Guardian'
        );
        // And the requesting guardian is currently switched into the child.
        update new Contact(Id = parent.Id, Logged_In_As_Contact__c = created.contactId);

        Test.startTest();
        System.runAs(guardianUser()) {
            FimbyIdentityRepository.clearCache();
            FimbyParentGuardianService.deleteManagedProfile(created.contactId);
        }
        Test.stopTest();

        Contact child = [
            SELECT Deactivation_Requested__c FROM Contact WHERE Id = :created.contactId
        ];
        System.assertEquals(true, child.Deactivation_Requested__c,
            'The profile must be queued for erasure');

        System.assertEquals(null,
            [SELECT Logged_In_As_Contact__c FROM Contact WHERE Id = :parent.Id]
                .Logged_In_As_Contact__c,
            'Nobody may be left acting as a profile that is being erased');

        System.assertEquals(1,
            [SELECT COUNT() FROM Notification__c WHERE Contact__c = :secondGuardian.Id],
            'The other guardian loses access and must be told');
    }

    @isTest
    static void someoneWithNoMandateCannotRemoveAProfile() {
        Contact parent = guardian();
        Account nh = [SELECT Id FROM Account WHERE Id = :parent.AccountId];
        List<Contact> others = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        User stranger = FimbyTestDataFactory.createCommunityUser(others[0].Id, null, true);

        FimbyParentGuardianService.FamilyMemberResult created;
        System.runAs(guardianUser()) {
            FimbyIdentityRepository.clearCache();
            created = FimbyParentGuardianService.createFamilyMember(
                input('Sam', Date.today().addYears(-9), true)
            );
        }

        Boolean refused = false;
        Test.startTest();
        System.runAs(stranger) {
            FimbyIdentityRepository.clearCache();
            try {
                FimbyParentGuardianService.deleteManagedProfile(created.contactId);
            } catch (Exception e) {
                refused = true;
            }
        }
        Test.stopTest();

        System.assertEquals(true, refused, 'Only a guardian may remove the profile');
        System.assertEquals(false,
            [SELECT Deactivation_Requested__c FROM Contact WHERE Id = :created.contactId]
                .Deactivation_Requested__c,
            'A refused request must leave the profile untouched');
    }

    @isTest
    static void anOrdinaryContactCannotBeRemovedThroughTheFamilyPath() {
        Contact parent = guardian();
        Account nh = [SELECT Id FROM Account WHERE Id = :parent.AccountId];
        List<Contact> others = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        Contact adult = others[0];

        insert new Support_Relationship__c(
            Relationship_Type__c = 'Parent_Guardian',
            Contact__c = parent.Id,
            Related_Contact__c = adult.Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Approved',
            Consent_Method__c = 'Guardian'
        );

        Boolean refused = false;
        Test.startTest();
        System.runAs(guardianUser()) {
            FimbyIdentityRepository.clearCache();
            try {
                FimbyParentGuardianService.deleteManagedProfile(adult.Id);
            } catch (Exception e) {
                refused = true;
            }
        }
        Test.stopTest();

        System.assertEquals(true, refused,
            'An adult neighbour speaks for themselves and is not removable this way');
    }

    // ============================================================
    // eraseOrphanedProfiles — the bulk seam used by the deletion cascade
    // ============================================================

    private static Contact makeChild(Id nhId, Id displayParentId, String firstName) {
        Contact child = new Contact(
            FirstName = firstName,
            LastName = 'Household',
            AccountId = nhId,
            Birthdate = Date.today().addYears(-12),
            Is_Parent_Proxied__c = true,
            Proxied_By_Contact__c = displayParentId
        );
        insert child;
        return child;
    }

    private static Boolean isFlagged(Id contactId) {
        return [SELECT Deactivation_Requested__c FROM Contact WHERE Id = :contactId]
            .Deactivation_Requested__c;
    }

    /**
     * The cascade can hand over several children at once when a guardian who looked
     * after siblings leaves, so this has to be one DML rather than a loop.
     */
    @isTest
    static void erasingOrphanedProfilesFlagsEveryChildWithNoGraceWindow() {
        Contact parent = guardian();
        Account nh = [SELECT Id FROM Account WHERE Id = :parent.AccountId];
        Contact maya = makeChild(nh.Id, parent.Id, 'Maya');
        Contact liam = makeChild(nh.Id, parent.Id, 'Liam');

        Test.startTest();
        FimbyParentGuardianService.eraseOrphanedProfiles(
            new Set<Id>{ maya.Id, liam.Id }
        );
        Test.stopTest();

        for (Contact child : [
            SELECT Deactivation_Requested__c, Grace_Started_At__c
            FROM Contact WHERE Id IN (:maya.Id, :liam.Id)
        ]) {
            System.assertEquals(true, child.Deactivation_Requested__c);
            System.assertEquals(null, child.Grace_Started_At__c,
                'A profile with no login has no use for a change-of-mind window');
        }
    }

    @isTest
    static void erasingOrphanedProfilesReturnsEveryoneSwitchedIntoThemToThemselves() {
        Contact parent = guardian();
        Account nh = [SELECT Id FROM Account WHERE Id = :parent.AccountId];
        List<Contact> others = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        Contact child = makeChild(nh.Id, parent.Id, 'Maya');

        update new List<Contact>{
            new Contact(Id = parent.Id, Logged_In_As_Contact__c = child.Id,
                        Logged_In_As_Neighbourhood__c = nh.Id),
            new Contact(Id = others[0].Id, Logged_In_As_Contact__c = child.Id,
                        Logged_In_As_Neighbourhood__c = nh.Id)
        };

        Test.startTest();
        FimbyParentGuardianService.eraseOrphanedProfiles(new Set<Id>{ child.Id });
        Test.stopTest();

        for (Contact adult : [
            SELECT Logged_In_As_Contact__c, Logged_In_As_Neighbourhood__c
            FROM Contact WHERE Id IN (:parent.Id, :others[0].Id)
        ]) {
            System.assertEquals(null, adult.Logged_In_As_Contact__c,
                'Nobody may be left acting as a profile being erased');
            System.assertEquals(null, adult.Logged_In_As_Neighbourhood__c);
        }
    }

    /**
     * Fails closed. A malformed relationship row pointing at an ordinary neighbour must
     * never be able to queue that neighbour's account for erasure.
     */
    @isTest
    static void erasingOrphanedProfilesRefusesContactsThatAreNotManagedProfiles() {
        Contact parent = guardian();
        Account nh = [SELECT Id FROM Account WHERE Id = :parent.AccountId];
        List<Contact> others = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        Contact child = makeChild(nh.Id, parent.Id, 'Maya');

        Test.startTest();
        FimbyParentGuardianService.eraseOrphanedProfiles(
            new Set<Id>{ child.Id, others[0].Id }
        );
        Test.stopTest();

        System.assertEquals(true, isFlagged(child.Id),
            'The real managed profile is still erased');
        System.assertEquals(false, isFlagged(others[0].Id),
            'An adult neighbour is never erased through the family path');
    }

    @isTest
    static void erasingOrphanedProfilesIgnoresEmptyInputAndRepeats() {
        Contact parent = guardian();
        Account nh = [SELECT Id FROM Account WHERE Id = :parent.AccountId];
        Contact child = makeChild(nh.Id, parent.Id, 'Maya');

        Test.startTest();
        FimbyParentGuardianService.eraseOrphanedProfiles(null);
        FimbyParentGuardianService.eraseOrphanedProfiles(new Set<Id>());
        FimbyParentGuardianService.eraseOrphanedProfiles(new Set<Id>{ child.Id });
        FimbyParentGuardianService.eraseOrphanedProfiles(new Set<Id>{ child.Id });
        Test.stopTest();

        System.assertEquals(true, isFlagged(child.Id),
            'A nightly job must be safe to run twice over the same child');
    }
}
