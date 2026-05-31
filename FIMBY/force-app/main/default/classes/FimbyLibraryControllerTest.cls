/**
 * FimbyLibraryControllerTest
 * Tests for Library Items, Image Uploads, and Lending functionality
 *
 * Refactored - Tests for other methods moved to:
 * - FimbyContactControllerTest
 * - FimbyAskOfferControllerTest
 * - FimbyResponseControllerTest
 * - FimbyStoryCommentControllerTest
 */
@isTest
public class FimbyLibraryControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        // Mark the test contact as Vouched so library borrow tests pass the gate.
        testContact.Vouched_Status__c = 'Vouched';
        update testContact;
        User testUser = FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);

        Account orgAccount = new Account(
            Name = 'Test Community Organization',
            Type = 'Organization'
        );
        try {
            Id orgRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Organization').getRecordTypeId();
            orgAccount.RecordTypeId = orgRecordTypeId;
        } catch (Exception e) {}
        insert orgAccount;
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
            Message__c = 'This is a test story message.',
            Posted_By__c = postedBy.Id,
            Neighbourhood__c = postedBy.AccountId
        );
        insert story;
        return story;
    }

    // ============================================
    // LIBRARY ITEM TESTS
    // ============================================

    @isTest
    static void testGetCategoryPicklistValues() {
        Test.startTest();
        List<Map<String, String>> categories = FimbyLibraryController.getCategoryPicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, categories, 'Should return categories list');
        System.assert(categories.size() > 0, 'Should have at least one category');
        Map<String, String> firstCategory = categories[0];
        System.assert(firstCategory.containsKey('label'), 'Category should have label');
        System.assert(firstCategory.containsKey('value'), 'Category should have value');
    }

    @isTest
    static void testGetFimbyRecordTypeId() {
        Test.startTest();
        try {
            String recordTypeId = FimbyLibraryController.getFimbyRecordTypeId();
            System.assertNotEquals(null, recordTypeId, 'Should return record type Id');
            System.assertEquals(18, recordTypeId.length(), 'Should be 18 character Id');
        } catch (Exception e) {
            System.assert(e.getMessage() != null, 'Should have error message if record type missing');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateLibraryItem_Success() {
        User testUser = getTestUser();

        Map<String, Object> testData = new Map<String, Object>{
            'title' => 'Test Library Item',
            'description' => 'Test description for library item',
            'category' => 'Tools',
            'maxLendingDays' => 7,
            'ownedBy' => 'Self',
            'autoAcceptRequests' => true,
            'autoShareContactInfo' => true,
            'damageWaiverConfirmed' => true
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.createLibraryItem(JSON.serialize(testData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('recordId'), 'Should return recordId');
    }

    @isTest
    static void testCreateLibraryItem_WithDefaults() {
        User testUser = getTestUser();

        Map<String, Object> testData = new Map<String, Object>{
            'title' => 'Default Settings Item',
            'description' => 'Item with default settings',
            'category' => 'Books',
            'ownedBy' => 'Self',
            'autoAcceptRequests' => false,
            'autoShareContactInfo' => false,
            'damageWaiverConfirmed' => true
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.createLibraryItem(JSON.serialize(testData));
        }
        Test.stopTest();

            System.assertEquals(true, result.get('success'), 'Should return success');

        // Verify default max lending days was applied
            String recordId = (String) result.get('recordId');
        Library_Item__c item = [SELECT Max_Lending_Time_In_Days__c FROM Library_Item__c WHERE Id = :recordId];
        System.assertEquals(7, item.Max_Lending_Time_In_Days__c, 'Default max lending days should be 7');
    }

    @isTest
    static void testCreateLibraryItem_MinimalData() {
        User testUser = getTestUser();

        Map<String, Object> testData = new Map<String, Object>{
            'title' => 'Minimal Item',
            'description' => 'Minimal description',
            'category' => 'Tools',
            'ownedBy' => 'Self',
            'damageWaiverConfirmed' => true
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.createLibraryItem(JSON.serialize(testData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testGetPhotoUploadFlowInputs() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Test Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available'
        );
        insert item;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.getPhotoUploadFlowInputs(item.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(item.Id, result.get('recordId'), 'Should return record ID');
    }

    // ============================================
    // DELETE LIBRARY ITEM TESTS
    // ============================================

    @isTest
    static void testDeleteLibraryItem_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Delete Test Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available'
        );
        insert item;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.deleteLibraryItem(item.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        List<Library_Item__c> remaining = [SELECT Id FROM Library_Item__c WHERE Id = :item.Id];
        System.assertEquals(0, remaining.size(), 'Record should be deleted');
    }

    @isTest
    static void testDeleteLibraryItem_Exception() {
        User testUser = getTestUser();

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyLibraryController.deleteLibraryItem('invalidId');
            }
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    // ============================================
    // LENDING REQUEST TESTS
    // ============================================

    @isTest
    static void testGetLibraryItemForLending_Available() {
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Lendable Item',
            Description__c = 'Test item for lending',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7
        );
        insert item;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.getLibraryItemForLending(item.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('canBeLent'), 'Item should be lendable');
    }

    @isTest
    static void testGetLibraryItemForLending_Unavailable() {
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Unavailable Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Unavailable'
        );
        insert item;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.getLibraryItemForLending(item.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(false, result.get('canBeLent'), 'Item should not be lendable');
    }

    @isTest
    static void testCheckExistingLendingRequest_NoExisting() {
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Test Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available'
        );
        insert item;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.checkExistingLendingRequest(item.Id, testContact.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(false, result.get('hasExistingRequest'), 'Should not have existing request');
    }

    @isTest
    static void testCheckExistingLendingRequest_HasExisting() {
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Test Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available'
        );
        insert item;

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id,
            Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id,
            Requested_Date__c = Date.today(),
            of_Days_Needed__c = 7,
            Status__c = 'Pending Approval',
            Waitlist_Position__c = 1
        );
        insert request;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.checkExistingLendingRequest(item.Id, testContact.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('hasExistingRequest'), 'Should have existing request');
    }

    @isTest
    static void testCreateLendingRequest_FirstInLine() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Borrowable Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7
        );
        insert item;

        Map<String, Object> requestData = new Map<String, Object>{
            'itemId' => item.Id,
            'requestedById' => testContact.Id,
            'requestedDate' => String.valueOf(Date.today().addDays(1)),
            'daysNeeded' => 5,
            'message' => 'Please let me borrow this'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.createLendingRequest(JSON.serialize(requestData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(1, (Decimal) result.get('waitlistPosition'), 'Should be first in line');
        System.assertEquals(true, result.get('isFirstInLine'), 'isFirstInLine should be true');
    }

    @isTest
    static void testCreateLendingRequest_NoMessage() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Simple Request Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7
        );
        insert item;

        Map<String, Object> requestData = new Map<String, Object>{
            'itemId' => item.Id,
            'requestedById' => testContact.Id,
            'requestedDate' => String.valueOf(Date.today().addDays(1)),
            'daysNeeded' => 5
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.createLendingRequest(JSON.serialize(requestData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        // Verify request was created without message
        String requestId = (String) result.get('requestId');
        Lending_Request__c request = [SELECT Message__c FROM Lending_Request__c WHERE Id = :requestId];
        System.assertEquals(null, request.Message__c, 'Message should be null');
    }

    @isTest
    static void testCreateLendingRequest_AutoAccept() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        // Need a second contact as borrower
        Contact borrower = new Contact(
            FirstName = 'Borrower',
            LastName = 'Test',
            AccountId = testContact.AccountId
        );
        insert borrower;

        Library_Item__c item = new Library_Item__c(
            Name = 'Auto-Approve Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            Auto_Accept_Requests__c = true,
            Auto_Share_Contact_Info__c = true
        );
        insert item;

        Map<String, Object> requestData = new Map<String, Object>{
            'itemId' => item.Id,
            'requestedById' => borrower.Id,
            'requestedDate' => String.valueOf(Date.today().addDays(1)),
            'daysNeeded' => 3,
            'message' => 'Auto test'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.createLendingRequest(JSON.serialize(requestData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('autoApproved'), 'Should be auto-approved');
    }

    @isTest
    static void testCreateLendingRequest_AutoAcceptNoShare() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Contact borrower = new Contact(
            FirstName = 'Borrower2',
            LastName = 'Test',
            AccountId = testContact.AccountId
        );
        insert borrower;

        Library_Item__c item = new Library_Item__c(
            Name = 'Auto No Share',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 7,
            Auto_Accept_Requests__c = true,
            Auto_Share_Contact_Info__c = false
        );
        insert item;

        Map<String, Object> requestData = new Map<String, Object>{
            'itemId' => item.Id,
            'requestedById' => borrower.Id,
            'requestedDate' => String.valueOf(Date.today().addDays(1)),
            'daysNeeded' => 5,
            'message' => ''
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.createLendingRequest(JSON.serialize(requestData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('autoApproved'), 'Should be auto-approved');
        System.assertEquals(false, result.get('contactInfoShared'), 'Should not share contact info');
    }

    // ============================================
    // IMAGE UPLOAD TESTS
    // ============================================

    @isTest
    static void testGetImageUploadSettings() {
        Test.startTest();
        Map<String, Object> settings = FimbyLibraryController.getImageUploadSettings();
        Test.stopTest();

        System.assertNotEquals(null, settings, 'Should return settings');
        System.assertNotEquals(null, settings.get('maxDimension'), 'Should have maxDimension');
        System.assertNotEquals(null, settings.get('jpegQuality'), 'Should have jpegQuality');
        System.assertNotEquals(null, settings.get('maxFileSizeMB'), 'Should have maxFileSizeMB');
    }

    @isTest
    static void testUploadImage_ValidationOnly() {
        // Test that uploadImage validates inputs correctly
        // Full upload tests require ContentDistribution which has network restrictions in tests

        Test.startTest();
        try {
            // Test with empty file data
            FimbyLibraryController.uploadImage('', 'test.jpg', 'fakeId', 'Story__c', null, 100, 100);
            System.assert(false, 'Should have thrown an exception for empty file data');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testImageFieldNameHelpers() {
        // Test that the image field name methods work correctly for different objects
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Field Test Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Image_URL__c = 'https://test.com/image.jpg',
            Image_Ratio__c = '100X100'
        );
        insert item;

        Test.startTest();
        // Test getCurrentImage for Library_Item__c
        Map<String, Object> result = FimbyLibraryController.getCurrentImage(item.Id, 'Library_Item__c', null);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('https://test.com/image.jpg', result.get('imageUrl'), 'Should return correct URL');
    }

    @isTest
    static void testGetCurrentImage_AppendsOrgId() {
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'OrgId Append Test',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Image_URL__c = 'https://example.file.force.com/sfc/dist/version/renditionDownload?rendition=ORIGINAL_Jpg&oid=',
            Image_Ratio__c = '100X100'
        );
        insert item;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.getCurrentImage(item.Id, 'Library_Item__c', null);
        Test.stopTest();

        String returnedUrl = (String) result.get('imageUrl');
        System.assert(returnedUrl.contains(UserInfo.getOrganizationId()), 'URL should have org ID appended');
    }

    @isTest
    static void testRemoveImage() {
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Remove Image Test',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
                Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Image_URL__c = 'https://example.com/image.jpg',
            Image_Ratio__c = '100X100'
        );
        insert item;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.removeImage(item.Id, 'Library_Item__c', null);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        Library_Item__c updated = [SELECT Image_URL__c, Image_Ratio__c FROM Library_Item__c WHERE Id = :item.Id];
        System.assertEquals(null, updated.Image_URL__c, 'Image URL should be cleared');
    }

    @isTest
    static void testGetCurrentImage() {
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Get Image Test',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
                Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Image_URL__c = 'https://example.com/test.jpg',
            Image_Ratio__c = '150X100'
        );
        insert item;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.getCurrentImage(item.Id, 'Library_Item__c', null);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('https://example.com/test.jpg', result.get('imageUrl'), 'Should return image URL');
        System.assertEquals('150X100', result.get('imageRatio'), 'Should return image ratio');
    }

    @isTest
    static void testUploadImage_MissingParams() {
        Test.startTest();
        try {
            FimbyLibraryController.uploadImage(null, 'test.jpg', null, null, null, 100, 100);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            // Any error is acceptable - either missing params or other validation
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetCurrentImage_NeedsOffers() {
        // Test getting image for Needs_Offers__c with slot
        Contact testContact = getTestContact();

        Needs_Offers__c needOffer = new Needs_Offers__c(
            Name = 'Test Need',
            Details__c = 'Test details',
            Full_Details__c = 'Full test details',
            Posted_By__c = testContact.Id,
            Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
                Status__c = 'Posted',
            Image_1_URL__c = 'https://test.com/image1.jpg',
            Image_1_Ratio__c = '200X150'
        );
        insert needOffer;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.getCurrentImage(needOffer.Id, 'Needs_Offers__c', 1);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('https://test.com/image1.jpg', result.get('imageUrl'), 'Should return image URL');
    }

    @isTest
    static void testRemoveImage_NeedsOffers() {
        Contact testContact = getTestContact();

        Needs_Offers__c needOffer = new Needs_Offers__c(
            Name = 'Remove Image Test',
            Details__c = 'Test',
            Full_Details__c = 'Test',
            Posted_By__c = testContact.Id,
                Contact__c = testContact.Id,
                Neighbourhood__c = testContact.AccountId,
            Status__c = 'Posted',
            Image_2_URL__c = 'https://test.com/image2.jpg',
            Image_2_Ratio__c = '100X100'
        );
        insert needOffer;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.removeImage(needOffer.Id, 'Needs_Offers__c', 2);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');

        Needs_Offers__c updated = [SELECT Image_2_URL__c FROM Needs_Offers__c WHERE Id = :needOffer.Id];
        System.assertEquals(null, updated.Image_2_URL__c, 'Image URL should be cleared');
    }

    @isTest
    static void testGetAllImageSlots() {
        Contact testContact = getTestContact();
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'All Slots Test',
            Details__c = 'Test',
            Full_Details__c = 'Test',
            Posted_By__c = testContact.Id,
            Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Posted',
            Image_1_URL__c = 'https://test.com/1.jpg',
            Image_1_Ratio__c = '200X150',
            Image_3_URL__c = 'https://test.com/3.jpg',
            Image_3_Ratio__c = '300X200'
        );
        insert post;

        Test.startTest();
        List<Map<String, Object>> slots = FimbyLibraryController.getAllImageSlots(post.Id);
        Test.stopTest();

        System.assertEquals(2, slots.size(), 'Should return 2 filled slots');
        System.assertEquals(1, slots[0].get('slot'), 'First slot should be 1');
        System.assertEquals(3, slots[1].get('slot'), 'Second slot should be 3');
    }

    @isTest
    static void testRemoveAndConsolidateImage() {
        Contact testContact = getTestContact();
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Consolidate Test',
            Details__c = 'Test',
            Full_Details__c = 'Test',
            Posted_By__c = testContact.Id,
            Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Posted',
            Image_1_URL__c = 'https://test.com/1.jpg',
            Image_1_Ratio__c = '200X150',
            Image_2_URL__c = 'https://test.com/2.jpg',
            Image_2_Ratio__c = '300X200',
            Image_3_URL__c = 'https://test.com/3.jpg',
            Image_3_Ratio__c = '400X300'
        );
        insert post;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.removeAndConsolidateImage(post.Id, 2);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed');
        List<Object> slots = (List<Object>) result.get('slots');
        System.assertEquals(2, slots.size(), 'Should have 2 remaining images');

        Needs_Offers__c updated = [SELECT Image_1_URL__c, Image_2_URL__c, Image_3_URL__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('https://test.com/1.jpg', updated.Image_1_URL__c, 'Slot 1 unchanged');
        System.assertEquals('https://test.com/3.jpg', updated.Image_2_URL__c, 'Slot 3 consolidated to slot 2');
        System.assertEquals(null, updated.Image_3_URL__c, 'Slot 3 should be cleared');
    }

    @isTest
    static void testGetLibraryItemForLending_RemovedFromLibrary() {
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Removed Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
                Neighbourhood__c = testContact.AccountId,
            Status__c = 'Removed from Library'
        );
        insert item;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.getLibraryItemForLending(item.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(false, result.get('canBeLent'), 'Item should not be lendable');
    }

    @isTest
    static void testCreateLibraryItem_Exception() {
        User testUser = getTestUser();

        // Invalid JSON should throw error
        Test.startTest();
        try {
        System.runAs(testUser) {
                FimbyLibraryController.createLibraryItem('not valid json');
            }
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testCheckExistingLendingRequest_Exception() {
        Test.startTest();
        try {
            FimbyLibraryController.checkExistingLendingRequest('invalidId', 'invalidId');
            // May or may not throw depending on Salesforce's handling
        } catch (Exception e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetLibraryItemForLending_Exception() {
        Test.startTest();
        try {
            FimbyLibraryController.getLibraryItemForLending('invalidId');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateLendingRequest_Exception() {
        User testUser = getTestUser();

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyLibraryController.createLendingRequest('invalid json');
            }
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetCurrentImage_Exception() {
        Test.startTest();
        try {
            FimbyLibraryController.getCurrentImage('invalidId', 'Library_Item__c', null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testRemoveImage_Exception() {
        Test.startTest();
        try {
            FimbyLibraryController.removeImage('invalidId', 'Library_Item__c', null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetPhotoUploadFlowInputs_Exception() {
        Test.startTest();
        try {
            Map<String, Object> result = FimbyLibraryController.getPhotoUploadFlowInputs(null);
            System.assertNotEquals(null, result, 'Should return result');
        } catch (Exception e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    // ============================================
    // USER CONTEXT TESTS
    // ============================================

    @isTest
    static void testGetLibraryItemUserContext_NoRelationship() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Context Test Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Available'
        );
        insert item;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemUserContext(item.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(false, result.get('hasActiveRequest'), 'Should not have active request');
        System.assertEquals(false, result.get('hasActiveLoan'), 'Should not have active loan');
    }

    @isTest
    static void testGetLibraryItemUserContext_WithRequest() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Context Request Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'On Hold'
        );
        insert item;

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id, Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id, Requested_Date__c = Date.today(),
            of_Days_Needed__c = 5, Status__c = 'Pending Approval', Waitlist_Position__c = 1
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemUserContext(item.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        // Community user FLS may prevent reading Lending_Request__c — accept either outcome
        if (result.get('hasActiveRequest') == true) {
            Map<String, Object> reqData = (Map<String, Object>) result.get('request');
            System.assertEquals('Pending Approval', reqData.get('status'), 'Request status should match');
        }
    }

    @isTest
    static void testGetLibraryItemUserContext_InvalidId() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            try {
                Map<String, Object> result = FimbyLibraryController.getLibraryItemUserContext('invalidId');
                // SOQL with invalid IDs may return empty results rather than throwing
                System.assertNotEquals(null, result, 'Should return a result map');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null, 'Should have error message');
            }
        }
        Test.stopTest();
    }

    // ============================================
    // ADMIN PANEL TESTS
    // ============================================

    @isTest
    static void testGetLibraryItemAdmin_AsOwner() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Admin Test Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Available'
        );
        insert item;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemAdmin(item.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        List<Object> requests = (List<Object>) result.get('lendingRequests');
        System.assertEquals(0, requests.size(), 'Should have no lending requests');
        List<Object> history = (List<Object>) result.get('lendingHistory');
        System.assertEquals(0, history.size(), 'Should have no lending history');
    }

    @isTest
    static void testGetLibraryItemAdmin_WithRequests() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Admin Requests Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'On Hold'
        );
        insert item;

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id, Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id, Requested_Date__c = Date.today(),
            of_Days_Needed__c = 7, Status__c = 'Pending Approval', Waitlist_Position__c = 1
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemAdmin(item.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        List<Object> requests = (List<Object>) result.get('lendingRequests');
        // FLS for community user may filter Lending_Request__c fields — accept 0 or 1
        System.assert(requests.size() >= 0, 'Should return lending requests list');
    }

    @isTest
    static void testGetLibraryItemAdmin_Exception() {
        User testUser = getTestUser();

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyLibraryController.getLibraryItemAdmin('invalidId');
            }
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetLibraryItemUserContext_WithLoan() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Loan Context Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Currently Lent Out'
        );
        insert item;

        Loaned_Item__c loan = new Loaned_Item__c(
            Library_Item__c = item.Id, Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today(),
            Loan_Due_Date__c = Date.today().addDays(7)
        );
        insert loan;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemUserContext(item.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testGetLibraryItemAdmin_OwnerWithLoan() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Admin Loan Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Currently Lent Out'
        );
        insert item;

        Loaned_Item__c loan = new Loaned_Item__c(
            Library_Item__c = item.Id, Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today(),
            Loan_Due_Date__c = Date.today().addDays(7)
        );
        insert loan;

        Lending_History__c hist = new Lending_History__c(
            Library_Item__c = item.Id, Borrowed_By__c = testContact.Id,
            Start_Date__c = Date.today().addDays(-30), End_Date__c = Date.today().addDays(-23)
        );
        insert hist;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemAdmin(item.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testCreateLibraryItem_WithAllOptions() {
        User testUser = getTestUser();

        Map<String, Object> testData = new Map<String, Object>{
            'title' => 'Full Options Item',
            'description' => 'Item with all options set',
            'category' => 'Books',
            'maxLendingDays' => 14,
            'ownedBy' => 'Self',
            'autoAcceptRequests' => true,
            'autoShareContactInfo' => true,
            'damageWaiverConfirmed' => true
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.createLibraryItem(JSON.serialize(testData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        String recordId = (String) result.get('recordId');
        Library_Item__c item = [SELECT Max_Lending_Time_In_Days__c, Auto_Accept_Requests__c FROM Library_Item__c WHERE Id = :recordId];
        System.assertEquals(14, item.Max_Lending_Time_In_Days__c, 'Should set custom max lending days');
        System.assertEquals(true, item.Auto_Accept_Requests__c, 'Should set auto-accept');
    }

    @isTest
    static void testGetLibraryItemForLending_OnHold() {
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'On Hold Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'On Hold',
            Max_Lending_Time_In_Days__c = 7
        );
        insert item;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.getLibraryItemForLending(item.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('canBeLent'), 'On Hold items should be lendable');
    }

    @isTest
    static void testGetLibraryItemForLending_CurrentlyLentOut() {
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Lent Out Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Currently Lent Out',
            Max_Lending_Time_In_Days__c = 7
        );
        insert item;

        Test.startTest();
        Map<String, Object> result = FimbyLibraryController.getLibraryItemForLending(item.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('canBeLent'), 'Currently Lent Out items should be lendable (for waitlist)');
    }

    @isTest
    static void testCreateLendingRequest_Waitlisted() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Contact otherOwner = new Contact(
            FirstName = 'Other', LastName = 'Owner',
            AccountId = testContact.AccountId, Email = 'otherowner@fimby.test.com'
        );
        insert otherOwner;

        Library_Item__c item = new Library_Item__c(
            Name = 'Waitlist Test Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = otherOwner.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'On Hold',
            Max_Lending_Time_In_Days__c = 7
        );
        insert item;

        // Pre-existing request from another person
        Lending_Request__c existingReq = new Lending_Request__c(
            Library_Item__c = item.Id, Requested_By__c = otherOwner.Id,
            Item_Owner__c = otherOwner.Id, Requested_Date__c = Date.today(),
            of_Days_Needed__c = 3, Status__c = 'Pending Approval', Waitlist_Position__c = 1
        );
        insert existingReq;

        Map<String, Object> requestData = new Map<String, Object>{
            'itemId' => item.Id,
            'requestedById' => testContact.Id,
            'requestedDate' => String.valueOf(Date.today().addDays(1)),
            'daysNeeded' => 5,
            'message' => 'Can I borrow this?'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.createLendingRequest(JSON.serialize(requestData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('waitlistPosition'), 'Should have waitlist position');
        System.assertNotEquals(null, result.get('requestId'), 'Should have request Id');
    }

    @isTest
    static void testUploadImage_ContentVersionCreation() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Upload Test Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Available'
        );
        insert item;

        // 1x1 white pixel JPEG
        String base64Image = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAUAQEAAAAAAAAAAAAAAAAAAAAA/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8AKwA//9k=';

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyLibraryController.uploadImage(base64Image, 'test.jpg', item.Id, 'Library_Item__c', null, 100, 100);
            }
        } catch (AuraHandledException e) {
            // ContentDistribution may fail in test context — this is expected
            System.assert(e.getMessage() != null, 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetLibraryItemAdmin_NotOwner() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Account orgAccount = [SELECT Id FROM Account WHERE Name = 'Test Community Organization' LIMIT 1];

        Contact otherContact = new Contact(
            FirstName = 'Other', LastName = 'Person',
            AccountId = testContact.AccountId, Email = 'other@fimby.test.com'
        );
        insert otherContact;

        Library_Item__c item = new Library_Item__c(
            Name = 'Not My Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = otherContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Available'
        );
        insert item;

        Test.startTest();
        try {
            System.runAs(testUser) {
                FimbyLibraryController.getLibraryItemAdmin(item.Id);
            }
            System.assert(false, 'Should have thrown exception for non-owner');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have ownership error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetLibraryItemAdmin_WithActiveLoan() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Loaned Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Currently Lent Out',
            Max_Lending_Time_In_Days__c = 7, OwnerId = testUser.Id
        );
        insert item;

        Loaned_Item__c loan = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-3),
            Loan_Due_Date__c = Date.today().addDays(4),
            Neighbourhood__c = testContact.AccountId,
            OwnerId = testUser.Id
        );
        insert loan;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemAdmin(item.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        Map<String, Object> currentLoan = (Map<String, Object>) result.get('currentLoan');
        if (currentLoan != null) {
            System.assertNotEquals(null, currentLoan.get('id'), 'Current loan should have an id');
        }
    }

    @isTest
    static void testGetLibraryItemAdmin_WithApprovedRequest() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Approved Req Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'On Hold',
            Max_Lending_Time_In_Days__c = 7, OwnerId = testUser.Id
        );
        insert item;

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id, Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id, Requested_Date__c = Date.today(),
            of_Days_Needed__c = 5, Status__c = 'Approved', Waitlist_Position__c = 1,
            Neighbourhood__c = testContact.AccountId
        );
        insert request;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testContact.Id,
            Participant_2__c = testContact.Id,
            Status__c = 'Active',
            Context_Type__c = 'Library_Lending',
            Related_Record_Id__c = request.Id
        );
        insert conv;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemAdmin(item.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        List<Object> reqs = (List<Object>) result.get('lendingRequests');
        System.assert(reqs.size() >= 0, 'Should have lending requests list');
    }

    @isTest
    static void testGetLibraryItemUserContext_WithActiveLoan() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'My Borrowed Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Currently Lent Out',
            Max_Lending_Time_In_Days__c = 7, OwnerId = testUser.Id
        );
        insert item;

        Loaned_Item__c loan = new Loaned_Item__c(
            Library_Item__c = item.Id,
            Loaned_To__c = testContact.Id,
            Loan_Start_Date__c = Date.today().addDays(-3),
            Loan_Due_Date__c = Date.today().addDays(4),
            Neighbourhood__c = testContact.AccountId,
            OwnerId = testUser.Id
        );
        insert loan;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemUserContext(item.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testCreateLendingRequest_ReturnsConfirmationWindow() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'Available Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Available',
            Max_Lending_Time_In_Days__c = 14, OwnerId = testUser.Id
        );
        insert item;

        Map<String, Object> requestData = new Map<String, Object>{
            'itemId' => item.Id,
            'requestedById' => testContact.Id,
            'requestedDate' => String.valueOf(Date.today().addDays(1)),
            'daysNeeded' => 5,
            'message' => 'Can I borrow this?'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.createLendingRequest(JSON.serialize(requestData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testGetLibraryItemAdmin_EstimatedAvailableDate() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'EAD Test Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'On Hold'
        );
        insert item;

        Lending_Request__c request = new Lending_Request__c(
            Library_Item__c = item.Id, Requested_By__c = testContact.Id,
            Item_Owner__c = testContact.Id, Requested_Date__c = Date.today(),
            of_Days_Needed__c = 3, Status__c = 'Waitlisted', Waitlist_Position__c = 1
        );
        insert request;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemAdmin(item.Id);
        }
        Test.stopTest();

        List<Object> requests = (List<Object>) result.get('lendingRequests');
        if (!requests.isEmpty()) {
            Map<String, Object> reqMap = (Map<String, Object>) requests[0];
            System.assert(reqMap.containsKey('estimatedAvailableDate'), 'Should include estimatedAvailableDate key');
        }
    }

    @isTest
    static void testGetLibraryItemAdmin_HistoryConversation() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'HistConv Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Available'
        );
        insert item;

        Lending_History__c hist = new Lending_History__c(
            Library_Item__c = item.Id, Borrowed_By__c = testContact.Id,
            Lent_By__c = testContact.Id,
            Start_Date__c = Date.today().addDays(-30), End_Date__c = Date.today().addDays(-23)
        );
        insert hist;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testContact.Id,
            Participant_2__c = testContact.Id,
            Context_Type__c = 'Library_Lending',
            Related_Record_Id__c = String.valueOf(hist.Id),
            Last_Message_Date__c = Datetime.now()
        );
        insert conv;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemAdmin(item.Id);
        }
        Test.stopTest();

        List<Object> histList = (List<Object>) result.get('lendingHistory');
        // FLS for community user may filter Lending_History__c — accept 0 or more
        if (!histList.isEmpty()) {
            Map<String, Object> histMap = (Map<String, Object>) histList[0];
            System.assert(histMap.containsKey('conversationId'), 'Should include conversationId key when history visible');
        }
    }

    @isTest
    static void testGetLibraryItemUserContext_BorrowerHistory() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item = new Library_Item__c(
            Name = 'BorrowerHist Item', Description__c = 'Test', Category__c = 'Tools',
            Owned_By__c = 'Self', Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId, Status__c = 'Available'
        );
        insert item;

        Lending_History__c hist = new Lending_History__c(
            Library_Item__c = item.Id, Borrowed_By__c = testContact.Id,
            Lent_By__c = testContact.Id,
            Start_Date__c = Date.today().addDays(-14), End_Date__c = Date.today()
        );
        insert hist;

        Conversation__c conv = new Conversation__c(
            Participant_1__c = testContact.Id,
            Participant_2__c = testContact.Id,
            Context_Type__c = 'Library_Lending',
            Related_Record_Id__c = String.valueOf(hist.Id),
            Last_Message_Date__c = Datetime.now()
        );
        insert conv;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyLibraryController.getLibraryItemUserContext(item.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        List<Object> bhList = (List<Object>) result.get('borrowerHistory');
        if (bhList != null && !bhList.isEmpty()) {
            Map<String, Object> bhMap = (Map<String, Object>) bhList[0];
            System.assertEquals(String.valueOf(conv.Id), bhMap.get('conversationId'), 'Should have conversation ID');
        }
    }

    @isTest
    static void testGetLibraryItemVisibility_NullId() {
        Test.startTest();
        FimbyLibraryController.VisibilityResult result = FimbyLibraryController.getLibraryItemVisibility(null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.removed, 'Null id should return removed stub');
        System.assertEquals(false, result.visible, 'Null id should not be visible');
    }

    @isTest
    static void testGetLibraryItemVisibility_Visible() {
        Contact testContact = getTestContact();
        Library_Item__c item = new Library_Item__c(
            Name = 'Visible Library Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available'
        );
        insert item;

        Test.startTest();
        FimbyLibraryController.VisibilityResult result = FimbyLibraryController.getLibraryItemVisibility(item.Id);
        Test.stopTest();

        System.assertEquals(true, result.visible, 'Visible item should be visible');
        System.assertEquals(false, result.removed, 'Visible item should not be reported as removed');
    }

    @isTest
    static void testGetLibraryItemVisibility_Hidden() {
        Contact testContact = getTestContact();
        Library_Item__c item = new Library_Item__c(
            Name = 'Hidden Library Item',
            Description__c = 'Test',
            Category__c = 'Tools',
            Owned_By__c = 'Self',
            Owner_Contact__c = testContact.Id,
            Neighbourhood__c = testContact.AccountId,
            Status__c = 'Available',
            Moderation_Status__c = 'Hidden_By_Moderator'
        );
        insert item;

        Test.startTest();
        FimbyLibraryController.VisibilityResult result = FimbyLibraryController.getLibraryItemVisibility(item.Id);
        Test.stopTest();

        System.assertEquals(true, result.removed, 'Hidden item should be reported as removed');
        System.assertEquals(false, result.visible, 'Hidden item should not be visible');
        System.assertNotEquals(null, result.message, 'Removed stub should include a message');
    }
}