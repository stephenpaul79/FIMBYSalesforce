@IsTest
public class FimbyHomeControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create neighbourhood and contact using factory
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        // Create community user with correct profile
        User communityUser = FimbyTestDataFactory.createCommunityUser(contact.Id, 'Customer Community User - Mobile App', true);

        // Create test data
        List<Story__c> stories = FimbyTestDataFactory.createStories(neighbourhood.Id, contact.Id, 5, true);
        List<Needs_Offers__c> askOfferItems = FimbyTestDataFactory.createAskOfferItems(neighbourhood.Id, contact.Id, 3, true);
        List<Library_Item__c> libraryItems = FimbyTestDataFactory.createLibraryItems(neighbourhood.Id, contact.Id, 2, true);

        // The factory creates everything we need:
        // - 1 neighbourhood with proper naming
        // - 1 contact linked to neighbourhood
        // - 1 community user with correct profile
        // - 5 stories
        // - 3 ask & offer items
        // - 2 library items
    }

    @IsTest
    static void testGetStories() {
        // Get test data created by factory
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            FimbyHomeController.StoriesResult result = FimbyHomeController.getStories(0, 10);

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertNotEquals(null, result.stories, 'Stories list should not be null');
            System.assertEquals(5, result.stories.size(), 'Should return 5 stories');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetAskOfferItems() {
        // Get test data created by factory
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Needs_Offers__c> result = FimbyHomeController.getAskOfferItems(0, 10);

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertEquals(3, result.size(), 'Should return 3 ask & offer items');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetLibraryItems() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Map<String, Object>> result = FimbyHomeController.getLibraryItems(0, 10);

            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertEquals(2, result.size(), 'Should return 2 library items');

            Map<String, Object> first = result[0];
            System.assertNotEquals(null, first.get('viewerState'), 'Should have viewerState');
            System.assertNotEquals(null, first.get('ctaLabel'), 'Should have ctaLabel');
            System.assertNotEquals(null, first.get('statusPillLabel'), 'Should have statusPillLabel');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetLibraryItems_ViewerContractOwner() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            List<Map<String, Object>> result = FimbyHomeController.getLibraryItems(0, 10);
            for (Map<String, Object> row : result) {
                System.assertEquals(FimbyConstants.LIB_VIEW_OWNER, row.get('viewerState'),
                    'Items owned by user should have owner viewerState');
                System.assertEquals('View Item', row.get('ctaLabel'), 'Owner CTA should be View Item');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetLibraryItems_AllBrowseableStatuses() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Library_Item__c onHoldItem = new Library_Item__c(
            Name = 'On Hold Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testNeighbourhood.Id, Status__c = 'On Hold'
        );
        Library_Item__c lentOutItem = new Library_Item__c(
            Name = 'Lent Out Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testNeighbourhood.Id, Status__c = 'Currently Lent Out'
        );
        insert new List<Library_Item__c>{ onHoldItem, lentOutItem };

        Test.startTest();
        System.runAs(testUser) {
            List<Map<String, Object>> result = FimbyHomeController.getLibraryItems(0, 20);
            System.assert(result.size() >= 4, 'Should return Available + On Hold + Currently Lent Out items');

            Set<String> statuses = new Set<String>();
            for (Map<String, Object> row : result) {
                statuses.add((String) row.get('Status__c'));
            }
            System.assert(statuses.contains('Available'), 'Should include Available items');
            System.assert(statuses.contains('On Hold'), 'Should include On Hold items');
            System.assert(statuses.contains('Currently Lent Out'), 'Should include Currently Lent Out items');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetStoriesException() {
        // Test exception handling using force exception parameter
        Test.startTest();
        try {
            // Use the overloaded method with forceException = true
            FimbyHomeController.getStories(0, 10, true);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Script-thrown exception') || e.getMessage().contains('Test exception for getStories'), 'Should contain test exception message: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetAskOfferItemsException() {
        // Test exception handling using force exception parameter
        Test.startTest();
        try {
            // Use the overloaded method with forceException = true
            FimbyHomeController.getAskOfferItems(10, true);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Script-thrown exception') || e.getMessage().contains('Test exception for getAskOfferItems'), 'Should contain test exception message: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetLibraryItemsException() {
        // Test exception handling using force exception parameter
        Test.startTest();
        try {
            // Use the overloaded method with forceException = true
            FimbyHomeController.getLibraryItems(10, true);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Script-thrown exception') || e.getMessage().contains('Test exception for getLibraryItems'), 'Should contain test exception message: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetUnifiedFeedReturnsAllTypes() {
        // Get test data created by factory
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            // Call unified feed with large page size to get all items
            FimbyHomeController.UnifiedFeedResult feedResult = FimbyHomeController.getUnifiedFeed(0, 50);

            // Verify result structure
            System.assertNotEquals(null, feedResult, 'Feed result should not be null');
            System.assertNotEquals(null, feedResult.items, 'Items list should not be null');
            System.assert(feedResult.items.size() > 0, 'Should return at least one item');

            // Collect feed types present in results
            Set<String> typesFound = new Set<String>();
            for (FimbyFeedItem feedItem : feedResult.items) {
                typesFound.add(feedItem.feedType);
                // Verify each item has required fields
                System.assertNotEquals(null, feedItem.recordId, 'Item recordId required');
                System.assertNotEquals(null, feedItem.objectApiName, 'Item objectApiName required');
            }

            // Verify all three content types are present
            System.assert(typesFound.contains('story'), 'Feed should include stories');
            System.assert(typesFound.contains('askOffer'), 'Feed should include ask & offer items');
            System.assert(typesFound.contains('library'), 'Feed should include library items');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetUnifiedFeedIncludesJustListedSkills() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Skill_Offer__c visibleSkill = new Skill_Offer__c(
            Name = 'Bike Repair',
            Skill_Category__c = 'Yard & Outdoor Work',
            Description__c = 'Happy to true a wheel.',
            Availability_Note__c = 'Weekday evenings',
            Owner_Contact__c = testContact.Id,
            Listed_By__c = testContact.Id,
            Neighbourhood__c = testNeighbourhood.Id,
            Status__c = FimbyConstants.SKILL_ACTIVE,
            Moderation_Status__c = 'Visible'
        );
        Skill_Offer__c hiddenSkill = visibleSkill.clone(false, true);
        hiddenSkill.Name = 'Hidden Skill';
        hiddenSkill.Moderation_Status__c = 'Hidden_By_Moderator';
        insert new List<Skill_Offer__c>{ visibleSkill, hiddenSkill };

        Test.startTest();
        System.runAs(testUser) {
            FimbyFeedItem skillItem;
            Boolean hiddenFound = false;
            for (FimbyFeedItem item : FimbyHomeController.getUnifiedFeed(0, 50).items) {
                if (item.recordId == visibleSkill.Id) skillItem = item;
                if (item.recordId == hiddenSkill.Id) hiddenFound = true;
            }
            System.assertNotEquals(null, skillItem, 'Active skill should appear in the All feed');
            System.assertEquals('skill', skillItem.feedType);
            System.assertEquals('Skill_Offer__c', skillItem.objectApiName);
            System.assertEquals('Weekday evenings', skillItem.availabilityNote);
            System.assertEquals(String.valueOf(testContact.Id), skillItem.ownerContactId);
            System.assert(!hiddenFound, 'Moderator-hidden skill must not appear');

            for (FimbyFeedItem item : FimbyHomeController.getUnifiedFeed(0, 50, 'askOffer', null).items) {
                System.assertNotEquals('skill', item.feedType, 'Skills only show under the All filter');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testUnifiedFeedStoryEngagementCountFromRollup() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Story__c story = [SELECT Id FROM Story__c WHERE Neighbourhood__c = :testNeighbourhood.Id LIMIT 1];

        insert new List<Story_Comment__c>{
            new Story_Comment__c(
                Story__c = story.Id,
                Body__c = 'Visible comment 1',
                Status__c = 'Active',
                Moderation_Status__c = 'Visible',
                Contact__c = testContact.Id,
                Posted_By__c = testContact.Id,
                Neighbourhood__c = testNeighbourhood.Id,
                Edit_Count__c = 0
            ),
            new Story_Comment__c(
                Story__c = story.Id,
                Body__c = 'Visible comment 2',
                Status__c = 'Active',
                Moderation_Status__c = 'Visible',
                Contact__c = testContact.Id,
                Posted_By__c = testContact.Id,
                Neighbourhood__c = testNeighbourhood.Id,
                Edit_Count__c = 0
            ),
            new Story_Comment__c(
                Story__c = story.Id,
                Body__c = 'Author-hidden (should not count)',
                Status__c = 'Hidden_By_Author',
                Moderation_Status__c = 'Visible',
                Contact__c = testContact.Id,
                Posted_By__c = testContact.Id,
                Neighbourhood__c = testNeighbourhood.Id,
                Edit_Count__c = 0
            )
        };

        Test.startTest();
        FimbyHomeController.UnifiedFeedResult feedResult;
        System.runAs(testUser) {
            feedResult = FimbyHomeController.getUnifiedFeed(0, 50);
        }
        Test.stopTest();

        Integer engagement = -1;
        for (FimbyFeedItem item : feedResult.items) {
            if (item.feedType == 'story' && item.recordId == story.Id) {
                engagement = item.engagementCount;
                break;
            }
        }
        System.assertEquals(2, engagement,
            'UnifiedFeedItem.engagementCount should reflect Comment_Count__c roll-up (Active + Visible only)');
    }

    @IsTest
    static void testGetUnifiedFeedSorting() {
        // Get test data created by factory
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            FimbyHomeController.UnifiedFeedResult feedResult = FimbyHomeController.getUnifiedFeed(0, 50);

            // Verify chronological order (newest first)
            List<FimbyFeedItem> items = feedResult.items;
            for (Integer i = 0; i < items.size() - 1; i++) {
                Datetime current = items[i].createdDate;
                Datetime next = items[i + 1].createdDate;
                System.assert(current >= next, 'Items must be sorted newest to oldest');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetUnifiedFeedPagination() {
        // Get test data created by factory
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        Test.startTest();
        System.runAs(testUser) {
            // Request small page to test pagination
            Integer pageSize = 3;
            FimbyHomeController.UnifiedFeedResult firstPage = FimbyHomeController.getUnifiedFeed(0, pageSize);

            System.assertEquals(pageSize, firstPage.items.size(), 'First page should have requested size');
            System.assert(firstPage.totalCount >= pageSize, 'Total should be at least page size');

            if (firstPage.hasMore) {
                // Fetch next page
                FimbyHomeController.UnifiedFeedResult secondPage = FimbyHomeController.getUnifiedFeed(pageSize, pageSize);
                System.assert(secondPage.items.size() > 0, 'Second page should have items when hasMore is true');

                // Ensure no overlap between pages
                Set<String> firstPageIds = new Set<String>();
                for (FimbyFeedItem item : firstPage.items) {
                    firstPageIds.add(item.recordId);
                }
                for (FimbyFeedItem item : secondPage.items) {
                    System.assert(!firstPageIds.contains(item.recordId), 'Pages should not overlap');
                }
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetOrganizationId() {
        Test.startTest();
        String orgId = FimbyHomeController.getOrganizationId();
        System.assertNotEquals(null, orgId, 'Organization ID should not be null');
        System.assertEquals(UserInfo.getOrganizationId(), orgId, 'Should return correct Organization ID');
        Test.stopTest();
    }

    @IsTest
    static void testGetUnifiedFeedHidesBlockedAuthors() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact viewer = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :viewer.Id LIMIT 1];
        Contact blockedAuthor = FimbyTestDataFactory.createNeighbourhoodContact(testNeighbourhood.Id, true);
        Story__c blockedStory = FimbyTestDataFactory.createStories(
            testNeighbourhood.Id, blockedAuthor.Id, 1, true
        )[0];

        insert new Blocked_Contact__c(
            Blocker__c = viewer.Id,
            Blocked__c = blockedAuthor.Id,
            Reason__c = 'QA block filter test'
        );

        Test.startTest();
        System.runAs(testUser) {
            FimbyHomeController.UnifiedFeedResult result = FimbyHomeController.getUnifiedFeed(0, 50);
            for (FimbyFeedItem item : result.items) {
                System.assertNotEquals(blockedStory.Id, item.recordId,
                    'Blocked author content should not appear in unified feed');
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void testFeedItemAskOfferDescriptionPrefersFullDetails() {
        Needs_Offers__c legacyOnly = new Needs_Offers__c(
            Details__c = 'Only preview',
            Full_Details__c = null
        );
        System.assertEquals(
            'Only preview',
            FimbyFeedItem.resolveAskOfferFeedDescription(legacyOnly),
            'Legacy rows without Full_Details__c should fall back to Details__c'
        );

        Needs_Offers__c withFull = new Needs_Offers__c(
            Details__c = 'preview...',
            Full_Details__c = 'Complete body text'
        );
        System.assertEquals(
            'Complete body text',
            FimbyFeedItem.resolveAskOfferFeedDescription(withFull),
            'Feed description should prefer Full_Details__c'
        );
    }

    @IsTest
    static void testUnifiedFeedAskOfferUsesFullDetails() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];

        String fullBody = 'FEED-FULL-MARKER-' + 'abcdefghijklmnopqrstuvwxyz'.repeat(20);
        String preview = fullBody.substring(0, 252) + '...';

        Id needRtId = Schema.SObjectType.Needs_Offers__c
            .getRecordTypeInfosByDeveloperName()
            .get('Need')
            .getRecordTypeId();

        Needs_Offers__c longAsk = new Needs_Offers__c(
            Name = 'Long body ask',
            Details__c = preview,
            Full_Details__c = fullBody,
            Type__c = 'Goods - Unperishable',
            Status__c = 'Posted',
            Neighbourhood__c = testNeighbourhood.Id,
            Contact__c = testContact.Id,
            Posted_By__c = testContact.Id,
            RecordTypeId = needRtId,
            Posted_Date__c = Datetime.now(),
            End_Date__c = Date.today().addDays(7)
        );
        insert longAsk;

        Test.startTest();
        System.runAs(testUser) {
            FimbyHomeController.UnifiedFeedResult feedResult = FimbyHomeController.getUnifiedFeed(0, 50);
            Boolean found = false;
            for (FimbyFeedItem item : feedResult.items) {
                if (item.recordId == longAsk.Id) {
                    found = true;
                    System.assertEquals(
                        fullBody,
                        item.description,
                        'Unified feed should return Full_Details__c for ask/offer cards'
                    );
                    break;
                }
            }
            System.assert(found, 'Long ask post should appear in unified feed');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUnifiedFeedShowsActiveAndLingeringPostsOnly() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :testContact.Id LIMIT 1];
        Id needRtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();

        Map<String, Needs_Offers__c> byLabel = new Map<String, Needs_Offers__c>{
            'accepted' => lifecyclePost('Accepted ask', 'Reply Accepted', null),
            'recent' => lifecyclePost('Recently answered', FimbyConstants.NEEDS_OFFERS_COMPLETED, Datetime.now().addDays(-2)),
            'old' => lifecyclePost('Answered long ago', FimbyConstants.NEEDS_OFFERS_COMPLETED, Datetime.now().addDays(-30)),
            'expired' => lifecyclePost('Quietly expired', 'Expired', Datetime.now().addDays(-1)),
            'cancelled' => lifecyclePost('Withdrawn', 'Cancelled', Datetime.now().addDays(-1))
        };
        for (Needs_Offers__c p : byLabel.values()) {
            p.Neighbourhood__c = testNeighbourhood.Id;
            p.Contact__c = testContact.Id;
            p.Posted_By__c = testContact.Id;
            p.RecordTypeId = needRtId;
        }
        insert byLabel.values();

        Test.startTest();
        Map<Id, FimbyFeedItem> shown = new Map<Id, FimbyFeedItem>();
        System.runAs(testUser) {
            for (FimbyFeedItem item : FimbyHomeController.getUnifiedFeed(0, 50).items) {
                shown.put(Id.valueOf(item.recordId), item);
            }
        }
        Test.stopTest();

        System.assert(shown.containsKey(byLabel.get('accepted').Id), 'Accepted asks stay visible.');
        System.assert(shown.containsKey(byLabel.get('recent').Id), 'Completed asks linger in the feed.');
        System.assertEquals('Answered', shown.get(byLabel.get('recent').Id).closedOutcome);
        System.assertEquals(0, shown.get(byLabel.get('accepted').Id).replyCount);
        System.assert(!shown.containsKey(byLabel.get('old').Id), 'Completed asks leave after the linger window.');
        System.assert(!shown.containsKey(byLabel.get('expired').Id), 'Expired asks leave the feed.');
        System.assert(!shown.containsKey(byLabel.get('cancelled').Id), 'Withdrawn asks leave the feed.');
    }

    private static Needs_Offers__c lifecyclePost(String name, String status, Datetime closedDate) {
        return new Needs_Offers__c(
            Name = name,
            Details__c = name,
            Type__c = 'Goods - Unperishable',
            Status__c = status,
            Closed_Date__c = closedDate,
            Posted_Date__c = Datetime.now().addDays(-3),
            End_Date__c = Date.today().addDays(7)
        );
    }

}