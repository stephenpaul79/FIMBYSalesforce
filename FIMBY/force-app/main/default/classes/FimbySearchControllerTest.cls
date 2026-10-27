@IsTest
public class FimbySearchControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User communityUser = FimbyTestDataFactory.createCommunityUser(contact.Id, 'Customer Community User - Mobile App', true);

        List<Story__c> stories = FimbyTestDataFactory.createStories(neighbourhood.Id, contact.Id, 3, true);
        List<Needs_Offers__c> askOfferItems = FimbyTestDataFactory.createAskOfferItems(neighbourhood.Id, contact.Id, 3, true);
        List<Library_Item__c> libraryItems = FimbyTestDataFactory.createLibraryItems(neighbourhood.Id, contact.Id, 2, true);

        // Create a second contact to be a shared contact
        Contact secondContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        // Create Shared_Contact_Info__c record between the two contacts
        Shared_Contact_Info__c sharedInfo = new Shared_Contact_Info__c(
            Contact__c = secondContact.Id,
            Shared_To__c = contact.Id
        );
        insert sharedInfo;
    }

    @IsTest
    static void testSearchAllFilter() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            // SOSL requires setting fixed search results in tests
            List<Id> fixedSearchResults = new List<Id>();
            for (Story__c s : [SELECT Id FROM Story__c]) { fixedSearchResults.add(s.Id); }
            for (Needs_Offers__c no : [SELECT Id FROM Needs_Offers__c]) { fixedSearchResults.add(no.Id); }
            for (Library_Item__c li : [SELECT Id FROM Library_Item__c]) { fixedSearchResults.add(li.Id); }
            for (Contact c : [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id]) { fixedSearchResults.add(c.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'all', 'relevance', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertNotEquals(null, result.items, 'Items should not be null');
            System.assert(result.items.size() > 0, 'Should return at least one result');
            System.assertNotEquals(null, result.countsByType, 'Counts by type should not be null');
            System.assert(result.countsByType.get('stories') >= 0, 'Stories count should exist');
            System.assert(result.countsByType.get('askOffer') >= 0, 'AskOffer count should exist');
            System.assert(result.countsByType.get('library') >= 0, 'Library count should exist');
            System.assert(result.countsByType.get('people') >= 0, 'People count should exist');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchStoriesFilter() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Story__c s : [SELECT Id FROM Story__c]) { fixedSearchResults.add(s.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'stories', 'newest', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertEquals('story', item.resultType, 'All results should be stories');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchAskOfferFilter() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Needs_Offers__c no : [SELECT Id FROM Needs_Offers__c]) { fixedSearchResults.add(no.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'askOffer', 'relevance', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertEquals('askOffer', item.resultType, 'All results should be askOffer');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchLibraryFilter() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Library_Item__c li : [SELECT Id FROM Library_Item__c]) { fixedSearchResults.add(li.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'library', 'relevance', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertEquals('library', item.resultType, 'All results should be library');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchPeopleFilter() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Resident', 'people', 'relevance', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assert(result.countsByType.get('people') > 0, 'People SOQL search should match neighbourhood contacts by name');
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertEquals('people', item.resultType, 'All results should be people');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchSharedContactFlag() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        List<Contact> contacts = [
            SELECT Id, FirstName
            FROM Contact
            WHERE AccountId = :testNeighbourhood.Id
            ORDER BY CreatedDate ASC
        ];
        Contact viewer = contacts[0];
        Contact sharedContact = contacts[1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            FimbySearchController.SearchResult result = FimbySearchController.search(
                sharedContact.FirstName, 'people', 'relevance', 20, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            Boolean foundShared = false;
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertNotEquals(null, item.hasSharedContact,
                    'People results must have hasSharedContact flag set');
                if (item.recordId == sharedContact.Id) {
                    foundShared = true;
                    System.assertEquals(true, item.hasSharedContact,
                        'Contact with shared info should be flagged as shared');
                }
            }
            System.assertEquals(true, foundShared, 'Shared contact should appear in people results');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchPeopleUnsharedBioNotMatched() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate ASC LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Contact privateContact = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, true);
        privateContact.About_Fun_Fact__c = 'SecretBioTokenUnshared999';
        update privateContact;

        Test.startTest();
        System.runAs(testUser) {
            FimbySearchController.SearchResult result = FimbySearchController.search(
                'SecretBioTokenUnshared999', 'people', 'relevance', 20, 0
            );

            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertNotEquals(privateContact.Id, item.recordId,
                    'Unshared contact bio text must not surface in people search');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchPeopleSharedBioMatched() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        List<Contact> contacts = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :testNeighbourhood.Id
            ORDER BY CreatedDate ASC
        ];
        Contact viewer = contacts[0];
        Contact sharedContact = contacts[1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        sharedContact.About_Enjoys_Doing__c = 'SharedBioTokenVisible777';
        update sharedContact;

        Test.startTest();
        System.runAs(testUser) {
            FimbySearchController.SearchResult result = FimbySearchController.search(
                'SharedBioTokenVisible777', 'people', 'relevance', 20, 0
            );

            Boolean found = false;
            for (FimbySearchController.SearchResultItem item : result.items) {
                if (item.recordId == sharedContact.Id) {
                    found = true;
                    System.assertEquals(true, item.hasSharedContact,
                        'Bio match should only apply to shared contacts');
                    System.assertNotEquals(null, item.description,
                        'Shared contact may show bio in search results');
                }
            }
            System.assertEquals(true, found,
                'Shared contact should match on profile bio fields');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchPeopleMatchesSharedSnapshotEmail() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate ASC LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        // A contact whose NAME does not contain the token
        Contact friend = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, false);
        friend.FirstName = 'Appy';
        friend.LastName = 'Reviewer';
        insert friend;

        // They shared their contact info (incl. email) TO the viewer
        insert new Shared_Contact_Info__c(
            Contact__c = friend.Id,
            Shared_To__c = viewer.Id,
            Email__c = 'stephenpaul79@example.com'
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbySearchController.SearchResult result = FimbySearchController.search(
                'stephen', 'people', 'relevance', 20, 0
            );

            Boolean found = false;
            for (FimbySearchController.SearchResultItem item : result.items) {
                if (item.recordId == friend.Id) { found = true; }
            }
            System.assertEquals(true, found,
                'Shared contact should be findable by an email token they shared with me');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchPeopleSnapshotDirectionRespected() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate ASC LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Contact other = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, false);
        other.FirstName = 'Quiet';
        other.LastName = 'Neighbour';
        insert other;

        // Only the viewer -> other direction exists, holding the VIEWER's email,
        // not the other contact's. Searching that token must not surface 'other'.
        insert new Shared_Contact_Info__c(
            Contact__c = viewer.Id,
            Shared_To__c = other.Id,
            Email__c = 'uniqueviewertoken@example.com'
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbySearchController.SearchResult result = FimbySearchController.search(
                'uniqueviewertoken', 'people', 'relevance', 20, 0
            );
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertNotEquals(other.Id, item.recordId,
                    'Snapshot search must only use the to-me direction');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchPeopleHidesBlockedContact() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate ASC LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Contact blockedContact = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, false);
        blockedContact.FirstName = 'Blocked';
        blockedContact.LastName = 'SearchTargetZzz';
        insert blockedContact;
        insert new Blocked_Contact__c(Blocker__c = viewer.Id, Blocked__c = blockedContact.Id);

        Test.startTest();
        System.runAs(testUser) {
            FimbySearchController.SearchResult result = FimbySearchController.search(
                'SearchTargetZzz', 'people', 'relevance', 20, 0
            );

            System.assertEquals(0, result.countsByType.get('people'),
                'Blocked contacts must not appear in people search');
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertNotEquals(blockedContact.Id, item.recordId,
                    'Blocked contact must not appear in people search');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testAskOfferResultUsesRepresentedOwnerAndMaskedAvatar() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate ASC LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Contact represented = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, false);
        represented.Image_URL__c = 'https://example.com/hidden-photo.jpg';
        represented.Mask_Avatar__c = true;
        insert represented;

        Needs_Offers__c representedPost = FimbyTestDataFactory.createAskOfferItems(testNeighbourhood.Id, viewer.Id, 1, true)[0];
        representedPost.Contact__c = represented.Id;
        representedPost.Posted_By__c = viewer.Id;
        update representedPost;

        Test.startTest();
        System.runAs(testUser) {
            Test.setFixedSearchResults(new List<Id>{ representedPost.Id });
            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'askOffer', 'relevance', 20, 0
            );

            Map<Id, FimbySearchController.SearchResultItem> byId = new Map<Id, FimbySearchController.SearchResultItem>();
            for (FimbySearchController.SearchResultItem item : result.items) {
                byId.put(item.recordId, item);
            }
            FimbySearchController.SearchResultItem representedItem = byId.get(representedPost.Id);
            System.assertNotEquals(null, representedItem, 'Represented post should be returned');
            System.assertEquals(represented.Id, representedItem.postedByContactId,
                'Ask/offer owner must be the represented Contact__c, not the real author');
            System.assert(String.isBlank(representedItem.postedByImageUrl),
                'A masked profile photo must never be returned');
            System.assertEquals(false, representedItem.isOrgContact, 'Person owner is not an org');
        }
        Test.stopTest();
    }

    @IsTest
    static void testApplyOwnerPrefersOrganisationLogo() {
        Account orgAccount = new Account(Name = 'Logo Org');
        insert orgAccount;
        Contact orgOwner = new Contact(
            Id = FimbyTestDataFactory.createNeighbourhoodContact(
                [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1].Id, true).Id,
            Is_Organization_Contact__c = true,
            Organization_Account__c = orgAccount.Id
        );
        orgOwner.putSObject('Organization_Account__r', new Account(Id = orgAccount.Id, Logo_URL__c = 'https://example.com/logo.png'));

        FimbySearchController.SearchResultItem item = new FimbySearchController.SearchResultItem();
        FimbySearchController.applyOwner(item, orgOwner.Id, orgOwner);

        System.assertEquals(orgOwner.Id, item.postedByContactId, 'Owner id should be set');
        System.assertEquals(true, item.isOrgContact, 'Org flag should be set');
        System.assertEquals(orgAccount.Id, item.orgAccountId, 'Org account should be set');
        System.assertEquals('https://example.com/logo.png', item.postedByImageUrl, 'Logo wins for organisations');
    }

    @IsTest
    static void testStoryResultCarriesOrganisationIdentityAndLogo() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate ASC LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Account orgAccount = new Account(Name = 'The Life Test', Logo_URL__c = 'https://example.com/life-logo.png');
        try {
            orgAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();
        } catch (Exception e) { /* RT may not exist in test org */ }
        insert orgAccount;
        Contact orgContact = new Contact(
            FirstName = 'The', LastName = 'Life Test', AccountId = testNeighbourhood.Id,
            Is_Organization_Contact__c = true, Organization_Account__c = orgAccount.Id
        );
        insert orgContact;

        Story__c orgStory = FimbyTestDataFactory.createStories(testNeighbourhood.Id, orgContact.Id, 1, false)[0];
        orgStory.Posted_By__c = orgContact.Id;
        orgStory.Contact__c = viewer.Id;
        insert orgStory;

        Test.startTest();
        System.runAs(testUser) {
            Test.setFixedSearchResults(new List<Id>{ orgStory.Id });
            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'stories', 'relevance', 20, 0
            );
            FimbySearchController.SearchResultItem found;
            for (FimbySearchController.SearchResultItem item : result.items) {
                if (item.recordId == orgStory.Id) {
                    found = item;
                }
            }
            System.assertNotEquals(null, found, 'Org story should be returned');
            System.assertEquals(orgContact.Id, found.postedByContactId, 'Story owner is Posted_By__c');
            System.assertEquals(true, found.isOrgContact, 'Org flag should be set');
            System.assertEquals(orgAccount.Id, found.orgAccountId, 'Org account should be returned');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchStoriesHidesBlockedAuthor() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate ASC LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Contact blockedAuthor = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, true);
        Story__c blockedStory = FimbyTestDataFactory.createStories(testNeighbourhood.Id, blockedAuthor.Id, 1, true)[0];
        blockedStory.Name = 'Blocked Author Story Unique';
        update blockedStory;
        insert new Blocked_Contact__c(Blocker__c = viewer.Id, Blocked__c = blockedAuthor.Id);

        Test.startTest();
        System.runAs(testUser) {
            Test.setFixedSearchResults(new List<Id>{ blockedStory.Id });

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Blocked', 'stories', 'relevance', 20, 0
            );

            System.assertEquals(0, result.countsByType.get('stories'),
                'A blocked author\'s story must not be counted.');
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertNotEquals(blockedStory.Id, item.recordId,
                    'A blocked author\'s story must not be returned.');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchSkillsHidesBlockedAuthor() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id, AccountId FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate ASC LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Contact blockedAuthor = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, true);
        Skill_Offer__c blockedSkill = new Skill_Offer__c(
            Name = 'Test Blocked Skill',
            Skill_Category__c = 'Tech Help',
            Owner_Contact__c = blockedAuthor.Id,
            Listed_By__c = blockedAuthor.Id,
            Neighbourhood__c = testNeighbourhood.Id,
            Status__c = FimbyConstants.SKILL_ACTIVE,
            Moderation_Status__c = 'Visible'
        );
        insert blockedSkill;
        insert new Blocked_Contact__c(Blocker__c = viewer.Id, Blocked__c = blockedAuthor.Id);

        Test.startTest();
        System.runAs(testUser) {
            Test.setFixedSearchResults(new List<Id>{ blockedSkill.Id });

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'skills', 'relevance', 20, 0
            );

            System.assertEquals(0, result.countsByType.get('skills'),
                'A blocked author\'s skill must not be counted.');
            for (FimbySearchController.SearchResultItem item : result.items) {
                System.assertNotEquals(blockedSkill.Id, item.recordId,
                    'A blocked author\'s skill must not be returned.');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchEmptyTerm() {
        Test.startTest();
        FimbySearchController.SearchResult result = FimbySearchController.search(
            '', 'all', 'relevance', 20, 0
        );

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.totalCount, 'Empty search should return 0 results');
        System.assertEquals(false, result.hasMore, 'Empty search should have no more results');
        Test.stopTest();
    }

    @IsTest
    static void testSearchShortTerm() {
        Test.startTest();
        FimbySearchController.SearchResult result = FimbySearchController.search(
            'a', 'all', 'relevance', 20, 0
        );

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.totalCount, 'Short search term should return 0 results');
        Test.stopTest();
    }

    @IsTest
    static void testSearchNullTerm() {
        Test.startTest();
        FimbySearchController.SearchResult result = FimbySearchController.search(
            null, 'all', 'relevance', 20, 0
        );

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.totalCount, 'Null search should return 0 results');
        Test.stopTest();
    }

    @IsTest
    static void testSearchSortNewest() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Story__c s : [SELECT Id FROM Story__c]) { fixedSearchResults.add(s.Id); }
            for (Needs_Offers__c no : [SELECT Id FROM Needs_Offers__c]) { fixedSearchResults.add(no.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'all', 'newest', 50, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            // Verify newest-first ordering for items with dates
            List<FimbySearchController.SearchResultItem> items = result.items;
            for (Integer i = 0; i < items.size() - 1; i++) {
                if (items[i].createdDate != null && items[i + 1].createdDate != null) {
                    System.assert(items[i].createdDate >= items[i + 1].createdDate,
                        'Items should be sorted newest first');
                }
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchSortOldest() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Story__c s : [SELECT Id FROM Story__c]) { fixedSearchResults.add(s.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', 'stories', 'oldest', 50, 0
            );

            System.assertNotEquals(null, result, 'Result should not be null');
            List<FimbySearchController.SearchResultItem> items = result.items;
            for (Integer i = 0; i < items.size() - 1; i++) {
                if (items[i].createdDate != null && items[i + 1].createdDate != null) {
                    System.assert(items[i].createdDate <= items[i + 1].createdDate,
                        'Items should be sorted oldest first');
                }
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchPagination() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Id> fixedSearchResults = new List<Id>();
            for (Story__c s : [SELECT Id FROM Story__c]) { fixedSearchResults.add(s.Id); }
            for (Needs_Offers__c no : [SELECT Id FROM Needs_Offers__c]) { fixedSearchResults.add(no.Id); }
            for (Library_Item__c li : [SELECT Id FROM Library_Item__c]) { fixedSearchResults.add(li.Id); }
            Test.setFixedSearchResults(fixedSearchResults);

            // First page: small page size
            FimbySearchController.SearchResult firstPage = FimbySearchController.search(
                'Test', 'all', 'relevance', 2, 0
            );

            System.assertNotEquals(null, firstPage, 'First page should not be null');
            System.assert(firstPage.items.size() <= 2, 'First page should respect pageSize');

            if (firstPage.hasMore) {
                FimbySearchController.SearchResult secondPage = FimbySearchController.search(
                    'Test', 'all', 'relevance', 2, 2
                );

                System.assertNotEquals(null, secondPage, 'Second page should not be null');
                System.assert(secondPage.items.size() > 0, 'Second page should have items');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testSearchDefaultParameters() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            Test.setFixedSearchResults(new List<Id>());

            FimbySearchController.SearchResult result = FimbySearchController.search(
                'Test', null, null, null, null
            );

            System.assertNotEquals(null, result, 'Result should not be null with null parameters');
        }
        Test.stopTest();
    }

    private static Contact createLinkedOrg(String name, Id neighbourhoodId, Boolean approved, String linkStatus) {
        Account org = new Account(
            Name = name,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Organization').getRecordTypeId(),
            Is_Approved_Community_Group__c = approved,
            Description = name + ' description'
        );
        insert org;
        Contact orgContact = new Contact(
            FirstName = 'Org', LastName = name, AccountId = neighbourhoodId,
            Is_Organization_Contact__c = true, Organization_Account__c = org.Id
        );
        insert orgContact;
        org.Organization_Contact__c = orgContact.Id;
        update org;
        insert new Community_Group_Neighbourhood__c(
            Organization__c = org.Id, Neighbourhood__c = neighbourhoodId,
            Status__c = linkStatus, Is_Primary__c = (linkStatus == 'Active')
        );
        return orgContact;
    }

    @IsTest
    static void testSearchOrgsReturnsApprovedActiveLinkedOrgsOnly() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate ASC LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Contact approved = createLinkedOrg('Zephyr Approved Group', testNeighbourhood.Id, true, 'Active');
        createLinkedOrg('Zephyr Pending Group', testNeighbourhood.Id, false, 'Active');
        createLinkedOrg('Zephyr Unlinked Group', testNeighbourhood.Id, true, 'Inactive');
        Account elsewhere = FimbyTestDataFactory.createNeighbourhood(true);
        createLinkedOrg('Zephyr Elsewhere Group', elsewhere.Id, true, 'Active');

        Test.startTest();
        FimbySearchController.SearchResult result;
        System.runAs(testUser) {
            result = FimbySearchController.search('Zephyr', 'orgs', 'relevance', 20, 0);
        }
        Test.stopTest();

        System.assertEquals(1, result.items.size(), 'Only the approved, actively linked, in-neighbourhood org is returned');
        FimbySearchController.SearchResultItem item = result.items[0];
        System.assertEquals('org', item.resultType, 'Org results carry their own type');
        System.assertEquals(approved.Id, item.recordId, 'Result points at the org contact');
        System.assertEquals(true, item.isOrgContact, 'Org flag drives the rounded-square avatar');
        System.assertEquals('Zephyr Approved Group', item.name, 'Uses the organisation name');
        System.assertEquals(1, result.countsByType.get('orgs'), 'Orgs count matches');
    }

    @IsTest
    static void testSearchOrgsHidesBlockedOrgAndAllFilterIncludesOrgs() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate ASC LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];

        Contact visible = createLinkedOrg('Quokka Visible Group', testNeighbourhood.Id, true, 'Active');
        Contact blocked = createLinkedOrg('Quokka Blocked Group', testNeighbourhood.Id, true, 'Active');
        insert new Blocked_Contact__c(Blocker__c = viewer.Id, Blocked__c = blocked.Id);

        Test.startTest();
        FimbySearchController.SearchResult result;
        System.runAs(testUser) {
            Test.setFixedSearchResults(new List<Id>());
            result = FimbySearchController.search('Quokka', 'all', 'relevance', 20, 0);
        }
        Test.stopTest();

        Set<Id> orgIds = new Set<Id>();
        for (FimbySearchController.SearchResultItem item : result.items) {
            if (item.resultType == 'org') orgIds.add(item.recordId);
        }
        System.assert(orgIds.contains(visible.Id), 'All filter includes matching orgs');
        System.assert(!orgIds.contains(blocked.Id), 'Blocked org is hidden');
    }
}