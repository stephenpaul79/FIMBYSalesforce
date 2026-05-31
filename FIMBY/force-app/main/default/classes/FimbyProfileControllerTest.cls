@IsTest
private class FimbyProfileControllerTest {

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
    static void testGetProfileData() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.getProfileData();
            System.assertEquals(true, result.get('success'), 'Should succeed');
            System.assertNotEquals(null, result.get('contactId'));
            System.assertNotEquals(null, result.get('firstName'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateProfileSection() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, String> fields = new Map<String, String>{
                'Pronouns__c' => 'they/them',
                'About_Neighbourhood_Tenure__c' => '5 years',
                'About_Fun_Fact__c' => 'I collect vintage maps'
            };
            Map<String, Object> result = FimbyProfileController.updateProfileSection(fields);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        Contact updated = [SELECT Pronouns__c, About_Neighbourhood_Tenure__c, About_Fun_Fact__c
                           FROM Contact WHERE Id = :testUser.ContactId];
        System.assertEquals('they/them', updated.Pronouns__c);
        System.assertEquals('5 years', updated.About_Neighbourhood_Tenure__c);
        System.assertEquals('I collect vintage maps', updated.About_Fun_Fact__c);
    }

    @IsTest
    static void testUpdateProfileSectionBlockedField() {
        User testUser = getTestUser();
        Boolean caughtError = false;

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyProfileController.updateProfileSection(
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
    static void testUpdateProfileSectionSyncsUserIdentityFields() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.updateProfileSection(
                new Map<String, String>{
                    'FirstName' => 'Updated',
                    'LastName' => 'Neighbour',
                    'Email' => 'updated.neighbour@testorg.com'
                }
            );
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        Contact updatedContact = [
            SELECT FirstName, LastName, Email
            FROM Contact
            WHERE Id = :testUser.ContactId
        ];
        System.assertEquals('Updated', updatedContact.FirstName);
        System.assertEquals('Neighbour', updatedContact.LastName);
        System.assertEquals('updated.neighbour@testorg.com', updatedContact.Email);

        User updatedUser = [
            SELECT FirstName, LastName, Email
            FROM User
            WHERE Id = :testUser.Id
        ];
        System.assertEquals('Updated', updatedUser.FirstName);
        System.assertEquals('Neighbour', updatedUser.LastName);
        System.assertEquals('updated.neighbour@testorg.com', updatedUser.Email);
    }

    @IsTest
    static void testUpdateProfileSectionDoesNotSyncUserWhenActingAsOther() {
        User testUser = getTestUser();
        Account neighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact supportee = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        insert new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Contact__c = supportee.Id,
            Status__c = 'Approved',
            Relationship_Type__c = 'Support_Person',
            Consent_Method__c = 'Verbal',
            Neighbourhood__c = neighbourhood.Id
        );

        update new Contact(Id = testUser.ContactId, Logged_In_As_Contact__c = supportee.Id);

        User beforeUser = [
            SELECT FirstName, LastName, Email
            FROM User
            WHERE Id = :testUser.Id
        ];

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.updateProfileSection(
                new Map<String, String>{
                    'FirstName' => 'Supportee',
                    'LastName' => 'Name',
                    'Email' => 'supportee@testorg.com'
                }
            );
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        Contact updatedSupportee = [
            SELECT FirstName, LastName, Email
            FROM Contact
            WHERE Id = :supportee.Id
        ];
        System.assertEquals('Supportee', updatedSupportee.FirstName);
        System.assertEquals('supportee@testorg.com', updatedSupportee.Email);

        User afterUser = [
            SELECT FirstName, LastName, Email
            FROM User
            WHERE Id = :testUser.Id
        ];
        System.assertEquals(beforeUser.FirstName, afterUser.FirstName);
        System.assertEquals(beforeUser.LastName, afterUser.LastName);
        System.assertEquals(beforeUser.Email, afterUser.Email);
    }

    @IsTest
    static void testGetSettingsData() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.getSettingsData();
            System.assertEquals(true, result.get('success'));
            System.assertNotEquals(null, result.get('username'));
            System.assertEquals(true, result.get('isActingAsSelf'),
                'User without an active Logged_In_As override is acting as themselves');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetSettingsDataReportsActingAsOther() {
        User testUser = getTestUser();
        Account neighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact supportee = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        insert new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Contact__c = supportee.Id,
            Status__c = 'Approved',
            Relationship_Type__c = 'Support_Person',
            Consent_Method__c = 'Verbal',
            Neighbourhood__c = neighbourhood.Id
        );

        update new Contact(Id = testUser.ContactId, Logged_In_As_Contact__c = supportee.Id);

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.getSettingsData();
            System.assertEquals(false, result.get('isActingAsSelf'),
                'When Logged_In_As_Contact__c overrides identity, isActingAsSelf is false');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateSettingsField() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.updateSettingsField('TimeZoneSidKey', 'America/Vancouver');
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        User updated = [SELECT TimeZoneSidKey FROM User WHERE Id = :testUser.Id];
        System.assertEquals('America/Vancouver', updated.TimeZoneSidKey);
    }

    @IsTest
    static void testUpdateSettingsToggle() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.updateSettingsToggle('Push_Messages__c', false);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        User updated = [SELECT Push_Messages__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals(false, updated.Push_Messages__c);
    }

    @IsTest
    static void testUpdateThemePreference() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.updateSettingsField('Theme_Preference__c', 'Dark');
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        User updated = [SELECT Theme_Preference__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals('Dark', updated.Theme_Preference__c);
    }

    @IsTest
    static void testGetSettingsReturnsTheme() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.getSettingsData();
            System.assertEquals(true, result.get('success'));
            System.assertNotEquals(null, result.get('themePreference'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateSettingsFieldBlocked() {
        User testUser = getTestUser();
        Boolean caughtError = false;

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyProfileController.updateSettingsField('IsActive', 'false');
            } catch (AuraHandledException e) {
                caughtError = true;
            }
        }
        Test.stopTest();

        System.assert(caughtError, 'Should block non-whitelisted field');
    }

    @IsTest
    static void testTriggerPasswordReset() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.triggerPasswordReset();
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetCelebrationContext() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.getCelebrationContext();
            System.assertNotEquals(null, result, 'Should return celebration context');
            System.assertNotEquals(null, result.get('confettiEnabled'), 'Should include confettiEnabled');
            System.assertNotEquals(null, result.get('memesEnabled'), 'Should include memesEnabled');
            System.assert(result.containsKey('firstBulkBuyCelebrated'), 'Should include firstBulkBuyCelebrated');
            System.assert(result.containsKey('firstBulkBuyReserveCelebrated'), 'Should include firstBulkBuyReserveCelebrated');
            System.assert(result.containsKey('completedBulkBuys'), 'Should include completedBulkBuys');
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetActiveSeasonalTheme() {
        Test.startTest();
        Map<String, Object> result = FimbyProfileController.getActiveSeasonalTheme();
        Test.stopTest();
        // May return null if no theme is active today -- that's fine
    }

    @IsTest
    static void testGetCelebrationActions() {
        Test.startTest();
        List<Map<String, String>> actions = FimbyProfileController.getCelebrationActions();
        Test.stopTest();
        System.assertNotEquals(null, actions, 'Should return celebration actions list');
        for (Map<String, String> action : actions) {
            System.assertNotEquals(null, action.get('actionKey'), 'Each action should have an actionKey');
            System.assertNotEquals(null, action.get('occasion'), 'Each action should have an occasion');
            System.assertNotEquals(null, action.get('animationStyle'), 'Each action should have an animationStyle');
        }
    }

    @IsTest
    static void testGetLoadingMessages() {
        Test.startTest();
        List<Map<String, String>> messages = FimbyProfileController.getLoadingMessages();
        Test.stopTest();
        System.assertNotEquals(null, messages, 'Should return messages list');
    }

    @IsTest
    static void testMarkFirstCelebration() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyProfileController.markFirstCelebration('First_Post_Celebrated__c');
        }
        Test.stopTest();

        Contact updated = [SELECT First_Post_Celebrated__c FROM Contact WHERE Id = :testUser.ContactId];
        System.assertEquals(true, updated.First_Post_Celebrated__c);
    }

    @IsTest
    static void testMarkFirstBulkBuyCelebration() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyProfileController.markFirstCelebration('First_Bulk_Buy_Celebrated__c');
        }
        Test.stopTest();

        Contact updated = [SELECT First_Bulk_Buy_Celebrated__c FROM Contact WHERE Id = :testUser.ContactId];
        System.assertEquals(true, updated.First_Bulk_Buy_Celebrated__c);
    }

    @IsTest
    static void testMarkFirstCelebrationBlockedField() {
        User testUser = getTestUser();
        Boolean caughtError = false;

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyProfileController.markFirstCelebration('IsActive');
            } catch (AuraHandledException e) {
                caughtError = true;
            }
        }
        Test.stopTest();

        System.assert(caughtError, 'Should block non-whitelisted field');
    }

    @IsTest
    static void testUpdateLastAppVisit() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            FimbyProfileController.updateLastAppVisit();
        }
        Test.stopTest();

        User updated = [SELECT Last_App_Visit__c FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, updated.Last_App_Visit__c, 'Last_App_Visit__c should be set');
    }

    @IsTest
    static void testCelebrationToggle() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.updateSettingsToggle('Celebration_Confetti_Enabled__c', false);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        User updated = [SELECT Celebration_Confetti_Enabled__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals(false, updated.Celebration_Confetti_Enabled__c);
    }

    /**
     * A4: Settings must surface the three new toggles so the LWC can render
     * and persist them. Confirms the getSettingsData payload contains the
     * new keys (presence test — values may be true or false depending on
     * default).
     */
    @IsTest
    static void testGetSettingsExposesNewA4Fields() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.getSettingsData();
            System.assertEquals(true, result.get('success'));
            System.assert(result.containsKey('pushEvents'),
                'Settings payload should expose pushEvents for the Events row');
            System.assert(result.containsKey('emailAlertEvents'),
                'Settings payload should expose emailAlertEvents for the Events row');
            System.assert(result.containsKey('fimbyOperatingUpdatesEnabled'),
                'Settings payload should expose fimbyOperatingUpdatesEnabled for the Updates section');
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdatePushEventsToggle() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.updateSettingsToggle('Push_Events__c', false);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        User updated = [SELECT Push_Events__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals(false, updated.Push_Events__c);
    }

    @IsTest
    static void testUpdateEmailAlertEventsToggle() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.updateSettingsToggle('Email_Alert_Events__c', false);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        User updated = [SELECT Email_Alert_Events__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals(false, updated.Email_Alert_Events__c);
    }

    @IsTest
    static void testUpdateFimbyOperatingUpdatesToggle() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.updateSettingsToggle('FIMBY_Operating_Updates_Enabled__c', false);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        User updated = [SELECT FIMBY_Operating_Updates_Enabled__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals(false, updated.FIMBY_Operating_Updates_Enabled__c,
            'Opt-out of FIMBY operating updates must persist on the User record');
    }

    /**
     * Negative test: the security-bypass design means we explicitly do NOT
     * expose Push_Account_Security__c or Email_Alert_Account_Security__c
     * fields. If a future change tries to allow them through the toggle
     * controller, this test will start passing the assertion negation and
     * the implementer will know to re-read the "No security toggle" plan
     * note before proceeding.
     */
    @IsTest
    static void testSecurityToggleFieldsAreNotInAllowlist() {
        User testUser = getTestUser();
        Boolean caughtPushSecurity = false;
        Boolean caughtEmailSecurity = false;

        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyProfileController.updateSettingsToggle('Push_Account_Security__c', false);
            } catch (AuraHandledException e) {
                caughtPushSecurity = true;
            }
            try {
                FimbyProfileController.updateSettingsToggle('Email_Alert_Account_Security__c', false);
            } catch (AuraHandledException e) {
                caughtEmailSecurity = true;
            }
        }
        Test.stopTest();

        System.assert(caughtPushSecurity,
            'Push_Account_Security__c must be blocked — security messages bypass all toggles by design');
        System.assert(caughtEmailSecurity,
            'Email_Alert_Account_Security__c must be blocked — security messages bypass all toggles by design');
    }

    @IsTest
    static void testRequestAccountDeletionWithGraceStampsGraceAndMintsToken() {
        User testUser = getTestUser();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.requestAccountDeletion(false);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        Contact updated = [
            SELECT Deactivation_Requested__c, Grace_Started_At__c
            FROM Contact WHERE Id = :testUser.ContactId
        ];
        System.assertEquals(false, updated.Deactivation_Requested__c,
            'Graceful default must NOT set Deactivation_Requested__c immediately');
        System.assertNotEquals(null, updated.Grace_Started_At__c,
            'Grace_Started_At__c should be stamped to start the 30-day window');
        System.assertEquals(1, FimbyReactivationEmailService.testEmailsSent,
            'Restore-link confirmation email should fire on graceful path');
        System.assertEquals(1,
            [SELECT COUNT() FROM Reactivation_Token__c WHERE Contact__c = :testUser.ContactId],
            'Graceful path mints a 30-day token for the restore email');
    }

    @IsTest
    static void testRequestAccountDeletionWithSkipGraceFlagsImmediately() {
        User testUser = getTestUser();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.requestAccountDeletion(true);
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        Contact updated = [
            SELECT Deactivation_Requested__c, Grace_Started_At__c
            FROM Contact WHERE Id = :testUser.ContactId
        ];
        System.assertEquals(true, updated.Deactivation_Requested__c,
            'skipGrace path must set Deactivation_Requested__c immediately');
        System.assertEquals(null, updated.Grace_Started_At__c,
            'skipGrace must not start a grace window');
        System.assertEquals(0, FimbyReactivationEmailService.testEmailsSent,
            'No restore email on skip-grace path');
    }

    @IsTest
    static void testRequestAccountDeactivationBackCompatRoutesToGrace() {
        User testUser = getTestUser();

        Test.startTest();
        System.runAs(testUser) {
            Map<String, Object> result = FimbyProfileController.requestAccountDeactivation();
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        Contact updated = [
            SELECT Deactivation_Requested__c, Grace_Started_At__c
            FROM Contact WHERE Id = :testUser.ContactId
        ];
        System.assertNotEquals(null, updated.Grace_Started_At__c,
            'Back-compat call defaults to the graceful path');
    }

    @IsTest
    static void testRequestAccountDeactivationBlockedWhenActingAsOther() {
        User testUser = getTestUser();
        Account neighbourhood = [SELECT Id FROM Account WHERE Name = 'Test Neighbourhood 1' LIMIT 1];
        Contact supportee = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        insert new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Contact__c = supportee.Id,
            Status__c = 'Approved',
            Relationship_Type__c = 'Support_Person',
            Consent_Method__c = 'Verbal',
            Neighbourhood__c = neighbourhood.Id
        );

        update new Contact(Id = testUser.ContactId, Logged_In_As_Contact__c = supportee.Id);

        Boolean caught = false;
        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbyProfileController.requestAccountDeletion(false);
            } catch (AuraHandledException e) {
                caught = true;
            }
        }
        Test.stopTest();

        System.assert(caught,
            'Supporter acting as someone else cannot delete via the in-app flow');
        Contact ownContact = [
            SELECT Deactivation_Requested__c, Grace_Started_At__c
            FROM Contact WHERE Id = :testUser.ContactId
        ];
        System.assertEquals(false, ownContact.Deactivation_Requested__c,
            'Real user contact is not flagged when supporter blocked');
        System.assertEquals(null, ownContact.Grace_Started_At__c,
            'Real user contact grace not started when supporter blocked');
        Contact supporteeContact = [
            SELECT Deactivation_Requested__c, Grace_Started_At__c
            FROM Contact WHERE Id = :supportee.Id
        ];
        System.assertEquals(false, supporteeContact.Deactivation_Requested__c,
            'Supportee contact is not flagged either');
        System.assertEquals(null, supporteeContact.Grace_Started_At__c,
            'Supportee contact grace not started either');
    }
}
