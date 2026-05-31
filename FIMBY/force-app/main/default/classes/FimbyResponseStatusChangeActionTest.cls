@isTest
public class FimbyResponseStatusChangeActionTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User testUser = FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);
    }

    private static User getTestUser() {
        return [SELECT Id, ContactId FROM User WHERE Email LIKE '%@testorg.com' AND IsActive = true LIMIT 1];
    }

    private static Needs_Offers__c createTestPost(Id contactId, Id neighbourhoodId) {
        Id recordTypeId;
        try {
            recordTypeId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Need').getRecordTypeId();
        } catch (Exception e) {
            recordTypeId = null;
        }
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Test Post',
            Details__c = 'Details',
            Full_Details__c = 'Full details',
            Status__c = 'Posted',
            Posted_By__c = contactId,
            Contact__c = contactId,
            Giver_Recipient_Type__c = 'Self',
            Neighbourhood__c = neighbourhoodId,
            End_Date__c = Date.today().addDays(7)
        );
        if (recordTypeId != null) {
            post.RecordTypeId = recordTypeId;
        }
        insert post;
        return post;
    }

    private static Response__c createTestResponse(Id contactId, Id postId) {
        Response__c resp = new Response__c(
            Name = 'Test Response',
            Contact__c = contactId,
            On_Behalf_Of_Contact__c = contactId,
            Need_Offer_Responded_To__c = postId,
            Status__c = 'New',
            Response__c = 'I can help',
            Responder_Unread_Count__c = 0,
            Poster_Unread_Count__c = 0
        );
        insert resp;
        return resp;
    }

    @isTest
    static void testExpiredStatus() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Contact c = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId];
            Needs_Offers__c post = createTestPost(c.Id, c.AccountId);
            Response__c resp = createTestResponse(c.Id, post.Id);

            FimbyResponseStatusChangeAction.StatusChangeInput input = new FimbyResponseStatusChangeAction.StatusChangeInput();
            input.responseId = resp.Id;
            input.newStatus = 'Expired';

            Test.startTest();
            FimbyResponseStatusChangeAction.createStatusSystemMessages(new List<FimbyResponseStatusChangeAction.StatusChangeInput>{ input });
            Test.stopTest();

            List<Response_Message__c> msgs = [
                SELECT Id, Body__c, Is_System_Message__c, System_Message_Type__c, Response__c
                FROM Response_Message__c
                WHERE Response__c = :resp.Id
            ];
            System.assertEquals(1, msgs.size(), 'Should create one system message');
            System.assertEquals('This post has expired', msgs[0].Body__c);
            System.assert(msgs[0].Is_System_Message__c, 'Should be a system message');
            System.assertEquals('Post_Expired', msgs[0].System_Message_Type__c);

            Response__c updated = [SELECT Responder_Unread_Count__c FROM Response__c WHERE Id = :resp.Id];
            System.assertEquals(1, updated.Responder_Unread_Count__c, 'Should increment unread count');
        }
    }

    @isTest
    static void testCancelledStatus() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Contact c = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId];
            Needs_Offers__c post = createTestPost(c.Id, c.AccountId);
            Response__c resp = createTestResponse(c.Id, post.Id);

            FimbyResponseStatusChangeAction.StatusChangeInput input = new FimbyResponseStatusChangeAction.StatusChangeInput();
            input.responseId = resp.Id;
            input.newStatus = 'Cancelled';

            Test.startTest();
            FimbyResponseStatusChangeAction.createStatusSystemMessages(new List<FimbyResponseStatusChangeAction.StatusChangeInput>{ input });
            Test.stopTest();

            List<Response_Message__c> msgs = [
                SELECT Id, Body__c, System_Message_Type__c
                FROM Response_Message__c
                WHERE Response__c = :resp.Id
            ];
            System.assertEquals(1, msgs.size(), 'Should create one system message');
            System.assertEquals('This post was removed by the author', msgs[0].Body__c);
            System.assertEquals('Post_Cancelled', msgs[0].System_Message_Type__c);
        }
    }

    @isTest
    static void testOtherStatus() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Contact c = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId];
            Needs_Offers__c post = createTestPost(c.Id, c.AccountId);
            Response__c resp = createTestResponse(c.Id, post.Id);

            FimbyResponseStatusChangeAction.StatusChangeInput input = new FimbyResponseStatusChangeAction.StatusChangeInput();
            input.responseId = resp.Id;
            input.newStatus = 'Completed';

            Test.startTest();
            FimbyResponseStatusChangeAction.createStatusSystemMessages(new List<FimbyResponseStatusChangeAction.StatusChangeInput>{ input });
            Test.stopTest();

            List<Response_Message__c> msgs = [
                SELECT Id, Body__c, System_Message_Type__c
                FROM Response_Message__c
                WHERE Response__c = :resp.Id
            ];
            System.assertEquals(1, msgs.size(), 'Should create one system message');
            System.assertEquals('Status changed to Completed', msgs[0].Body__c);
            System.assertEquals('Status_Change', msgs[0].System_Message_Type__c);
        }
    }

    @isTest
    static void testBulkInputs() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Contact c = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId];
            Needs_Offers__c post = createTestPost(c.Id, c.AccountId);

            List<FimbyResponseStatusChangeAction.StatusChangeInput> inputs = new List<FimbyResponseStatusChangeAction.StatusChangeInput>();
            List<Response__c> responses = new List<Response__c>();
            for (Integer i = 0; i < 5; i++) {
                responses.add(new Response__c(
                    Name = 'Bulk Response ' + i,
                    Contact__c = c.Id,
                    On_Behalf_Of_Contact__c = c.Id,
                    Need_Offer_Responded_To__c = post.Id,
                    Status__c = 'New',
                    Response__c = 'Bulk help ' + i,
                    Responder_Unread_Count__c = 0,
                    Poster_Unread_Count__c = 0
                ));
            }
            insert responses;

            for (Response__c r : responses) {
                FimbyResponseStatusChangeAction.StatusChangeInput input = new FimbyResponseStatusChangeAction.StatusChangeInput();
                input.responseId = r.Id;
                input.newStatus = 'Expired';
                inputs.add(input);
            }

            Test.startTest();
            FimbyResponseStatusChangeAction.createStatusSystemMessages(inputs);
            Test.stopTest();

            List<Response_Message__c> msgs = [
                SELECT Id FROM Response_Message__c
                WHERE Response__c IN :responses
            ];
            System.assertEquals(5, msgs.size(), 'Should create a system message per response');
        }
    }

    @isTest
    static void testInvalidResponseId() {
        FimbyResponseStatusChangeAction.StatusChangeInput input = new FimbyResponseStatusChangeAction.StatusChangeInput();
        input.responseId = 'a00000000000000AAA';
        input.newStatus = 'Expired';

        Test.startTest();
        FimbyResponseStatusChangeAction.createStatusSystemMessages(
            new List<FimbyResponseStatusChangeAction.StatusChangeInput>{ input }
        );
        Test.stopTest();

        List<Response_Message__c> msgs = [SELECT Id FROM Response_Message__c];
        System.assertEquals(0, msgs.size(), 'Should not create messages for invalid response');
    }

    @isTest
    static void testEmptyInput() {
        Test.startTest();
        FimbyResponseStatusChangeAction.createStatusSystemMessages(
            new List<FimbyResponseStatusChangeAction.StatusChangeInput>()
        );
        Test.stopTest();

        List<Response_Message__c> msgs = [SELECT Id FROM Response_Message__c];
        System.assertEquals(0, msgs.size(), 'No messages for empty input');
    }

    @isTest
    static void testNullUnreadCount() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            Contact c = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId];
            Needs_Offers__c post = createTestPost(c.Id, c.AccountId);

            Response__c resp = new Response__c(
                Name = 'Null Count Response',
                Contact__c = c.Id,
                On_Behalf_Of_Contact__c = c.Id,
                Need_Offer_Responded_To__c = post.Id,
                Status__c = 'New',
                Response__c = 'Help'
            );
            insert resp;

            FimbyResponseStatusChangeAction.StatusChangeInput input = new FimbyResponseStatusChangeAction.StatusChangeInput();
            input.responseId = resp.Id;
            input.newStatus = 'Expired';

            Test.startTest();
            FimbyResponseStatusChangeAction.createStatusSystemMessages(
                new List<FimbyResponseStatusChangeAction.StatusChangeInput>{ input }
            );
            Test.stopTest();

            Response__c updated = [SELECT Responder_Unread_Count__c FROM Response__c WHERE Id = :resp.Id];
            System.assertEquals(1, updated.Responder_Unread_Count__c, 'Should handle null unread count gracefully');
        }
    }
}
