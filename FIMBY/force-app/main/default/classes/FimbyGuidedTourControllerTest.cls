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
            System.assertEquals(false, state.get('bannerEligible'));
            System.assertNotEquals(null, state.get('firstName'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testBannerHiddenWhileBioBannerActive() {
        User testUser = getTestUser();
        FimbySettings.setMock(new FIMBY_App_Settings__mdt(Live_Tour_Enabled__c = false));

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> state = FimbyGuidedTourController.getLiveTourState();
            System.assertEquals(false, state.get('bannerEligible'),
                'Tour banner must wait until the say-hi banner is retired');
        }
        Test.stopTest();
    }

    @IsTest
    static void testBannerEligibleAfterBioBannerDismissed() {
        User testUser = getTestUser();
        FimbySettings.setMock(new FIMBY_App_Settings__mdt(Live_Tour_Enabled__c = false));
        update new Contact(Id = testUser.ContactId, Bio_Banner_Dismissed__c = true);

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> state = FimbyGuidedTourController.getLiveTourState();
            System.assertEquals(true, state.get('bannerEligible'),
                'Tour banner is offered regardless of the autostart flag');
            System.assertEquals(false, state.get('autostartEligible'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testBannerEligibleAfterBioPosted() {
        User testUser = getTestUser();
        update new Contact(Id = testUser.ContactId, Bio_Post_Completed__c = true);

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> state = FimbyGuidedTourController.getLiveTourState();
            System.assertEquals(true, state.get('bannerEligible'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testBannerHiddenOnceTourDismissedOrCompleted() {
        User testUser = getTestUser();
        update new Contact(Id = testUser.ContactId, Bio_Post_Completed__c = true);

        Test.startTest();
        System.runAs(testUser) {
            FimbyGuidedTourController.setLiveTourStatus(FimbyConstants.ONBOARDING_DISMISSED, false);
            System.assertEquals(false, FimbyGuidedTourController.getLiveTourState().get('bannerEligible'),
                'Hard dismiss retires the tour banner for good');

            FimbyGuidedTourController.setLiveTourStatus(FimbyConstants.ONBOARDING_COMPLETED, false);
            System.assertEquals(false, FimbyGuidedTourController.getLiveTourState().get('bannerEligible'));
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
