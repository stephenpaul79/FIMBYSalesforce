@IsTest
public class FimbyMyStuffControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(neighbourhood.Id, 3, true);
        Contact contact = contacts[0];
        User communityUser = FimbyTestDataFactory.createCommunityUser(contact.Id, 'Customer Community User - Mobile App', true);

        List<Story__c> stories = FimbyTestDataFactory.createStories(neighbourhood.Id, contact.Id, 3, true);
        List<Needs_Offers__c> askOfferItems = FimbyTestDataFactory.createAskOfferItems(neighbourhood.Id, contact.Id, 4, true);
        List<Library_Item__c> libraryItems = FimbyTestDataFactory.createLibraryItems(neighbourhood.Id, contact.Id, 2, true);

        // Archived posts (inactive statuses) for archive tests
        List<Needs_Offers__c> archivedPosts = new List<Needs_Offers__c>();
        for (Integer i = 0; i < 2; i++) {
            archivedPosts.add(new Needs_Offers__c(
                Name = 'Archived Post ' + i,
                Details__c = 'Archived post details',
                Type__c = 'Goods - Unperishable',
                Category__c = 'Tools',
                Status__c = 'Expired',
                Neighbourhood__c = neighbourhood.Id,
                Posted_By__c = contact.Id,
                Contact__c = contact.Id
            ));
        }
        insert archivedPosts;

        // Unavailable library item for library archive test
        Library_Item__c unavailableItem = new Library_Item__c(
            Name = 'Archived Library Item',
            Description__c = 'No longer available',
            Category__c = 'Tools',
            Status__c = 'Unavailable',
            Neighbourhood__c = neighbourhood.Id,
            Owner_Contact__c = contact.Id
        );
        insert unavailableItem;

        // Lending history record for borrow history test
        Lending_History__c history = new Lending_History__c(
            Name = 'Past Borrow',
            Borrowed_By__c = contact.Id,
            Lent_By__c = contacts[1].Id,
            Library_Item__c = libraryItems[0].Id,
            Start_Date__c = Date.today().addDays(-30),
            End_Date__c = Date.today().addDays(-5)
        );
        insert history;
    }

    @IsTest
    static void testGetMyProfile() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            Map<String, String> profile = FimbyMyStuffController.getMyProfile();

            System.assertNotEquals(null, profile, 'Profile should not be null');
            System.assert(profile.containsKey('name'), 'Profile should contain name');
            System.assert(profile.containsKey('neighbourhood'), 'Profile should contain neighbourhood');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMineSummary() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Integer> summary = FimbyMyStuffController.getMineSummary();

            System.assertNotEquals(null, summary, 'Summary should not be null');
            System.assert(summary.containsKey('postsCount'), 'Should have postsCount');
            System.assert(summary.containsKey('storiesCount'), 'Should have storiesCount');
            System.assert(summary.containsKey('libraryCount'), 'Should have libraryCount');
            System.assert(summary.containsKey('borrowedCount'), 'Should have borrowedCount');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyPosts() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Needs_Offers__c> posts = FimbyMyStuffController.getMyPosts(20);

            System.assertNotEquals(null, posts, 'Posts should not be null');
            // Posts belong to the contact created in setup
            System.assertEquals(6, posts.size(), 'Should return 6 posts (4 active + 2 archived)');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyStories() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Story__c> stories = FimbyMyStuffController.getMyStories(10);

            System.assertNotEquals(null, stories, 'Stories should not be null');
            System.assertEquals(3, stories.size(), 'Should return 3 stories');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyLibraryItems() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<FimbyMyStuffController.LibraryItemWrapper> items = FimbyMyStuffController.getMyLibraryItems(20);

            System.assertNotEquals(null, items, 'Library items should not be null');
            System.assertEquals(3, items.size(), 'Should return 3 library items (2 available + 1 unavailable)');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyBorrowedItems() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<FimbyMyStuffController.BorrowedItemWrapper> items = FimbyMyStuffController.getMyBorrowedItems();

            System.assertNotEquals(null, items, 'Borrowed items should not be null');
            // No borrowed items in test setup, so should be 0
            System.assertEquals(0, items.size(), 'Should return 0 borrowed items (none setup)');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyPostsArchive() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            FimbyMyStuffController.ArchiveResult result = FimbyMyStuffController.getMyPostsArchive(20, 0, 'All');
            System.assertNotEquals(null, result, 'Archive result should not be null');
            System.assertEquals(2, result.totalCount, 'Should have 2 archived (inactive) posts');
            System.assertEquals(2, result.items.size(), 'Should return 2 items');

            // Test with filter
            FimbyMyStuffController.ArchiveResult filteredResult = FimbyMyStuffController.getMyPostsArchive(20, 0, 'Need');
            System.assertNotEquals(null, filteredResult, 'Filtered result should not be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyStoriesArchive() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            // Only 3 stories exist; archive excludes the 10 most recent, so 0 in archive
            FimbyMyStuffController.ArchiveResult result = FimbyMyStuffController.getMyStoriesArchive(20, 0, 'All');
            System.assertNotEquals(null, result, 'Archive result should not be null');
            System.assertEquals(0, result.totalCount, 'Should have 0 stories in archive (all 3 are recent)');

            // Test with type filter
            FimbyMyStuffController.ArchiveResult filteredResult = FimbyMyStuffController.getMyStoriesArchive(20, 0, 'Thank You');
            System.assertNotEquals(null, filteredResult, 'Filtered result should not be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyLibraryItemsArchive() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            FimbyMyStuffController.ArchiveResult result = FimbyMyStuffController.getMyLibraryItemsArchive(20, 0, 'All');
            System.assertNotEquals(null, result, 'Archive result should not be null');
            System.assertEquals(1, result.totalCount, 'Should have 1 unavailable library item in archive');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyBorrowHistory() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            FimbyMyStuffController.ArchiveResult result = FimbyMyStuffController.getMyBorrowHistory(20, 0, 'All');
            System.assertNotEquals(null, result, 'Borrow history result should not be null');
            System.assert(result.totalCount >= 0, 'Total count should be non-negative');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyContacts() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            // No shared contacts in base setup, should return empty list
            List<FimbyMyStuffController.ContactCardWrapper> contacts = FimbyMyStuffController.getMyContacts(null);
            System.assertNotEquals(null, contacts, 'Contacts should not be null');
            System.assertEquals(0, contacts.size(), 'Should return 0 contacts (none shared in setup)');

            // Test with search term
            List<FimbyMyStuffController.ContactCardWrapper> searched = FimbyMyStuffController.getMyContacts('Someone');
            System.assertNotEquals(null, searched, 'Searched contacts should not be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyContactsWithSharedInfo() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        // Create a second contact and share info
        Contact otherContact = new Contact(
            FirstName = 'Other',
            LastName = 'Neighbour',
            Email = 'other@test.com',
            AccountId = testNeighbourhood.Id
        );
        insert otherContact;

        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = testContact.Id,
            Shared_To__c = otherContact.Id,
            Email__c = 'other@test.com',
            Phone__c = '0400000000'
        );
        insert sci;

        Test.startTest();
        System.runAs(testUser) {
            List<FimbyMyStuffController.ContactCardWrapper> contacts = FimbyMyStuffController.getMyContacts(null);
            System.assertEquals(1, contacts.size(), 'Should return 1 shared contact');
            System.assertNotEquals(null, contacts[0].name, 'Contact should have a name');
            System.assertEquals(true, contacts[0].iSharedWithThem, 'testContact shared with otherContact');
            System.assertEquals(false, contacts[0].theySharedWithMe, 'otherContact did not share with testContact');
            System.assertEquals(sci.Id, contacts[0].mySharedInfoId, 'Should have mySharedInfoId for edit');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyContactsWithDirectionFlags() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Contact otherContact = new Contact(
            FirstName = 'Recipient',
            LastName = 'Neighbour',
            Email = 'recipient@test.com',
            AccountId = testNeighbourhood.Id
        );
        insert otherContact;

        Shared_Contact_Info__c sciThemShared = new Shared_Contact_Info__c(
            Contact__c = otherContact.Id,
            Shared_To__c = testContact.Id,
            Email__c = 'recipient@test.com',
            Phone__c = '0411111111'
        );
        insert sciThemShared;

        Test.startTest();
        System.runAs(testUser) {
            List<FimbyMyStuffController.ContactCardWrapper> contacts = FimbyMyStuffController.getMyContacts(null);
            System.assertEquals(1, contacts.size(), 'Should return 1 shared contact');
            System.assertEquals(true, contacts[0].theySharedWithMe, 'otherContact shared with testContact');
            System.assertEquals(false, contacts[0].iSharedWithThem, 'testContact did not share with otherContact');
            System.assertEquals(null, contacts[0].mySharedInfoId, 'No mySharedInfoId when they shared with me');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMineSummaryIncludesContacts() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Integer> summary = FimbyMyStuffController.getMineSummary();
            System.assert(summary.containsKey('contactsCount'), 'Should have contactsCount key');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyLibraryItemsWithActiveLoan() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];
        Library_Item__c testItem = [SELECT Id FROM Library_Item__c WHERE Owner_Contact__c = :testContact.Id LIMIT 1];

        // Create a loaned item so the loan-joining code is exercised
        System.runAs(testUser) {
            Loaned_Item__c loan = new Loaned_Item__c(
                Library_Item__c = testItem.Id,
                Loaned_To__c = testContact.Id,
                Loan_Start_Date__c = Date.today().addDays(-7),
                Loan_Due_Date__c = Date.today().addDays(7)
            );
            insert loan;
        }

        Test.startTest();
        System.runAs(testUser) {
            List<FimbyMyStuffController.LibraryItemWrapper> items = FimbyMyStuffController.getMyLibraryItems(20);

            System.assertNotEquals(null, items, 'Library items should not be null');
            System.assertEquals(3, items.size(), 'Should return 3 library items (1 loaned + 1 available + 1 unavailable)');

            // At least one item should have loan info
            Boolean foundLoanInfo = false;
            for (FimbyMyStuffController.LibraryItemWrapper w : items) {
                if (w.loanedToName != null) {
                    foundLoanInfo = true;
                }
            }
            System.assert(foundLoanInfo, 'At least one library item should have active loan info');

            // Also test borrowed items now that we have a loan
            List<FimbyMyStuffController.BorrowedItemWrapper> borrowed = FimbyMyStuffController.getMyBorrowedItems();
            System.assert(borrowed.size() > 0, 'Should return at least 1 borrowed item');
            System.assertNotEquals(null, borrowed[0].itemName, 'Borrowed item should have a name');
            System.assertNotEquals(null, borrowed[0].dueDate, 'Borrowed item should have a due date');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchNeighbourhoodContacts() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Map<String, Object>> results = FimbyMyStuffController.searchNeighbourhoodContacts('Resident');
            System.assertNotEquals(null, results, 'Results should not be null');
            System.assert(results.size() >= 2, 'Should find other neighbourhood contacts (excl self)');

            List<Map<String, Object>> emptyResults = FimbyMyStuffController.searchNeighbourhoodContacts('xyznonexistent');
            System.assertEquals(0, emptyResults.size(), 'No match search should return empty');

            List<Map<String, Object>> shortSearch = FimbyMyStuffController.searchNeighbourhoodContacts('a');
            System.assertEquals(0, shortSearch.size(), 'Search under 2 chars returns empty');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetMyContactDetailsForSharing() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> details = FimbyMyStuffController.getMyContactDetailsForSharing();
            System.assertNotEquals(null, details, 'Details should not be null');
            System.assert(details.containsKey('email'), 'Should have email key');
        }
        Test.stopTest();
    }

    @IsTest
    static void testRevokeSharedContactInfo() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Contact otherContact = new Contact(
            FirstName = 'Revoke',
            LastName = 'Target',
            Email = 'revoke@test.com',
            AccountId = testNeighbourhood.Id
        );
        insert otherContact;

        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = testContact.Id,
            Shared_To__c = otherContact.Id,
            Email__c = 'revoke@test.com',
            Status__c = 'Active'
        );
        insert sci;

        Test.startTest();
        System.runAs(testUser) {
            // Verify it appears as active
            List<FimbyMyStuffController.ContactCardWrapper> contacts = FimbyMyStuffController.getMyContacts(null);
            FimbyMyStuffController.ContactCardWrapper card = null;
            for (FimbyMyStuffController.ContactCardWrapper c : contacts) {
                if (c.contactId == otherContact.Id) card = c;
            }
            System.assertNotEquals(null, card, 'Should find the contact');
            System.assertEquals(false, card.isRevoked, 'Should not be revoked initially');

            // Revoke
            FimbyMyStuffController.revokeSharedContactInfo(sci.Id);

            // Verify it now shows as revoked
            contacts = FimbyMyStuffController.getMyContacts(null);
            card = null;
            for (FimbyMyStuffController.ContactCardWrapper c : contacts) {
                if (c.contactId == otherContact.Id) card = c;
            }
            System.assertNotEquals(null, card, 'Should still find the contact');
            System.assertEquals(true, card.isRevoked, 'Should be revoked');
            System.assertEquals('Revoked', card.mySharedStatus, 'Status should be Revoked');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUndoRevokeSharedContactInfo() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Contact otherContact = new Contact(
            FirstName = 'Undo',
            LastName = 'Target',
            Email = 'undo@test.com',
            AccountId = testNeighbourhood.Id
        );
        insert otherContact;

        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = testContact.Id,
            Shared_To__c = otherContact.Id,
            Email__c = 'undo@test.com',
            Status__c = 'Revoked'
        );
        insert sci;

        Test.startTest();
        System.runAs(testUser) {
            // Undo the revoke
            FimbyMyStuffController.undoRevokeSharedContactInfo(sci.Id);

            // Verify it's active again
            List<FimbyMyStuffController.ContactCardWrapper> contacts = FimbyMyStuffController.getMyContacts(null);
            FimbyMyStuffController.ContactCardWrapper card = null;
            for (FimbyMyStuffController.ContactCardWrapper c : contacts) {
                if (c.contactId == otherContact.Id) card = c;
            }
            System.assertNotEquals(null, card, 'Should find the contact');
            System.assertEquals(false, card.isRevoked, 'Should no longer be revoked');
            System.assertEquals('Active', card.mySharedStatus, 'Status should be Active');
        }
        Test.stopTest();
    }

    @IsTest
    static void testShareContactInfoDirect() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 2];
        Contact testContact = contacts[0];
        Contact otherContact = contacts[1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        String shareData = '{"recipientContactId":"' + otherContact.Id + '",' +
            '"shareEmail":true,"sharePhone":false,"shareAddress":false,' +
            '"email":"share@test.com","phone":"","street":"","city":"","state":"","postalCode":"","country":""}';

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyMyStuffController.shareContactInfoDirect(shareData);
            System.assertEquals(true, result.get('success'), 'Share should succeed');
            System.assertNotEquals(null, result.get('sharedContactInfoId'), 'Should return Shared_Contact_Info__c Id');
        }
        Test.stopTest();
    }

    @IsTest
    static void testShareContactInfoDirectReactivatesRevoked() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Contact otherContact = new Contact(
            FirstName = 'Reactivate',
            LastName = 'Target',
            Email = 'reactivate@test.com',
            AccountId = testNeighbourhood.Id
        );
        insert otherContact;

        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = testContact.Id,
            Shared_To__c = otherContact.Id,
            Email__c = 'old@test.com',
            Status__c = 'Revoked'
        );
        insert sci;

        String shareData = '{"recipientContactId":"' + otherContact.Id + '",' +
            '"shareEmail":true,"sharePhone":false,"shareAddress":false,' +
            '"email":"new@test.com","phone":"","street":"","city":"","state":"","postalCode":"","country":""}';

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyMyStuffController.shareContactInfoDirect(shareData);
            System.assertEquals(true, result.get('success'), 'Re-share should succeed');
        }
        Test.stopTest();

        sci = [SELECT Status__c, Email__c FROM Shared_Contact_Info__c WHERE Id = :sci.Id];
        System.assertEquals('Active', sci.Status__c, 'Re-share should reactivate revoked record');
        System.assertEquals('new@test.com', sci.Email__c, 'Email should update on re-share');
    }

    @IsTest
    static void testShareContactInfoDirectPreservesAdditionalInfo() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 2];
        Contact testContact = contacts[0];
        Contact otherContact = contacts[1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = testContact.Id,
            Shared_To__c = otherContact.Id,
            Email__c = 'keep@test.com',
            Additional_Info__c = 'Ring the side gate',
            Status__c = 'Active'
        );
        insert sci;

        String shareData = '{"recipientContactId":"' + otherContact.Id + '",' +
            '"shareEmail":true,"sharePhone":false,"shareAddress":false,' +
            '"email":"keep@test.com","phone":"","street":"","city":"","state":"","postalCode":"","country":""}';

        Test.startTest();
        System.runAs(testUser) {
            FimbyMyStuffController.shareContactInfoDirect(shareData);
        }
        Test.stopTest();

        sci = [SELECT Additional_Info__c FROM Shared_Contact_Info__c WHERE Id = :sci.Id];
        System.assertEquals('Ring the side gate', sci.Additional_Info__c,
            'Additional info should be preserved when not sent in payload');
    }

    @IsTest
    static void testGetNeighbourProfile_sameNeighbourhood() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate];
        Contact viewer = contacts[0];
        Contact neighbour = contacts[1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> profile = FimbyMyStuffController.getNeighbourProfile(neighbour.Id);
            System.assertEquals(neighbour.Id, profile.get('contactId'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetNeighbourProfile_deniedCrossNeighbourhood() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Account otherNeighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        otherNeighbourhood.Name = 'Remote Neighbourhood';
        update otherNeighbourhood;
        Contact remoteContact = FimbyTestDataFactory.createNeighbourhoodContact(otherNeighbourhood.Id, true);

        Boolean threw = false;
        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyMyStuffController.getNeighbourProfile(remoteContact.Id);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Cross-neighbourhood profile should be denied');
    }
}