@isTest
public class FimbyResponseControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User testUser = FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);
    }

    private static User getTestUser() {
        Contact testContact = getTestContact();
        List<User> users = [
            SELECT Id, ContactId
            FROM User
            WHERE ContactId = :testContact.Id
              AND IsActive = true
            LIMIT 1
        ];
        System.assert(!users.isEmpty(), 'TestSetup must create a community User for the test Contact.');
        return users[0];
    }

    private static Contact getTestContact() {
        return [SELECT Id, AccountId, Logged_In_As_Contact__c FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1];
    }

    private static Needs_Offers__c createTestNeedOffer(User owner, Boolean autoAccept, Integer quantity) {
        Needs_Offers__c needOffer;
        System.runAs(owner) {
            Id recordTypeId;
            try {
                recordTypeId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();
            } catch (Exception e) {
                recordTypeId = null;
            }

            Contact ownerContact = [SELECT Id, AccountId FROM Contact WHERE Id = :[SELECT ContactId FROM User WHERE Id = :owner.Id].ContactId LIMIT 1];

            needOffer = new Needs_Offers__c(
                Name = 'Test Need/Offer',
                Details__c = 'Test details',
                Full_Details__c = 'Full test details',
                Status__c = 'Posted',
                Posted_By__c = ownerContact.Id,
                Contact__c = ownerContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = ownerContact.AccountId,
                Total_Quantity__c = quantity,
                Per_Response_Limit__c = quantity,
                Auto_Accept_Responses__c = autoAccept,
                End_Date__c = Date.today().addDays(7)
            );
            if (recordTypeId != null) {
                needOffer.RecordTypeId = recordTypeId;
            }
            insert needOffer;
        }
        return needOffer;
    }

    private static Needs_Offers__c createTestNeed(User owner, Integer quantity) {
        Needs_Offers__c need;
        System.runAs(owner) {
            Id recordTypeId;
            try {
                recordTypeId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();
            } catch (Exception e) {
                recordTypeId = null;
            }

            Contact ownerContact = [SELECT Id, AccountId FROM Contact WHERE Id = :[SELECT ContactId FROM User WHERE Id = :owner.Id].ContactId LIMIT 1];

            need = new Needs_Offers__c(
                Name = 'Test Need',
                Details__c = 'Need details',
                Status__c = 'Posted',
                Posted_By__c = ownerContact.Id,
                Contact__c = ownerContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = ownerContact.AccountId,
                Total_Quantity__c = quantity,
                Per_Response_Limit__c = quantity,
                Auto_Accept_Responses__c = false,
                End_Date__c = Date.today().addDays(7)
            );
            if (recordTypeId != null) {
                need.RecordTypeId = recordTypeId;
            }
            insert need;
        }
        return need;
    }

    @isTest
    static void testNeed_SecondResponseWhenAvailabilityZero() {
        User poster = getTestUser();
        Needs_Offers__c need = createTestNeed(poster, 1);

        User responder1 = poster;
        User responder2 = poster;

        Map<String, Object> firstResponse = new Map<String, Object>{
            'needOfferId' => need.Id,
            'subject' => 'First offer',
            'responseDetails' => 'First neighbour can help',
            'amountRequested' => 1,
            'decline' => false
        };

        Test.startTest();
        Map<String, Object> result1;
        System.runAs(responder1) {
            result1 = FimbyResponseController.createResponse(JSON.serialize(firstResponse));
        }
        System.assertEquals(true, result1.get('success'), 'First response should succeed');

        Map<String, Object> loadResult = FimbyResponseController.getNeedsOffersForResponse(need.Id);
        System.assertEquals(true, loadResult.get('success'), 'Need should still accept responses when availability is zero');

        Map<String, Object> secondResponse = new Map<String, Object>{
            'needOfferId' => need.Id,
            'subject' => 'Second offer',
            'responseDetails' => 'Another neighbour can help',
            'amountRequested' => 1,
            'decline' => false
        };
        Map<String, Object> result2;
        System.runAs(responder2) {
            result2 = FimbyResponseController.createResponse(JSON.serialize(secondResponse));
        }
        Test.stopTest();

        System.assertEquals(true, result2.get('success'), 'Second Need response should succeed even when Total_Available is 0');
        System.assertEquals(2, [SELECT COUNT() FROM Response__c WHERE Need_Offer_Responded_To__c = :need.Id]);
    }

    @isTest
    static void testGetNeedsOffersForResponse_Success() {
        User testUser = getTestUser();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        Test.startTest();
        Map<String, Object> result = FimbyResponseController.getNeedsOffersForResponse(testNeedOffer.Id);
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        Map<String, Object> needOffer = (Map<String, Object>) result.get('needOffer');
        System.assertEquals(testNeedOffer.Id, needOffer.get('id'), 'Should return correct Need/Offer Id');
    }

    @isTest
    static void testGetNeedsOffersForResponse_NoRecordId() {
        Test.startTest();
        Map<String, Object> result = FimbyResponseController.getNeedsOffersForResponse('');
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure');
        System.assertEquals('noRecordId', result.get('error'), 'Should have noRecordId error');
    }

    @isTest
    static void testGetNeedsOffersForResponse_NoneAvailable() {
        User testUser = getTestUser();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 0);

        Test.startTest();
        Map<String, Object> result = FimbyResponseController.getNeedsOffersForResponse(testNeedOffer.Id);
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure when none available');
        System.assertEquals('noneAvailable', result.get('error'), 'Should have noneAvailable error');
    }

    @isTest
    static void testCheckExistingResponse_NoExisting() {
        User testUser = getTestUser();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.checkExistingResponse(testNeedOffer.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(false, result.get('hasExistingResponse'), 'Should not have existing response');
    }

    @isTest
    static void testCheckExistingResponse_HasExisting() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        Response__c existingResponse = new Response__c(
            Name = 'Existing Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = testContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(testUser) {
            insert existingResponse;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.checkExistingResponse(testNeedOffer.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('hasExistingResponse'), 'Should have existing response');
    }

    @isTest
    static void testCreateResponse_Success() {
        User testUser = getTestUser();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        Map<String, Object> responseData = new Map<String, Object>{
            'needOfferId' => testNeedOffer.Id,
            'subject' => 'Test Response Subject',
            'responseDetails' => 'Test response details',
            'amountRequested' => 2,
            'decline' => false
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.createResponse(JSON.serialize(responseData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('responseId'), 'Should return responseId');
        System.assertEquals('New', result.get('status'), 'Status should be New');
    }

    @isTest
    static void testCreateResponse_AutoAccept() {
        User testUser = getTestUser();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, true, 5);

        Map<String, Object> responseData = new Map<String, Object>{
            'needOfferId' => testNeedOffer.Id,
            'subject' => 'Auto Accept Response',
            'responseDetails' => 'Should be auto accepted',
            'amountRequested' => 1,
            'decline' => false
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.createResponse(JSON.serialize(responseData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('Accepted', result.get('status'), 'Status should be Accepted');
    }

    @isTest
    static void testCreateResponse_Declined() {
        User testUser = getTestUser();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        Map<String, Object> responseData = new Map<String, Object>{
            'needOfferId' => testNeedOffer.Id,
            'subject' => 'Declining Response',
            'responseDetails' => 'Not interested',
            'amountRequested' => 0,
            'decline' => true
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.createResponse(JSON.serialize(responseData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('Declined', result.get('status'), 'Status should be Declined');
    }

    @isTest
    static void testCreateResponse_InactivePost() {
        User testUser = getTestUser();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        System.runAs(testUser) {
            testNeedOffer.Status__c = 'Cancelled';
            update testNeedOffer;
        }

        Map<String, Object> responseData = new Map<String, Object>{
            'needOfferId' => testNeedOffer.Id,
            'subject' => 'Late Response',
            'responseDetails' => 'Should be rejected',
            'amountRequested' => 1,
            'decline' => false
        };

        Test.startTest();
        Boolean exceptionThrown = false;
        String exceptionMessage = '';
        System.runAs(testUser) {
            try {
                FimbyResponseController.createResponse(JSON.serialize(responseData));
            } catch (AuraHandledException e) {
                exceptionThrown = true;
                exceptionMessage = e.getMessage();
            }
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Should throw AuraHandledException for inactive post');
        System.assert(exceptionMessage.contains('no longer accepting responses'),
            'Exception message should mention post is no longer accepting responses: ' + exceptionMessage);
    }

    @isTest
    static void testGetResponseForStatusUpdate_HasAccess() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        Response__c testResponse = new Response__c(
            Name = 'Test Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = testContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(testUser) {
            insert testResponse;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.getResponseForStatusUpdate(testResponse.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('hasAccess'), 'User should have access');
    }

    @isTest
    static void testGetResponseForStatusUpdate_PosterNotResponseOwner() {
        User posterUser = getTestUser();
        Contact posterContact = getTestContact();

        Contact responderContact = new Contact(
            FirstName = 'Status',
            LastName = 'Responder',
            AccountId = posterContact.AccountId,
            Email = 'status.responder@fimby.test.com'
        );
        insert responderContact;
        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Needs_Offers__c testNeedOffer = createTestNeedOffer(posterUser, false, 5);

        Response__c testResponse = new Response__c(
            Name = 'Responder Owned Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = responderContact.Id,
            On_Behalf_Of_Contact__c = responderContact.Id,
            Reply_To_Contact__c = posterContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(responderUser) {
            insert testResponse;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseController.getResponseForStatusUpdate(testResponse.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('hasAccess'), 'Poster should access responder-owned response');
    }

    @isTest
    static void testUpdateResponseStatus_PosterAcceptsResponderOwnedResponse() {
        User posterUser = getTestUser();
        Contact posterContact = getTestContact();

        Contact responderContact = new Contact(
            FirstName = 'Accept',
            LastName = 'Responder',
            AccountId = posterContact.AccountId,
            Email = 'accept.responder@fimby.test.com'
        );
        insert responderContact;
        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Needs_Offers__c testNeedOffer = createTestNeedOffer(posterUser, false, 5);

        Response__c testResponse = new Response__c(
            Name = 'Accept Test Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = responderContact.Id,
            On_Behalf_Of_Contact__c = responderContact.Id,
            Reply_To_Contact__c = posterContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(responderUser) {
            insert testResponse;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseController.updateResponseStatus(testResponse.Id, 'Accepted');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Poster should accept responder-owned response');
        System.assertEquals('Accepted', result.get('newStatus'), 'Status should be Accepted');

        Response__c updated = [SELECT Status__c FROM Response__c WHERE Id = :testResponse.Id];
        System.assertEquals('Accepted', updated.Status__c, 'Response row should persist Accepted status');
    }

    @isTest
    static void testUpdateResponseStatus_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        Response__c testResponse = new Response__c(
            Name = 'Test Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = testContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(testUser) {
            insert testResponse;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.updateResponseStatus(testResponse.Id, 'Accepted');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('Accepted', result.get('newStatus'), 'New status should be Accepted');
    }

    @isTest
    static void testUpdateResponseStatus_AutoShareContactInfo() {
        User posterUser = getTestUser();
        Contact posterContact = [SELECT Id, Email FROM Contact WHERE Id = :posterUser.ContactId];
        posterContact.Email = 'poster.autoshare.ctrl@fimby.test.com';
        update posterContact;

        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact responderContact = new Contact(
            FirstName = 'AutoShare',
            LastName = 'ResponderCtrl',
            AccountId = neighbourhood.Id,
            Email = 'autoshare.responder.ctrl@fimby.test.com'
        );
        insert responderContact;

        Needs_Offers__c testNeedOffer = createTestNeedOffer(posterUser, false, 5);
        testNeedOffer.Auto_Share_Contact_Info__c = true;
        update testNeedOffer;

        Response__c testResponse = new Response__c(
            Name = 'Auto Share Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = responderContact.Id,
            On_Behalf_Of_Contact__c = responderContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(posterUser) {
            insert testResponse;
        }

        Test.startTest();
        System.runAs(posterUser) {
            FimbyResponseController.updateResponseStatus(testResponse.Id, 'Accepted');
        }
        Test.stopTest();

        List<Shared_Contact_Info__c> shares = [
            SELECT Id, Contact__c, Shared_To__c, Response__c
            FROM Shared_Contact_Info__c
            WHERE Response__c = :testResponse.Id
        ];
        System.assertEquals(1, shares.size(), 'Status modal accept should auto-share contact info');
        System.assertEquals(posterContact.Id, shares[0].Contact__c);
        System.assertEquals(responderContact.Id, shares[0].Shared_To__c);
    }

    @isTest
    static void testCreateResponse_AutoAcceptAutoShareContactInfo() {
        User posterUser = getTestUser();
        Contact posterContact = [SELECT Id, Email FROM Contact WHERE Id = :posterUser.ContactId];
        posterContact.Email = 'poster.autoshare.create@fimby.test.com';
        update posterContact;

        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact responderContact = new Contact(
            FirstName = 'AutoShare',
            LastName = 'ResponderCreate',
            AccountId = neighbourhood.Id,
            Email = 'autoshare.responder.create@fimby.test.com'
        );
        insert responderContact;
        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Needs_Offers__c testNeedOffer = createTestNeedOffer(posterUser, true, 5);
        testNeedOffer.Auto_Share_Contact_Info__c = true;
        update testNeedOffer;

        Map<String, Object> responseData = new Map<String, Object>{
            'needOfferId' => testNeedOffer.Id,
            'subject' => 'Auto accept auto share',
            'responseDetails' => 'Testing auto share on auto accept',
            'amountRequested' => 1
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(responderUser) {
            result = FimbyResponseController.createResponse(JSON.serialize(responseData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals('Accepted', result.get('status'));
        Id responseId = (Id) result.get('responseId');

        List<Shared_Contact_Info__c> shares = [
            SELECT Id, Contact__c, Shared_To__c
            FROM Shared_Contact_Info__c
            WHERE Response__c = :responseId
        ];
        System.assertEquals(1, shares.size(), 'Auto-accept create should auto-share contact info');
        System.assertEquals(posterContact.Id, shares[0].Contact__c);
        System.assertEquals(responderContact.Id, shares[0].Shared_To__c);
    }

    @isTest
    static void testGetResponseForShareContactInfo_AsPoster() {
        User posterUser = getTestUser();
        Contact posterContact = getTestContact();
        
        // Create a second contact in the same household for responder
        Contact responderContact = new Contact(
            FirstName = 'Responder',
            LastName = 'Test',
            AccountId = posterContact.AccountId,
            Email = 'responder@fimby.test.com'
        );
        insert responderContact;
        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Needs_Offers__c testNeedOffer;
        System.runAs(posterUser) {
            testNeedOffer = new Needs_Offers__c(
                Name = 'Poster Need for Share',
                Details__c = 'Details',
                Full_Details__c = 'Full details',
                Status__c = 'Posted',
                Posted_By__c = posterContact.Id,
                Contact__c = posterContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = posterContact.AccountId,
                Total_Quantity__c = 5,
                Per_Response_Limit__c = 5,
                Auto_Accept_Responses__c = false,
                End_Date__c = Date.today().addDays(7)
            );
            insert testNeedOffer;
        }

        Response__c testResponse = new Response__c(
            Name = 'Test Share Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = responderContact.Id,
            On_Behalf_Of_Contact__c = responderContact.Id,
            Reply_To_Contact__c = posterContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        insert testResponse;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseController.getResponseForShareContactInfo(testResponse.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success: ' + result.get('message'));
        System.assertEquals(true, result.get('isPostedBy'), 'Should be posted by');
    }

    @isTest
    static void testGetResponseForShareContactInfo_AsResponderWithoutReplyTo() {
        User posterUser = getTestUser();
        Contact posterContact = getTestContact();

        Contact responderContact = new Contact(
            FirstName = 'ShareResponder',
            LastName = 'Test',
            AccountId = posterContact.AccountId,
            Email = 'shareresponder@fimby.test.com'
        );
        insert responderContact;
        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Needs_Offers__c testNeedOffer;
        System.runAs(posterUser) {
            testNeedOffer = new Needs_Offers__c(
                Name = 'Responder Share Need',
                Details__c = 'Details',
                Full_Details__c = 'Full details',
                Status__c = 'Posted',
                Posted_By__c = posterContact.Id,
                Contact__c = posterContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = posterContact.AccountId,
                Total_Quantity__c = 5,
                Per_Response_Limit__c = 5,
                Auto_Accept_Responses__c = false,
                End_Date__c = Date.today().addDays(7)
            );
            insert testNeedOffer;
        }

        Response__c testResponse = new Response__c(
            Name = 'Responder Share Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = responderContact.Id,
            On_Behalf_Of_Contact__c = responderContact.Id,
            Status__c = 'Accepted',
            Amount_Requested__c = 1
        );
        System.runAs(responderUser) {
            insert testResponse;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(responderUser) {
            result = FimbyResponseController.getResponseForShareContactInfo(testResponse.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Responder should load share data: ' + result.get('message'));
        System.assertEquals(false, result.get('isPostedBy'), 'Should not be poster');
        Map<String, Object> recipient = (Map<String, Object>) result.get('recipient');
        System.assertEquals(posterContact.Id, recipient.get('id'), 'Recipient should resolve to poster');
    }

    @isTest
    static void testShareContactInfo_Success() {
        User posterUser = getTestUser();
        Contact posterContact = getTestContact();
        
        // Create a second contact in the same household for responder
        Contact responderContact = new Contact(
            FirstName = 'Responder2',
            LastName = 'Test',
            AccountId = posterContact.AccountId,
            Email = 'responder2@fimby.test.com'
        );
        insert responderContact;
        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Needs_Offers__c testNeedOffer;
        System.runAs(posterUser) {
            testNeedOffer = new Needs_Offers__c(
                Name = 'Share Test Need',
                Details__c = 'Details',
                Full_Details__c = 'Full details',
                Status__c = 'Posted',
                Posted_By__c = posterContact.Id,
                Contact__c = posterContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = posterContact.AccountId,
                Total_Quantity__c = 5,
                Per_Response_Limit__c = 5,
                End_Date__c = Date.today().addDays(7)
            );
            insert testNeedOffer;
        }

        Response__c testResponse = new Response__c(
            Name = 'Share Test Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = responderContact.Id,
            Reply_To_Contact__c = posterContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        insert testResponse;

        Map<String, Object> shareData = new Map<String, Object>{
            'responseId' => testResponse.Id,
            'sharingContactId' => posterContact.Id,
            'recipientContactId' => responderContact.Id,
            'shareEmail' => true,
            'sharePhone' => true,
            'shareAddress' => false,
            'email' => 'poster@test.com',
            'phone' => '555-1234'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseController.shareContactInfo(JSON.serialize(shareData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('systemMessage'), 'Should return thread system message');
        Map<String, Object> systemMessage = (Map<String, Object>) result.get('systemMessage');
        System.assertEquals('Contact_Shared', systemMessage.get('systemMessageType'));
        Id sharedId = (Id) result.get('sharedContactInfoId');
        System.assertNotEquals(null, sharedId, 'Should return shared contact info ID');

        Shared_Contact_Info__c sci = [SELECT Id, Shared_To__c, Response__c, Origin__c FROM Shared_Contact_Info__c WHERE Id = :sharedId];
        System.assertEquals(responderContact.Id, sci.Shared_To__c, 'Shared_To__c should be recipient');
        System.assertEquals(testResponse.Id, sci.Response__c, 'Response__c should be set');
        System.assertEquals('Response', sci.Origin__c, 'Origin__c should be Response');
    }

    @isTest
    static void testShareContactInfo_EmailSentToUser() {
        User posterUser = getTestUser();
        Contact posterContact = getTestContact();

        Contact responderContact = new Contact(
            FirstName = 'EmailTest',
            LastName = 'Responder',
            AccountId = posterContact.AccountId,
            Email = 'emailtest@fimby.test.com'
        );
        insert responderContact;
        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Needs_Offers__c testNeedOffer;
        System.runAs(posterUser) {
            testNeedOffer = new Needs_Offers__c(
                Name = 'Email Share Test',
                Details__c = 'Details',
                Full_Details__c = 'Full details',
                Status__c = 'Posted',
                Posted_By__c = posterContact.Id,
                Contact__c = posterContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = posterContact.AccountId,
                Total_Quantity__c = 5,
                Per_Response_Limit__c = 5,
                End_Date__c = Date.today().addDays(7)
            );
            insert testNeedOffer;
        }

        Response__c testResponse = new Response__c(
            Name = 'Email Share Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = responderContact.Id,
            Reply_To_Contact__c = posterContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        insert testResponse;

        // Responder shares with poster — poster has a User, so email path is covered
        Map<String, Object> shareData = new Map<String, Object>{
            'responseId' => testResponse.Id,
            'sharingContactId' => responderContact.Id,
            'recipientContactId' => posterContact.Id,
            'shareEmail' => true,
            'sharePhone' => false,
            'shareAddress' => true,
            'email' => 'responder@test.com',
            'street' => '123 Main St',
            'city' => 'Vancouver',
            'state' => 'BC',
            'postalCode' => 'V6B 1A1',
            'country' => 'Canada'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(responderUser) {
            result = FimbyResponseController.shareContactInfo(JSON.serialize(shareData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testShareContactInfo_NoEmailOnReshare() {
        User posterUser = getTestUser();
        Contact posterContact = getTestContact();

        Contact responderContact = new Contact(
            FirstName = 'Reshare',
            LastName = 'Responder',
            AccountId = posterContact.AccountId,
            Email = 'reshare@fimby.test.com'
        );
        insert responderContact;
        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Needs_Offers__c testNeedOffer;
        System.runAs(posterUser) {
            testNeedOffer = new Needs_Offers__c(
                Name = 'Reshare Test Need',
                Details__c = 'Details',
                Full_Details__c = 'Full details',
                Status__c = 'Posted',
                Posted_By__c = posterContact.Id,
                Contact__c = posterContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = posterContact.AccountId,
                Total_Quantity__c = 5,
                Per_Response_Limit__c = 5,
                End_Date__c = Date.today().addDays(7)
            );
            insert testNeedOffer;
        }

        Response__c testResponse = new Response__c(
            Name = 'Reshare Test Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = responderContact.Id,
            Reply_To_Contact__c = posterContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        insert testResponse;

        insert new Shared_Contact_Info__c(
            Contact__c = responderContact.Id,
            Shared_To__c = posterContact.Id,
            Email__c = 'responder@test.com',
            Status__c = 'Active',
            Origin__c = 'Response'
        );

        FimbyTransactionalEmailService.oweaCached = null;
        FimbyTransactionalEmailService.testSendInvocationCount = 0;

        Map<String, Object> shareData = new Map<String, Object>{
            'responseId' => testResponse.Id,
            'sharingContactId' => responderContact.Id,
            'recipientContactId' => posterContact.Id,
            'shareEmail' => true,
            'sharePhone' => false,
            'shareAddress' => false,
            'email' => 'responder@test.com'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(responderUser) {
            result = FimbyResponseController.shareContactInfo(JSON.serialize(shareData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Re-share should succeed');
        System.assertEquals(0, FimbyTransactionalEmailService.testSendInvocationCount, 'Should not email when share content is unchanged');
    }

    @isTest
    static void testShareContactInfo_EmailOnExpandedReshare() {
        User posterUser = getTestUser();
        Contact posterContact = getTestContact();

        Contact responderContact = new Contact(
            FirstName = 'Expanded',
            LastName = 'Responder',
            AccountId = posterContact.AccountId,
            Email = 'expanded@fimby.test.com'
        );
        insert responderContact;
        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Needs_Offers__c testNeedOffer;
        System.runAs(posterUser) {
            testNeedOffer = new Needs_Offers__c(
                Name = 'Expanded Reshare Need',
                Details__c = 'Details',
                Full_Details__c = 'Full details',
                Status__c = 'Posted',
                Posted_By__c = posterContact.Id,
                Contact__c = posterContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = posterContact.AccountId,
                Total_Quantity__c = 5,
                Per_Response_Limit__c = 5,
                End_Date__c = Date.today().addDays(7)
            );
            insert testNeedOffer;
        }

        Response__c testResponse = new Response__c(
            Name = 'Expanded Reshare Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = responderContact.Id,
            Reply_To_Contact__c = posterContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        insert testResponse;

        insert new Shared_Contact_Info__c(
            Contact__c = responderContact.Id,
            Shared_To__c = posterContact.Id,
            Email__c = 'responder@test.com',
            Status__c = 'Active',
            Origin__c = 'Response'
        );

        FimbyTransactionalEmailService.oweaCached = null;
        FimbyTransactionalEmailService.testSendInvocationCount = 0;

        Map<String, Object> shareData = new Map<String, Object>{
            'responseId' => testResponse.Id,
            'sharingContactId' => responderContact.Id,
            'recipientContactId' => posterContact.Id,
            'shareEmail' => true,
            'sharePhone' => true,
            'shareAddress' => false,
            'email' => 'responder@test.com',
            'phone' => '555-7777'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(responderUser) {
            result = FimbyResponseController.shareContactInfo(JSON.serialize(shareData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Expanded re-share should succeed');
        System.assertEquals(1, FimbyTransactionalEmailService.testSendInvocationCount, 'Should email when newly sharing phone');
    }

    @isTest
    static void testGetResponseForReply_NotFound() {
        User testUser = getTestUser();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.getResponseForReply('a0z000000000000AAA');
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'), 'Should return failure for non-existent response');
        System.assertEquals('notFound', result.get('error'), 'Should have notFound error');
    }

    @isTest
    static void testGetResponseForReply_AsPoster() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        Response__c testResponse = new Response__c(
            Name = 'Test Reply Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = testContact.Id,
            On_Behalf_Of_Contact__c = testContact.Id,
            Reply_To_Contact__c = testContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(testUser) {
            insert testResponse;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.getResponseForReply(testResponse.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('isPoster'), 'User should be poster');
    }

    @isTest
    static void testGetResponseForReply_AsResponder() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        // Create response owned by the testUser (so they're the responder)
        Response__c testResponse = new Response__c(
            Name = 'Test Responder Reply',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = testContact.Id,
            On_Behalf_Of_Contact__c = testContact.Id,
            Reply_To_Contact__c = testContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(testUser) {
            insert testResponse;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.getResponseForReply(testResponse.Id);
        }
        Test.stopTest();

        // User is both poster (need/offer owner) and responder (response owner)
        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testSubmitResponseReply_Success() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        Response__c testResponse = new Response__c(
            Name = 'Test Submit Reply Response',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = testContact.Id,
            Reply_To_Contact__c = testContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(testUser) {
            insert testResponse;
        }

        Map<String, Object> replyData = new Map<String, Object>{
            'responseId' => testResponse.Id,
            'subject' => 'Test Reply Subject',
            'message' => 'Test reply message',
            'newStatus' => 'Accepted',
            'shareContactInfo' => false
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.submitResponseReply(JSON.serialize(replyData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
    }

    @isTest
    static void testUpdateResponseStatus_AllStatuses() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Needs_Offers__c testNeedOffer = createTestNeedOffer(testUser, false, 5);

        Response__c testResponse = new Response__c(
            Name = 'Test All Statuses',
            Need_Offer_Responded_To__c = testNeedOffer.Id,
            Contact__c = testContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 1
        );
        System.runAs(testUser) {
            insert testResponse;
        }

        Test.startTest();
        Map<String, Object> result1;
        System.runAs(testUser) {
            result1 = FimbyResponseController.updateResponseStatus(testResponse.Id, 'Accepted');
        }
        System.assertEquals(true, result1.get('success'), 'Should accept');
        System.assertEquals('Accepted', result1.get('newStatus'), 'Status should be Accepted');

        Map<String, Object> result2;
        System.runAs(testUser) {
            result2 = FimbyResponseController.updateResponseStatus(testResponse.Id, 'Declined');
        }
        System.assertEquals(true, result2.get('success'), 'Should decline');
        Test.stopTest();
    }

    // ============================================
    // Quick Event Response Tests
    // ============================================

    private static Needs_Offers__c createTestEvent(User owner, String eventType) {
        Needs_Offers__c evt;
        System.runAs(owner) {
            Id recordTypeId;
            try {
                recordTypeId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();
            } catch (Exception e) {
                recordTypeId = null;
            }
            Contact ownerContact = [SELECT Id, AccountId FROM Contact WHERE Id = :[SELECT ContactId FROM User WHERE Id = :owner.Id].ContactId LIMIT 1];
            evt = new Needs_Offers__c(
                Name = 'Test Event',
                Details__c = 'Event details',
                Status__c = 'Posted',
                Type__c = 'Event',
                Event_Type__c = eventType,
                Posted_By__c = ownerContact.Id,
                Contact__c = ownerContact.Id,
                Giver_Recipient_Type__c = 'Self',
                Neighbourhood__c = ownerContact.AccountId,
                Total_Quantity__c = 20,
                Per_Response_Limit__c = 5,
                Auto_Accept_Responses__c = true,
                End_Date__c = Date.today().addDays(14)
            );
            if (recordTypeId != null) evt.RecordTypeId = recordTypeId;
            insert evt;
        }
        return evt;
    }

    @isTest
    static void testQuickEventResponse_RespondIdempotent() {
        User testUser = getTestUser();
        Needs_Offers__c evt = createTestEvent(testUser, 'Open_Event');

        Test.startTest();
        Map<String, Object> result1;
        Map<String, Object> result2;
        System.runAs(testUser) {
            result1 = FimbyResponseController.quickEventResponse(evt.Id, 'respond', 1);
            result2 = FimbyResponseController.quickEventResponse(evt.Id, 'respond', 1);
        }
        Test.stopTest();

        System.assertEquals(true, result1.get('success'));
        System.assertEquals(false, result1.get('alreadyResponded'), 'First call creates new response');
        System.assertEquals('Accepted', result1.get('status'));
        System.assertEquals(true, result2.get('success'));
        System.assertEquals(true, result2.get('alreadyResponded'), 'Second call is idempotent');
        System.assertEquals(result1.get('responseId'), result2.get('responseId'), 'Same response returned');
    }

    @isTest
    static void testQuickEventResponse_WithdrawAndRejoin() {
        User testUser = getTestUser();
        Needs_Offers__c evt = createTestEvent(testUser, 'Open_Event');

        Test.startTest();
        Map<String, Object> respondResult;
        Map<String, Object> withdrawResult;
        Map<String, Object> rejoinResult;
        System.runAs(testUser) {
            respondResult = FimbyResponseController.quickEventResponse(evt.Id, 'respond', 1);
            withdrawResult = FimbyResponseController.quickEventResponse(evt.Id, 'withdraw', null);
            rejoinResult = FimbyResponseController.quickEventResponse(evt.Id, 'respond', 2);
        }
        Test.stopTest();

        System.assertEquals('Accepted', respondResult.get('status'));
        System.assertEquals('Cancelled', withdrawResult.get('status'));
        System.assertEquals(false, withdrawResult.get('alreadyWithdrawn'));
        System.assertEquals('Accepted', rejoinResult.get('status'));
        System.assertEquals(false, rejoinResult.get('alreadyResponded'), 'Rejoin creates new response');
        System.assertNotEquals(respondResult.get('responseId'), rejoinResult.get('responseId'), 'New response created on rejoin');
    }

    @isTest
    static void testQuickEventResponse_UpdateGuests() {
        User testUser = getTestUser();
        Needs_Offers__c evt = createTestEvent(testUser, 'Open_Event');

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            FimbyResponseController.quickEventResponse(evt.Id, 'respond', 1);
            result = FimbyResponseController.quickEventResponse(evt.Id, 'updateGuests', 4);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(4, (Integer) result.get('guestCount'));
    }

    @isTest
    static void testQuickEventResponse_WithdrawIdempotent() {
        User testUser = getTestUser();
        Needs_Offers__c evt = createTestEvent(testUser, 'Community_Event');

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.quickEventResponse(evt.Id, 'withdraw', null);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals(true, result.get('alreadyWithdrawn'));
    }

    @isTest
    static void testQuickEventResponse_CommunityEventInterested() {
        User testUser = getTestUser();
        Needs_Offers__c evt = createTestEvent(testUser, 'Community_Event');

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyResponseController.quickEventResponse(evt.Id, 'respond', 1);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals('Accepted', result.get('status'));
    }

    @isTest
    static void testQuickEventResponse_InactivePost() {
        User testUser = getTestUser();
        Needs_Offers__c evt = createTestEvent(testUser, 'Open_Event');
        System.runAs(testUser) {
            evt.Status__c = 'Cancelled';
            update evt;
        }

        Test.startTest();
        Boolean gotError = false;
        System.runAs(testUser) {
            try {
                FimbyResponseController.quickEventResponse(evt.Id, 'respond', 1);
            } catch (AuraHandledException e) {
                gotError = true;
            }
        }
        Test.stopTest();
        System.assert(gotError, 'Should throw for inactive post');
    }

    @isTest
    static void testQuickEventResponse_MissingParams() {
        Test.startTest();
        Boolean gotError = false;
        User testUser = getTestUser();
        System.runAs(testUser) {
            try {
                FimbyResponseController.quickEventResponse(null, 'respond', 1);
            } catch (AuraHandledException e) {
                gotError = true;
            }
        }
        Test.stopTest();
        System.assert(gotError, 'Should throw for missing params');
    }

    @isTest
    static void testGetOrCreateEventConversation_IntentGated() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Account neighbourhood = [SELECT Id FROM Account WHERE Id = :testContact.AccountId LIMIT 1];
        Contact posterContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User posterUser = FimbyTestDataFactory.createCommunityUser(posterContact.Id, null, true);
        Needs_Offers__c evt = createTestEvent(posterUser, 'Open_Event');

        Test.startTest();
        Boolean gotError = false;
        System.runAs(testUser) {
            try {
                FimbyResponseController.getOrCreateEventConversation(evt.Id, null);
            } catch (AuraHandledException e) {
                gotError = true;
            }
        }
        Test.stopTest();
        System.assert(gotError, 'Should throw when no active response exists');
    }

    @isTest
    static void testGetOrCreateEventConversation_AfterResponse() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Account neighbourhood = [SELECT Id FROM Account WHERE Id = :testContact.AccountId LIMIT 1];
        Contact posterContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User posterUser = FimbyTestDataFactory.createCommunityUser(posterContact.Id, null, true);
        Needs_Offers__c evt = createTestEvent(posterUser, 'Open_Event');

        Test.startTest();
        System.runAs(testUser) {
            FimbyResponseController.quickEventResponse(evt.Id, 'respond', 1);
        }
        Map<String, Object> convResult;
        Map<String, Object> convResult2;
        System.runAs(testUser) {
            convResult = FimbyResponseController.getOrCreateEventConversation(evt.Id, null);
            convResult2 = FimbyResponseController.getOrCreateEventConversation(evt.Id, null);
        }
        Test.stopTest();

        System.assertEquals(true, convResult.get('success'));
        System.assertEquals(true, convResult.get('isNew'));
        System.assertEquals(true, convResult2.get('success'));
        System.assertEquals(false, convResult2.get('isNew'), 'Second call should find existing conversation');
        System.assertEquals(convResult.get('conversationId'), convResult2.get('conversationId'));
    }

    @isTest
    static void testGetOrCreateEventConversation_PosterInitiated() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Account neighbourhood = [SELECT Id FROM Account WHERE Id = :testContact.AccountId LIMIT 1];
        Contact posterContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User posterUser = FimbyTestDataFactory.createCommunityUser(posterContact.Id, null, true);
        Needs_Offers__c evt = createTestEvent(posterUser, 'Open_Event');

        System.runAs(testUser) {
            FimbyResponseController.quickEventResponse(evt.Id, 'respond', 1);
        }
        FimbyIdentityRepository.clearCache();

        Test.startTest();
        Map<String, Object> convResult;
        System.runAs(posterUser) {
            convResult = FimbyResponseController.getOrCreateEventConversation(evt.Id, testContact.Id);
        }
        Test.stopTest();

        System.assertEquals(true, convResult.get('success'));
        System.assertEquals(true, convResult.get('isNew'));
        System.assertNotEquals(null, convResult.get('conversationId'));
    }

    @isTest
    static void testQuickEventResponse_WithdrawNotification_SkipsPush() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Account neighbourhood = [SELECT Id FROM Account WHERE Id = :testContact.AccountId LIMIT 1];
        Contact posterContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User posterUser = FimbyTestDataFactory.createCommunityUser(posterContact.Id, null, true);
        Needs_Offers__c evt = createTestEvent(posterUser, 'Open_Event');

        System.runAs(testUser) {
            FimbyResponseController.quickEventResponse(evt.Id, 'respond', 1);
        }

        List<Notification__c> respondNotifs = [
            SELECT Id FROM Notification__c
            WHERE Contact__c = :posterContact.Id AND Type__c = :FimbyConstants.NOTIF_RESPONSE
        ];
        for (Notification__c n : respondNotifs) {
            n.Read_Date__c = Datetime.now();
        }
        if (!respondNotifs.isEmpty()) {
            update respondNotifs;
        }

        Test.startTest();
        System.runAs(testUser) {
            FimbyResponseController.quickEventResponse(evt.Id, 'withdraw', null);
        }
        Test.stopTest();

        List<Notification__c> withdrawNotifs = [
            SELECT Push_Status__c, Title__c, Type__c
            FROM Notification__c
            WHERE Contact__c = :posterContact.Id
            AND Type__c = :FimbyConstants.NOTIF_RESPONSE
            AND Read_Date__c = null
        ];
        System.assert(!withdrawNotifs.isEmpty(), 'Withdraw notification should exist');
        System.assertEquals(null, withdrawNotifs[0].Push_Status__c,
            'Withdraw notification should have null Push_Status (in-app only)');
    }

    @isTest
    static void testGetOrCreateEventConversation_PosterTargetNoResponse() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();
        Account neighbourhood = [SELECT Id FROM Account WHERE Id = :testContact.AccountId LIMIT 1];
        Contact posterContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User posterUser = FimbyTestDataFactory.createCommunityUser(posterContact.Id, null, true);
        Needs_Offers__c evt = createTestEvent(posterUser, 'Open_Event');

        Test.startTest();
        Boolean gotError = false;
        System.runAs(posterUser) {
            try {
                FimbyResponseController.getOrCreateEventConversation(evt.Id, testContact.Id);
            } catch (AuraHandledException e) {
                gotError = true;
            }
        }
        Test.stopTest();
        System.assert(gotError, 'Should throw when target has no active response');
    }
}