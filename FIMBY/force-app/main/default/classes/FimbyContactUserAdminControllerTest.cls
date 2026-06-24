@IsTest
private class FimbyContactUserAdminControllerTest {

    @TestSetup
    static void setupData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(contact.Id, 'Customer Community User - Mobile App', true);
    }

    private static Contact getTestContact() {
        Account neighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        return [SELECT Id FROM Contact WHERE AccountId = :neighbourhood.Id LIMIT 1];
    }

    @IsTest
    static void getLinkedUser_returnsUserForContact() {
        Contact testContact = getTestContact();

        Test.startTest();
        FimbyContactUserAdminController.LinkedUserResult result =
            FimbyContactUserAdminController.getLinkedUser(testContact.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Expected a linked user');
        System.assertNotEquals(null, result.userId);
        System.assertNotEquals(null, result.username);
        System.assertEquals(true, result.isActive);
    }

    @IsTest
    static void getLinkedUser_returnsNullWhenNoUser() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(false);
        Contact orphanContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        Test.startTest();
        FimbyContactUserAdminController.LinkedUserResult result =
            FimbyContactUserAdminController.getLinkedUser(orphanContact.Id);
        Test.stopTest();

        System.assertEquals(null, result);
    }

    @IsTest
    static void getLinkedUser_returnsNullForNullContactId() {
        Test.startTest();
        FimbyContactUserAdminController.LinkedUserResult result =
            FimbyContactUserAdminController.getLinkedUser(null);
        Test.stopTest();

        System.assertEquals(null, result);
    }
}
