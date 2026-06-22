@IsTest
private class FimbyGuidedTourControllerTest {

    @TestSetup
    static void setupData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(contact.Id, 'Customer Community User - Mobile App', true);
    }

    private static User getTestUser() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        return [SELECT Id, ContactId FROM User WHERE ContactId = :testContact.Id LIMIT 1];
    }

    @IsTest
    static void testGetLiveTourStateDefaults() {
        User testUser = getTestUser();
        FimbySettings.setMock(new FIMBY_App_Settings__mdt(Live_Tour_Enabled__c = false));

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> state = FimbyGuidedTourController.getLiveTourState();
            System.assertEquals(FimbyConstants.ONBOARDING_NOT_STARTED, state.get('liveTourStatus'));
            System.assertEquals(false, state.get('bioPostCompleted'));
            System.assertEquals(false, state.get('autostartEligible'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testAutostartEligibleWhenFlagOn() {
        User testUser = getTestUser();
        FimbySettings.setMock(new FIMBY_App_Settings__mdt(Live_Tour_Enabled__c = true));

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> state = FimbyGuidedTourController.getLiveTourState();
            System.assertEquals(true, state.get('autostartEligible'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testSetLiveTourStatusCompleted() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyGuidedTourController.setLiveTourStatus(
                FimbyConstants.ONBOARDING_COMPLETED,
                true
            );
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        Contact updated = [
            SELECT Live_Tour_Status__c, Live_Tour_Extended_Completed__c
            FROM Contact
            WHERE Id = :testUser.ContactId
        ];
        System.assertEquals(FimbyConstants.ONBOARDING_COMPLETED, updated.Live_Tour_Status__c);
        System.assertEquals(true, updated.Live_Tour_Extended_Completed__c);
    }

    @IsTest
    static void testSetLiveTourStatusDismissed() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyGuidedTourController.setLiveTourStatus(FimbyConstants.ONBOARDING_DISMISSED, false);
        }
        Test.stopTest();

        Contact updated = [
            SELECT Live_Tour_Status__c
            FROM Contact
            WHERE Id = :testUser.ContactId
        ];
        System.assertEquals(FimbyConstants.ONBOARDING_DISMISSED, updated.Live_Tour_Status__c);
    }
}
