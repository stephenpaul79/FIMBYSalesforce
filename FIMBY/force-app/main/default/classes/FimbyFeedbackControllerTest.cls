@isTest
public class FimbyFeedbackControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User testUser = FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);
    }

    private static User getTestUser() {
        return [SELECT Id, ContactId FROM User WHERE Email LIKE '%@testorg.com' AND IsActive = true LIMIT 1];
    }

    private static Contact getTestContact() {
        return [SELECT Id, AccountId, Logged_In_As_Contact__c FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1];
    }

    private static final String TEST_JPEG_BASE64 =
        'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAUAQEAAAAAAAAAAAAAAAAAAAAA/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8AKwA//9k=';

    private static Id createFeedbackViaSubmit(User testUser) {
        Map<String, Object> feedbackData = new Map<String, Object>{
            'feedbackType' => 'Bug',
            'title' => 'Screenshot Test Feedback',
            'details' => 'Feedback created for screenshot tests.',
            'relatedRecordId' => null
        };
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyFeedbackController.submitFeedback(JSON.serialize(feedbackData));
        }
        return (Id) result.get('feedbackId');
    }

    @isTest
    static void testGetFeedbackTypePicklist() {
        Test.startTest();
        List<String> values = FimbyFeedbackController.getFeedbackTypePicklist();
        Test.stopTest();

        System.assertNotEquals(null, values, 'Should return picklist values');
        System.assert(values.size() >= 0, 'Should return a list');
        System.assert(!values.contains('Content Report'), 'Content Report is report-flow only');
    }

    @isTest
    static void testSubmitFeedback_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Map<String, Object> feedbackData = new Map<String, Object>{
            'feedbackType' => 'Bug',
            'title' => 'Test Feedback',
            'details' => 'This is test feedback details.',
            'relatedRecordId' => null
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyFeedbackController.submitFeedback(JSON.serialize(feedbackData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('feedbackId'), 'Should return feedback ID');

        List<Feedback__c> feedbacks = [
            SELECT Id, Name, Type__c, Details__c, Contact__c, Posted_By__c
            FROM Feedback__c
            WHERE Posted_By__c = :testContact.Id
        ];
        System.assertEquals(1, feedbacks.size(), 'Should have created feedback record');
        System.assertEquals('Test Feedback', feedbacks[0].Name, 'Title should match');
        System.assertEquals(testContact.Id, feedbacks[0].Contact__c, 'Contact__c should be real actor');
        System.assertEquals(testContact.Id, feedbacks[0].Posted_By__c, 'Posted_By__c should be acting-as contact');
    }

    @isTest
    static void testSubmitFeedback_WithRelatedRecord() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Map<String, Object> feedbackData = new Map<String, Object>{
            'feedbackType' => 'Bug',
            'title' => 'Feedback with Related Record',
            'details' => 'This is feedback about a specific record.',
            'relatedRecordId' => 'a0B000000000001'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyFeedbackController.submitFeedback(JSON.serialize(feedbackData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        List<Feedback__c> feedbacks = [
            SELECT Id, Related_Record_ID__c
            FROM Feedback__c
            WHERE Posted_By__c = :testContact.Id
        ];
        System.assertEquals(1, feedbacks.size(), 'Should have created feedback record');
        System.assertEquals('a0B000000000001', feedbacks[0].Related_Record_ID__c, 'Should have set related record ID');
    }

    @isTest
    static void testSubmitFeedback_ActingOnBehalf() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Account neighbourhood = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' LIMIT 1];
        Contact onBehalfContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = testContact.Id,
            Related_Contact__c = onBehalfContact.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = neighbourhood.Id
        );
        insert rel;

        testContact.Logged_In_As_Contact__c = onBehalfContact.Id;
        testContact.Logged_In_As_Neighbourhood__c = neighbourhood.Id;
        update testContact;

        Map<String, Object> feedbackData = new Map<String, Object>{
            'feedbackType' => 'Bug',
            'title' => 'On Behalf Feedback',
            'details' => 'Submitted on behalf of another contact.',
            'relatedRecordId' => null
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyFeedbackController.submitFeedback(JSON.serialize(feedbackData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        Feedback__c fb = [
            SELECT Id, Contact__c, Posted_By__c
            FROM Feedback__c
            WHERE Id = :(Id) result.get('feedbackId')
        ];
        System.assertEquals(testContact.Id, fb.Contact__c, 'Contact__c should be the real actor');
        System.assertEquals(onBehalfContact.Id, fb.Posted_By__c, 'Posted_By__c should be the acting-as contact');
    }

    @isTest
    static void testSubmitFeedback_RejectsContentReport() {
        User testUser = getTestUser();

        Map<String, Object> feedbackData = new Map<String, Object>{
            'feedbackType' => 'Content Report',
            'title' => 'Should fail',
            'details' => 'Use report flag instead.',
            'relatedRecordId' => null
        };

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyFeedbackController.submitFeedback(JSON.serialize(feedbackData));
            }
            System.assert(false, 'Should reject Content Report type');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testSubmitFeedback_InvalidJson() {
        User testUser = getTestUser();

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyFeedbackController.submitFeedback('{not valid json');
            }
            System.assert(false, 'Should throw for invalid JSON');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    // ============================================
    // Screenshot upload (mirrors FimbyLibraryControllerTest image tests)
    // ============================================

    @isTest
    static void testUploadScreenshot_ValidationOnly() {
        Test.startTest();
        try {
            FimbyFeedbackController.uploadScreenshot('', 'test.jpg', 'fakeId', 100, 100);
            System.assert(false, 'Should have thrown an exception for empty file data');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testUploadScreenshot_MissingParams() {
        Test.startTest();
        try {
            FimbyFeedbackController.uploadScreenshot(null, 'test.jpg', null, 100, 100);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testUploadScreenshot_Success() {
        User testUser = getTestUser();
        Id feedbackId = createFeedbackViaSubmit(testUser);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyFeedbackController.uploadScreenshot(
                TEST_JPEG_BASE64,
                'screenshot.jpg',
                feedbackId,
                800,
                600
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should upload screenshot');
        System.assertNotEquals(null, result.get('viewUrl'), 'Should return preview URL');

        Feedback__c updated = [
            SELECT Image_URL__c, Image_Dimensions__c
            FROM Feedback__c
            WHERE Id = :feedbackId
        ];
        System.assertNotEquals(null, updated.Image_URL__c, 'Should set image URL');
        System.assertEquals('Rectangle (Wide)', updated.Image_Dimensions__c, 'Should derive wide dimensions');
    }

    @isTest
    static void testUploadScreenshot_SquareDimensions() {
        User testUser = getTestUser();
        Id feedbackId = createFeedbackViaSubmit(testUser);

        Test.startTest();
        System.runAs(testUser) {
            FimbyFeedbackController.uploadScreenshot(
                TEST_JPEG_BASE64,
                'square.jpg',
                feedbackId,
                100,
                100
            );
        }
        Test.stopTest();

        Feedback__c updated = [
            SELECT Image_Dimensions__c
            FROM Feedback__c
            WHERE Id = :feedbackId
        ];
        System.assertEquals('Square', updated.Image_Dimensions__c, 'Should derive square dimensions');
    }

    @isTest
    static void testUploadScreenshot_TallDimensions() {
        User testUser = getTestUser();
        Id feedbackId = createFeedbackViaSubmit(testUser);

        Test.startTest();
        System.runAs(testUser) {
            FimbyFeedbackController.uploadScreenshot(
                TEST_JPEG_BASE64,
                'tall.jpg',
                feedbackId,
                400,
                800
            );
        }
        Test.stopTest();

        Feedback__c updated = [
            SELECT Image_Dimensions__c
            FROM Feedback__c
            WHERE Id = :feedbackId
        ];
        System.assertEquals('Rectangle (Tall)', updated.Image_Dimensions__c, 'Should derive tall dimensions');
    }

    @isTest
    static void testUploadScreenshot_NullDimensions() {
        User testUser = getTestUser();
        Id feedbackId = createFeedbackViaSubmit(testUser);

        Test.startTest();
        System.runAs(testUser) {
            FimbyFeedbackController.uploadScreenshot(
                TEST_JPEG_BASE64,
                'nodims.jpg',
                feedbackId,
                null,
                null
            );
        }
        Test.stopTest();

        Feedback__c updated = [
            SELECT Image_Dimensions__c
            FROM Feedback__c
            WHERE Id = :feedbackId
        ];
        System.assertEquals('Square', updated.Image_Dimensions__c, 'Missing dimensions should default to square');
    }

    @isTest
    static void testUploadScreenshot_ContentVersionCreation() {
        User testUser = getTestUser();
        Id feedbackId = createFeedbackViaSubmit(testUser);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyFeedbackController.uploadScreenshot(
                TEST_JPEG_BASE64,
                'screenshot.jpg',
                feedbackId,
                100,
                100
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Test upload should succeed via test stub URL');
    }

    @isTest
    static void testGetScreenshot() {
        User testUser = getTestUser();
        Id feedbackId = createFeedbackViaSubmit(testUser);

        update new Feedback__c(
            Id = feedbackId,
            Image_URL__c = 'https://example.com/test.jpg'
        );

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyFeedbackController.getScreenshot(feedbackId);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('https://example.com/test.jpg', result.get('imageUrl'), 'Should return image URL');
    }

    @isTest
    static void testUploadScreenshot_NotOwner() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Contact otherContact = new Contact(
            FirstName = 'Other',
            LastName = 'Person',
            AccountId = testContact.AccountId,
            Email = 'other.feedback@fimby.test.com'
        );
        insert otherContact;

        Feedback__c feedback = new Feedback__c(
            Name = 'Not My Feedback',
            Type__c = 'Bug',
            Details__c = 'Owned by someone else.',
            Contact__c = otherContact.Id,
            Posted_By__c = otherContact.Id,
            Neighbourhood__c = testContact.AccountId
        );
        insert feedback;

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyFeedbackController.uploadScreenshot(
                    TEST_JPEG_BASE64,
                    'screenshot.jpg',
                    feedback.Id,
                    100,
                    100
                );
            }
            System.assert(false, 'Should have thrown exception for non-owner');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have ownership error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetScreenshot_MissingRecord() {
        User testUser = getTestUser();

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyFeedbackController.getScreenshot('');
            }
            System.assert(false, 'Should have thrown exception for blank record id');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetScreenshot_NotFound() {
        User testUser = getTestUser();
        String fakeId = Feedback__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001';

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyFeedbackController.getScreenshot(fakeId);
            }
            System.assert(false, 'Should have thrown exception for missing feedback');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testExtractBase64DataViaHelper() {
        FimbyFeedbackController.ScreenshotHelper helper = new FimbyFeedbackController.ScreenshotHelper();
        System.assertEquals('ABC123==', helper.extractBase64Data('data:image/jpeg;base64,ABC123=='));
        System.assertEquals('ABC123==', helper.extractBase64Data('ABC123=='));
        System.assertEquals(null, helper.extractBase64Data(null));
    }

    @isTest
    static void testBuildDistributionUrl() {
        ContentVersion cv = new ContentVersion(
            Title = 'test',
            PathOnClient = 'test.txt',
            VersionData = Blob.valueOf('x'),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId, ContentBodyId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        ContentDistribution cd = new ContentDistribution(
            ContentVersionId = cv.Id,
            Name = 'test',
            PreferencesAllowViewInBrowser = true,
            PreferencesNotifyOnVisit = false,
            PreferencesPasswordRequired = false,
            PreferencesAllowOriginalDownload = true
        );
        insert cd;
        cd = [SELECT Id, DistributionPublicUrl FROM ContentDistribution WHERE Id = :cd.Id LIMIT 1];

        FimbyFeedbackController.ScreenshotHelper helper = new FimbyFeedbackController.ScreenshotHelper();
        String url = helper.buildDistributionUrl(cv, cd);

        System.assert(url.contains('rendition=ORIGINAL_Jpg'));
        System.assert(url.contains('versionId='));
        System.assert(url.contains('contentId='));
        System.assert(url.endsWith('&oid='));
    }

    @isTest
    static void testUploadScreenshot_WithUrlOverride() {
        User testUser = getTestUser();
        Id feedbackId = createFeedbackViaSubmit(testUser);

        FimbyFeedbackController.testScreenshotUrlOverride =
            'https://test.example.com/feedback_override.jpg&oid=';

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyFeedbackController.uploadScreenshot(
                TEST_JPEG_BASE64,
                'override.jpg',
                feedbackId,
                100,
                100
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should upload screenshot');
        Feedback__c updated = [
            SELECT Image_URL__c
            FROM Feedback__c
            WHERE Id = :feedbackId
        ];
        System.assertEquals(
            'https://test.example.com/feedback_override.jpg&oid=',
            updated.Image_URL__c,
            'Should use test override URL'
        );

        FimbyFeedbackController.testScreenshotUrlOverride = null;
    }

    @isTest
    static void testGetScreenshot_AppendsOrgId() {
        User testUser = getTestUser();
        Id feedbackId = createFeedbackViaSubmit(testUser);

        update new Feedback__c(
            Id = feedbackId,
            Image_URL__c = 'https://example.file.force.com/sfc/dist/version/renditionDownload?rendition=ORIGINAL_Jpg&oid='
        );

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyFeedbackController.getScreenshot(feedbackId);
        }
        Test.stopTest();

        String returnedUrl = (String) result.get('imageUrl');
        System.assert(returnedUrl.contains(UserInfo.getOrganizationId()), 'URL should have org ID appended');
    }

    @isTest
    static void testRemoveScreenshot() {
        User testUser = getTestUser();
        Id feedbackId = createFeedbackViaSubmit(testUser);

        update new Feedback__c(
            Id = feedbackId,
            Image_URL__c = 'https://example.com/image.jpg',
            Image_Dimensions__c = 'Square'
        );

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyFeedbackController.removeScreenshot(feedbackId);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        Feedback__c updated = [
            SELECT Image_URL__c, Image_Dimensions__c
            FROM Feedback__c
            WHERE Id = :feedbackId
        ];
        System.assertEquals(null, updated.Image_URL__c, 'Image URL should be cleared');
        System.assertEquals(null, updated.Image_Dimensions__c, 'Image dimensions should be cleared');
    }

    @isTest
    static void testRemoveScreenshot_NotOwner() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Contact otherContact = new Contact(
            FirstName = 'Other',
            LastName = 'Remover',
            AccountId = testContact.AccountId,
            Email = 'other.remove@fimby.test.com'
        );
        insert otherContact;

        Feedback__c feedback = new Feedback__c(
            Name = 'Not My Feedback',
            Type__c = 'Bug',
            Details__c = 'Owned by someone else.',
            Contact__c = otherContact.Id,
            Posted_By__c = otherContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Image_URL__c = 'https://example.com/image.jpg',
            Image_Dimensions__c = 'Square'
        );
        insert feedback;

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyFeedbackController.removeScreenshot(feedback.Id);
            }
            System.assert(false, 'Should have thrown exception for non-owner');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have ownership error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testUploadScreenshot_ActingOnBehalf() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Account neighbourhood = [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' LIMIT 1];
        Contact onBehalfContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = testContact.Id,
            Related_Contact__c = onBehalfContact.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = neighbourhood.Id
        );
        insert rel;

        testContact.Logged_In_As_Contact__c = onBehalfContact.Id;
        testContact.Logged_In_As_Neighbourhood__c = neighbourhood.Id;
        update testContact;

        Map<String, Object> feedbackData = new Map<String, Object>{
            'feedbackType' => 'Bug',
            'title' => 'On Behalf Screenshot',
            'details' => 'Submitted on behalf of another contact.',
            'relatedRecordId' => null
        };

        Id feedbackId;
        System.runAs(testUser) {
            feedbackId = (Id) FimbyFeedbackController.submitFeedback(JSON.serialize(feedbackData)).get('feedbackId');
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyFeedbackController.uploadScreenshot(
                TEST_JPEG_BASE64,
                'behalf.jpg',
                feedbackId,
                600,
                400
            );
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Acting-as submitter should upload screenshot');
    }
}
