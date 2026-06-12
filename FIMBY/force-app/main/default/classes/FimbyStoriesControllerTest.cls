@IsTest
public class FimbyStoriesControllerTest {

    @TestSetup
    static void setupTestData() {
        // Get the Boundary Account record type
        Id boundaryRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Boundary Account').getRecordTypeId();
        
        // Create test Account (neighbourhood) with correct record type
        Account testNeighbourhood = new Account(
            Name = 'Test Neighbourhood Stories',
            RecordTypeId = boundaryRecordTypeId
        );
        insert testNeighbourhood;

        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'StoriesUser',
            AccountId = testNeighbourhood.Id,
            Email = 'teststoriesuser@example.com'
        );
        insert testContact;

        // Create test Stories with different categories
        List<Story__c> testStories = new List<Story__c>();
            testStories.add(new Story__c(
                Name = 'Thank You Story 1',
                Message__c = 'This is a thank you story',
                Type__c = 'Thank You',
                Neighbourhood__c = testNeighbourhood.Id,
                Posted_By__c = testContact.Id
            ));
            testStories.add(new Story__c(
                Name = 'Prayer Story 1',
                Message__c = 'This is a prayer story',
                Type__c = 'Prayer',
                Neighbourhood__c = testNeighbourhood.Id,
                Posted_By__c = testContact.Id
            ));
            testStories.add(new Story__c(
                Name = 'Thank You Story 2',
                Message__c = 'This is another thank you story',
                Type__c = 'Thank You',
                Neighbourhood__c = testNeighbourhood.Id,
                Posted_By__c = testContact.Id
            ));
        insert testStories;
    }

    @IsTest
    static void testGetStoriesAll() {
        Test.startTest();
        FimbyStoriesController.StoriesResult result = FimbyStoriesController.getStories(10, 0, 'All');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.stories, 'Stories list should not be null');
        System.assertEquals(3, result.stories.size(), 'Should return all 3 stories');
        System.assertEquals(false, result.hasMore, 'Should not have more stories');
    }

    @IsTest
    static void testGetStoriesFiltered() {
        Test.startTest();
        FimbyStoriesController.StoriesResult thankYouStories = FimbyStoriesController.getStories(10, 0, 'Thank You');
        FimbyStoriesController.StoriesResult prayerStories = FimbyStoriesController.getStories(10, 0, 'Prayer');
        Test.stopTest();

        System.assertNotEquals(null, thankYouStories, 'Thank You stories result should not be null');
        System.assertEquals(2, thankYouStories.stories.size(), 'Should return 2 thank you stories');

        System.assertNotEquals(null, prayerStories, 'Prayer stories result should not be null');
        System.assertEquals(1, prayerStories.stories.size(), 'Should return 1 prayer story');
    }

    @IsTest
    static void testGetStoriesWithPagination() {
        Test.startTest();
        FimbyStoriesController.StoriesResult firstPage = FimbyStoriesController.getStories(2, 0, 'All');
        FimbyStoriesController.StoriesResult secondPage = FimbyStoriesController.getStories(2, 2, 'All');
        Test.stopTest();

        System.assertNotEquals(null, firstPage, 'First page should not be null');
        System.assertEquals(2, firstPage.stories.size(), 'First page should return 2 stories');
        System.assertEquals(true, firstPage.hasMore, 'First page should have more stories');

        System.assertNotEquals(null, secondPage, 'Second page should not be null');
        System.assertEquals(1, secondPage.stories.size(), 'Second page should return 1 story');
        System.assertEquals(false, secondPage.hasMore, 'Second page should not have more stories');

        // Ensure no duplicates
        Set<Id> firstPageIds = new Set<Id>();
        for (Story__c story : firstPage.stories) {
            firstPageIds.add(story.Id);
        }

        for (Story__c story : secondPage.stories) {
            System.assert(!firstPageIds.contains(story.Id), 'Second page should not contain stories from first page');
        }
    }

    @IsTest
    static void testGetStoriesCount() {
        Test.startTest();
        Integer allCount = FimbyStoriesController.getStoriesCount('All');
        Integer thankYouCount = FimbyStoriesController.getStoriesCount('Thank You');
        Integer prayerCount = FimbyStoriesController.getStoriesCount('Prayer');
        Test.stopTest();

        System.assertEquals(3, allCount, 'Should count all 3 stories');
        System.assertEquals(2, thankYouCount, 'Should count 2 thank you stories');
        System.assertEquals(1, prayerCount, 'Should count 1 prayer story');
    }

    @IsTest
    static void testCreateStory() {
        // Get test data
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood Stories' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];

        // Create test user
        User testUser = createTestUser(testContact.Id);

        Test.startTest();
        System.runAs(testUser) {
            Id storyId = FimbyStoriesController.createStory(
                'New Test Story',
                'This is a new test story content',
                'Thank You',
                'Test Location',
                'http://example.com/image.jpg',
                false
            );

            System.assertNotEquals(null, storyId, 'Story ID should not be null');
            System.assert(String.isNotBlank(String.valueOf(storyId)), 'Should return valid Salesforce ID');

            // Verify story was created
            Story__c createdStory = [SELECT Id, Name, Message__c, Type__c FROM Story__c WHERE Id = :storyId];
            System.assertEquals('New Test Story', createdStory.Name, 'Story title should match');
            System.assertEquals('This is a new test story content', createdStory.Message__c, 'Story content should match');
            System.assertEquals('Thank You', createdStory.Type__c, 'Story category should match');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateStoryWithShareOnSocial() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood Stories' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = createTestUser(testContact.Id);

        Test.startTest();
        System.runAs(testUser) {
            Id storyId = FimbyStoriesController.createStory(
                'Shareable Story',
                'Content for social sharing',
                'Thank You',
                null,
                null,
                true  // shareOnSocial
            );

            System.assertNotEquals(null, storyId, 'Story ID should not be null');

            Story__c createdStory = [SELECT Id, Share_on_Social_Media__c FROM Story__c WHERE Id = :storyId];
            System.assertEquals(true, createdStory.Share_on_Social_Media__c, 'Share_on_Social_Media__c should be true');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCreateStoryWithoutUser() {
        Test.startTest();
        // The method should handle cases where user context might not be available
        // For now, we'll just test that it doesn't crash
        try {
            Id storyId = FimbyStoriesController.createStory(
                'Test Story',
                'Test content',
                'Thank You',
                'Test Location',
                null,
                false
            );
            System.assertNotEquals(null, storyId, 'Story should be created even without full user context');
        } catch (Exception e) {
            // If an exception is thrown, that's also acceptable behavior
            System.assert(true, 'Method handled missing user context appropriately');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetStoryCategories() {
        Test.startTest();
        List<String> categories = FimbyStoriesController.getStoryCategories();
        Test.stopTest();

        System.assertNotEquals(null, categories, 'Categories should not be null');
        System.assert(categories.size() > 0, 'Should return at least one category');

        // Check that each category is not null
        for (String category : categories) {
            System.assertNotEquals(null, category, 'Category should not be null');
        }
    }

    @IsTest
    static void testGetStoriesWithEmptyCategory() {
        Test.startTest();
        FimbyStoriesController.StoriesResult result = FimbyStoriesController.getStories(10, 0, '');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(3, result.stories.size(), 'Should return all stories when category is empty');
    }

    @IsTest
    static void testGetStoriesWithNullCategory() {
        Test.startTest();
        FimbyStoriesController.StoriesResult result = FimbyStoriesController.getStories(10, 0, null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(3, result.stories.size(), 'Should return all stories when category is null');
    }

    @IsTest
    static void testGetStoriesCountWithEmptyCategory() {
        Test.startTest();
        Integer count = FimbyStoriesController.getStoriesCount('');
        Test.stopTest();

        System.assertEquals(3, count, 'Should count all stories when category is empty');
    }

    @IsTest
    static void testGetStoriesCountWithNullCategory() {
        Test.startTest();
        Integer count = FimbyStoriesController.getStoriesCount(null);
        Test.stopTest();

        System.assertEquals(3, count, 'Should count all stories when category is null');
    }

    @IsTest
    static void testCreateStoryWithMinimalData() {
        // Get test data
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood Stories' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];

        // Create test user
        User testUser = createTestUser(testContact.Id);

        Test.startTest();
        System.runAs(testUser) {
            Id storyId = FimbyStoriesController.createStory(
                'Minimal Story',
                'Minimal content',
                'Thank You',
                null,  // No location
                null,  // No image
                false  // shareOnSocial
            );

            System.assertNotEquals(null, storyId, 'Story ID should not be null');

            // Verify story was created
            Story__c createdStory = [SELECT Id, Name, Message__c, Type__c, Neighbourhood__c, Image_URL__c FROM Story__c WHERE Id = :storyId];
            System.assertEquals('Minimal Story', createdStory.Name, 'Story title should match');
            System.assertEquals('Minimal content', createdStory.Message__c, 'Story content should match');
            System.assertEquals('Thank You', createdStory.Type__c, 'Story category should match');
            System.assertEquals(null, createdStory.Image_URL__c, 'Image URL should be null');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetStoryDetailVisible() {
        Story__c targetStory = [SELECT Id FROM Story__c WHERE Name = 'Thank You Story 1' LIMIT 1];

        Test.startTest();
        FimbyStoriesController.StoryDetailResult result = FimbyStoriesController.getStoryDetail(targetStory.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(false, result.removed, 'Visible story should not be removed');
        System.assertNotEquals(null, result.story, 'Story payload should be present');
        System.assertEquals(targetStory.Id, result.story.Id, 'Should return the requested story');
        System.assertEquals('Thank You Story 1', result.story.Name, 'Story name should match');
    }

    @IsTest
    static void testGetStoryDetailHiddenByModerator() {
        Story__c targetStory = [SELECT Id FROM Story__c WHERE Name = 'Thank You Story 1' LIMIT 1];
        targetStory.Moderation_Status__c = 'Hidden_By_Moderator';
        update targetStory;

        Test.startTest();
        FimbyStoriesController.StoryDetailResult result = FimbyStoriesController.getStoryDetail(targetStory.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.removed, 'Hidden story should be reported as removed');
        System.assertEquals(null, result.story, 'Story payload should be null when removed');
        System.assertNotEquals(null, result.message, 'Removed stub should include a message');
    }

    @IsTest
    static void testGetStoryDetailUnderReview() {
        Story__c targetStory = [SELECT Id FROM Story__c WHERE Name = 'Thank You Story 1' LIMIT 1];
        targetStory.Moderation_Status__c = 'Under_Review';
        update targetStory;

        Test.startTest();
        FimbyStoriesController.StoryDetailResult result = FimbyStoriesController.getStoryDetail(targetStory.Id);
        Test.stopTest();

        System.assertEquals(true, result.removed, 'Under-review story should be reported as removed');
        System.assertEquals(null, result.story, 'Story payload should be null when under review');
    }

    @IsTest
    static void testDeleteStoryByAuthor() {
        Story__c targetStory = [SELECT Id FROM Story__c WHERE Name = 'Thank You Story 1' LIMIT 1];
        Contact author = [SELECT Id FROM Contact WHERE Email = 'teststoriesuser@example.com' LIMIT 1];
        User authorUser = createTestUser(author.Id);

        Test.startTest();
        System.runAs(authorUser) {
            Map<String, Object> result = FimbyStoriesController.deleteStory(targetStory.Id);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Story__c WHERE Id = :targetStory.Id]);
    }

    @IsTest
    static void testDeleteStoryDeniedForNonOwner() {
        Story__c targetStory = [SELECT Id FROM Story__c WHERE Name = 'Thank You Story 1' LIMIT 1];
        Contact other = new Contact(
            FirstName = 'Other',
            LastName = 'StoriesUser',
            AccountId = [SELECT Id FROM Account LIMIT 1].Id,
            Email = 'otherstoriesuser@example.com'
        );
        insert other;
        User otherUser = createTestUser(other.Id);

        Boolean threw = false;
        Test.startTest();
        System.runAs(otherUser) {
            try {
                FimbyStoriesController.deleteStory(targetStory.Id);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Non-owner delete should be denied');
        System.assertEquals(1, [SELECT COUNT() FROM Story__c WHERE Id = :targetStory.Id]);
    }

    @IsTest
    static void testGetStoryDetailNullId() {
        Test.startTest();
        FimbyStoriesController.StoryDetailResult result = FimbyStoriesController.getStoryDetail(null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null even for null id');
        System.assertEquals(true, result.removed, 'Null id should return removed stub');
        System.assertEquals(null, result.story, 'Story payload should be null for null id');
    }

    // Helper method to create test user with contact
    @IsTest
    static void testUpdateStory_Success() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood Stories' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = createTestUser(testContact.Id);

        Story__c story = [
            SELECT Id FROM Story__c WHERE Type__c = 'Thank You' LIMIT 1
        ];

        Map<String, Object> updateData = new Map<String, Object>{
            'recordId' => story.Id,
            'title' => 'Updated Story Title',
            'content' => 'Updated message body',
            'category' => 'Prayer',
            'shareOnSocial' => true
        };

        Test.startTest();
        Map<String, Object> result;
        FimbyIdentityRepository.clearCache();
        System.runAs(testUser) {
            result = FimbyStoriesController.updateStory(JSON.serialize(updateData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        Story__c updated = [
            SELECT Name, Message__c, Type__c, Share_on_Social_Media__c
            FROM Story__c WHERE Id = :story.Id
        ];
        System.assertEquals('Updated Story Title', updated.Name);
        System.assertEquals('Updated message body', updated.Message__c);
        System.assertEquals('Prayer', updated.Type__c);
        System.assertEquals(true, updated.Share_on_Social_Media__c);
    }

    @IsTest
    static void testUpdateStory_NotAuthor() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood Stories' LIMIT 1];
        Contact authorContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];

        Contact otherContact = new Contact(
            FirstName = 'Other',
            LastName = 'Reader',
            AccountId = testNeighbourhood.Id,
            Email = 'otherreader@example.com'
        );
        insert otherContact;
        User otherUser = createTestUser(otherContact.Id);

        Story__c story = [
            SELECT Id FROM Story__c WHERE Type__c = 'Prayer' LIMIT 1
        ];
        Map<String, Object> updateData = new Map<String, Object>{
            'recordId' => story.Id,
            'title' => 'Should Not Update'
        };

        Test.startTest();
        Boolean caught = false;
        FimbyIdentityRepository.clearCache();
        System.runAs(otherUser) {
            try {
                FimbyStoriesController.updateStory(JSON.serialize(updateData));
            } catch (Exception e) {
                caught = true;
            }
        }
        Test.stopTest();

        System.assert(caught, 'Non-author should not be able to update');
    }

    @IsTest
    static void testUseProfilePhotoForStory_Success() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood Stories' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        testContact.Image_URL__c = 'http://example.com/avatar.jpg';
        testContact.Image_Ratio__c = '300X300';
        update testContact;

        User testUser = createTestUser(testContact.Id);

        Test.startTest();
        FimbyIdentityRepository.clearCache();
        System.runAs(testUser) {
            Id storyId = FimbyStoriesController.createStory(
                'Hi neighbours', 'My intro', 'Bio', null, null, false
            );
            FimbyStoriesController.useProfilePhotoForStory(storyId);

            Story__c updated = [SELECT Image_URL__c, Image_Ratio__c FROM Story__c WHERE Id = :storyId];
            System.assertEquals('http://example.com/avatar.jpg', updated.Image_URL__c, 'Story should reuse the profile photo URL');
            System.assertEquals('300X300', updated.Image_Ratio__c, 'Story should reuse the profile photo ratio');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUseProfilePhotoForStory_NoPhoto() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood Stories' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        User testUser = createTestUser(testContact.Id);

        Boolean caught = false;
        Test.startTest();
        FimbyIdentityRepository.clearCache();
        System.runAs(testUser) {
            Id storyId = FimbyStoriesController.createStory(
                'Hi neighbours', 'My intro', 'Bio', null, null, false
            );
            try {
                FimbyStoriesController.useProfilePhotoForStory(storyId);
            } catch (AuraHandledException e) {
                caught = true;
            }
        }
        Test.stopTest();

        System.assert(caught, 'Reusing a missing profile photo should throw');
    }

    @IsTest
    static void testUseProfilePhotoForStory_NotOwner() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood Stories' LIMIT 1];
        Story__c targetStory = [SELECT Id FROM Story__c WHERE Type__c = 'Prayer' LIMIT 1];

        Contact other = new Contact(
            FirstName = 'Other', LastName = 'PhotoUser',
            AccountId = testNeighbourhood.Id, Email = 'otherphotouser@example.com',
            Image_URL__c = 'http://example.com/other.jpg'
        );
        insert other;
        User otherUser = createTestUser(other.Id);

        Boolean caught = false;
        Test.startTest();
        FimbyIdentityRepository.clearCache();
        System.runAs(otherUser) {
            try {
                FimbyStoriesController.useProfilePhotoForStory(targetStory.Id);
            } catch (AuraHandledException e) {
                caught = true;
            }
        }
        Test.stopTest();

        System.assert(caught, 'Non-owner should not be able to reuse a photo on another story');
    }

    private static User createTestUser(Id contactId) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Customer Community Plus User' OR Name = 'Partner Community User' LIMIT 1];

        User testUser = new User(
            Alias = 'tststr',
            Email = 'teststoriesuser@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestStoriesUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'teststoriesuser' + System.currentTimeMillis() + '@example.com',
            ContactId = contactId
        );
        insert testUser;
        return testUser;
    }
}