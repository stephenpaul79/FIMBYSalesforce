@IsTest
private class FimbyOnboardingControllerTest {

    @TestSetup
    static void setupData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User communityUser = FimbyTestDataFactory.createCommunityUser(contact.Id, 'Customer Community User - Mobile App', true);
    }

    private static User getTestUser() {
        Account testNeighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact testContact = [SELECT Id FROM Contact WHERE AccountId = :testNeighbourhood.Id LIMIT 1];
        return [SELECT Id, ContactId FROM User WHERE ContactId = :testContact.Id LIMIT 1];
    }

    @IsTest
    static void testGetOnboardingStatusNewUser() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.getOnboardingStatus();
            System.assertEquals(false, result.get('profileCompleted'), 'New user should not have completed profile');
            System.assertEquals('Not Started', result.get('walkthroughStatus'));
            System.assertEquals(true, result.get('showWalkthrough'));
            System.assertEquals(false, result.get('bioPostCompleted'), 'New user should not have completed bio post');
        }
        Test.stopTest();
    }

    @IsTest
    static void testCompleteProfileSetup() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, String> fields = new Map<String, String>{
                'FirstName' => 'Sarah',
                'LastName' => 'TestResident',
                'Pronouns__c' => 'she/her'
            };
            Map<String, Object> result = FimbyOnboardingController.completeProfileSetup(fields);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        Contact updated = [SELECT FirstName, Pronouns__c, Onboarding_Profile_Completed__c
                           FROM Contact WHERE Id = :testUser.ContactId];
        System.assertEquals('Sarah', updated.FirstName);
        System.assertEquals('she/her', updated.Pronouns__c);
        System.assertEquals(true, updated.Onboarding_Profile_Completed__c);
    }

    @IsTest
    static void testCompleteProfileBlockedField() {
        User testUser = getTestUser();
        Boolean caughtError = false;

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyOnboardingController.completeProfileSetup(
                    new Map<String, String>{ 'Logged_In_As_Contact__c' => 'hacked' }
                );
            } catch (AuraHandledException e) {
                caughtError = true;
            }
        }
        Test.stopTest();

        System.assert(caughtError, 'Should block non-whitelisted field');
    }

    @IsTest
    static void testDismissWalkthroughTemporary() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.dismissWalkthrough(false);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        User updated = [SELECT Onboarding_Walkthrough_Dismissed_At__c, Onboarding_Walkthrough_Status__c
                        FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, updated.Onboarding_Walkthrough_Dismissed_At__c);
        System.assertNotEquals('Dismissed', updated.Onboarding_Walkthrough_Status__c);
    }

    @IsTest
    static void testDismissWalkthroughPermanent() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.dismissWalkthrough(true);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        User updated = [SELECT Onboarding_Walkthrough_Status__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals('Dismissed', updated.Onboarding_Walkthrough_Status__c);
    }

    @IsTest
    static void testCompleteWalkthrough() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.completeWalkthrough();
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        User updated = [SELECT Onboarding_Walkthrough_Status__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals('Completed', updated.Onboarding_Walkthrough_Status__c);
    }

    @IsTest
    static void testGetOnboardingStatusAfterProfileComplete() {
        User testUser = getTestUser();

        Contact c = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        c.Onboarding_Profile_Completed__c = true;
        update c;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.getOnboardingStatus();
            System.assertEquals(true, result.get('profileCompleted'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetOnboardingStatusAfterDismiss() {
        User testUser = getTestUser();

        Contact c = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        c.Onboarding_Profile_Completed__c = true;
        update c;

        User u = [SELECT Id FROM User WHERE Id = :testUser.Id];
        u.Onboarding_Walkthrough_Status__c = 'Dismissed';
        update u;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.getOnboardingStatus();
            System.assertEquals(true, result.get('profileCompleted'));
            System.assertEquals('Dismissed', result.get('walkthroughStatus'));
            System.assertEquals(false, result.get('showWalkthrough'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetBioPostStatusInitiallyFalse() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Boolean status = FimbyOnboardingController.getBioPostStatus();
            System.assertEquals(false, status, 'New user should not have bio post completed');
        }
        Test.stopTest();
    }

    @IsTest
    static void testMarkBioPostCompletedFromPost() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.markBioPostCompleted(true, null);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        Contact updated = [SELECT Bio_Post_Completed__c FROM Contact WHERE Id = :testUser.ContactId];
        System.assertEquals(true, updated.Bio_Post_Completed__c, 'Post path should flip flag to true');
    }

    @IsTest
    static void testMarkBioPostCompletedFromSkip() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.markBioPostCompleted(false, null);
            System.assertEquals(true, result.get('success'));
            System.assertEquals(true, result.get('skipped'), 'Skip path should report skipped:true');
        }
        Test.stopTest();

        // The "say hi" banner / soft-gate keeps nudging until the bio is
        // actually posted, so a skip must NOT flip the completion flag.
        Contact updated = [SELECT Bio_Post_Completed__c FROM Contact WHERE Id = :testUser.ContactId];
        System.assertEquals(false, updated.Bio_Post_Completed__c, 'Skip path should leave flag false');
    }

    @IsTest
    static void testGetBioPostStatusAfterMark() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyOnboardingController.markBioPostCompleted(true, null);
            Boolean status = FimbyOnboardingController.getBioPostStatus();
            System.assertEquals(true, status, 'Status should reflect the flipped flag');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetOnboardingStatusIncludesBioPostCompleted() {
        User testUser = getTestUser();

        Contact c = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        c.Bio_Post_Completed__c = true;
        update c;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.getOnboardingStatus();
            System.assertEquals(true, result.get('bioPostCompleted'), 'Status should expose bioPostCompleted for replay/skip routing');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetWalkthroughSlidesReturnsEmptyStub() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            List<Map<String, String>> slides = FimbyOnboardingController.getWalkthroughSlides();
            System.assertNotEquals(null, slides, 'Deprecated stub should still return a list');
            System.assertEquals(0, slides.size(), 'Deprecated stub should return empty list');
        }
        Test.stopTest();
    }

    @IsTest
    static void testSaveQuietHoursPreference() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyOnboardingController.saveQuietHoursPreference('11PM_7AM');
        }
        Test.stopTest();

        User updated = [SELECT Quiet_Hours_Preference__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals('11PM_7AM', updated.Quiet_Hours_Preference__c);
    }

    @IsTest
    static void testGetOnboardingStatusOrganizationContactBypass() {
        User testUser = getTestUser();
        Account neighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Contact orgContact = new Contact(
            FirstName = 'Strathcona',
            LastName = 'Vineyard',
            AccountId = neighbourhood.Id,
            Is_Organization_Contact__c = true,
            Onboarding_Profile_Completed__c = false,
            Bio_Post_Completed__c = false
        );
        insert orgContact;

        Account orgAcct = new Account(
            Name = 'Test Org Account',
            RecordTypeId = orgRtId,
            Organization_Contact__c = orgContact.Id,
            Is_Approved_Community_Group__c = true
        );
        insert orgAcct;
        orgContact.Organization_Account__c = orgAcct.Id;
        update orgContact;

        insert new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Organization__c = orgAcct.Id,
            Neighbourhood__c = neighbourhood.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved',
            Consent_Method__c = 'Written'
        );

        Contact helper = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        helper.Logged_In_As_Contact__c = orgContact.Id;
        update helper;
        FimbyIdentityRepository.clearCache();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.getOnboardingStatus();
            System.assertEquals(true, result.get('profileCompleted'),
                'Organization acting identity should bypass profile onboarding');
            System.assertEquals(true, result.get('bioPostCompleted'));
        }
        Test.stopTest();

        Contact stamped = [SELECT Onboarding_Profile_Completed__c, Bio_Post_Completed__c
                           FROM Contact WHERE Id = :orgContact.Id];
        System.assertEquals(false, stamped.Onboarding_Profile_Completed__c,
            'Bypass is runtime; flags stamped only on completeProfileSetup');
    }

    @IsTest
    static void testCompleteProfileSetupOrganizationContactStampsFlags() {
        User testUser = getTestUser();
        Account neighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Contact orgContact = new Contact(
            FirstName = 'Org',
            LastName = 'Only',
            AccountId = neighbourhood.Id,
            Is_Organization_Contact__c = true,
            Onboarding_Profile_Completed__c = false
        );
        insert orgContact;
        Account orgAcct = new Account(
            Name = 'Stamp Test Org',
            RecordTypeId = orgRtId,
            Organization_Contact__c = orgContact.Id
        );
        insert orgAcct;
        orgContact.Organization_Account__c = orgAcct.Id;
        update orgContact;
        insert new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Organization__c = orgAcct.Id,
            Neighbourhood__c = neighbourhood.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved',
            Consent_Method__c = 'Written'
        );

        Contact helper = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        helper.Logged_In_As_Contact__c = orgContact.Id;
        update helper;
        FimbyIdentityRepository.clearCache();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.completeProfileSetup(
                new Map<String, String>{ 'FirstName' => 'Should', 'LastName' => 'Ignore' }
            );
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        Contact updated = [SELECT Onboarding_Profile_Completed__c, Bio_Post_Completed__c
                           FROM Contact WHERE Id = :orgContact.Id];
        System.assertEquals(true, updated.Onboarding_Profile_Completed__c);
        System.assertEquals(true, updated.Bio_Post_Completed__c);
    }

    @IsTest
    static void testGetOnboardingStatusTempDismissExpired() {
        User testUser = getTestUser();

        Contact c = [SELECT Id FROM Contact WHERE Id = :testUser.ContactId];
        c.Onboarding_Profile_Completed__c = true;
        update c;

        User u = [SELECT Id FROM User WHERE Id = :testUser.Id];
        u.Onboarding_Walkthrough_Dismissed_At__c = DateTime.now().addHours(-24);
        update u;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyOnboardingController.getOnboardingStatus();
            System.assertEquals(true, result.get('showWalkthrough'), 'Should show walkthrough after 12+ hours');
        }
        Test.stopTest();
    }

}
