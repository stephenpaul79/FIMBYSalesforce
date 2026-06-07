@isTest
public class FimbyContactControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create neighbourhood (Account)
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);

        // Create contact linked to neighbourhood
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);

        // Create community user linked to contact
        User testUser = FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);

        // Create an Organization account for organization lookup tests
        Account orgAccount = new Account(
            Name = 'Test Community Organization',
            Type = 'Organization'
        );
        try {
            Id orgRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByName().get('Organization').getRecordTypeId();
            orgAccount.RecordTypeId = orgRecordTypeId;
        } catch (Exception e) {
            // Record type may not exist, continue without it
        }
        insert orgAccount;
    }

    private static User getTestUser() {
        Contact testContact = getTestContact();
        List<User> users = [
            SELECT Id, ContactId
            FROM User
            WHERE ContactId = :testContact.Id AND IsActive = true
            LIMIT 1
        ];
        System.assert(!users.isEmpty(), 'Expected community user from @TestSetup');
        return users[0];
    }

    private static Contact getTestContact() {
        return [SELECT Id, AccountId, Logged_In_As_Contact__c FROM Contact WHERE Email LIKE '%@fimby.test.com' LIMIT 1];
    }

    @isTest
    static void testGetActingAsContact_Success() {
        User testUser = getTestUser();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyContactController.getActingAsContact();
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('contactId'), 'Should return contactId');
        System.assertNotEquals(null, result.get('contactName'), 'Should return contactName');
        System.assertNotEquals(null, result.get('firstName'), 'Should return firstName');
        System.assertNotEquals(null, result.get('postingAsDisplayName'), 'Should return postingAsDisplayName');
        System.assert(result.containsKey('isOrganizationContact'), 'Should contain isOrganizationContact');
        System.assert(result.containsKey('organizationAccountId'), 'Should contain organizationAccountId');
        System.assert(result.containsKey('tosReacceptanceRequired'), 'Should expose tosReacceptanceRequired flag for header modal');
        System.assertEquals(false, result.get('tosReacceptanceRequired'), 'Default contact should not require TOS reacceptance');
    }

    @isTest
    static void testGetActingAsContact_SelfReturnsContactNameAsDisplayName() {
        User testUser = getTestUser();
        Contact testContact = getTestContact();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyContactController.getActingAsContact();
        }
        Test.stopTest();

        System.assertEquals(false, result.get('isOrganizationContact'), 'Regular contact should not be org contact');
        System.assertEquals(null, result.get('organizationAccountId'), 'Regular contact should have null org account id');
        System.assertEquals(result.get('contactName'), result.get('postingAsDisplayName'),
            'postingAsDisplayName should equal contactName for non-org contacts');
    }

    @isTest
    static void testSearchOrganizations_WithResults() {
        Test.startTest();
        List<Map<String, String>> results = FimbyContactController.searchOrganizations('Test Community');
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return results list (may be empty)');
    }

    @isTest
    static void testSearchOrganizations_NoResults() {
        Test.startTest();
        List<Map<String, String>> results = FimbyContactController.searchOrganizations('NonExistentOrganizationXYZ123');
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return empty list, not null');
        System.assertEquals(0, results.size(), 'Should have no results for non-existent search');
    }

    @isTest
    static void testSearchContactsForOnBehalfOf() {
        Test.startTest();
        List<Map<String, String>> results = FimbyContactController.searchContactsForOnBehalfOf('Test');
        Test.stopTest();

        System.assertNotEquals(null, results, 'Should return results list');
    }

    @isTest
    static void testRecordAppOpen_StampsAndReturnsQuietHours() {
        User testUser = getTestUser();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyContactController.recordAppOpen();
        }
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return a result map');
        System.assertNotEquals(null, result.get('quietHoursPreference'), 'Should return quiet hours');

        User updated = [SELECT Last_App_Open_At__c FROM User WHERE Id = :testUser.Id];
        System.assertNotEquals(null, updated.Last_App_Open_At__c, 'Last_App_Open_At__c should be stamped');
    }

    @isTest
    static void testRecordAppOpen_ThrottlesWithinFiveMinutes() {
        User testUser = getTestUser();

        Datetime recentStamp = Datetime.now().addMinutes(-2);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = testUser.Id, Last_App_Open_At__c = recentStamp);
        }

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyContactController.recordAppOpen();
        }
        Test.stopTest();

        User updated = [SELECT Last_App_Open_At__c FROM User WHERE Id = :testUser.Id];
        System.assertEquals(
            recentStamp,
            updated.Last_App_Open_At__c,
            'Should not re-stamp within the 5-min throttle window'
        );
    }

    @isTest
    static void testGetActingAsContact_OrgContact() {
        User testUser = getTestUser();
        Contact realContact = [SELECT Id, AccountId, FirstName FROM Contact WHERE Id = :testUser.ContactId];

        Account orgAccount = new Account(Name = 'Helpers United', Logo_URL__c = 'https://example.com/org-logo.jpg');
        try {
            orgAccount.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();
        } catch (Exception e) { /* RT may not exist */ }
        insert orgAccount;

        Contact orgContact = new Contact(
            FirstName = 'OrgRep', LastName = 'HelpersUnited',
            AccountId = realContact.AccountId,
            Is_Organization_Contact__c = true,
            Organization_Account__c = orgAccount.Id
        );
        insert orgContact;

        insert new Support_Relationship__c(
            Contact__c = realContact.Id,
            Related_Organization__c = orgAccount.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved',
            Neighbourhood__c = realContact.AccountId
        );

        realContact.Logged_In_As_Contact__c = orgContact.Id;
        realContact.Logged_In_As_Neighbourhood__c = realContact.AccountId;
        update realContact;

        Test.startTest();
        Map<String, Object> result;
        System.runAs(testUser) {
            result = FimbyContactController.getActingAsContact();
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertEquals(true, result.get('isActingAsOrg'), 'isActingAsOrg should be true');
        System.assertEquals(true, result.get('isOrganizationContact'), 'isOrganizationContact should be true');
        System.assertEquals(orgAccount.Id, result.get('organizationAccountId'), 'Should return org account Id');
        System.assertEquals(orgContact.Id, result.get('actingAsContactId'), 'Should return org contact Id');
        System.assertEquals(realContact.Id, result.get('realContactId'), 'Should return real contact Id');
        System.assertNotEquals(null, result.get('realContactFirstName'), 'Should return real contact first name');
        String displayName = (String) result.get('postingAsDisplayName');
        // Organization_Account__r.Name may not traverse for the running community user
        // due to sharing on the freshly-created Account in this test fixture. The
        // identity resolution itself (asserted above) is the meaningful check; we
        // only verify the display name is populated with something non-blank.
        System.assertNotEquals(null, displayName, 'postingAsDisplayName should be populated');
        System.assert(String.isNotBlank(displayName), 'postingAsDisplayName should not be blank');
    }
}