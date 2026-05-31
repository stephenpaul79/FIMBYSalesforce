@IsTest
private class FimbyAccountDeactivationBatchTest {

    private static Id getNeighbourhoodId() {
        return [SELECT Id FROM Account WHERE Name LIKE 'Test Neighbourhood%' LIMIT 1].Id;
    }

    private static Contact getDeactivatingContact() {
        return [
            SELECT Id, FirstName, LastName, Email, Phone, MobilePhone,
                   MailingStreet, About_Fun_Fact__c, Deactivation_Requested__c
            FROM Contact
            WHERE Deactivation_Requested__c = true
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
}
