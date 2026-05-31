@isTest
public class FimbyStoryCommentControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);
    }

    private static User getTestUser() {
        return [SELECT Id, ContactId FROM User WHERE Email LIKE '%@testorg.com' AND IsActive = true LIMIT 1];
    }

    private static Contact getTestContact() {
        return [SELECT Id, AccountId, Logged_In_As_Contact__c FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1];
    }

    private static Story__c createTestStory(Contact postedBy) {
        Story__c story = new Story__c(
            Name = 'Test Story Title',
            Message__c = 'This is a test story message for comment testing.',
            Posted_By__c = postedBy.Id,
            Contact__c = postedBy.Id,
            Neighbourhood__c = postedBy.AccountId
        );
        insert story;
        return story;
    }

    // ============================================
    // GET STORY FOR COMMENT
    // ============================================

    @isTest
    static void testGetStoryForComment_Success() {
        Contact testContact = getTestContact();
        Story__c testStory = createTestStory(testContact);

        Test.startTest();
        Map<String, Object> result = FimbyStoryCommentController.getStoryForComment(testStory.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        Map<String, Object> story = (Map<String, Object>) result.get('story');
        System.assertEquals(testStory.Id, story.get('id'));
        System.assertEquals('Test Story Title', story.get('name'));
        System.assertEquals(testContact.Id, story.get('ownerContactId'));
    }

    @isTest
    static void testGetStoryForComment_InvalidId() {
        Test.startTest();
        try {
            FimbyStoryCommentController.getStoryForComment('invalidId123');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Error getting story'));
        }
        Test.stopTest();
    }

    // ============================================
    // SEARCH CONTACTS FOR MENTION
    // ============================================

    @isTest
    static void testSearchContactsForMention_ReturnsContactIds() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Contact other = FimbyTestDataFactory.createNeighbourhoodContact(testContact.AccountId, true);

        Test.startTest();
        List<Map<String, String>> results;
        System.runAs(testUser) {
            results = FimbyStoryCommentController.searchContactsForMention('Test');
        }
        Test.stopTest();

        System.assertNotEquals(null, results);
        Boolean foundAContact = false;
        for (Map<String, String> r : results) {
            String idStr = r.get('id');
            System.assert(idStr.startsWith('003'), 'Mention id should be a Contact Id, got: ' + idStr);
            foundAContact = true;
        }
        System.assert(foundAContact, 'Should return at least one contact from the same neighbourhood');
    }

    @isTest
    static void testSearchContactsForMention_NoResults() {
        User testUser = getTestUser();
        Test.startTest();
        List<Map<String, String>> results;
        System.runAs(testUser) {
            results = FimbyStoryCommentController.searchContactsForMention('XYZNonExistentName123');
        }
        Test.stopTest();
        System.assertEquals(0, results.size(), 'Should have no results');
    }

    // ============================================
    // POST STORY COMMENT
    // ============================================

    @isTest
    static void testPostStoryComment_Success_DualStamping() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Contact storyOwner = FimbyTestDataFactory.createNeighbourhoodContact(testContact.AccountId, true);

        Test.startTest();
        Map<String, Object> result;
        Story__c testStory;
        System.runAs(testUser) {
            testStory = createTestStory(storyOwner);
            Map<String, Object> commentData = new Map<String, Object>{
                'storyId' => testStory.Id,
                'commentText' => 'A neighbourly comment.',
                'commentContactId' => testContact.Id
            };
            result = FimbyStoryCommentController.postStoryComment(JSON.serialize(commentData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertNotEquals(null, result.get('commentId'), 'Controller must return commentId');

        Id commentId = (Id) result.get('commentId');
        Story_Comment__c row = [
            SELECT Story__c, Body__c, Status__c, Moderation_Status__c,
                   Contact__c, Posted_By__c, Neighbourhood__c, Edit_Count__c
            FROM Story_Comment__c WHERE Id = :commentId
        ];
        System.assertEquals(testStory.Id, row.Story__c);
        System.assertEquals('A neighbourly comment.', row.Body__c);
        System.assertEquals('Active', row.Status__c);
        System.assertEquals('Visible', row.Moderation_Status__c);
        System.assertEquals(testContact.Id, row.Contact__c, 'Submitted By = real contact');
        System.assertEquals(testContact.Id, row.Posted_By__c, 'Post Owner = acting-as (== real here)');
        System.assertEquals(testContact.AccountId, row.Neighbourhood__c);
        System.assertEquals(0, row.Edit_Count__c);

        Story__c updatedStory = [SELECT Last_Comment__c, Last_Comment_Contact__c FROM Story__c WHERE Id = :testStory.Id];
        System.assertEquals('A neighbourly comment.', updatedStory.Last_Comment__c);
        System.assertEquals(testContact.Id, updatedStory.Last_Comment_Contact__c);
    }

    @isTest
    static void testPostStoryComment_NotifiesStoryOwner() {
        User testUser = getTestUser();
        Contact commenter = getTestContact();
        Contact owner = FimbyTestDataFactory.createNeighbourhoodContact(commenter.AccountId, true);

        Test.startTest();
        System.runAs(testUser) {
            Story__c testStory = createTestStory(owner);
            Map<String, Object> commentData = new Map<String, Object>{
                'storyId' => testStory.Id,
                'commentText' => 'Notifying owner.',
                'commentContactId' => commenter.Id
            };
            FimbyStoryCommentController.postStoryComment(JSON.serialize(commentData));
        }
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Id, Contact__c, Type__c
            FROM Notification__c
            WHERE Contact__c = :owner.Id AND Type__c = 'Comment'
        ];
        System.assertEquals(1, notifs.size(), 'Story owner should get one Comment notification');
    }

    @isTest
    static void testPostStoryComment_OwnStorySkipsNotification() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            Story__c testStory = createTestStory(testContact);
            Map<String, Object> commentData = new Map<String, Object>{
                'storyId' => testStory.Id,
                'commentText' => 'Commenting on my own story',
                'commentContactId' => testContact.Id
            };
            result = FimbyStoryCommentController.postStoryComment(JSON.serialize(commentData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        List<Notification__c> notifs = [
            SELECT Id FROM Notification__c
            WHERE Contact__c = :testContact.Id AND Type__c = 'Comment'
        ];
        System.assertEquals(0, notifs.size());
    }

    @isTest
    static void testPostStoryComment_MentionFanOut() {
        User testUser = getTestUser();
        Contact commenter = getTestContact();
        Contact mentioned = FimbyTestDataFactory.createNeighbourhoodContact(commenter.AccountId, true);
        Contact owner = FimbyTestDataFactory.createNeighbourhoodContact(commenter.AccountId, true);

        Test.startTest();
        Story__c testStory;
        System.runAs(testUser) {
            testStory = createTestStory(owner);
            Map<String, Object> commentData = new Map<String, Object>{
                'storyId' => testStory.Id,
                'commentText' => 'Hey @neighbour check this',
                'commentContactId' => commenter.Id,
                'mentionContactIds' => new List<String>{ String.valueOf(mentioned.Id) }
            };
            FimbyStoryCommentController.postStoryComment(JSON.serialize(commentData));
        }
        Test.stopTest();

        Story_Comment__c row = [SELECT Mention_Contact_Ids__c FROM Story_Comment__c WHERE Story__c = :testStory.Id LIMIT 1];
        System.assert(row.Mention_Contact_Ids__c != null && row.Mention_Contact_Ids__c.contains(mentioned.Id), 'Mentions persisted');

        List<Notification__c> mentionNotifs = [
            SELECT Id FROM Notification__c
            WHERE Contact__c = :mentioned.Id AND Type__c = 'Comment'
        ];
        System.assertEquals(1, mentionNotifs.size(), 'Mentioned contact should receive a notification');
    }

    @isTest
    static void testPostStoryComment_RequiresStoryAndBody() {
        User testUser = getTestUser();
        Map<String, Object> badData = new Map<String, Object>{
            'storyId' => '',
            'commentText' => '',
            'commentContactId' => null
        };

        Boolean threw = false;
        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyStoryCommentController.postStoryComment(JSON.serialize(badData));
            }
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Blank story id + body should throw');
    }

    // ============================================
    // UPDATE STORY COMMENT
    // ============================================

    @isTest
    static void testUpdateStoryComment_IncrementsEditCountAndSnapshots() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Test.startTest();
        Id commentId;
        System.runAs(testUser) {
            Story__c testStory = createTestStory(testContact);
            Map<String, Object> postData = new Map<String, Object>{
                'storyId' => testStory.Id,
                'commentText' => 'First version of the comment',
                'commentContactId' => testContact.Id
            };
            Map<String, Object> posted = FimbyStoryCommentController.postStoryComment(JSON.serialize(postData));
            commentId = (Id) posted.get('commentId');

            Map<String, Object> editData = new Map<String, Object>{
                'commentId' => commentId,
                'commentText' => 'Second, edited version of the comment'
            };
            Map<String, Object> result = FimbyStoryCommentController.updateStoryComment(JSON.serialize(editData));
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        Story_Comment__c row = [
            SELECT Body__c, Body_Snapshot__c, Edit_Count__c, Edited_Date__c
            FROM Story_Comment__c WHERE Id = :commentId
        ];
        System.assertEquals('Second, edited version of the comment', row.Body__c);
        System.assertEquals('First version of the comment', row.Body_Snapshot__c);
        System.assertEquals(1, row.Edit_Count__c);
        System.assertNotEquals(null, row.Edited_Date__c);
    }

    @isTest
    static void testUpdateStoryComment_BlocksNonAuthors() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Contact author = FimbyTestDataFactory.createNeighbourhoodContact(testContact.AccountId, true);

        Boolean threw = false;
        Test.startTest();
        System.runAs(testUser) {
            Story__c testStory = createTestStory(author);
            Story_Comment__c comment = new Story_Comment__c(
                Story__c = testStory.Id,
                Body__c = 'Author wrote this',
                Status__c = 'Active',
                Moderation_Status__c = 'Visible',
                Contact__c = author.Id,
                Posted_By__c = author.Id,
                Neighbourhood__c = author.AccountId,
                Edit_Count__c = 0
            );
            insert comment;

            Map<String, Object> editData = new Map<String, Object>{
                'commentId' => comment.Id,
                'commentText' => 'Not my comment, should fail'
            };
            try {
                FimbyStoryCommentController.updateStoryComment(JSON.serialize(editData));
            } catch (Exception e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Updating someone else\'s comment should throw');
    }

    // ============================================
    // SOFT DELETE
    // ============================================

    @isTest
    static void testSoftDeleteStoryComment_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Test.startTest();
        Id commentId;
        Id storyId;
        System.runAs(testUser) {
            Story__c testStory = createTestStory(testContact);
            storyId = testStory.Id;
            Map<String, Object> postData = new Map<String, Object>{
                'storyId' => testStory.Id,
                'commentText' => 'About to be soft-deleted',
                'commentContactId' => testContact.Id
            };
            Map<String, Object> posted = FimbyStoryCommentController.postStoryComment(JSON.serialize(postData));
            commentId = (Id) posted.get('commentId');

            Map<String, Object> result = FimbyStoryCommentController.softDeleteStoryComment(commentId);
            System.assertEquals(true, result.get('success'));

            List<Map<String, Object>> visible = FimbyStoryCommentController.getStoryComments(testStory.Id);
            for (Map<String, Object> c : visible) {
                System.assertNotEquals(commentId, c.get('id'),
                    'Hidden_By_Author rows must not appear in getStoryComments');
            }
        }
        Test.stopTest();

        Story_Comment__c row = [SELECT Status__c FROM Story_Comment__c WHERE Id = :commentId];
        System.assertEquals('Hidden_By_Author', row.Status__c);
    }

    @isTest
    static void testSoftDeleteStoryComment_BlocksNonAuthors() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Contact author = FimbyTestDataFactory.createNeighbourhoodContact(testContact.AccountId, true);

        Boolean threw = false;
        Test.startTest();
        System.runAs(testUser) {
            Story__c testStory = createTestStory(author);
            Story_Comment__c comment = new Story_Comment__c(
                Story__c = testStory.Id,
                Body__c = 'Someone else wrote this',
                Status__c = 'Active',
                Moderation_Status__c = 'Visible',
                Contact__c = author.Id,
                Posted_By__c = author.Id,
                Neighbourhood__c = author.AccountId,
                Edit_Count__c = 0
            );
            insert comment;

            try {
                FimbyStoryCommentController.softDeleteStoryComment(comment.Id);
            } catch (Exception e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Removing someone else\'s comment should throw');
    }

    // ============================================
    // GET STORY COMMENTS + BLOCKING
    // ============================================

    @isTest
    static void testGetStoryComments_FiltersBlockedAuthor() {
        User testUser = getTestUser();
        Contact viewer = getTestContact();
        Contact blocked = FimbyTestDataFactory.createNeighbourhoodContact(viewer.AccountId, true);

        insert new Blocked_Contact__c(
            Blocker__c = viewer.Id,
            Blocked__c = blocked.Id
        );

        Test.startTest();
        Id blockedCommentId;
        List<Map<String, Object>> results;
        System.runAs(testUser) {
            Story__c testStory = createTestStory(viewer);
            Story_Comment__c blockedComment = new Story_Comment__c(
                Story__c = testStory.Id,
                Body__c = 'You should not see this',
                Status__c = 'Active',
                Moderation_Status__c = 'Visible',
                Contact__c = blocked.Id,
                Posted_By__c = blocked.Id,
                Neighbourhood__c = viewer.AccountId,
                Edit_Count__c = 0
            );
            insert blockedComment;
            blockedCommentId = blockedComment.Id;

            results = FimbyStoryCommentController.getStoryComments(testStory.Id);
        }
        Test.stopTest();

        for (Map<String, Object> c : results) {
            System.assertNotEquals(blockedCommentId, c.get('id'),
                'Comments from a blocked author must not be returned');
        }
    }

    @isTest
    static void testGetStoryComments_NullStoryId() {
        User testUser = getTestUser();
        Test.startTest();
        List<Map<String, Object>> results;
        System.runAs(testUser) {
            results = FimbyStoryCommentController.getStoryComments(null);
        }
        Test.stopTest();
        System.assertNotEquals(null, results);
        System.assertEquals(0, results.size());
    }
}
