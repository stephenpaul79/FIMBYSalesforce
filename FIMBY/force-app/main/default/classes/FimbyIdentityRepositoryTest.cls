@isTest
public class FimbyIdentityRepositoryTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact testContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User testUser = FimbyTestDataFactory.createCommunityUser(testContact.Id, null, true);
    }

    private static User getTestUser() {
        return [SELECT Id, ContactId FROM User WHERE Email LIKE '%@testorg.com' AND IsActive = true LIMIT 1];
    }

    @isTest
    static void testGetCurrentUser() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            FimbyIdentityRepository.clearCache();

            Test.startTest();
            User result = FimbyIdentityRepository.getCurrentUser();
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return a User');
            System.assertEquals(testUser.Id, result.Id, 'Should return the running user');
            System.assertNotEquals(null, result.ContactId, 'User should have a ContactId');
        }
    }

    @isTest
    static void testGetCurrentUserCaching() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            FimbyIdentityRepository.clearCache();

            Test.startTest();
            User first = FimbyIdentityRepository.getCurrentUser();
            User second = FimbyIdentityRepository.getCurrentUser();
            Test.stopTest();

            System.assert(first === second, 'Subsequent calls should return the same cached instance');
        }
    }

    @isTest
    static void testGetActingAsContactId() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            FimbyIdentityRepository.clearCache();

            Test.startTest();
            Id actingAsId = FimbyIdentityRepository.getActingAsContactId();
            Test.stopTest();

            System.assertNotEquals(null, actingAsId, 'Should resolve an acting-as Contact Id');
        }
    }

    @isTest
    static void testGetActingAsContactIdWithApprovedRelationship() {
        User testUser = getTestUser();
        Contact c = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId];

        Account otherNeighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact otherContact = FimbyTestDataFactory.createNeighbourhoodContact(otherNeighbourhood.Id, true);

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = c.Id,
            Related_Contact__c = otherContact.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = otherNeighbourhood.Id
        );
        insert rel;

        c.Logged_In_As_Contact__c = otherContact.Id;
        c.Logged_In_As_Neighbourhood__c = otherNeighbourhood.Id;
        update c;

        System.runAs(testUser) {
            FimbyIdentityRepository.clearCache();

            Test.startTest();
            Id actingAsId = FimbyIdentityRepository.getActingAsContactId();
            Test.stopTest();

            System.assertEquals(otherContact.Id, actingAsId,
                'Should return Logged_In_As_Contact__c when backed by an approved relationship');
        }
    }

    @isTest
    static void testGetActingAsContactIdClearsStaleOverride() {
        User testUser = getTestUser();
        Contact c = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId];

        Account otherNeighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact otherContact = FimbyTestDataFactory.createNeighbourhoodContact(otherNeighbourhood.Id, true);

        c.Logged_In_As_Contact__c = otherContact.Id;
        c.Logged_In_As_Neighbourhood__c = otherNeighbourhood.Id;
        update c;

        System.runAs(testUser) {
            FimbyIdentityRepository.clearCache();

            Test.startTest();
            Id actingAsId = FimbyIdentityRepository.getActingAsContactId();
            Test.stopTest();

            System.assertEquals(testUser.ContactId, actingAsId,
                'Should fall back to self when no approved relationship backs the override');
        }
    }

    @isTest
    static void testGetNeighbourhoodIdWithOverride() {
        User testUser = getTestUser();
        Contact c = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId];

        Account otherNeighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        c.Logged_In_As_Neighbourhood__c = otherNeighbourhood.Id;
        update c;

        System.runAs(testUser) {
            FimbyIdentityRepository.clearCache();

            Test.startTest();
            Id nhId = FimbyIdentityRepository.getNeighbourhoodId();
            Test.stopTest();

            System.assertEquals(otherNeighbourhood.Id, nhId,
                'Should return the Logged_In_As_Neighbourhood__c override');
        }
    }

    @isTest
    static void testGetCurrentContact() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            FimbyIdentityRepository.clearCache();

            Test.startTest();
            Contact result = FimbyIdentityRepository.getCurrentContact();
            Test.stopTest();

            System.assertNotEquals(null, result, 'Should return the user Contact');
            System.assertEquals(testUser.ContactId, result.Id, 'Should be the correct Contact');
        }
    }

    @isTest
    static void testGetNeighbourhoodId() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            FimbyIdentityRepository.clearCache();

            Test.startTest();
            Id nhId = FimbyIdentityRepository.getNeighbourhoodId();
            Test.stopTest();

            System.assertNotEquals(null, nhId, 'Should return a neighbourhood (Account) Id');
        }
    }

    @isTest
    static void testGetIdentity() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            FimbyIdentityRepository.clearCache();

            Test.startTest();
            FimbyIdentityRepository.Identity ident = FimbyIdentityRepository.getIdentity();
            Test.stopTest();

            System.assertNotEquals(null, ident.currentUser, 'Identity should include User');
            System.assertNotEquals(null, ident.contact, 'Identity should include Contact');
            System.assertNotEquals(null, ident.actingAsContactId, 'Identity should include actingAsContactId');
            System.assertNotEquals(null, ident.neighbourhoodId, 'Identity should include neighbourhoodId');
        }
    }

    @isTest
    static void testClearCache() {
        User testUser = getTestUser();
        System.runAs(testUser) {
            FimbyIdentityRepository.getCurrentUser();
            FimbyIdentityRepository.clearCache();

            Test.startTest();
            User fresh = FimbyIdentityRepository.getCurrentUser();
            Test.stopTest();

            System.assertNotEquals(null, fresh, 'Should re-query after cache clear');
        }
    }

    @isTest
    static void testBuildOrgDisplayName() {
        System.assertEquals('Acme Corp (Jane)', FimbyIdentityRepository.buildOrgDisplayName('Acme Corp', 'Jane'));
        System.assertEquals('Acme Corp', FimbyIdentityRepository.buildOrgDisplayName('Acme Corp', null));
        System.assertEquals('Acme Corp', FimbyIdentityRepository.buildOrgDisplayName('Acme Corp', ''));
        System.assertEquals('Jane', FimbyIdentityRepository.buildOrgDisplayName(null, 'Jane'));
        System.assertEquals('Jane', FimbyIdentityRepository.buildOrgDisplayName('', 'Jane'));
        System.assertEquals(null, FimbyIdentityRepository.buildOrgDisplayName(null, null));
    }

    @isTest
    static void testGetIdentityWithOrgContact() {
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

        System.runAs(testUser) {
            FimbyIdentityRepository.clearCache();

            Test.startTest();
            FimbyIdentityRepository.Identity ident = FimbyIdentityRepository.getIdentity();
            Test.stopTest();

            System.assertEquals(true, ident.isOrgContact, 'Should identify as org contact');
            System.assertEquals(orgContact.Id, ident.actingAsContactId, 'Acting-as should be org contact');
            System.assertNotEquals(null, ident.actingAsContact, 'Should have acting-as contact record');
            System.assertEquals(
                'Helpers United (' + realContact.FirstName + ')',
                ident.orgDisplayName,
                'orgDisplayName should be "OrgName (RealFirstName)"'
            );
            System.assertEquals('https://example.com/org-logo.jpg', ident.orgAvatarUrl,
                'orgAvatarUrl should be org logo');
        }
    }
}
