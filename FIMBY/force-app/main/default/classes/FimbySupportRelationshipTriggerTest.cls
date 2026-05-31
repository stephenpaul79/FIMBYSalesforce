@isTest
public class FimbySupportRelationshipTriggerTest {

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact helperContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        Contact subjectContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        User helperUser = FimbyTestDataFactory.createCommunityUser(helperContact.Id, null, true);
    }

    private static User getHelperUser() {
        return [SELECT Id, ContactId FROM User WHERE Email LIKE '%@testorg.com' AND IsActive = true LIMIT 1];
    }

    private static Contact getSubjectContact() {
        User u = getHelperUser();
        return [SELECT Id, AccountId FROM Contact WHERE Id != :u.ContactId LIMIT 1];
    }

    private static Account getNeighbourhood() {
        return [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' LIMIT 1];
    }

    @isTest
    static void testDuplicateGuardBlocksDuplicate() {
        User testUser = getHelperUser();
        Contact subject = getSubjectContact();
        Account nh = getNeighbourhood();

        Support_Relationship__c rel1 = new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Contact__c = subject.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id
        );
        insert rel1;

        Test.startTest();
        Boolean blocked = false;
        try {
            Support_Relationship__c rel2 = new Support_Relationship__c(
                Contact__c = testUser.ContactId,
                Related_Contact__c = subject.Id,
                Relationship_Type__c = 'Support_Person',
                Status__c = 'Pending',
                Neighbourhood__c = nh.Id
            );
            insert rel2;
        } catch (DmlException e) {
            blocked = true;
        }
        Test.stopTest();

        System.assert(blocked, 'Should block duplicate relationship for same pair/neighbourhood/type');
    }

    @isTest
    static void testAdminApprovalCreatesNotification() {
        User testUser = getHelperUser();
        Contact subject = getSubjectContact();
        Account nh = getNeighbourhood();

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Contact__c = subject.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Pending',
            Neighbourhood__c = nh.Id
        );
        insert rel;

        Integer notifCountBefore = [SELECT COUNT() FROM Notification__c WHERE Contact__c = :testUser.ContactId];

        Test.startTest();
        rel.Status__c = 'Approved';
        update rel;
        Test.stopTest();

        Integer notifCountAfter = [SELECT COUNT() FROM Notification__c WHERE Contact__c = :testUser.ContactId];
        System.assert(notifCountAfter > notifCountBefore, 'Approval should create a notification');
    }

    @isTest
    static void testRevocationEnqueuesQueueable() {
        User testUser = getHelperUser();
        Contact subject = getSubjectContact();
        Account nh = getNeighbourhood();

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Contact__c = subject.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id
        );
        insert rel;

        Contact helper = new Contact(
            Id = testUser.ContactId,
            Logged_In_As_Contact__c = subject.Id,
            Logged_In_As_Neighbourhood__c = nh.Id
        );
        update helper;

        Test.startTest();
        rel.Status__c = 'Revoked';
        update rel;
        Test.stopTest();

        Contact updatedHelper = [SELECT Logged_In_As_Contact__c FROM Contact WHERE Id = :testUser.ContactId];
        System.assertEquals(null, updatedHelper.Logged_In_As_Contact__c,
            'Revocation queueable should clear the identity override');
    }

    @isTest
    static void testAllowsDifferentTypeForSamePair() {
        User testUser = getHelperUser();
        Contact subject = getSubjectContact();
        Account nh = getNeighbourhood();

        Account orgAcct = new Account(
            Name = 'Test Org',
            RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Organization' LIMIT 1].Id
        );
        insert orgAcct;

        Support_Relationship__c rel1 = new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Contact__c = subject.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id
        );
        insert rel1;

        Test.startTest();
        Support_Relationship__c rel2 = new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Organization__c = orgAcct.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Pending',
            Neighbourhood__c = nh.Id
        );
        insert rel2;
        Test.stopTest();

        System.assertNotEquals(null, rel2.Id, 'Should allow different relationship types for the same person');
    }

    @isTest
    static void testPendingInsertCreatesModeratorTask() {
        User testUser = getHelperUser();
        Contact subject = getSubjectContact();
        Account nh = getNeighbourhood();

        Test.startTest();
        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Contact__c = subject.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Pending',
            Neighbourhood__c = nh.Id
        );
        insert rel;
        Test.stopTest();

        List<Moderator_Task__c> tasks = [
            SELECT Id, Category__c, Related_Record_Id__c
            FROM Moderator_Task__c
            WHERE Category__c = 'Support_Relationship_Approval'
              AND Related_Record_Id__c = :String.valueOf(rel.Id)
        ];
        System.assertEquals(1, tasks.size(), 'Pending support relationship should create moderator task');
    }

    @isTest
    static void testPendingCommunityGroupRepCreatesModeratorTask() {
        User testUser = getHelperUser();
        Account nh = getNeighbourhood();
        Account orgAcct = new Account(
            Name = 'Moderator Task Org',
            RecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'Organization' LIMIT 1].Id
        );
        insert orgAcct;

        Test.startTest();
        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Organization__c = orgAcct.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Pending',
            Neighbourhood__c = nh.Id
        );
        insert rel;
        Test.stopTest();

        List<Moderator_Task__c> tasks = [
            SELECT Id, Summary__c
            FROM Moderator_Task__c
            WHERE Category__c = 'Support_Relationship_Approval'
              AND Related_Record_Id__c = :String.valueOf(rel.Id)
        ];
        System.assertEquals(1, tasks.size());
        System.assert(tasks[0].Summary__c.contains('Community group'));
    }
}
