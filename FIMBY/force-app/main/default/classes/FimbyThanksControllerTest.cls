/**
 * Test class for FimbyThanksController
 */
@isTest
private class FimbyThanksControllerTest {

    @TestSetup
    static void setupTestData() {
        FimbyTestDataFactory.FimbyTestDataSetup setup = FimbyTestDataFactory.createCompleteTestSetup();

        Contact extraContact = FimbyTestDataFactory.createNeighbourhoodContact(setup.neighbourhood.Id, true);

        Needs_Offers__c needOffer = FimbyTestDataFactory.createAskOfferItems(
            setup.neighbourhood.Id, extraContact.Id, 1, true
        )[0];

        Response__c response = new Response__c(
            Name = 'Test Response',
            Contact__c = setup.contact.Id,
            Need_Offer_Responded_To__c = needOffer.Id,
            Neighbourhood__c = setup.neighbourhood.Id
        );
        insert response;
    }

    @isTest
    static void testSendThanks_Success() {
        User communityUser = [
            SELECT Id, ContactId FROM User
            WHERE Profile.Name = 'Customer Community User' AND IsActive = true LIMIT 1
        ];
        Contact recipient = [SELECT Id, Name FROM Contact WHERE Id = :communityUser.ContactId LIMIT 1];
        Response__c response = [SELECT Id FROM Response__c LIMIT 1];

        Map<String, Object> thanksData = new Map<String, Object>{
            'recipientId' => recipient.Id,
            'message' => 'Thank you so much for your help!',
            'relatedRecordId' => response.Id
        };

        Test.startTest();
        Map<String, Object> result = FimbyThanksController.sendThanks(JSON.serialize(thanksData));
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('posterToResponder', result.get('direction'), 'Direction should be posterToResponder');

        List<FeedItem> feeds = [SELECT Id FROM FeedItem WHERE ParentId = :recipient.Id];
        System.assertEquals(0, feeds.size(), 'Thanks should no longer create a Chatter FeedItem (replaced by Notification + thread card)');

        Response__c updatedResp = [SELECT Poster_Thanked__c, Responder_Thanked__c FROM Response__c WHERE Id = :response.Id];
        System.assertEquals(true, updatedResp.Poster_Thanked__c, 'Poster_Thanked__c should be stamped');
        System.assertEquals(false, updatedResp.Responder_Thanked__c, 'Responder_Thanked__c should remain false');

        List<Response_Message__c> thanksMsgs = [
            SELECT Id, Body__c, Is_System_Message__c, System_Message_Type__c
            FROM Response_Message__c
            WHERE Response__c = :response.Id AND System_Message_Type__c = 'Thanks_Sent'
        ];
        System.assertEquals(1, thanksMsgs.size(), 'Should create one thanks system message');
        System.assertEquals(true, thanksMsgs[0].Is_System_Message__c, 'Should be a system message');
        System.assert(thanksMsgs[0].Body__c.contains('Thank you so much'), 'Thread message should contain the thanks text');

        List<Notification__c> thanksNotifs = [
            SELECT Id, Contact__c, Type__c
            FROM Notification__c
            WHERE Contact__c = :recipient.Id AND Type__c = 'Thanks_Received'
        ];
        System.assertEquals(1, thanksNotifs.size(), 'Recipient should get one Thanks_Received notification');
    }

    @isTest
    static void testSendThanks_ResponderToPoster() {
        Response__c response = [
            SELECT Id, Need_Offer_Responded_To__r.Contact__c
            FROM Response__c LIMIT 1
        ];
        Id posterId = response.Need_Offer_Responded_To__r.Contact__c;
        Contact posterContact = [SELECT Id, Name FROM Contact WHERE Id = :posterId LIMIT 1];

        Map<String, Object> thanksData = new Map<String, Object>{
            'recipientId' => posterContact.Id,
            'message' => 'Thanks for sharing!',
            'relatedRecordId' => response.Id
        };

        Test.startTest();
        Map<String, Object> result = FimbyThanksController.sendThanks(JSON.serialize(thanksData));
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals('responderToPoster', result.get('direction'), 'Direction should be responderToPoster');

        Response__c updatedResp = [SELECT Poster_Thanked__c, Responder_Thanked__c FROM Response__c WHERE Id = :response.Id];
        System.assertEquals(false, updatedResp.Poster_Thanked__c, 'Poster_Thanked__c should remain false');
        System.assertEquals(true, updatedResp.Responder_Thanked__c, 'Responder_Thanked__c should be stamped');
    }

    @isTest
    static void testSendThanks_WithoutRelatedRecord() {
        User communityUser = [
            SELECT Id, ContactId FROM User
            WHERE Profile.Name = 'Customer Community User' AND IsActive = true LIMIT 1
        ];
        Contact recipient = [SELECT Id, Name FROM Contact WHERE Id = :communityUser.ContactId LIMIT 1];

        Map<String, Object> thanksData = new Map<String, Object>{
            'recipientId' => recipient.Id,
            'message' => 'Thanks for everything!',
            'relatedRecordId' => ''
        };

        Test.startTest();
        Map<String, Object> result = FimbyThanksController.sendThanks(JSON.serialize(thanksData));
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success even without related record');
    }

    @isTest
    static void testSendThanks_RecipientWithoutEmail() {
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact noEmailContact = new Contact(
            FirstName = 'No',
            LastName = 'Email',
            AccountId = neighbourhood.Id
        );
        insert noEmailContact;

        Map<String, Object> thanksData = new Map<String, Object>{
            'recipientId' => noEmailContact.Id,
            'message' => 'Thank you!',
            'relatedRecordId' => ''
        };

        Test.startTest();
        Map<String, Object> result = FimbyThanksController.sendThanks(JSON.serialize(thanksData));
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should succeed even without recipient email');
    }

    @isTest
    static void testSendThanks_InvalidRecipient() {
        Map<String, Object> thanksData = new Map<String, Object>{
            'recipientId' => '003000000000000AAA', // Invalid ID
            'message' => 'Thank you!',
            'relatedRecordId' => ''
        };

        Test.startTest();
        try {
            FimbyThanksController.sendThanks(JSON.serialize(thanksData));
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Error sending thanks'), 'Should contain error message');
        }
        Test.stopTest();
    }
}