/**
 * @description Coverage for FimbySessionController.endAllSessions.
 *
 * AuthSession is a system-managed object: Apex cannot insert it and, in test
 * context, the queries return no rows. The controller's isEmpty() guards mean
 * no DML fires here — so these tests verify the method runs end-to-end (query +
 * guards) without error as the running community user, which is the contract
 * the logout handler relies on (best-effort, never throws on the empty case).
 */
@isTest
private class FimbySessionControllerTest {

    @TestSetup
    static void setup() {
        Account hood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(hood.Id, true);
        FimbyTestDataFactory.createCommunityUser(c.Id, null, true);
    }

    private static User getTestUser() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        List<User> users = [
            SELECT Id FROM User WHERE ContactId = :c.Id AND IsActive = true LIMIT 1
        ];
        System.assert(!users.isEmpty(), 'TestSetup must create a community User for the test Contact.');
        return users[0];
    }

    @isTest
    static void endAllSessions_completes_without_error() {
        User u = getTestUser();
        Test.startTest();
        System.runAs(u) {
            // No AuthSession rows exist in test context; the method should run
            // its queries and isEmpty() guards and return cleanly.
            FimbySessionController.endAllSessions();
        }
        Test.stopTest();

        // Reaching here means no AuraHandledException was thrown.
        System.assert(true, 'endAllSessions completed for the running user.');
    }
}
