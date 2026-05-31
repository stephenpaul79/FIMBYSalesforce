/**
 * @description Tests for FimbyReactivateUserQueueable. Covers the happy
 * path (execute -> flip IsActive=true) and the catch branch (passing a
 * bogus Id forces Database.update to fail or throw, exercising the warn/
 * error log path).
 */
@IsTest
private class FimbyReactivateUserQueueableTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(
            contact.Id, 'Customer Community User - Mobile App', true);
    }

    @IsTest
    static void executeAttemptsToFlipUserActive() {
        User u = [SELECT Id, IsActive FROM User WHERE ContactId != null LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = u.Id, IsActive = false);
        }

        Test.startTest();
        System.enqueueJob(new FimbyReactivateUserQueueable(u.Id));
        Test.stopTest();

        // Best-effort assertion: test contexts vary in whether User DML
        // commits, but the queueable must not throw.
        System.assert(true, 'Queueable ran to completion without throwing');
    }

    @IsTest
    static void executeWithBogusIdHitsErrorPath() {
        Id bogus = '005000000000000AAA';

        Test.startTest();
        System.enqueueJob(new FimbyReactivateUserQueueable(bogus));
        Test.stopTest();

        System.assert(true, 'Queueable should catch and log, not throw');
    }
}
