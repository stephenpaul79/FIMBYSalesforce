@IsTest
private class FimbyAccountDeactivationBatchTest {

    private static Id getNeighbourhoodId() {
        return [SELECT Id FROM Account WHERE Name LIKE 'Test Neighbourhood%' LIMIT 1].Id;
    }

    /**
     * Excludes parent-managed profiles so the cascade tests below, which create their
     * own flagged children, cannot change which Contact this unordered lookup returns.
     */
    private static Contact getDeactivatingContact() {
        return [
            SELECT Id, FirstName, LastName, Email, Phone, MobilePhone,
                   MailingStreet, About_Fun_Fact__c, Deactivation_Requested__c
            FROM Contact
            WHERE Deactivation_Requested__c = true
              AND Is_Parent_Proxied__c = false
            LIMIT 1
        ];
    }

    @TestSetup
    static void setupData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);

        Contact deactivating = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, false);
        deactivating.Phone = '555-1234';
        deactivating.MailingStreet = '123 Test St';
        deactivating.About_Fun_Fact__c = 'Loves cats';
        insert deactivating;

        deactivating.Deactivation_Requested__c = true;
        update deactivating;

        Contact other = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        insert new Notification__c(
            Contact__c = deactivating.Id,
            Title__c = 'Test notification',
            Type__c = 'Response'
        );

        FimbyTestDataFactory.createStories(neighbourhood.Id, deactivating.Id, 1, true);

        Story__c authoredStory = new Story__c(
            Posted_By__c = other.Id,
            Contact__c = deactivating.Id,
            Neighbourhood__c = neighbourhood.Id
        );
        insert authoredStory;

        FimbyTestDataFactory.createNeedsOffers(neighbourhood.Id, deactivating.Id, 'Need', 1, true);
        FimbyTestDataFactory.createLibraryItems(neighbourhood.Id, deactivating.Id, 1, true);

        List<Library_Item__c> listedFor = FimbyTestDataFactory.createLibraryItems(neighbourhood.Id, other.Id, 1, false);
        listedFor[0].Listed_By__c = deactivating.Id;
        insert listedFor;

        insert new Blocked_Contact__c(
            Blocker__c = deactivating.Id,
            Blocked__c = other.Id
        );

        insert new Feedback__c(
            Name = 'Test Feedback',
            Type__c = 'Bug',
            Details__c = 'Found a bug',
            Posted_By__c = deactivating.Id,
            Neighbourhood__c = neighbourhood.Id
        );

        Conversation__c groupConv = new Conversation__c(
            Is_Group__c = true,
            Group_Name__c = 'Test Group',
            Status__c = 'Active'
        );
        insert groupConv;

        insert new Conversation_Member__c(
            Conversation__c = groupConv.Id,
            Contact__c = deactivating.Id,
            Role__c = 'Owner',
            Status__c = 'Active',
            Joined_Date__c = System.now()
        );

        insert new Conversation_Member__c(
            Conversation__c = groupConv.Id,
            Contact__c = other.Id,
            Role__c = 'Member',
            Status__c = 'Active',
            Joined_Date__c = System.now()
        );

        insert new Message__c(
            Conversation__c = groupConv.Id,
            Sender__c = deactivating.Id,
            Sent_By__c = deactivating.Id,
            Body__c = 'Authored by deactivating user',
            Sent_Date__c = System.now()
        );

        insert new Message__c(
            Conversation__c = groupConv.Id,
            Sender__c = other.Id,
            Sent_By__c = other.Id,
            Body__c = 'Authored by the surviving user',
            Sent_Date__c = System.now()
        );

        insert new Lending_History__c(
            Library_Item__c = listedFor[0].Id,
            Borrowed_By__c = deactivating.Id,
            Lent_By__c = other.Id,
            Start_Date__c = Date.today().addDays(-30),
            End_Date__c = Date.today().addDays(-15),
            Neighbourhood__c = neighbourhood.Id
        );

        insert new Support_Relationship__c(
            Contact__c = deactivating.Id,
            Related_Contact__c = other.Id,
            Status__c = 'Approved',
            Relationship_Type__c = 'Support_Person',
            Consent_Method__c = 'Verbal',
            Neighbourhood__c = neighbourhood.Id
        );
    }

    @IsTest
    static void anonymizesContactAndDeletesOwnedContent() {
        Contact deactivating = getDeactivatingContact();
        Id contactId = deactivating.Id;

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        List<Contact> remaining = [
            SELECT Id, FirstName, LastName, Email, Phone, MailingStreet,
                   About_Fun_Fact__c, Deactivation_Requested__c
            FROM Contact WHERE Id = :contactId
        ];
        System.assertEquals(1, remaining.size(),
            'Contact should be retained as anonymized stub, not hard-deleted');
        System.assertEquals('A former', remaining[0].FirstName);
        System.assertEquals('neighbour', remaining[0].LastName);
        System.assertEquals(null, remaining[0].Email);
        System.assertEquals(null, remaining[0].Phone);
        System.assertEquals(null, remaining[0].MailingStreet);
        System.assertEquals(null, remaining[0].About_Fun_Fact__c);
        System.assertEquals(false, remaining[0].Deactivation_Requested__c);

        System.assertEquals(0, [SELECT COUNT() FROM Notification__c WHERE Contact__c = :contactId]);
        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c
            WHERE Posted_By__c = :contactId OR Contact__c = :contactId]);
        System.assertEquals(0, [SELECT COUNT() FROM Story__c
            WHERE Posted_By__c = :contactId OR Contact__c = :contactId],
            'Stories where deactivating contact was real-author OR post-owner should be deleted');
        System.assertEquals(0, [SELECT COUNT() FROM Library_Item__c
            WHERE Owner_Contact__c = :contactId OR Listed_By__c = :contactId],
            'Library items where deactivating contact was owner OR lister should be deleted');
        System.assertEquals(0, [SELECT COUNT() FROM Support_Relationship__c
            WHERE Contact__c = :contactId OR Related_Contact__c = :contactId]);
    }

    @IsTest
    static void deletesGroupChatMembershipAndAuthoredMessages() {
        Contact deactivating = getDeactivatingContact();
        Id contactId = deactivating.Id;
        Id otherContactId = [SELECT Id FROM Contact
            WHERE Deactivation_Requested__c = false LIMIT 1].Id;

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Conversation_Member__c
            WHERE Contact__c = :contactId],
            'Deactivating user removed from group conversations');
        System.assertEquals(1, [SELECT COUNT() FROM Conversation_Member__c
            WHERE Contact__c = :otherContactId],
            'Other neighbours stay in the group conversation');

        System.assertEquals(0, [SELECT COUNT() FROM Message__c WHERE Sender__c = :contactId],
            'Messages authored by deactivating user are hard-deleted (not nulled)');
        System.assertEquals(1, [SELECT COUNT() FROM Message__c WHERE Sender__c = :otherContactId],
            'Other members\u2019 messages stay');
    }

    @IsTest
    static void keepsBlockedContactRowsAfterDeactivation() {
        Contact deactivating = getDeactivatingContact();
        Id contactId = deactivating.Id;

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        Integer remainingBlocks = [SELECT COUNT() FROM Blocked_Contact__c
            WHERE Blocker__c = :contactId OR Blocked__c = :contactId];
        System.assertEquals(1, remainingBlocks,
            'Blocked_Contact__c rows survive deactivation; the anonymized stub still resolves the FK');
    }

    @IsTest
    static void marksFeedbackForDelayedAnonymizationInsteadOfDeleting() {
        Contact deactivating = getDeactivatingContact();
        Id contactId = deactivating.Id;

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        List<Feedback__c> rows = [
            SELECT Id, Anonymize_After__c, Posted_By__c
            FROM Feedback__c WHERE Posted_By__c = :contactId
        ];
        System.assertEquals(1, rows.size(),
            'Feedback row is retained; submitter ref is anonymized later by a separate batch');
        System.assertEquals(Date.today().addDays(90), rows[0].Anonymize_After__c);
    }

    @IsTest
    static void anonymizesLendingHistoryReferences() {
        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        List<Lending_History__c> hist = [
            SELECT Borrowed_By__c, Lent_By__c FROM Lending_History__c
        ];
        System.assertEquals(1, hist.size(),
            'Lending history is retained for the surviving counterparty');
        System.assertEquals(null, hist[0].Borrowed_By__c,
            'Deactivating user reference is nulled');
    }

    @IsTest
    static void defersDeactivationWhileActiveLendingRequestExists() {
        Id neighbourhoodId = getNeighbourhoodId();
        Contact deactivating = getDeactivatingContact();
        Id contactId = deactivating.Id;
        Contact other = [SELECT Id FROM Contact WHERE Id != :contactId LIMIT 1];

        Library_Item__c item = FimbyTestDataFactory.createLibraryItems(neighbourhoodId, other.Id, 1, true)[0];

        Lending_Request__c openRequest = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = contactId,
            Item_Owner__c = other.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1,
            Neighbourhood__c = neighbourhoodId
        );
        insert openRequest;

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        Contact still = [SELECT FirstName, LastName, Deactivation_Requested__c
            FROM Contact WHERE Id = :contactId];
        System.assertNotEquals('A former', still.FirstName,
            'Active lending request defers deactivation; contact stays untouched');
        System.assertEquals(true, still.Deactivation_Requested__c,
            'Flag remains set so the next nightly run reconsiders');
    }

    @IsTest
    static void defersDeactivationWhileUnreturnedLoanExists() {
        Id neighbourhoodId = getNeighbourhoodId();
        Contact deactivating = getDeactivatingContact();
        Id contactId = deactivating.Id;
        Contact other = [SELECT Id FROM Contact WHERE Id != :contactId LIMIT 1];

        Library_Item__c item = FimbyTestDataFactory.createLibraryItems(neighbourhoodId, other.Id, 1, true)[0];

        Loaned_Item__c loan = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Owned_By__c = other.Id,
            Loaned_To__c = contactId,
            Loan_Start_Date__c = Date.today().addDays(-7),
            Loan_Due_Date__c = Date.today().addDays(7),
            Neighbourhood__c = neighbourhoodId
        );
        insert loan;

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        Contact still = [SELECT FirstName, Deactivation_Requested__c
            FROM Contact WHERE Id = :contactId];
        System.assertNotEquals('A former', still.FirstName,
            'Unreturned loan defers deactivation');
        System.assertEquals(true, still.Deactivation_Requested__c);
    }

    @IsTest
    static void terminalLendingStatusesDoNotDefer() {
        Id neighbourhoodId = getNeighbourhoodId();
        Contact deactivating = getDeactivatingContact();
        Id contactId = deactivating.Id;
        Contact other = [SELECT Id FROM Contact WHERE Id != :contactId LIMIT 1];

        Library_Item__c item = FimbyTestDataFactory.createLibraryItems(neighbourhoodId, other.Id, 1, true)[0];

        Lending_Request__c declined = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = contactId,
            Item_Owner__c = other.Id,
            Requested_Date__c = Date.today().addDays(1),
            of_Days_Needed__c = 3,
            Status__c = 'Cancelled',
            Waitlist_Position__c = 1,
            Neighbourhood__c = neighbourhoodId
        );
        insert declined;

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        Contact still = [SELECT FirstName FROM Contact WHERE Id = :contactId];
        System.assertEquals('A former', still.FirstName,
            'Cancelled lending requests do not defer deactivation');
    }

    @IsTest
    static void skipsContactStillInsideGraceWindow() {
        Id neighbourhoodId = getNeighbourhoodId();
        Contact inGrace = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhoodId, false);
        inGrace.FirstName = 'StillHere';
        inGrace.Deactivation_Requested__c = true;
        inGrace.Grace_Started_At__c = System.now().addDays(-5);
        insert inGrace;
        Id inGraceId = inGrace.Id;

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        Contact after = [SELECT FirstName FROM Contact WHERE Id = :inGraceId];
        System.assertEquals('StillHere', after.FirstName,
            'In-grace contact must NOT be anonymized by the scrub batch even when Deactivation_Requested__c=true');
    }

    @IsTest
    static void schedulableInstanceCanBeScheduled() {
        Test.startTest();
        String jobId = System.schedule(
            'Test FIMBY Deactivation',
            '0 0 0 * * ?',
            new FimbyAccountDeactivationBatch()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }

    // ============================================================
    // Parent-managed profile cascade
    //
    // Guardians and children are built inside each test, never in @TestSetup: the
    // helpers above resolve Contacts with unordered LIMIT 1 lookups, so a shared
    // parent-managed row would change what unrelated tests pick up. Children get no
    // User, matching production and avoiding Contact/User mixed DML.
    // ============================================================

    private static Contact makeGuardian(Id nhId, String firstName, Boolean flagForDeletion) {
        Contact guardian = FimbyTestDataFactory.createNeighbourhoodContact(nhId, false);
        guardian.FirstName = firstName;
        insert guardian;
        if (flagForDeletion) {
            update new Contact(Id = guardian.Id, Deactivation_Requested__c = true);
        }
        return guardian;
    }

    private static Contact makeManagedChild(Id nhId, Id displayParentId, String firstName) {
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

    private static Support_Relationship__c guardianMandate(Id nhId, Id guardianId, Id childId) {
        Support_Relationship__c rel = new Support_Relationship__c(
            Relationship_Type__c = 'Parent_Guardian',
            Contact__c = guardianId,
            Related_Contact__c = childId,
            Neighbourhood__c = nhId,
            Status__c = 'Approved',
            Consent_Method__c = 'Guardian'
        );
        insert rel;
        return rel;
    }

    /**
     * The published deletion policy promises the adult and the child are "scrubbed
     * together on the same nightly cleanup", so the child must be anonymized in this
     * run rather than waiting for tomorrow's.
     */
    @IsTest
    static void lastGuardianScrubTakesTheChildInTheSameRun() {
        Id nhId = getNeighbourhoodId();
        Contact guardian = makeGuardian(nhId, 'Departing', true);
        Contact child = makeManagedChild(nhId, guardian.Id, 'Maya');
        guardianMandate(nhId, guardian.Id, child.Id);

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        Contact scrubbed = [
            SELECT FirstName, Is_Parent_Proxied__c, Proxied_By_Contact__c, Birthdate
            FROM Contact WHERE Id = :child.Id
        ];
        System.assertEquals('A former', scrubbed.FirstName,
            'The child is anonymized in the same run as their last guardian');
        System.assertEquals(false, scrubbed.Is_Parent_Proxied__c);
        System.assertEquals(null, scrubbed.Proxied_By_Contact__c);
        System.assertEquals(null, scrubbed.Birthdate,
            'A child birthdate is the whole point of the erasure');
    }

    /**
     * Two guardians leaving at once, in a single chunk. The separate-chunk case cannot
     * be driven through the real batch — a test method may only trigger one
     * executeBatch — so it is covered directly in
     * FimbyManagedProfileCascadeServiceTest.twoGuardiansLeavingInSeparateChunksStillOrphansTheChild.
     */
    @IsTest
    static void twoGuardiansLeavingTogetherStillLeaveNoOrphan() {
        Id nhId = getNeighbourhoodId();
        Contact first = makeGuardian(nhId, 'FirstOut', true);
        Contact second = makeGuardian(nhId, 'SecondOut', true);
        Contact child = makeManagedChild(nhId, first.Id, 'Maya');
        guardianMandate(nhId, first.Id, child.Id);
        guardianMandate(nhId, second.Id, child.Id);

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 200);
        Test.stopTest();

        System.assertEquals('A former',
            [SELECT FirstName FROM Contact WHERE Id = :child.Id].FirstName,
            'Losing both guardians at once must still erase the child');
    }

    @IsTest
    static void childSurvivesWhenAnotherGuardianRemains() {
        Id nhId = getNeighbourhoodId();
        Contact leaving = makeGuardian(nhId, 'Departing', true);
        Contact staying = makeGuardian(nhId, 'Staying', false);
        Contact child = makeManagedChild(nhId, leaving.Id, 'Maya');
        guardianMandate(nhId, leaving.Id, child.Id);
        guardianMandate(nhId, staying.Id, child.Id);

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        Contact kept = [
            SELECT FirstName, Is_Parent_Proxied__c, Proxied_By_Contact__c,
                   Deactivation_Requested__c
            FROM Contact WHERE Id = :child.Id
        ];
        System.assertEquals('Maya', kept.FirstName,
            'The profile carries on unchanged for the remaining guardian');
        System.assertEquals(true, kept.Is_Parent_Proxied__c);
        System.assertEquals(false, kept.Deactivation_Requested__c);
        System.assertEquals(staying.Id, kept.Proxied_By_Contact__c,
            'The display parent moves silently to the guardian who is still here');

        System.assertEquals(1, [
            SELECT COUNT() FROM Support_Relationship__c
            WHERE Related_Contact__c = :child.Id AND Contact__c = :staying.Id
        ], 'The surviving mandate is untouched');
    }

    /**
     * The old cleanup deleted any relationship merely referencing the departing adult.
     * A guardian who had approved the co-guardian's mandate would therefore destroy it
     * on the way out, orphaning the child the cascade had just judged safe.
     */
    @IsTest
    static void survivingMandateApprovedByTheDepartingGuardianIsKept() {
        Id nhId = getNeighbourhoodId();
        Contact leaving = makeGuardian(nhId, 'Departing', true);
        Contact staying = makeGuardian(nhId, 'Staying', false);
        Contact child = makeManagedChild(nhId, staying.Id, 'Maya');
        guardianMandate(nhId, leaving.Id, child.Id);

        Support_Relationship__c survivor = guardianMandate(nhId, staying.Id, child.Id);
        update new Support_Relationship__c(Id = survivor.Id, Approved_By__c = leaving.Id);

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        List<Support_Relationship__c> kept = [
            SELECT Id, Approved_By__c FROM Support_Relationship__c WHERE Id = :survivor.Id
        ];
        System.assertEquals(1, kept.size(),
            'A mandate the departing adult merely approved belongs to someone else');
        System.assertEquals(null, kept[0].Approved_By__c,
            'The audit lookup is nulled rather than the row deleted');
        System.assertEquals('Maya',
            [SELECT FirstName FROM Contact WHERE Id = :child.Id].FirstName,
            'The child keeps their surviving guardian and is not erased');
    }

    /**
     * A child holding a borrowed item is flagged but deferred, exactly as an adult
     * would be, then picked up once the loan is resolved.
     */
    @IsTest
    static void orphanedChildWithAnOpenLoanIsFlaggedButDeferred() {
        Id nhId = getNeighbourhoodId();
        Contact guardian = makeGuardian(nhId, 'Departing', true);
        Contact lender = makeGuardian(nhId, 'Lender', false);
        Contact child = makeManagedChild(nhId, guardian.Id, 'Maya');
        guardianMandate(nhId, guardian.Id, child.Id);

        // A pending request from a different adult: the child is a party to it, but the
        // departing guardian is not, so it should outlive this run along with the child.
        Support_Relationship__c pending = new Support_Relationship__c(
            Relationship_Type__c = 'Parent_Guardian',
            Contact__c = lender.Id,
            Related_Contact__c = child.Id,
            Neighbourhood__c = nhId,
            Status__c = 'Pending',
            Consent_Method__c = 'Guardian'
        );
        insert pending;

        Library_Item__c item =
            FimbyTestDataFactory.createLibraryItems(nhId, lender.Id, 1, true)[0];
        Loaned_Item__c loan = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Owned_By__c = lender.Id,
            Loaned_To__c = child.Id,
            Loan_Start_Date__c = Date.today().addDays(-3),
            Loan_Due_Date__c = Date.today().addDays(4),
            Neighbourhood__c = nhId
        );
        insert loan;

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        Contact deferred = [
            SELECT FirstName, Deactivation_Requested__c, Grace_Started_At__c
            FROM Contact WHERE Id = :child.Id
        ];
        System.assertEquals('Maya', deferred.FirstName,
            'A child with an item still out is not scrubbed mid-loan');
        System.assertEquals(true, deferred.Deactivation_Requested__c,
            'The flag persists so a later run finishes the job');
        System.assertEquals(null, deferred.Grace_Started_At__c,
            'No grace window: the profile has no login to change its mind with');
        System.assertEquals(1, [
            SELECT COUNT() FROM Support_Relationship__c WHERE Id = :pending.Id
        ], 'A deferred child keeps its remaining rows until the run that scrubs it');
    }

    /**
     * The other half of the deferral: a child flagged by an earlier run, whose loan has
     * since been returned, is picked up and scrubbed like any other flagged Contact.
     * Set up directly in the state that earlier run would have left behind, because a
     * test method can only drive one batch through Test.stopTest().
     */
    @IsTest
    static void previouslyDeferredOrphanIsScrubbedByALaterRun() {
        Id nhId = getNeighbourhoodId();
        Contact child = makeManagedChild(nhId, null, 'Maya');
        update new Contact(
            Id = child.Id,
            Deactivation_Requested__c = true,
            Grace_Started_At__c = null
        );

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        Contact scrubbed = [
            SELECT FirstName, Is_Parent_Proxied__c, Birthdate
            FROM Contact WHERE Id = :child.Id
        ];
        System.assertEquals('A former', scrubbed.FirstName,
            'A child left flagged by an earlier deferral is finished off later');
        System.assertEquals(false, scrubbed.Is_Parent_Proxied__c);
        System.assertEquals(null, scrubbed.Birthdate);
    }

    @IsTest
    static void ordinaryAdultWithAMalformedMandateIsNotErased() {
        Id nhId = getNeighbourhoodId();
        Contact leaving = makeGuardian(nhId, 'Departing', true);
        Contact ordinaryAdult = makeGuardian(nhId, 'Ordinary', false);
        guardianMandate(nhId, leaving.Id, ordinaryAdult.Id);

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        Contact untouched = [
            SELECT FirstName, Deactivation_Requested__c FROM Contact WHERE Id = :ordinaryAdult.Id
        ];
        System.assertEquals('Ordinary', untouched.FirstName,
            'A malformed relationship row must never erase an adult neighbour');
        System.assertEquals(false, untouched.Deactivation_Requested__c);
    }

    @IsTest
    static void orphanedChildContentIsRemovedOnTheSameRun() {
        Id nhId = getNeighbourhoodId();
        Contact guardian = makeGuardian(nhId, 'Departing', true);
        Contact child = makeManagedChild(nhId, guardian.Id, 'Maya');
        guardianMandate(nhId, guardian.Id, child.Id);

        FimbyTestDataFactory.createStories(nhId, child.Id, 1, true);
        FimbyTestDataFactory.createNeedsOffers(nhId, child.Id, 'Need', 1, true);
        insert new Notification__c(
            Contact__c = child.Id,
            Title__c = 'For the child',
            Type__c = 'Response'
        );

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Story__c
            WHERE Posted_By__c = :child.Id OR Contact__c = :child.Id],
            'A child\u2019s posts go with the profile');
        System.assertEquals(0, [SELECT COUNT() FROM Needs_Offers__c
            WHERE Posted_By__c = :child.Id OR Contact__c = :child.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Notification__c
            WHERE Contact__c = :child.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Support_Relationship__c
            WHERE Related_Contact__c = :child.Id],
            'The spent mandate is cleared away with the profile');
    }

    /**
     * A nightly job has to be safe to re-run. A Contact still carrying the flag but no
     * longer a managed profile is what a half-finished earlier run looks like; the
     * cascade must pass over it rather than treating it as a fresh orphan.
     */
    @IsTest
    static void aFlaggedContactThatIsNoLongerProxiedIsNotTreatedAsAnOrphan() {
        Id nhId = getNeighbourhoodId();
        Contact guardian = makeGuardian(nhId, 'Departing', true);
        Contact alreadyScrubbed = makeManagedChild(nhId, guardian.Id, 'Maya');
        guardianMandate(nhId, guardian.Id, alreadyScrubbed.Id);
        update new Contact(Id = alreadyScrubbed.Id, Is_Parent_Proxied__c = false);

        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        Test.stopTest();

        System.assertEquals(false,
            [SELECT Deactivation_Requested__c FROM Contact WHERE Id = :alreadyScrubbed.Id]
                .Deactivation_Requested__c,
            'Re-running must neither throw nor re-flag a Contact that is no longer proxied');
        System.assertEquals('A former',
            [SELECT FirstName FROM Contact WHERE Id = :guardian.Id].FirstName,
            'The departing guardian is still scrubbed normally');
    }

    /**
     * The cascade is deliberately fail-closed. If the child cannot be resolved, the
     * chunk must roll back entirely — a guardian disappearing while their child stays
     * behind unflagged is the exact state this feature exists to prevent.
     */
    @IsTest
    static void aFailedCascadeRollsBackTheWholeChunk() {
        Id nhId = getNeighbourhoodId();
        Contact guardian = makeGuardian(nhId, 'Departing', true);
        Contact child = makeManagedChild(nhId, guardian.Id, 'Maya');
        Support_Relationship__c mandateRow = guardianMandate(nhId, guardian.Id, child.Id);

        FimbyManagedProfileCascadeService.throwOnResolveForTest = true;
        Boolean surfaced = false;
        Test.startTest();
        Database.executeBatch(new FimbyAccountDeactivationBatch(), 10);
        try {
            // The exception has to escape execute() for Salesforce to roll the chunk
            // back, which means Test.stopTest() rethrows it here.
            Test.stopTest();
        } catch (Exception e) {
            surfaced = true;
        }
        FimbyManagedProfileCascadeService.throwOnResolveForTest = false;

        // Escaping execute() is the whole mechanism: Salesforce rolls the chunk back
        // precisely because nothing catches it there. The rollback itself cannot be
        // asserted from here, since catching an exception in Apex does not undo DML —
        // only an exception that ends the transaction does.
        System.assertEquals(true, surfaced,
            'A cascade failure must escape execute() so the platform rolls the chunk back');
        System.assertNotEquals(null, mandateRow.Id);

        Contact stillThere = [
            SELECT FirstName, Deactivation_Requested__c FROM Contact WHERE Id = :guardian.Id
        ];
        System.assertNotEquals('A former', stillThere.FirstName,
            'The guardian must not be anonymized when their child could not be resolved');
        System.assertEquals(true, stillThere.Deactivation_Requested__c,
            'The flag survives so the next run retries');
        System.assertEquals('Maya',
            [SELECT FirstName FROM Contact WHERE Id = :child.Id].FirstName);
    }
}
