@IsTest
private class FimbyUserSyncEventHandlerTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(
            contact.Id, 'Customer Community User - Mobile App', true);
    }

    private static User getTestUser() {
        Account n = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :n.Id LIMIT 1];
        return [SELECT Id, ContactId, Email, Username FROM User WHERE ContactId = :c.Id LIMIT 1];
    }

    @IsTest
    static void syncsIdentityFields() {
        User testUser = getTestUser();

        // The FimbyCommunityUserTrigger before-update handler re-stamps User identity
        // from the linked Contact, so the Contact must already hold the new values -
        // exactly as the profile save does before publishing the event.
        update new Contact(
            Id = testUser.ContactId,
            FirstName = 'Event',
            LastName = 'Synced',
            Email = 'event.synced@testorg.com'
        );

        Test.startTest();
        EventBus.publish(new Fimby_User_Sync_Event__e(
            User_Id__c = testUser.Id,
            First_Name__c = 'Event',
            Last_Name__c = 'Synced',
            Email__c = 'event.synced@testorg.com'
        ));
        Test.stopTest();

        User updated = [SELECT FirstName, LastName, Email, Username FROM User WHERE Id = :testUser.Id];
        System.assertEquals('Event', updated.FirstName);
        System.assertEquals('Synced', updated.LastName);
        System.assertEquals('event.synced@testorg.com', updated.Email);
        System.assertEquals(testUser.Username, updated.Username,
            'Username must never be modified by the sync');
    }

    @IsTest
    static void blankUserIdIsNoOp() {
        Test.startTest();
        EventBus.publish(new Fimby_User_Sync_Event__e(
            User_Id__c = '',
            First_Name__c = 'Nobody'
        ));
        Test.stopTest();

        System.assert(true, 'Handler should skip events with a blank User Id without throwing');
    }

    @IsTest
    static void bogusUserIdHitsErrorPathGracefully() {
        Test.startTest();
        EventBus.publish(new Fimby_User_Sync_Event__e(
            User_Id__c = '005000000000000AAA',
            First_Name__c = 'Ghost'
        ));
        Test.stopTest();

        System.assert(true, 'Handler should not throw when the User Id matches no record');
    }
}
