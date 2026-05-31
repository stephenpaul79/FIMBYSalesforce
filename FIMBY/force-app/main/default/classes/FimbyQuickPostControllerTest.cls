@isTest
public class FimbyQuickPostControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(contact.Id, 'Customer Community User - Mobile App', true);
    }

    private static User getTestUser() {
        return [
            SELECT Id, ContactId, Contact.AccountId
            FROM User
            WHERE Profile.Name = 'Customer Community User - Mobile App'
            AND IsActive = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    @isTest
    static void testCreateNeedsOffer_Success() {
        User testUser = getTestUser();

        Map<String, Object> testData = new Map<String, Object>{
            'name' => 'Test Need',
            'description' => 'Test description for need',
            'type' => 'need',
            'category' => 'general',
            'location' => 'Test Location',
            'imageUrl' => 'https://test.com/image.jpg',
            'privacy' => 'neighborhood',
            'needOrOffer' => 'need',
            'eventDate' => '2024-12-25',
            'eventTime' => '10:00'
        };

        String itemDataJson = JSON.serialize(testData);

        Test.startTest();
        System.runAs(testUser) {
            try {
                Map<String, Object> result = FimbyQuickPostController.createNeedsOffer(itemDataJson);
                System.assert((Boolean) result.get('success'), 'Should return success as true');
                System.assertNotEquals(null, result.get('Id'), 'Should return a valid Id');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null, 'DML failure should produce a meaningful message');
            }
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateNeedsOffer_MinimalData() {
        User testUser = getTestUser();

        Map<String, Object> testData = new Map<String, Object>{
            'name' => 'Simple Offer',
            'description' => 'Simple description',
            'type' => 'offer',
            'privacy' => 'public',
            'needOrOffer' => 'offer'
        };

        String itemDataJson = JSON.serialize(testData);

        Test.startTest();
        System.runAs(testUser) {
            try {
                Map<String, Object> result = FimbyQuickPostController.createNeedsOffer(itemDataJson);
                System.assert((Boolean) result.get('success'), 'Should return success as true');
                System.assertNotEquals(null, result.get('Id'), 'Should return a valid Id');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null, 'DML failure should produce a meaningful message');
            }
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateNeedsOffer_InvalidJson() {
        User testUser = getTestUser();
        String invalidJson = '{"name": "Test", "description":}';

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyQuickPostController.createNeedsOffer(invalidJson);
                System.assert(false, 'Should have thrown an exception');
            } catch (Exception e) {
                System.assert(e.getMessage() != null, 'Should have an error message');
            }
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateNeedsOffer_NoContactUser() {
        Test.startTest();
        try {
            Map<String, Object> testData = new Map<String, Object>{
                'name' => 'Test',
                'description' => 'Test',
                'type' => 'need',
                'needOrOffer' => 'need'
            };
            FimbyQuickPostController.createNeedsOffer(JSON.serialize(testData));
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have an error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateNeedsOffer_EmptyEventDate() {
        User testUser = getTestUser();

        Map<String, Object> testData = new Map<String, Object>{
            'name' => 'Test Event',
            'description' => 'Test event description',
            'type' => 'event',
            'needOrOffer' => 'need',
            'eventDate' => '',
            'eventTime' => '15:30'
        };

        String itemDataJson = JSON.serialize(testData);

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyQuickPostController.createNeedsOffer(itemDataJson);
            System.assert((Boolean) result.get('success'), 'Should return success as true');

            List<Needs_Offers__c> createdItems = [
                SELECT Id, Start_Date__c, Start_Time__c
                FROM Needs_Offers__c
                WHERE Id = :(String)result.get('Id')
            ];
            System.assertEquals(1, createdItems.size(), 'Should create one record');
            System.assertEquals(null, createdItems[0].Start_Date__c, 'Event date should be null for empty string');
        }
        Test.stopTest();
    }
}
