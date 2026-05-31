@IsTest
public class FimbyCounterServiceTest {

    @TestSetup
    static void setupTestData() {
        FimbyTestDataFactory.createCompleteTestSetup();
    }

    private static Contact getTestContact() {
        User u = [SELECT Id, ContactId FROM User
            WHERE Profile.Name = 'Customer Community User' AND IsActive = true LIMIT 1];
        return [SELECT Id, AccountId, Need_Offers_Posted__c, Need_Postings_For_Self__c,
                       Offer_Postings_For_Self__c, Offer_Postings_For_Others__c,
                       Responses_Posted__c,
                       Need_Responses_For_Self__c, Need_Responses_For_Others__c
                FROM Contact WHERE Id = :u.ContactId LIMIT 1];
    }

    @IsTest
    static void testOnPostCreated_NeedSelf() {
        Contact c = getTestContact();
        Decimal before = c.Need_Offers_Posted__c != null ? c.Need_Offers_Posted__c : 0;
        Decimal beforeNeed = c.Need_Postings_For_Self__c != null ? c.Need_Postings_For_Self__c : 0;

        Test.startTest();
        FimbyCounterService.onPostCreated(c.Id, FimbyConstants.RT_NEED, false);
        Test.stopTest();

        Contact after = [SELECT Need_Offers_Posted__c, Need_Postings_For_Self__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(before + 1, after.Need_Offers_Posted__c, 'Need_Offers_Posted should increment');
        System.assertEquals(beforeNeed + 1, after.Need_Postings_For_Self__c, 'Need self should increment');
    }

    @IsTest
    static void testOnPostCreated_OfferForOther() {
        Contact c = getTestContact();

        Test.startTest();
        FimbyCounterService.onPostCreated(c.Id, FimbyConstants.RT_OFFER, true);
        Test.stopTest();

        Contact after = [SELECT Offer_Postings_For_Others__c FROM Contact WHERE Id = :c.Id];
        System.assert(after.Offer_Postings_For_Others__c >= 1, 'Offer other should increment');
    }

    @IsTest
    static void testOnPostDeleted_Decrements() {
        Contact c = getTestContact();
        FimbyCounterService.onPostCreated(c.Id, FimbyConstants.RT_NEED, false);

        Test.startTest();
        FimbyCounterService.onPostDeleted(c.Id, FimbyConstants.RT_NEED, false);
        Test.stopTest();

        Contact after = [SELECT Need_Postings_For_Self__c FROM Contact WHERE Id = :c.Id];
        Decimal original = c.Need_Postings_For_Self__c != null ? c.Need_Postings_For_Self__c : 0;
        System.assertEquals(original, after.Need_Postings_For_Self__c, 'Should return to original after +1 then -1');
    }

    @IsTest
    static void testOnResponseCreated_AutoAccepted() {
        Contact c = getTestContact();

        Test.startTest();
        FimbyCounterService.onResponseCreated(c.Id, FimbyConstants.RT_NEED, false, FimbyConstants.RESPONSE_ACCEPTED);
        Test.stopTest();

        Contact after = [SELECT Responses_Posted__c, Need_Responses_For_Self__c FROM Contact WHERE Id = :c.Id];
        System.assert(after.Responses_Posted__c >= 1, 'Responses_Posted should increment');
        System.assert(after.Need_Responses_For_Self__c >= 1, 'Need response self should increment when auto-accepted');
    }

    @IsTest
    static void testOnResponseCreated_NewStatus_NoSpecificCounter() {
        Contact c = getTestContact();
        Decimal beforeNeedResp = c.Need_Responses_For_Self__c != null ? c.Need_Responses_For_Self__c : 0;

        Test.startTest();
        FimbyCounterService.onResponseCreated(c.Id, FimbyConstants.RT_NEED, false, FimbyConstants.RESPONSE_NEW);
        Test.stopTest();

        Contact after = [SELECT Need_Responses_For_Self__c FROM Contact WHERE Id = :c.Id];
        Decimal afterVal = after.Need_Responses_For_Self__c != null ? after.Need_Responses_For_Self__c : 0;
        System.assertEquals(beforeNeedResp, afterVal,
            'Specific counter should NOT increment for New status');
    }

    @IsTest
    static void testOnResponseStatusChanged_NewToAccepted() {
        Contact c = getTestContact();
        Decimal before = c.Need_Responses_For_Self__c != null ? c.Need_Responses_For_Self__c : 0;

        Test.startTest();
        FimbyCounterService.onResponseStatusChanged(
            c.Id, FimbyConstants.RT_NEED, false,
            FimbyConstants.RESPONSE_NEW, FimbyConstants.RESPONSE_ACCEPTED
        );
        Test.stopTest();

        Contact after = [SELECT Need_Responses_For_Self__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(before + 1, after.Need_Responses_For_Self__c, 'Should increment on acceptance');
    }

    @IsTest
    static void testOnResponseStatusChanged_AcceptedToCancelled() {
        Contact c = getTestContact();
        FimbyCounterService.onResponseStatusChanged(
            c.Id, FimbyConstants.RT_NEED, false,
            FimbyConstants.RESPONSE_NEW, FimbyConstants.RESPONSE_ACCEPTED
        );

        Test.startTest();
        FimbyCounterService.onResponseCancelled(
            c.Id, FimbyConstants.RT_NEED, false, FimbyConstants.RESPONSE_ACCEPTED
        );
        Test.stopTest();

        Contact after = [SELECT Need_Responses_For_Self__c, Responses_Posted__c FROM Contact WHERE Id = :c.Id];
        Decimal original = c.Need_Responses_For_Self__c != null ? c.Need_Responses_For_Self__c : 0;
        System.assertEquals(original, after.Need_Responses_For_Self__c, 'Should decrement back to original');
    }

    @IsTest
    static void testAccountCountersUpdate() {
        Contact c = getTestContact();
        Account accBefore = [SELECT Need_Postings_For_Self__c FROM Account WHERE Id = :c.AccountId];
        Decimal before = accBefore.Need_Postings_For_Self__c != null ? accBefore.Need_Postings_For_Self__c : 0;

        Test.startTest();
        FimbyCounterService.onPostCreated(c.Id, FimbyConstants.RT_NEED, false);
        Test.stopTest();

        Account accAfter = [SELECT Need_Postings_For_Self__c FROM Account WHERE Id = :c.AccountId];
        Decimal afterVal = accAfter.Need_Postings_For_Self__c != null ? accAfter.Need_Postings_For_Self__c : 0;
        System.assert(afterVal > before, 'Account counter should increase after post creation');
    }

    @IsTest
    static void testNullGuards() {
        Test.startTest();
        FimbyCounterService.onPostCreated(null, 'Need', false);
        FimbyCounterService.onPostDeleted(null, 'Offer', false);
        FimbyCounterService.onResponseCreated(null, 'Need', false, 'New');
        FimbyCounterService.onResponseStatusChanged(null, 'Need', false, 'New', 'Accepted');
        FimbyCounterService.onResponseCancelled(null, 'Need', false, 'New');
        FimbyCounterService.onContactActivationChanged(null, 1, true);
        Test.stopTest();

        System.assert(true, 'Should not throw on null inputs');
    }

    @IsTest
    static void testFloorAtZero() {
        Contact c = getTestContact();

        Test.startTest();
        FimbyCounterService.onPostDeleted(c.Id, FimbyConstants.RT_NEED, false);
        Test.stopTest();

        Contact after = [SELECT Need_Postings_For_Self__c FROM Contact WHERE Id = :c.Id];
        System.assert(after.Need_Postings_For_Self__c >= 0, 'Counter should not go below zero');
    }
}
