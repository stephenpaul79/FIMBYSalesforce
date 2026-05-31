@isTest
public class FimbyQuickResponseControllerTest {

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
        return [SELECT Id, AccountId FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1];
    }

    @isTest
    static void testBlankParams() {
        Test.startTest();
        try {
            FimbyQuickResponseController.getQuickResponseContext('', '');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), 'Should mention required params');
        }
        Test.stopTest();
    }

    @isTest
    static void testStoryType() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Story__c story;
        System.runAs(testUser) {
            story = new Story__c(
                Name = 'Test Story',
                Message__c = 'Test message content.',
                Type__c = 'Thank You',
                Neighbourhood__c = testContact.AccountId,
                Posted_By__c = testContact.Id
            );
            insert story;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyQuickResponseController.getQuickResponseContext(story.Id, 'story');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('form', result.get('viewState'), 'Should return form viewState');
        System.assertNotEquals(null, result.get('identity'), 'Should include identity');
        System.assertNotEquals(null, result.get('context'), 'Should include context');
    }

    @isTest
    static void testAskOfferType() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Needs_Offers__c post;
        System.runAs(testUser) {
            Id recordTypeId;
            try {
                recordTypeId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();
            } catch (Exception e) {
                recordTypeId = null;
            }

            post = new Needs_Offers__c(
                Name = 'Test Offer',
                Details__c = 'Test details',
                Status__c = 'Posted',
                Posted_By__c = testContact.Id,
                Contact__c = testContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = testContact.AccountId,
                Total_Quantity__c = 5,
                End_Date__c = Date.today().addDays(7)
            );
            if (recordTypeId != null) post.RecordTypeId = recordTypeId;
            insert post;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyQuickResponseController.getQuickResponseContext(post.Id, 'askOffer');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('context'), 'Should include post context');

        Map<String, Object> ctx = (Map<String, Object>) result.get('context');
        System.assertEquals('Test Offer', ctx.get('name'), 'Should return post name');
    }

    @isTest
    static void testOpenEventType() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Needs_Offers__c post;
        System.runAs(testUser) {
            Id recordTypeId;
            try {
                recordTypeId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();
            } catch (Exception e) {
                recordTypeId = null;
            }

            post = new Needs_Offers__c(
                Name = 'Community BBQ',
                Details__c = 'Open event',
                Status__c = 'Posted',
                Type__c = 'Event',
                Event_Type__c = 'Open_Event',
                Posted_By__c = testContact.Id,
                Contact__c = testContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = testContact.AccountId,
                Total_Quantity__c = 20,
                Start_Date__c = Date.today().addDays(3),
                End_Date__c = Date.today().addDays(7)
            );
            if (recordTypeId != null) post.RecordTypeId = recordTypeId;
            insert post;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyQuickResponseController.getQuickResponseContext(post.Id, 'openEvent');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('form', result.get('viewState'), 'No existing check for events');

        Map<String, Object> ctx = (Map<String, Object>) result.get('context');
        System.assertEquals('Open_Event', ctx.get('eventType'), 'Should include eventType');
    }

    @isTest
    static void testLibraryType() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Library_Item__c item;
        System.runAs(testUser) {
            item = new Library_Item__c(
                Name = 'Borrowed Drill',
                Description__c = 'Power drill for home use.',
                Category__c = 'Tools',
                Status__c = 'Available',
                Neighbourhood__c = testContact.AccountId,
                Owner_Contact__c = testContact.Id
            );
            insert item;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyQuickResponseController.getQuickResponseContext(item.Id, 'library');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('context'), 'Should include library context');
    }

    @isTest
    static void testAlreadyRespondedAskOffer() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Needs_Offers__c post;
        System.runAs(testUser) {
            Id recordTypeId;
            try {
                recordTypeId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();
            } catch (Exception e) {
                recordTypeId = null;
            }

            post = new Needs_Offers__c(
                Name = 'Test Need',
                Details__c = 'Test details',
                Status__c = 'Posted',
                Posted_By__c = testContact.Id,
                Contact__c = testContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = testContact.AccountId,
                Total_Quantity__c = 3,
                End_Date__c = Date.today().addDays(7)
            );
            if (recordTypeId != null) post.RecordTypeId = recordTypeId;
            insert post;

            Response__c resp = new Response__c(
                Need_Offer_Responded_To__c = post.Id,
                Response__c = 'Already responded',
                Amount_Requested__c = 1
            );
            insert resp;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyQuickResponseController.getQuickResponseContext(post.Id, 'askOffer');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('alreadyResponded', result.get('viewState'), 'Should detect existing response');
    }
}
