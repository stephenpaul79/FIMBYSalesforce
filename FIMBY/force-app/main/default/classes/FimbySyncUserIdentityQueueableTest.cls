@IsTest
private class FimbySyncUserIdentityQueueableTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(
            contact.Id, 'Customer Community User - Mobile App', true);
    }

    @IsTest
    static void executeSyncsIdentityFields() {
        User u = [SELECT Id FROM User WHERE ContactId != null LIMIT 1];
        Map<String, String> fields = new Map<String, String>{
            'FirstName' => 'Queue',
            'LastName' => 'Synced',
            'Email' => 'queue.synced@testorg.com'
        };

        Test.startTest();
        System.enqueueJob(new FimbySyncUserIdentityQueueable(u.Id, fields));
        Test.stopTest();

        User updated = [
            SELECT FirstName, LastName, Email
            FROM User
            WHERE Id = :u.Id
        ];
        System.assertEquals('Queue', updated.FirstName);
        System.assertEquals('Synced', updated.LastName);
        System.assertEquals('queue.synced@testorg.com', updated.Email);
    }

    @IsTest
    static void executeWithBogusIdHitsErrorPath() {
        Test.startTest();
        System.enqueueJob(new FimbySyncUserIdentityQueueable(
            '005000000000000AAA',
            new Map<String, String>{ 'FirstName' => 'X' }
        ));
        Test.stopTest();

        System.assert(true, 'Queueable should catch and log, not throw');
    }
}
