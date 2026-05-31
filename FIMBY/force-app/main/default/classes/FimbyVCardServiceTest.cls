@IsTest
public class FimbyVCardServiceTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(neighbourhood.Id, 2, true);
        Contact sharer = contacts[0];
        Contact recipient = contacts[1];
        User communityUser = FimbyTestDataFactory.createCommunityUser(recipient.Id, 'Customer Community User - Mobile App', true);

        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = sharer.Id,
            Shared_To__c = recipient.Id,
            Email__c = 'sharer@test.com',
            Phone__c = '0400111222',
            Street__c = '42 Main St',
            City__c = 'Melbourne',
            Province_State__c = 'VIC',
            Postal_Code__c = '3000',
            Country__c = 'Australia',
            Status__c = 'Active'
        );
        insert sci;
    }

    @IsTest
    static void testGetVCard_Success() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate LIMIT 2];
        Contact sharer = contacts[0];
        Contact recipient = contacts[1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :recipient.Id LIMIT 1];

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/fimby/vcard';
        req.httpMethod = 'GET';
        req.params.put('contactId', sharer.Id);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        System.runAs(testUser) {
            FimbyVCardService.getVCard();
        }
        Test.stopTest();

        RestResponse res = RestContext.response;
        System.assertEquals(200, res.statusCode, 'Should return 200');
        String body = res.responseBody.toString();
        System.assert(body.contains('BEGIN:VCARD'), 'Should contain vCard header');
        System.assert(body.contains('END:VCARD'), 'Should contain vCard footer');
        System.assert(body.contains('FN:'), 'Should contain full name line');
        System.assert(body.contains('N:'), 'Should contain structured name line');
        System.assert(body.contains('sharer@test.com'), 'Should contain shared email');
        System.assert(body.contains('0400111222'), 'Should contain shared phone');
        System.assert(body.contains('42 Main St'), 'Should contain shared street');
        System.assert(res.headers.get('Content-Type').contains('text/vcard'), 'Content-Type should be vcard');
    }

    @IsTest
    static void testGetVCard_MissingContactId() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate LIMIT 2];
        Contact recipient = contacts[1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :recipient.Id LIMIT 1];

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/fimby/vcard';
        req.httpMethod = 'GET';
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        System.runAs(testUser) {
            FimbyVCardService.getVCard();
        }
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode, 'Should return 400 for missing param');
    }

    @IsTest
    static void testGetVCard_NoSharedRecord() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate LIMIT 2];
        Contact recipient = contacts[1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :recipient.Id LIMIT 1];

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/fimby/vcard';
        req.httpMethod = 'GET';
        req.params.put('contactId', recipient.Id);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        System.runAs(testUser) {
            FimbyVCardService.getVCard();
        }
        Test.stopTest();

        System.assertEquals(404, RestContext.response.statusCode, 'Should return 404 when no shared record exists');
    }

    @IsTest
    static void testGetVCard_RevokedNotReturned() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id ORDER BY CreatedDate LIMIT 2];
        Contact sharer = contacts[0];
        Contact recipient = contacts[1];
        User testUser = [SELECT Id FROM User WHERE ContactId = :recipient.Id LIMIT 1];

        Shared_Contact_Info__c sci = [
            SELECT Id FROM Shared_Contact_Info__c
            WHERE Contact__c = :sharer.Id AND Shared_To__c = :recipient.Id LIMIT 1
        ];
        sci.Status__c = 'Revoked';
        update sci;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/fimby/vcard';
        req.httpMethod = 'GET';
        req.params.put('contactId', sharer.Id);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        System.runAs(testUser) {
            FimbyVCardService.getVCard();
        }
        Test.stopTest();

        System.assertEquals(404, RestContext.response.statusCode, 'Revoked records should not be returned');
    }
}
