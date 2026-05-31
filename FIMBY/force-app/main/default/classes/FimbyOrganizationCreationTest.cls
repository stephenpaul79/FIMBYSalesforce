@IsTest
private class FimbyOrganizationCreationTest {

    private static final String REQUESTER_NAME = 'Org Requester Contact';

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        neighbourhood.Active__c = 'Yes';
        update neighbourhood;
        insert new Postal_Codes__c(
            Name = 'V6A 1A1',
            Neighbourhood_Account__c = neighbourhood.Id
        );
        Contact requester = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        requester.LastName = REQUESTER_NAME;
        update requester;
        FimbyTestDataFactory.createCommunityUser(requester.Id, null, true);
    }

    private static User getRequesterUser() {
        Contact requester = [
            SELECT Id FROM Contact WHERE LastName = :REQUESTER_NAME LIMIT 1
        ];
        return [SELECT Id, ContactId FROM User WHERE ContactId = :requester.Id LIMIT 1];
    }

    private static Account getNeighbourhood() {
        Contact requester = [SELECT AccountId FROM Contact WHERE LastName = :REQUESTER_NAME LIMIT 1];
        return [SELECT Id FROM Account WHERE Id = :requester.AccountId LIMIT 1];
    }

    @IsTest
    static void createOrganizationRequest_informalWithPhone() {
        User requester = getRequesterUser();
        Map<String, Object> params = new Map<String, Object>{
            'orgName' => 'Neighbourhood Mutual Aid',
            'billingPostalCode' => 'V6A 1A1',
            'orgType' => 'Mutual_Aid',
            'requesterOrgRole' => 'Coordinator',
            'isRegisteredCharity' => false,
            'orgPhone' => '6045550100',
            'authorizationImageUrl' => 'https://example.com/auth.jpg',
            'cgaAccepted' => true,
            'cgaVersion' => '1.0'
        };

        Id accountId;
        System.runAs(requester) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationRequestService.createOrganizationRequest(params);
            Test.stopTest();
            accountId = (Id) result.get('accountId');
        }

        System.assertNotEquals(null, accountId);
        Account org = [SELECT Verification_Method__c FROM Account WHERE Id = :accountId];
        System.assert(org.Verification_Method__c.contains('Phone'));
    }

    @IsTest
    static void createOrganizationRequest_fullDetailsAndEmail() {
        User requester = getRequesterUser();
        Map<String, Object> params = new Map<String, Object>{
            'orgName' => 'Full Detail Org',
            'billingStreet' => '123 Main St',
            'billingCity' => 'Vancouver',
            'billingState' => 'BC',
            'billingPostalCode' => 'V6A 1A1',
            'billingCountry' => 'Canada',
            'orgType' => 'Community_Group',
            'requesterOrgRole' => 'Coordinator',
            'isRegisteredCharity' => false,
            'orgEmail' => 'group@example.com',
            'website' => 'https://example.com/group',
            'description' => 'Neighbourhood mutual aid group',
            'authorizationImageUrl' => 'https://example.com/auth.jpg',
            'cgaAccepted' => true,
            'cgaVersion' => '1.0'
        };

        Id accountId;
        System.runAs(requester) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationRequestService.createOrganizationRequest(params);
            Test.stopTest();
            accountId = (Id) result.get('accountId');
        }

        Account org = [
            SELECT Org_Email__c, Website, Description, BillingStreet, Verification_Method__c
            FROM Account WHERE Id = :accountId
        ];
        System.assertEquals('group@example.com', org.Org_Email__c);
        System.assertEquals('https://example.com/group', org.Website);
        System.assert(org.Verification_Method__c.contains('Email'));
    }

    @IsTest
    static void uploadOrganizationVerificationDoc_returnsOkInTests() {
        User requester = getRequesterUser();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Account org = new Account(
            Name = 'Upload Target Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending'
        );
        insert org;

        System.runAs(requester) {
            Test.startTest();
            String result = FimbyOrganizationRequestService.uploadOrganizationVerificationDoc(
                'data:image/jpeg;base64,/9j/4AAQ',
                'proof.jpg',
                org.Id,
                100,
                100
            );
            Test.stopTest();
            System.assertEquals('ok', result);
        }

        org = [
            SELECT Verification_Document_URL__c
            FROM Account
            WHERE Id = :org.Id
        ];
        System.assert(org.Verification_Document_URL__c.contains('proof.jpg'), org.Verification_Document_URL__c);
    }

    @IsTest
    static void uploadOrganizationVerificationDoc_requiresFileData() {
        User requester = getRequesterUser();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Account org = new Account(
            Name = 'Upload Missing Data Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending'
        );
        insert org;

        Boolean threw = false;
        System.runAs(requester) {
            try {
                FimbyOrganizationRequestService.uploadOrganizationVerificationDoc(
                    '', 'proof.jpg', org.Id, null, null
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void createOrganizationRequest_resolvesNeighbourhoodFromPostalCode() {
        User requester = getRequesterUser();
        Account nh = getNeighbourhood();
        Map<String, Object> params = new Map<String, Object>{
            'orgName' => 'Auto Neighbourhood Org',
            'billingPostalCode' => 'V6A 1A1',
            'orgType' => 'Community_Group',
            'requesterOrgRole' => 'Coordinator',
            'isRegisteredCharity' => false,
            'orgPhone' => '6045550101',
            'authorizationImageUrl' => 'https://example.com/auth.jpg',
            'cgaAccepted' => true,
            'cgaVersion' => '1.0'
        };

        Id accountId;
        Id srId;
        System.runAs(requester) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationRequestService.createOrganizationRequest(params);
            Test.stopTest();
            accountId = (Id) result.get('accountId');
            srId = (Id) result.get('supportRelationshipId');
        }

        System.assertNotEquals(null, accountId);
        Community_Group_Neighbourhood__c junction = [
            SELECT Neighbourhood__c
            FROM Community_Group_Neighbourhood__c
            WHERE Organization__c = :accountId
            LIMIT 1
        ];
        System.assertEquals(nh.Id, junction.Neighbourhood__c);

        Support_Relationship__c sr = [
            SELECT Neighbourhood__c
            FROM Support_Relationship__c
            WHERE Id = :srId
        ];
        System.assertEquals(nh.Id, sr.Neighbourhood__c);
    }

    @IsTest
    static void createOrganizationRequest_unknownPostalCodeFails() {
        User requester = getRequesterUser();
        Map<String, Object> params = new Map<String, Object>{
            'orgName' => 'Outside FIMBY Org',
            'billingPostalCode' => 'Z9Z 9Z9',
            'orgType' => 'Community_Group',
            'requesterOrgRole' => 'Coordinator',
            'isRegisteredCharity' => false,
            'orgPhone' => '6045550101',
            'authorizationImageUrl' => 'https://example.com/auth.jpg',
            'cgaAccepted' => true
        };

        Boolean threw = false;
        System.runAs(requester) {
            try {
                FimbyOrganizationRequestService.createOrganizationRequest(params);
            } catch (AuraHandledException e) {
                threw = true;
                System.assert(
                    e.getMessage().contains('postal code'),
                    'Expected postal code error: ' + e.getMessage()
                );
            }
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void createOrganizationRequest_inactivePostalCodeFails() {
        User requester = getRequesterUser();
        Account inactive = FimbyTestDataFactory.createNeighbourhood(true);
        inactive.Active__c = 'No';
        update inactive;
        insert new Postal_Codes__c(
            Name = 'V6B 2B2',
            Neighbourhood_Account__c = inactive.Id
        );

        Map<String, Object> params = new Map<String, Object>{
            'orgName' => 'Inactive Area Org',
            'billingPostalCode' => 'V6B 2B2',
            'orgType' => 'Community_Group',
            'requesterOrgRole' => 'Coordinator',
            'isRegisteredCharity' => false,
            'orgPhone' => '6045550101',
            'authorizationImageUrl' => 'https://example.com/auth.jpg',
            'cgaAccepted' => true
        };

        Boolean threw = false;
        System.runAs(requester) {
            try {
                FimbyOrganizationRequestService.createOrganizationRequest(params);
            } catch (AuraHandledException e) {
                threw = true;
                System.assert(
                    e.getMessage().contains('isn\'t open'),
                    'Expected inactive neighbourhood error: ' + e.getMessage()
                );
            }
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void validateOrganizationRequestInputs_charityRequiresProof() {
        User requester = getRequesterUser();
        Boolean threw = false;
        System.runAs(requester) {
            try {
                FimbyOrganizationRequestService.validateOrganizationRequestInputs(
                    'Charity Org', 'V6A 1A1', 'Nonprofit', 'Director', true, true,
                    null, null, null, null, null
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void buildVerificationMethods_includesPhoneAndEmail() {
        List<String> methods = FimbyOrganizationRequestService.buildVerificationMethods(
            false, null, null, '6045550100', 'group@example.com', 'base64data'
        );
        System.assert(methods.contains('Phone'));
        System.assert(methods.contains('Email'));
        System.assert(methods.contains('Uploaded_Document'));
    }

    @IsTest
    static void createOrganizationRequest_charityPath() {
        User requester = getRequesterUser();
        Test.startTest();
        System.runAs(requester) {
            FimbyOrganizationRequestService.validateOrganizationRequestInputs(
                'New Charity Org', 'V6A 1A1', 'Nonprofit', 'Director', true, true,
                'https://www.canada.ca/en/revenue-agency/services/charities/example',
                '123456789RR0001', null, null, null
            );
            List<String> methods = FimbyOrganizationRequestService.buildVerificationMethods(
                true, 'https://www.canada.ca/example', '123456789RR0001', null, null, null
            );
            System.assert(methods.contains('CRA_URL'));
            System.assert(methods.contains('Charity_Registration_Number'));
        }
        Test.stopTest();
    }

    @IsTest
    static void createOrganizationRequest_informalRequiresVerification() {
        User requester = getRequesterUser();
        Map<String, Object> params = new Map<String, Object>{
            'orgName' => 'Informal Group',
            'billingPostalCode' => 'V6A 1A1',
            'orgType' => 'Community_Group',
            'requesterOrgRole' => 'Coordinator',
            'isRegisteredCharity' => false,
            'cgaAccepted' => true
        };

        Boolean threw = false;
        Test.startTest();
        System.runAs(requester) {
            try {
                FimbyOrganizationRequestService.createOrganizationRequest(params);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Informal group without verification should fail');
    }

    @IsTest
    static void approveOrganization_createsOrgContactAndActivatesJunction() {
        User requester = getRequesterUser();
        Account nh = getNeighbourhood();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();

        Contact modContact = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);

        Account org = new Account(
            Name = 'Approve Me Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending',
            Is_Approved_Community_Group__c = false,
            Submitted_By__c = requester.ContactId
        );
        insert org;

        insert new Community_Group_Neighbourhood__c(
            Organization__c = org.Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Inactive',
            Is_Primary__c = false
        );

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Organization_Approval',
            Priority__c = 'Standard',
            Status__c = 'New',
            Related_Record_Id__c = String.valueOf(org.Id),
            Related_Record_Type__c = 'Account',
            Summary__c = 'New organization: Approve Me Org',
            Task_Dedup_Key__c = nh.Id + ':Organization_Approval:Account:' + org.Id
        );
        insert task;

        Test.startTest();
        FimbyModeratorActionService.approveOrganization(org.Id, task.Id, modContact.Id);
        Test.stopTest();

        Account updated = [
            SELECT Is_Approved_Community_Group__c, Verification_Status__c, Organization_Contact__c
            FROM Account WHERE Id = :org.Id
        ];
        System.assertEquals(true, updated.Is_Approved_Community_Group__c);
        System.assertEquals('Verified', updated.Verification_Status__c);
        System.assertNotEquals(null, updated.Organization_Contact__c);

        Contact orgContact = [
            SELECT Is_Organization_Contact__c, Organization_Account__c
            FROM Contact WHERE Id = :updated.Organization_Contact__c
        ];
        System.assertEquals(true, orgContact.Is_Organization_Contact__c);
        System.assertEquals(org.Id, orgContact.Organization_Account__c);

        Community_Group_Neighbourhood__c junction = [
            SELECT Status__c FROM Community_Group_Neighbourhood__c
            WHERE Organization__c = :org.Id LIMIT 1
        ];
        System.assertEquals('Active', junction.Status__c);
    }

    @IsTest
    static void approveSupportRelationship_blocksUnverifiedOrgRep() {
        User requester = getRequesterUser();
        Account nh = getNeighbourhood();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Contact modContact = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);

        Account org = new Account(
            Name = 'Unverified Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending',
            Is_Approved_Community_Group__c = false
        );
        insert org;

        Support_Relationship__c sr = new Support_Relationship__c(
            Contact__c = requester.ContactId,
            Related_Organization__c = org.Id,
            Neighbourhood__c = nh.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Pending'
        );
        insert sr;

        Boolean threw = false;
        Test.startTest();
        try {
            FimbyModeratorActionService.approveSupportRelationship(sr.Id, null, modContact.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void approveSupportRelationship_blocksRepWhenOrgPendingDespiteLegacyApprovedFlag() {
        User requester = getRequesterUser();
        Account nh = getNeighbourhood();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Contact modContact = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);

        Account org = new Account(
            Name = 'Legacy Flag Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending',
            Is_Approved_Community_Group__c = true
        );
        insert org;

        Support_Relationship__c sr = new Support_Relationship__c(
            Contact__c = requester.ContactId,
            Related_Organization__c = org.Id,
            Neighbourhood__c = nh.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Pending'
        );
        insert sr;

        Boolean threw = false;
        Test.startTest();
        try {
            FimbyModeratorActionService.approveSupportRelationship(sr.Id, null, modContact.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw);
    }

    @IsTest
    static void rejectOrganization_marksRejectedAndDeclinesRep() {
        User requester = getRequesterUser();
        Account nh = getNeighbourhood();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Contact modContact = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);

        Account org = new Account(
            Name = 'Reject Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending',
            Submitted_By__c = requester.ContactId
        );
        insert org;

        Support_Relationship__c sr = new Support_Relationship__c(
            Contact__c = requester.ContactId,
            Related_Organization__c = org.Id,
            Neighbourhood__c = nh.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Pending'
        );
        insert sr;

        Test.startTest();
        FimbyModeratorActionService.rejectOrganization(org.Id, 'Other', 'Unable to verify', null, modContact.Id);
        Test.stopTest();

        Account updated = [SELECT Verification_Status__c FROM Account WHERE Id = :org.Id];
        System.assertEquals('Rejected', updated.Verification_Status__c);

        Support_Relationship__c updatedSr = [SELECT Status__c FROM Support_Relationship__c WHERE Id = :sr.Id];
        System.assertEquals('Declined', updatedSr.Status__c);
    }

    @IsTest
    static void searchOrganizations_excludesUnapprovedOrg() {
        User requester = getRequesterUser();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        insert new Account(
            Name = 'Hidden Pending Org',
            RecordTypeId = orgRtId,
            Is_Approved_Community_Group__c = false,
            Verification_Status__c = 'Pending'
        );

        Test.startTest();
        List<Map<String, String>> results;
        System.runAs(requester) {
            results = FimbyContactController.searchOrganizations('Hidden Pending');
        }
        Test.stopTest();
        System.assertEquals(0, results.size());
    }

    @IsTest
    static void stalenessJob_executesWithoutError() {
        Test.startTest();
        new FimbyModeratorTaskStalenessJob().execute(null);
        Test.stopTest();
        System.assert(true);
    }
}
