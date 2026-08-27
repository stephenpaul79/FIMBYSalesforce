/**
 * @description Covers the no-orphan invariant for parent-managed profiles.
 *
 * Fixtures are built inside each test rather than in @TestSetup on purpose. Sibling
 * test classes resolve their Contacts with unordered LIMIT 1 lookups, and a shared
 * parent-managed Contact would quietly change which row those helpers return.
 *
 * Children are created without a User, which is both what production does and what
 * keeps these tests clear of Contact/User mixed-DML restrictions.
 */
@IsTest
private class FimbyManagedProfileCascadeServiceTest {

    private static Account neighbourhood() {
        return FimbyTestDataFactory.createNeighbourhood(true);
    }

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

    private static Support_Relationship__c mandate(
        Id nhId, Id guardianId, Id childId, String type, String status
    ) {
        Support_Relationship__c rel = new Support_Relationship__c(
            Relationship_Type__c = type,
            Contact__c = guardianId,
            Related_Contact__c = childId,
            Neighbourhood__c = nhId,
            Status__c = status,
            Consent_Method__c = 'Guardian'
        );
        insert rel;
        return rel;
    }

    private static Support_Relationship__c guardianMandate(Id nhId, Id guardianId, Id childId) {
        return mandate(nhId, guardianId, childId, 'Parent_Guardian', 'Approved');
    }

    private static Boolean isFlagged(Id contactId) {
        return [
            SELECT Deactivation_Requested__c FROM Contact WHERE Id = :contactId
        ].Deactivation_Requested__c;
    }

    private static Id displayParentOf(Id childId) {
        return [SELECT Proxied_By_Contact__c FROM Contact WHERE Id = :childId]
            .Proxied_By_Contact__c;
    }

    /**
     * Simulates one batch chunk: capture while the mandates exist, delete this
     * chunk's mandates, then ask who is left. Mirrors cascadeManagedProfiles.
     */
    private static FimbyManagedProfileCascadeService.CascadeResult runChunk(Set<Id> departingIds) {
        Set<Id> candidates =
            FimbyManagedProfileCascadeService.candidateChildrenOf(departingIds);
        delete [
            SELECT Id FROM Support_Relationship__c
            WHERE Contact__c IN :departingIds OR Related_Contact__c IN :departingIds
        ];
        return FimbyManagedProfileCascadeService.resolveAfterGuardianRemoval(candidates);
    }

    /**
     * The whole point of the feature: the last mandate going means the profile goes,
     * because a young person must never be left with a presence nobody looks after.
     */
    @IsTest
    static void soleGuardianLeavingOrphansAndFlagsTheChild() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        Contact child = makeChild(nh.Id, adults[0].Id, 'Maya');
        guardianMandate(nh.Id, adults[0].Id, child.Id);

        Test.startTest();
        FimbyManagedProfileCascadeService.CascadeResult result =
            runChunk(new Set<Id>{ adults[0].Id });
        Test.stopTest();

        System.assertEquals(1, result.orphanIds.size(), 'The child lost their last guardian');
        System.assert(result.orphanIds.contains(child.Id));
        System.assertEquals(0, result.repairedChildIds.size());
        System.assertEquals(true, isFlagged(child.Id),
            'An orphaned profile must be queued for erasure');
    }

    /**
     * A surviving guardian keeps the profile alive. The display parent has to move,
     * though, or the child would keep showing an adult who has left.
     */
    @IsTest
    static void survivingGuardianKeepsTheChildAndInheritsTheDisplayParent() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 2, true);
        Contact leaving = adults[0];
        Contact staying = adults[1];

        Contact child = makeChild(nh.Id, leaving.Id, 'Maya');
        guardianMandate(nh.Id, leaving.Id, child.Id);
        guardianMandate(nh.Id, staying.Id, child.Id);

        Test.startTest();
        FimbyManagedProfileCascadeService.CascadeResult result =
            runChunk(new Set<Id>{ leaving.Id });
        Test.stopTest();

        System.assertEquals(0, result.orphanIds.size(),
            'A child with a remaining guardian is not an orphan');
        System.assertEquals(1, result.repairedChildIds.size());
        System.assertEquals(false, isFlagged(child.Id),
            'The profile carries on unchanged for the remaining guardian');
        System.assertEquals(staying.Id, displayParentOf(child.Id),
            'The display parent moves to the guardian who is still here');
    }

    /**
     * A pointer that still points at a real guardian is left alone; churning it would
     * change what the child's profile says for no reason.
     */
    @IsTest
    static void leavingANonDisplayGuardianDoesNotDisturbTheDisplayParent() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 2, true);
        Contact displayParent = adults[0];
        Contact leaving = adults[1];

        Contact child = makeChild(nh.Id, displayParent.Id, 'Maya');
        guardianMandate(nh.Id, displayParent.Id, child.Id);
        guardianMandate(nh.Id, leaving.Id, child.Id);

        Test.startTest();
        FimbyManagedProfileCascadeService.CascadeResult result =
            runChunk(new Set<Id>{ leaving.Id });
        Test.stopTest();

        System.assertEquals(0, result.orphanIds.size());
        System.assertEquals(0, result.repairedChildIds.size(),
            'Nothing to repair when the display parent is still a guardian');
        System.assertEquals(displayParent.Id, displayParentOf(child.Id));
    }

    /**
     * The reason this class captures candidates before deleting rather than checking
     * first: Salesforce may hand two guardians of one child to different batch chunks,
     * and a pre-check would let each conclude the other was still standing.
     */
    @IsTest
    static void twoGuardiansLeavingInSeparateChunksStillOrphansTheChild() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 2, true);
        Contact first = adults[0];
        Contact second = adults[1];

        Contact child = makeChild(nh.Id, first.Id, 'Maya');
        guardianMandate(nh.Id, first.Id, child.Id);
        guardianMandate(nh.Id, second.Id, child.Id);

        Test.startTest();
        FimbyManagedProfileCascadeService.CascadeResult firstChunk =
            runChunk(new Set<Id>{ first.Id });
        FimbyManagedProfileCascadeService.CascadeResult secondChunk =
            runChunk(new Set<Id>{ second.Id });
        Test.stopTest();

        System.assertEquals(0, firstChunk.orphanIds.size(),
            'The first chunk still sees a surviving guardian');
        System.assertEquals(1, secondChunk.orphanIds.size(),
            'The chunk that removes the final mandate is the one that erases the child');
        System.assert(secondChunk.orphanIds.contains(child.Id));
        System.assertEquals(true, isFlagged(child.Id));
    }

    @IsTest
    static void twoChildrenAreResolvedInOneBulkCall() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 2, true);
        Contact leaving = adults[0];
        Contact staying = adults[1];

        Contact orphanChild = makeChild(nh.Id, leaving.Id, 'Maya');
        Contact keptChild = makeChild(nh.Id, leaving.Id, 'Liam');
        guardianMandate(nh.Id, leaving.Id, orphanChild.Id);
        guardianMandate(nh.Id, leaving.Id, keptChild.Id);
        guardianMandate(nh.Id, staying.Id, keptChild.Id);

        Test.startTest();
        FimbyManagedProfileCascadeService.CascadeResult result =
            runChunk(new Set<Id>{ leaving.Id });
        Test.stopTest();

        System.assertEquals(1, result.orphanIds.size());
        System.assert(result.orphanIds.contains(orphanChild.Id));
        System.assertEquals(1, result.repairedChildIds.size());
        System.assert(result.repairedChildIds.contains(keptChild.Id));
        System.assertEquals(true, isFlagged(orphanChild.Id));
        System.assertEquals(false, isFlagged(keptChild.Id));
        System.assertEquals(staying.Id, displayParentOf(keptChild.Id));
    }

    /**
     * A malformed Parent_Guardian row pointing at an ordinary adult must never be able
     * to erase that adult. Failing closed here is the difference between a data bug
     * and deleting a neighbour's account.
     */
    @IsTest
    static void anOrdinaryAdultIsNeverFlaggedByAMalformedMandate() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 2, true);
        Contact leaving = adults[0];
        Contact ordinaryAdult = adults[1];

        guardianMandate(nh.Id, leaving.Id, ordinaryAdult.Id);

        Test.startTest();
        FimbyManagedProfileCascadeService.CascadeResult result =
            runChunk(new Set<Id>{ leaving.Id });
        Test.stopTest();

        System.assertEquals(0, result.orphanIds.size(),
            'A Contact that is not a managed profile is not ours to erase');
        System.assertEquals(false, isFlagged(ordinaryAdult.Id));
    }

    /**
     * Only an Approved Parent_Guardian mandate keeps a profile alive. A support person,
     * a pending request, or a revoked row is not somebody looking after a child.
     */
    @IsTest
    static void nonGuardianAndNonApprovedRowsDoNotKeepAChildAlive() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 4, true);
        Contact leaving = adults[0];

        Contact child = makeChild(nh.Id, leaving.Id, 'Maya');
        guardianMandate(nh.Id, leaving.Id, child.Id);
        mandate(nh.Id, adults[1].Id, child.Id, 'Support_Person', 'Approved');
        mandate(nh.Id, adults[2].Id, child.Id, 'Parent_Guardian', 'Pending');
        mandate(nh.Id, adults[3].Id, child.Id, 'Parent_Guardian', 'Revoked');

        Test.startTest();
        FimbyManagedProfileCascadeService.CascadeResult result =
            runChunk(new Set<Id>{ leaving.Id });
        Test.stopTest();

        System.assertEquals(1, result.orphanIds.size(),
            'None of those rows is an approved guardian mandate');
        System.assertEquals(true, isFlagged(child.Id));
    }

    @IsTest
    static void emptyAndNullInputDoNothing() {
        Test.startTest();
        System.assertEquals(0,
            FimbyManagedProfileCascadeService.candidateChildrenOf(null).size());
        System.assertEquals(0,
            FimbyManagedProfileCascadeService.candidateChildrenOf(new Set<Id>()).size());
        System.assertEquals(0,
            FimbyManagedProfileCascadeService.resolveAfterGuardianRemoval(null).orphanIds.size());
        System.assertEquals(0,
            FimbyManagedProfileCascadeService.resolveAfterGuardianRemoval(new Set<Id>())
                .orphanIds.size());
        System.assertEquals(0,
            FimbyManagedProfileCascadeService.atRiskIfGuardianDeparts(null).size());
        Test.stopTest();
    }

    /**
     * A nightly job that retries must be safe to retry. Re-resolving a child already
     * flagged and already stripped of mandates must not throw or double-count.
     */
    @IsTest
    static void resolvingAnAlreadyFlaggedOrphanIsIdempotent() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        Contact child = makeChild(nh.Id, adults[0].Id, 'Maya');
        guardianMandate(nh.Id, adults[0].Id, child.Id);

        Test.startTest();
        runChunk(new Set<Id>{ adults[0].Id });
        FimbyManagedProfileCascadeService.CascadeResult again =
            FimbyManagedProfileCascadeService.resolveAfterGuardianRemoval(
                new Set<Id>{ child.Id });
        Test.stopTest();

        System.assertEquals(1, again.orphanIds.size(),
            'Still an orphan, and re-flagging it is harmless');
        System.assertEquals(true, isFlagged(child.Id));
    }

    /**
     * Anyone still switched into a profile being erased has to be put back in their own
     * shoes, or they would keep acting as a presence that is on its way out.
     */
    @IsTest
    static void orphaningReturnsAnyoneSwitchedIntoTheChildToThemselves() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        Contact child = makeChild(nh.Id, adults[0].Id, 'Maya');
        guardianMandate(nh.Id, adults[0].Id, child.Id);
        update new Contact(
            Id = adults[0].Id,
            Logged_In_As_Contact__c = child.Id,
            Logged_In_As_Neighbourhood__c = nh.Id
        );

        Test.startTest();
        runChunk(new Set<Id>{ adults[0].Id });
        Test.stopTest();

        Contact adult = [
            SELECT Logged_In_As_Contact__c, Logged_In_As_Neighbourhood__c
            FROM Contact WHERE Id = :adults[0].Id
        ];
        System.assertEquals(null, adult.Logged_In_As_Contact__c);
        System.assertEquals(null, adult.Logged_In_As_Neighbourhood__c);
    }

    // ============================================================
    // atRiskIfGuardianDeparts — confirmation copy only
    // ============================================================

    @IsTest
    static void aSoleGuardianIsWarnedAndNamedTheChild() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        Contact child = makeChild(nh.Id, adults[0].Id, 'Maya');
        guardianMandate(nh.Id, adults[0].Id, child.Id);

        Test.startTest();
        List<FimbyManagedProfileCascadeService.ManagedProfileRisk> risks =
            FimbyManagedProfileCascadeService.atRiskIfGuardianDeparts(adults[0].Id);
        Test.stopTest();

        System.assertEquals(1, risks.size());
        System.assertEquals(child.Id, risks[0].contactId);
        System.assertEquals('Maya', risks[0].firstName,
            'The warning names the young person rather than saying "a profile"');
    }

    @IsTest
    static void anActiveCoGuardianMeansNoWarning() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 2, true);
        Contact child = makeChild(nh.Id, adults[0].Id, 'Maya');
        guardianMandate(nh.Id, adults[0].Id, child.Id);
        guardianMandate(nh.Id, adults[1].Id, child.Id);

        Test.startTest();
        List<FimbyManagedProfileCascadeService.ManagedProfileRisk> risks =
            FimbyManagedProfileCascadeService.atRiskIfGuardianDeparts(adults[0].Id);
        Test.stopTest();

        System.assertEquals(0, risks.size(),
            'The profile carries on with the other guardian, so there is nothing to warn about');
    }

    /**
     * A co-guardian already heading out is not somebody to rely on. This deliberately
     * over-warns: if they restore within their grace window the child survives and the
     * warning turns out cautious, which is far better than staying silent.
     */
    @IsTest
    static void aCoGuardianAlreadyLeavingDoesNotCountAsDependable() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 3, true);
        Contact child = makeChild(nh.Id, adults[0].Id, 'Maya');
        guardianMandate(nh.Id, adults[0].Id, child.Id);
        guardianMandate(nh.Id, adults[1].Id, child.Id);
        guardianMandate(nh.Id, adults[2].Id, child.Id);

        update new List<Contact>{
            new Contact(Id = adults[1].Id, Grace_Started_At__c = System.now()),
            new Contact(Id = adults[2].Id, Deactivation_Requested__c = true)
        };

        Test.startTest();
        List<FimbyManagedProfileCascadeService.ManagedProfileRisk> risks =
            FimbyManagedProfileCascadeService.atRiskIfGuardianDeparts(adults[0].Id);
        Test.stopTest();

        System.assertEquals(1, risks.size(),
            'Neither co-guardian can be relied on to keep the profile');
        System.assertEquals(child.Id, risks[0].contactId);
    }

    @IsTest
    static void aSupportPersonRelationshipRaisesNoManagedProfileWarning() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 2, true);
        mandate(nh.Id, adults[0].Id, adults[1].Id, 'Support_Person', 'Approved');

        Test.startTest();
        List<FimbyManagedProfileCascadeService.ManagedProfileRisk> risks =
            FimbyManagedProfileCascadeService.atRiskIfGuardianDeparts(adults[0].Id);
        Test.stopTest();

        System.assertEquals(0, risks.size(),
            'Supporting an adult who speaks for themselves is not a parent-managed profile');
    }

    @IsTest
    static void twoAtRiskChildrenAreBothNamed() {
        Account nh = neighbourhood();
        List<Contact> adults = FimbyTestDataFactory.createNeighbourhoodContacts(nh.Id, 1, true);
        Contact maya = makeChild(nh.Id, adults[0].Id, 'Maya');
        Contact liam = makeChild(nh.Id, adults[0].Id, 'Liam');
        guardianMandate(nh.Id, adults[0].Id, maya.Id);
        guardianMandate(nh.Id, adults[0].Id, liam.Id);

        Test.startTest();
        List<FimbyManagedProfileCascadeService.ManagedProfileRisk> risks =
            FimbyManagedProfileCascadeService.atRiskIfGuardianDeparts(adults[0].Id);
        Test.stopTest();

        System.assertEquals(2, risks.size());
        Set<String> names = new Set<String>();
        for (FimbyManagedProfileCascadeService.ManagedProfileRisk risk : risks) {
            names.add(risk.firstName);
        }
        System.assert(names.contains('Maya'));
        System.assert(names.contains('Liam'));
    }
}
