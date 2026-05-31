@isTest
public class FimbyResponseThreadControllerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact posterContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User posterUser = FimbyTestDataFactory.createCommunityUser(posterContact.Id, null, true);

        Contact responderContact = new Contact(
            FirstName = 'Responder',
            LastName = 'ThreadTest',
            AccountId = neighbourhood.Id,
            Email = 'responder.threadtest@fimby.test.com'
        );
        insert responderContact;
    }

    private static User getPosterUser() {
        return [SELECT Id, ContactId FROM User WHERE Email LIKE '%@testorg.com' AND IsActive = true LIMIT 1];
    }

    private static Contact getPosterContact() {
        return [SELECT Id, AccountId, Logged_In_As_Contact__c FROM Contact WHERE Email LIKE '%@fimby.test.com' AND LastName != 'ThreadTest' LIMIT 1];
    }

    private static Contact getResponderContact() {
        return [SELECT Id, AccountId, Logged_In_As_Contact__c FROM Contact WHERE LastName = 'ThreadTest' LIMIT 1];
    }

    private static Needs_Offers__c createTestPost(User owner, Integer quantity) {
        Needs_Offers__c post;
        System.runAs(owner) {
            Contact ownerContact = [SELECT Id, AccountId FROM Contact WHERE Id = :[SELECT ContactId FROM User WHERE Id = :owner.Id].ContactId LIMIT 1];

            Id recordTypeId;
            try {
                recordTypeId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Offer').getRecordTypeId();
            } catch (Exception e) {
                recordTypeId = null;
            }

            post = new Needs_Offers__c(
                Name = 'Thread Test Post',
                Details__c = 'Test details for thread',
                Full_Details__c = 'Full test details for thread',
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
            if (recordTypeId != null) post.RecordTypeId = recordTypeId;
            insert post;
        }
        return post;
    }

    private static Response__c createTestResponse(Needs_Offers__c post, Contact responder, Contact poster, User runAs) {
        Response__c resp = new Response__c(
            Name = 'Thread Test Response',
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = responder.Id,
            On_Behalf_Of_Contact__c = responder.Id,
            Reply_To_Contact__c = poster.Id,
            Status__c = 'New',
            Amount_Requested__c = 2
        );
        System.runAs(runAs) {
            insert resp;
        }
        return resp;
    }

    @isTest
    static void testGetThread_Success() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.getThread(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('isPoster'), 'Should be poster');
        System.assertNotEquals(null, result.get('response'), 'Should have response data');
        System.assertNotEquals(null, result.get('post'), 'Should have post data');
        System.assertEquals(false, result.get('contactShared'), 'Should be false when no Shared_Contact_Info__c exists');
    }

    @isTest
    static void testGetThread_ContactSharedTrue() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        Shared_Contact_Info__c sci = new Shared_Contact_Info__c(
            Contact__c = posterContact.Id,
            Shared_To__c = responderContact.Id,
            Email__c = 'poster@test.com',
            Origin__c = 'Response'
        );
        insert sci;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.getThread(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('contactShared'), 'Should be true when Shared_Contact_Info__c exists');
    }

    @isTest
    static void testGetThread_NotFound() {
        User posterUser = getPosterUser();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.getThread('a0z000000000000AAA');
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals('notFound', result.get('error'));
    }

    @isTest
    static void testGetThread_NoRecordId() {
        User posterUser = getPosterUser();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.getThread('');
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals('noRecordId', result.get('error'));
    }

    @isTest
    static void testGetMessages() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.getMessages(resp.Id, 20, 0);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertNotEquals(null, result.get('messages'));
    }

    @isTest
    static void testSendMessage_Success() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.sendMessage(resp.Id, 'Hello from poster');
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertNotEquals(null, result.get('messageId'));

        List<Response_Message__c> msgs = [SELECT Id, Body__c FROM Response_Message__c WHERE Response__c = :resp.Id];
        System.assertEquals(1, msgs.size(), 'Should have 1 message');
        System.assertEquals('Hello from poster', msgs[0].Body__c);
    }

    @isTest
    static void testSendMessage_EmptyBody() {
        User posterUser = getPosterUser();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.sendMessage('someId', '');
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals('invalidInput', result.get('error'));
    }

    @isTest
    static void testUpdateResponseAmount() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 10);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(responderUser) {
            result = FimbyResponseThreadController.updateResponseAmount(resp.Id, 3);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed: ' + result);
        System.assertEquals(3, ((Decimal) result.get('newAmount')).intValue());

        Response__c updated = [SELECT Amount_Requested__c FROM Response__c WHERE Id = :resp.Id];
        System.assertEquals(3, updated.Amount_Requested__c);
    }

    @isTest
    static void testUpdateResponseAmount_NotResponder() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 10);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.updateResponseAmount(resp.Id, 3);
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals('notAuthorized', result.get('error'));
    }

    @isTest
    static void testAcceptResponse() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.acceptResponse(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals('Accepted', result.get('newStatus'));

        Response__c updated = [SELECT Status__c FROM Response__c WHERE Id = :resp.Id];
        System.assertEquals('Accepted', updated.Status__c);

        List<Response_Message__c> sysMsgs = [
            SELECT Body__c, Is_System_Message__c
            FROM Response_Message__c
            WHERE Response__c = :resp.Id AND Is_System_Message__c = true
        ];
        System.assertEquals(1, sysMsgs.size(), 'Should have system message');
    }

    @isTest
    static void testAcceptResponse_AutoShareContactInfo() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        post.Auto_Share_Contact_Info__c = true;
        update post;

        posterContact.Email = 'poster.autoshare@fimby.test.com';
        update posterContact;

        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.acceptResponse(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        List<Shared_Contact_Info__c> shares = [
            SELECT Id, Contact__c, Shared_To__c, Response__c, Email__c
            FROM Shared_Contact_Info__c
            WHERE Response__c = :resp.Id
        ];
        System.assertEquals(1, shares.size(), 'Accept should create Shared_Contact_Info__c when auto-share is on');
        System.assertEquals(posterContact.Id, shares[0].Contact__c);
        System.assertEquals(responderContact.Id, shares[0].Shared_To__c);
    }

    @isTest
    static void testDeclineResponse() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.declineResponse(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals('Declined', result.get('newStatus'));
    }

    @isTest
    static void testCancelResponse() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        User responderUser = FimbyTestDataFactory.createCommunityUser(responderContact.Id, null, true);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(responderUser) {
            result = FimbyResponseThreadController.cancelResponse(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals('Cancelled', result.get('newStatus'));
    }

    @isTest
    static void testCompleteResponse() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        resp.Status__c = 'Accepted';
        update resp;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.completeResponse(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));
        System.assertEquals('Completed', result.get('newStatus'));
    }

    @isTest
    static void testInvalidStatusTransition() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        resp.Status__c = 'Declined';
        update resp;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.acceptResponse(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(false, result.get('success'));
        System.assertEquals('invalidTransition', result.get('error'));
    }

    @isTest
    static void testStatusChangeAction_Expired() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        Test.startTest();
        FimbyResponseStatusChangeAction.StatusChangeInput input = new FimbyResponseStatusChangeAction.StatusChangeInput();
        input.responseId = resp.Id;
        input.newStatus = 'Expired';
        FimbyResponseStatusChangeAction.createStatusSystemMessages(new List<FimbyResponseStatusChangeAction.StatusChangeInput>{ input });
        Test.stopTest();

        List<Response_Message__c> msgs = [SELECT Body__c, Is_System_Message__c, System_Message_Type__c FROM Response_Message__c WHERE Response__c = :resp.Id];
        System.assertEquals(1, msgs.size(), 'Should have 1 system message');
        System.assertEquals(true, msgs[0].Is_System_Message__c);
        System.assertEquals('Post_Expired', msgs[0].System_Message_Type__c);
    }

    @isTest
    static void testGetShareContactInfoData() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Needs_Offers__c post = createTestPost(posterUser, 5);
        Response__c resp = createTestResponse(post, responderContact, posterContact, posterUser);

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.getShareContactInfoData(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success: ' + result.get('message'));
    }

    @isTest
    static void testGetThread_OrgPosterFields() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Account neighbourhood = [SELECT Id FROM Account WHERE Id = :posterContact.AccountId];

        Account orgAccount = new Account(Name = 'Garden Club', Logo_URL__c = 'https://example.com/garden.jpg');
        try {
            orgAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();
        } catch (Exception e) { /* RT may not exist */ }
        insert orgAccount;

        Contact orgContact = new Contact(
            FirstName = 'OrgPoster', LastName = 'GardenClub',
            AccountId = neighbourhood.Id,
            Is_Organization_Contact__c = true,
            Organization_Account__c = orgAccount.Id
        );
        insert orgContact;

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Org Thread Post',
            Details__c = 'Posted by org contact',
            Full_Details__c = 'Full org post details',
            Status__c = 'Posted',
            Posted_By__c = orgContact.Id,
            Contact__c = orgContact.Id,
            Giver_Recipient_Type__c = 'Self',
            Neighbourhood__c = neighbourhood.Id,
            Total_Quantity__c = 5,
            Per_Response_Limit__c = 5,
            Auto_Accept_Responses__c = false,
            End_Date__c = Date.today().addDays(7)
        );
        insert post;

        Response__c resp = new Response__c(
            Name = 'Response to org post',
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = posterContact.Id,
            On_Behalf_Of_Contact__c = posterContact.Id,
            Reply_To_Contact__c = orgContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 2
        );
        System.runAs(posterUser) {
            insert resp;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.getThread(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('isResponder'), 'User should be responder');

        Map<String, Object> postData = (Map<String, Object>) result.get('post');
        System.assertEquals(true, postData.get('postedByIsOrg'), 'Poster should be org contact');
        System.assertEquals('Garden Club', postData.get('postedByName'), 'Poster name should be org account name');
        System.assertEquals('https://example.com/garden.jpg', postData.get('postedByImageUrl'),
            'Poster image should be org logo');
    }

    @isTest
    static void testGetThread_OrgResponderFields() {
        User posterUser = getPosterUser();
        Contact posterContact = getPosterContact();
        Contact responderContact = getResponderContact();
        Account neighbourhood = [SELECT Id FROM Account WHERE Id = :posterContact.AccountId];

        Account orgAccount = new Account(Name = 'Helper Org', Logo_URL__c = 'https://example.com/helper.jpg');
        try {
            orgAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();
        } catch (Exception e) { /* RT may not exist */ }
        insert orgAccount;

        Contact orgContact = new Contact(
            FirstName = 'OrgResp', LastName = 'HelperOrg',
            AccountId = neighbourhood.Id,
            Is_Organization_Contact__c = true,
            Organization_Account__c = orgAccount.Id
        );
        insert orgContact;

        Needs_Offers__c post = createTestPost(posterUser, 5);

        Response__c resp = new Response__c(
            Name = 'Org Response',
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = orgContact.Id,
            On_Behalf_Of_Contact__c = orgContact.Id,
            Reply_To_Contact__c = posterContact.Id,
            Status__c = 'New',
            Amount_Requested__c = 2
        );
        System.runAs(posterUser) {
            insert resp;
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(posterUser) {
            result = FimbyResponseThreadController.getThread(resp.Id);
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('isPoster'), 'User should be poster');

        Map<String, Object> responseData = (Map<String, Object>) result.get('response');
        System.assertEquals(true, responseData.get('responderIsOrg'), 'Responder should be org contact');
        System.assertEquals('Helper Org', responseData.get('responderName'),
            'Responder name should be org account name');
        System.assertEquals('https://example.com/helper.jpg', responseData.get('responderImageUrl'),
            'Responder image should be org logo');
    }
}
