/**
 * @description Direct tests for FimbyReactivationRequestEventHandler. The
 * controller-side tests in FimbyReactivationControllerTest exercise the
 * end-to-end publish path (EventBus.publish -> trigger -> handler), but those
 * cover the happy paths via the public API. This class hits the handler
 * directly with crafted payloads to lock down the per-event guards (blank
 * input, unknown username, no-grace contact, past-grace contact) without
 * going through the platform event bus, so each gate fails fast and
 * deterministically even when the event bus is flaky in CI.
 */
@IsTest
private class FimbyReactivationRequestEventHandlerTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(
            contact.Id, 'Customer Community User - Mobile App', true);
    }

    private static Contact pausedContact() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        update new Contact(
            Id = c.Id,
            Grace_Started_At__c = System.now().addDays(-2)
        );
        return [SELECT Id, Grace_Started_At__c FROM Contact WHERE Id = :c.Id];
    }

    private static User communityUser() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        return [SELECT Id, Username FROM User WHERE ContactId = :c.Id LIMIT 1];
    }

    @IsTest
    static void handleEventPublishMintsTokenAndSendsEmail() {
        Contact c = pausedContact();
        User u = communityUser();
        FimbyReactivationEmailService.testEmailsSent = 0;

        // Goes through EventBus so the trigger -> handler wiring is exercised.
        Test.startTest();
        EventBus.publish(new Reactivation_Request_Event__e(
            Username__c = u.Username
        ));
        Test.stopTest();

        System.assertEquals(1,
            [SELECT COUNT() FROM Reactivation_Token__c WHERE Contact__c = :c.Id],
            'Subscriber should mint exactly one token per published request');
        System.assertEquals(1, FimbyReactivationEmailService.testEmailsSent,
            'Subscriber should send the restore-link email');
    }

    @IsTest
    static void handleBlankUsernameIsNoOp() {
        Contact c = pausedContact();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        EventBus.publish(new Reactivation_Request_Event__e(Username__c = ''));
        EventBus.publish(new Reactivation_Request_Event__e(Username__c = '   '));
        EventBus.publish(new Reactivation_Request_Event__e(Username__c = null));
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Reactivation_Token__c WHERE Contact__c = :c.Id]);
        System.assertEquals(0, FimbyReactivationEmailService.testEmailsSent);
    }

    @IsTest
    static void handleUnknownUsernameIsNoOp() {
        Contact c = pausedContact();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        EventBus.publish(new Reactivation_Request_Event__e(
            Username__c = 'no-such-user-zz@example.com.fimby'
        ));
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Reactivation_Token__c WHERE Contact__c = :c.Id]);
        System.assertEquals(0, FimbyReactivationEmailService.testEmailsSent);
    }

    @IsTest
    static void handleUserWithNoGraceIsNoOp() {
        // Skip pausedContact() so Grace_Started_At__c stays null
        User u = communityUser();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        EventBus.publish(new Reactivation_Request_Event__e(
            Username__c = u.Username
        ));
        Test.stopTest();

        System.assertEquals(0, FimbyReactivationEmailService.testEmailsSent,
            'Users without an active grace window should not receive a link');
    }

    @IsTest
    static void handlePastGraceIsNoOp() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        update new Contact(
            Id = c.Id,
            Grace_Started_At__c = System.now().addDays(-60)
        );
        User u = communityUser();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        EventBus.publish(new Reactivation_Request_Event__e(
            Username__c = u.Username
        ));
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Reactivation_Token__c WHERE Contact__c = :c.Id]);
        System.assertEquals(0, FimbyReactivationEmailService.testEmailsSent);
    }
}
