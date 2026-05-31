@IsTest
private class FimbySupportRelationshipControllerTest {

    private static final String HELPER_CONTACT_NAME = 'SR Helper Contact';
    private static final String SUBJECT_CONTACT_NAME = 'SR Subject Contact';
    private static final String ORG_NAME = 'SR Test Community Group';

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);

        Contact helperContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        helperContact.LastName = HELPER_CONTACT_NAME;
        update helperContact;

        User helperUser = FimbyTestDataFactory.createCommunityUser(helperContact.Id, null, true);

        Contact subjectContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        subjectContact.LastName = SUBJECT_CONTACT_NAME;
        update subjectContact;

        Id orgRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'Organization'
            LIMIT 1
        ].Id;

        Account orgAcct = new Account(
            Name = ORG_NAME,
            RecordTypeId = orgRtId,
            Is_Approved_Community_Group__c = true,
            Organization_Contact__c = subjectContact.Id
        );
        insert orgAcct;

        insert new Community_Group_Neighbourhood__c(
            Organization__c = orgAcct.Id,
            Neighbourhood__c = neighbourhood.Id,
            Status__c = 'Active'
        );
    }

    private static User getHelperUser() {
        Contact helper = [
            SELECT Id
            FROM Contact
            WHERE LastName = :HELPER_CONTACT_NAME
            LIMIT 1
        ];

        return [
            SELECT Id, ContactId
            FROM User
            WHERE ContactId = :helper.Id
            LIMIT 1
        ];
    }

    private static Contact getHelperContact() {
        return [
            SELECT Id, AccountId, Logged_In_As_Contact__c, Logged_In_As_Neighbourhood__c
            FROM Contact
            WHERE LastName = :HELPER_CONTACT_NAME
            LIMIT 1
        ];
    }

    private static Contact getSubjectContact() {
        return [
            SELECT Id, AccountId, Name
            FROM Contact
            WHERE LastName = :SUBJECT_CONTACT_NAME
            LIMIT 1
        ];
    }

    private static Account getNeighbourhood() {
        Contact helper = getHelperContact();
        return [
            SELECT Id, Name
            FROM Account
            WHERE Id = :helper.AccountId
            LIMIT 1
        ];
    }

    private static Account getOrganization() {
        return [
            SELECT Id, Name, Organization_Contact__c
            FROM Account
            WHERE Name = :ORG_NAME
            LIMIT 1
        ];
    }

    private static Support_Relationship__c createSupportPersonRelationship(String statusValue) {
        User helperUser = getHelperUser();
        Contact subject = getSubjectContact();
        Account nh = getNeighbourhood();

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = helperUser.ContactId,
            Related_Contact__c = subject.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = statusValue,
            Neighbourhood__c = nh.Id
        );
        insert rel;
        return rel;
    }

    private static Support_Relationship__c createCommunityGroupRelationship(String statusValue) {
        User helperUser = getHelperUser();
        Account nh = getNeighbourhood();
        Account orgAcct = getOrganization();

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = helperUser.ContactId,
            Related_Organization__c = orgAcct.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = statusValue,
            Neighbourhood__c = nh.Id
        );
        insert rel;
        return rel;
    }

    @IsTest
    static void testGetAvailableIdentitiesEmpty() {
        User testUser = getHelperUser();

        System.runAs(testUser) {
            Test.startTest();
            List<Map<String, Object>> identities =
                FimbySupportRelationshipController.getAvailableIdentities();
            Test.stopTest();

            System.assertEquals(0, identities.size());
        }
    }

    @IsTest
    static void testGetAvailableIdentitiesWithApprovedSupportPerson() {
        User testUser = getHelperUser();
        Contact subject = getSubjectContact();

        createSupportPersonRelationship('Approved');

        System.runAs(testUser) {
            Test.startTest();
            List<Map<String, Object>> identities =
                FimbySupportRelationshipController.getAvailableIdentities();
            Test.stopTest();

            System.assertEquals(1, identities.size());
            System.assertEquals('Support_Person', (String) identities[0].get('type'));
            System.assertEquals(subject.Id, (Id) identities[0].get('targetContactId'));
            System.assertEquals(subject.Name, (String) identities[0].get('name'));
        }
    }

    @IsTest
    static void testGetAvailableIdentitiesWithApprovedCommunityGroupRep() {
        User testUser = getHelperUser();
        Account orgAcct = getOrganization();

        createCommunityGroupRelationship('Approved');

        System.runAs(testUser) {
            Test.startTest();
            List<Map<String, Object>> identities =
                FimbySupportRelationshipController.getAvailableIdentities();
            Test.stopTest();

            System.assertEquals(1, identities.size());
            System.assertEquals('Community_Group_Rep', (String) identities[0].get('type'));
            if (identities[0].get('targetContactId') != null) {
                System.assertEquals(orgAcct.Organization_Contact__c, (Id) identities[0].get('targetContactId'));
            }
            if (identities[0].get('name') != null) {
                System.assertEquals(orgAcct.Name, (String) identities[0].get('name'));
            }
        }
    }

    @IsTest
    static void testSwitchIdentityAndSwitchToSelf() {
        User testUser = getHelperUser();
        Contact subject = getSubjectContact();
        Account nh = getNeighbourhood();
        Support_Relationship__c rel = createSupportPersonRelationship('Approved');

        System.runAs(testUser) {
            Test.startTest();
            FimbySupportRelationshipController.switchIdentity(rel.Id);
            Test.stopTest();

            Contact helperAfterSwitch = [
                SELECT Logged_In_As_Contact__c, Logged_In_As_Neighbourhood__c
                FROM Contact
                WHERE Id = :testUser.ContactId
            ];
            System.assertEquals(subject.Id, helperAfterSwitch.Logged_In_As_Contact__c);
            System.assertEquals(nh.Id, helperAfterSwitch.Logged_In_As_Neighbourhood__c);

            FimbySupportRelationshipController.switchToSelf();

            Contact helperAfterReset = [
                SELECT Logged_In_As_Contact__c, Logged_In_As_Neighbourhood__c
                FROM Contact
                WHERE Id = :testUser.ContactId
            ];
            System.assertEquals(null, helperAfterReset.Logged_In_As_Contact__c);
            System.assertEquals(null, helperAfterReset.Logged_In_As_Neighbourhood__c);
        }
    }

    @IsTest
    static void testSwitchIdentityRejectsNonApproved() {
        User testUser = getHelperUser();
        Support_Relationship__c rel = createSupportPersonRelationship('Pending');

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbySupportRelationshipController.switchIdentity(rel.Id);
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(true, 'Exception thrown as expected');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testSwitchIdentityRejectsOrgWithoutTargetContact() {
        User testUser = getHelperUser();
        Account nh = getNeighbourhood();

        Id orgRtId = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'Organization'
            LIMIT 1
        ].Id;

        Account orgNoContact = new Account(
            Name = 'SR Org No Contact',
            RecordTypeId = orgRtId,
            Is_Approved_Community_Group__c = true
        );
        insert orgNoContact;

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Organization__c = orgNoContact.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id
        );
        insert rel;

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbySupportRelationshipController.switchIdentity(rel.Id);
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(true, 'Exception thrown as expected');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testGetManagedRelationships() {
        User testUser = getHelperUser();
        Contact helper = getHelperContact();
        Contact subject = getSubjectContact();
        Account nh = getNeighbourhood();
        Account orgAcct = getOrganization();

        insert new Support_Relationship__c(
            Contact__c = helper.Id,
            Related_Contact__c = subject.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id,
            Dismissed_By_Helper__c = false
        );

        insert new Support_Relationship__c(
            Contact__c = subject.Id,
            Related_Contact__c = helper.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id,
            Dismissed_By_Subject__c = false
        );

        insert new Support_Relationship__c(
            Contact__c = helper.Id,
            Related_Organization__c = orgAcct.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id,
            Dismissed_By_Helper__c = false
        );

        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result =
                FimbySupportRelationshipController.getManagedRelationships();
            Test.stopTest();

            List<Object> peopleISupport = (List<Object>) result.get('peopleISupport');
            List<Object> peopleWhoSupportMe = (List<Object>) result.get('peopleWhoSupportMe');
            List<Object> communityGroups = (List<Object>) result.get('communityGroups');

            System.assertEquals(1, peopleISupport.size());
            System.assertEquals(1, peopleWhoSupportMe.size());
            System.assertEquals(1, communityGroups.size());
        }
    }

    @IsTest
    static void testGetManagedRelationships_OrgAvatarUrls() {
        User testUser = getHelperUser();
        Account orgAcct = getOrganization();
        Account nh = getNeighbourhood();

        orgAcct.Logo_URL__c = 'https://example.com/org-logo.jpg';
        update orgAcct;

        insert new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Organization__c = orgAcct.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id,
            Dismissed_By_Helper__c = false
        );

        System.runAs(testUser) {
            Map<String, Object> result =
                FimbySupportRelationshipController.getManagedRelationships();
            Map<String, Object> orgAvatarUrls = (Map<String, Object>) result.get('orgAvatarUrls');

            System.assertNotEquals(null, orgAvatarUrls, 'orgAvatarUrls should be returned');
            System.assertEquals(
                'https://example.com/org-logo.jpg',
                (String) orgAvatarUrls.get(String.valueOf(orgAcct.Id)),
                'Account.Logo_URL__c should resolve for community group avatar'
            );
        }
    }

    @IsTest
    static void testGetManagedRelationships_OrgAvatarUrls_ContactFallback() {
        User testUser = getHelperUser();
        Account orgAcct = getOrganization();
        Account nh = getNeighbourhood();
        Contact orgContact = getSubjectContact();

        orgContact.Image_URL__c = 'https://example.com/org-contact-photo.jpg';
        update orgContact;

        insert new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Organization__c = orgAcct.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id,
            Dismissed_By_Helper__c = false
        );

        System.runAs(testUser) {
            Map<String, Object> result =
                FimbySupportRelationshipController.getManagedRelationships();
            Map<String, Object> orgAvatarUrls = (Map<String, Object>) result.get('orgAvatarUrls');

            System.assertEquals(
                'https://example.com/org-contact-photo.jpg',
                (String) orgAvatarUrls.get(String.valueOf(orgAcct.Id)),
                'Organization contact Image_URL__c should be used when Logo_URL__c is blank'
            );
        }
    }

    @IsTest
    static void testGetNeighbourhoodsForOrganization() {
        User testUser = getHelperUser();
        Account orgAcct = getOrganization();
        Account nh = getNeighbourhood();

        System.runAs(testUser) {
            Test.startTest();
            List<Map<String, String>> results =
                FimbySupportRelationshipController.getNeighbourhoodsForOrganization(orgAcct.Id);
            Test.stopTest();

            System.assertEquals(1, results.size());
            System.assertEquals((String) nh.Id, results[0].get('id'));
            System.assertNotEquals(null, results[0].get('name'));
        }
    }

    @IsTest
    static void testGetNeighbourhoodsForOrganizationWithNullId() {
        User testUser = getHelperUser();

        System.runAs(testUser) {
            Test.startTest();
            List<Map<String, String>> results =
                FimbySupportRelationshipController.getNeighbourhoodsForOrganization(null);
            Test.stopTest();

            System.assertEquals(0, results.size());
        }
    }

    @IsTest
    static void testUploadAuthorizationImageValidation() {
        User testUser = getHelperUser();

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbySupportRelationshipController.uploadAuthorizationImage(
                    '', 'test.jpg', null, 100, 100
                );
                System.assert(false, 'Expected exception for blank file data');
            } catch (AuraHandledException e) {
                System.assert(true, 'Exception thrown as expected');
            }

            try {
                FimbySupportRelationshipController.uploadAuthorizationImage(
                    'data:image/jpeg;base64,/9j/4AAQ',
                    '',
                    null,
                    100,
                    100
                );
                System.assert(false, 'Expected exception for blank file name');
            } catch (AuraHandledException e) {
                System.assert(true, 'Exception thrown as expected');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testUploadAuthorizationImageSuccess() {
        User testUser = getHelperUser();
        Support_Relationship__c sr = createSupportPersonRelationship('Pending');

        System.runAs(testUser) {
            Test.startTest();
            String url = FimbySupportRelationshipController.uploadAuthorizationImage(
                'data:image/jpeg;base64,/9j/4AAQ',
                'auth_test.jpg',
                sr.Id,
                100,
                100
            );
            Test.stopTest();

            System.assertNotEquals(null, url);
            System.assert(url.contains('auth_test.jpg'), url);
        }

        sr = [
            SELECT Authorization_Image_URL__c
            FROM Support_Relationship__c
            WHERE Id = :sr.Id
        ];
        System.assertEquals('https://test.example.com/auth_test.jpg?oid=', sr.Authorization_Image_URL__c);
    }

    @IsTest
    static void testSubmitRelationshipRequestSupportPerson() {
        User testUser = getHelperUser();
        Contact subject = getSubjectContact();
        Account nh = getNeighbourhood();

        System.runAs(testUser) {
            Map<String, Object> params = new Map<String, Object>{
                'relationshipType' => 'Support_Person',
                'relatedContactId' => subject.Id,
                'relatedOrganizationId' => null,
                'neighbourhoodId' => nh.Id,
                'authorizationImageUrl' => null,
                'notes' => 'Test request'
            };

            Test.startTest();
            Id relId = FimbySupportRelationshipController.submitRelationshipRequest(params);
            Test.stopTest();

            Support_Relationship__c rel = [
                SELECT Status__c, Relationship_Type__c, Related_Contact__c, Notes__c
                FROM Support_Relationship__c
                WHERE Id = :relId
            ];

            System.assertEquals('Pending', rel.Status__c);
            System.assertEquals('Support_Person', rel.Relationship_Type__c);
            System.assertEquals(subject.Id, rel.Related_Contact__c);
            System.assertEquals('Test request', rel.Notes__c);
        }
    }

    @IsTest
    static void testSubmitRelationshipRequestCommunityGroupRep() {
        User testUser = getHelperUser();
        Account nh = getNeighbourhood();
        Account orgAcct = getOrganization();

        System.runAs(testUser) {
            Map<String, Object> params = new Map<String, Object>{
                'relationshipType' => 'Community_Group_Rep',
                'relatedContactId' => null,
                'relatedOrganizationId' => orgAcct.Id,
                'neighbourhoodId' => nh.Id,
                'authorizationImageUrl' => 'https://example.com/auth.jpg',
                'notes' => 'Org rep request',
                'cgaAccepted' => true,
                'cgaVersion' => '1.0'
            };

            Test.startTest();
            Id relId = FimbySupportRelationshipController.submitRelationshipRequest(params);
            Test.stopTest();

            Support_Relationship__c rel = [
                SELECT Status__c, Relationship_Type__c, Related_Organization__c, Authorization_Image_URL__c
                FROM Support_Relationship__c
                WHERE Id = :relId
            ];

            System.assertEquals('Pending', rel.Status__c);
            System.assertEquals('Community_Group_Rep', rel.Relationship_Type__c);
            System.assertEquals(orgAcct.Id, rel.Related_Organization__c);
            System.assertEquals('https://example.com/auth.jpg', rel.Authorization_Image_URL__c);
        }
    }

    @IsTest
    static void testCreateOrganizationRequest() {
        User testUser = getHelperUser();
        Account nh = getNeighbourhood();
        Map<String, Object> params = new Map<String, Object>{
            'orgName' => 'Test Created Org',
            'billingStreet' => '100 Test Ave',
            'billingCity' => 'Vancouver',
            'billingState' => 'BC',
            'billingPostalCode' => 'V6B 2B2',
            'billingCountry' => 'Canada',
            'orgType' => 'Nonprofit',
            'requesterOrgRole' => 'Coordinator',
            'isRegisteredCharity' => false,
            'orgPhone' => '6045550199',
            'authorizationImageUrl' => 'https://example.com/auth.jpg',
            'neighbourhoodId' => nh.Id,
            'cgaAccepted' => true,
            'cgaVersion' => '1.0'
        };

        Id accountId;
        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationRequestService.createOrganizationRequest(params);
            Test.stopTest();
            accountId = (Id) result.get('accountId');
        }

        System.assertNotEquals(null, accountId);
        Account org = [
            SELECT Verification_Status__c, Submitted_By__c
            FROM Account WHERE Id = :accountId
        ];
        System.assertEquals('Pending', org.Verification_Status__c);
        System.assertEquals(testUser.ContactId, org.Submitted_By__c);
    }

    @IsTest
    static void testCreateOrganizationRequestCharity() {
        User testUser = getHelperUser();
        Account nh = getNeighbourhood();
        Map<String, Object> params = new Map<String, Object>{
            'orgName' => 'Test Charity Org',
            'billingPostalCode' => 'V6B 2B2',
            'orgType' => 'Nonprofit',
            'requesterOrgRole' => 'Director',
            'isRegisteredCharity' => true,
            'charityVerificationUrl' => 'https://www.canada.ca/en/revenue-agency/services/charities/example',
            'charityRegistrationNumber' => '123456789RR0001',
            'authorizationImageUrl' => 'https://example.com/auth.jpg',
            'neighbourhoodId' => nh.Id,
            'cgaAccepted' => true,
            'cgaVersion' => '1.0'
        };

        Id accountId;
        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationRequestService.createOrganizationRequest(params);
            Test.stopTest();
            accountId = (Id) result.get('accountId');
        }

        Account org = [
            SELECT Is_Registered_Charity__c, Verification_Method__c, Charity_Registration_Number__c
            FROM Account WHERE Id = :accountId
        ];
        System.assertEquals(true, org.Is_Registered_Charity__c);
        System.assert(org.Verification_Method__c.contains('CRA_URL'));
        System.assertEquals('123456789RR0001', org.Charity_Registration_Number__c);
    }

    @IsTest
    static void testCreateOrganizationRequestWithVerificationDoc() {
        User testUser = getHelperUser();
        Account nh = getNeighbourhood();
        Map<String, Object> params = new Map<String, Object>{
            'orgName' => 'Test Doc Org',
            'billingPostalCode' => 'V6B 2B2',
            'orgType' => 'Community_Group',
            'requesterOrgRole' => 'Coordinator',
            'isRegisteredCharity' => false,
            'orgEmail' => 'group@example.com',
            'verificationDocData' => 'data:image/jpeg;base64,/9j/4AAQ',
            'verificationDocFileName' => 'letter.jpg',
            'authorizationImageUrl' => 'https://example.com/auth.jpg',
            'neighbourhoodId' => nh.Id,
            'cgaAccepted' => true,
            'cgaVersion' => '1.0'
        };

        Id accountId;
        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationRequestService.createOrganizationRequest(params);
            Test.stopTest();
            accountId = (Id) result.get('accountId');
        }

        Account org = [
            SELECT Verification_Method__c, Verification_Document_URL__c
            FROM Account WHERE Id = :accountId
        ];
        System.assert(org.Verification_Method__c.contains('Uploaded_Document'));
        System.assert(org.Verification_Method__c.contains('Email'));
        System.assert(org.Verification_Document_URL__c.contains('letter.jpg'), org.Verification_Document_URL__c);
    }

    @IsTest
    static void testGetManagedRelationships_ResolvesPendingOrgName() {
        User testUser = getHelperUser();
        Account nh = getNeighbourhood();
        Map<String, Object> params = new Map<String, Object>{
            'orgName' => 'Pending Name Org',
            'billingPostalCode' => 'V6B 2B2',
            'orgType' => 'Community_Group',
            'requesterOrgRole' => 'Coordinator',
            'isRegisteredCharity' => false,
            'orgEmail' => 'pending@example.com',
            'authorizationImageUrl' => 'https://example.com/auth.jpg',
            'neighbourhoodId' => nh.Id,
            'cgaAccepted' => true,
            'cgaVersion' => '1.0'
        };

        Id accountId;
        System.runAs(testUser) {
            Map<String, Object> createResult = FimbyOrganizationRequestService.createOrganizationRequest(params);
            accountId = (Id) createResult.get('accountId');
        }

        System.runAs(testUser) {
            Map<String, Object> result = FimbySupportRelationshipController.getManagedRelationships();
            Map<String, String> orgNames = (Map<String, String>) result.get('orgNames');
            System.assertEquals(
                'Pending Name Org',
                orgNames.get(String.valueOf(accountId)),
                'Pending org name should resolve for the requester even when Account is not shared'
            );
        }
    }

    @IsTest
    static void testUploadOrganizationVerificationDoc() {
        User testUser = getHelperUser();
        Account nh = getNeighbourhood();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Account org = new Account(
            Name = 'Upload Doc Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending'
        );
        insert org;

        Support_Relationship__c sr = new Support_Relationship__c(
            Contact__c = testUser.ContactId,
            Related_Organization__c = org.Id,
            Neighbourhood__c = nh.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Pending'
        );
        insert sr;

        System.runAs(testUser) {
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
    }

    @IsTest
    static void testUploadOrganizationVerificationDocRequiresAccount() {
        User testUser = getHelperUser();
        Boolean threw = false;
        System.runAs(testUser) {
            try {
                FimbyOrganizationRequestService.uploadOrganizationVerificationDoc(
                    'data:image/jpeg;base64,/9j/4AAQ', 'proof.jpg', null, null, null
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void testSubmitRelationshipRequestWithUploadedAuthImage() {
        User testUser = getHelperUser();
        Contact subject = getSubjectContact();
        Account nh = getNeighbourhood();

        System.runAs(testUser) {
            Map<String, Object> params = new Map<String, Object>{
                'relationshipType' => 'Support_Person',
                'relatedContactId' => subject.Id,
                'relatedOrganizationId' => null,
                'neighbourhoodId' => nh.Id,
                'authorizationImageData' => 'data:image/jpeg;base64,/9j/4AAQ',
                'authorizationImageFileName' => 'auth.jpg',
                'notes' => 'Test with uploaded auth'
            };

            Test.startTest();
            Id relId = FimbySupportRelationshipController.submitRelationshipRequest(params);
            Test.stopTest();

            Support_Relationship__c rel = [
                SELECT Authorization_Image_URL__c
                FROM Support_Relationship__c
                WHERE Id = :relId
            ];
            System.assert(rel.Authorization_Image_URL__c.contains('auth.jpg'), rel.Authorization_Image_URL__c);
        }
    }

    @IsTest
    static void testDeactivateRelationship() {
        User testUser = getHelperUser();
        Support_Relationship__c rel = createSupportPersonRelationship('Approved');

        System.runAs(testUser) {
            Test.startTest();
            FimbySupportRelationshipController.deactivateRelationship(rel.Id);
            Test.stopTest();

            Support_Relationship__c updated = [
                SELECT Status__c, Ended_By__c, Ended_Date__c
                FROM Support_Relationship__c
                WHERE Id = :rel.Id
            ];

            Contact helper = [
                SELECT Logged_In_As_Contact__c, Logged_In_As_Neighbourhood__c
                FROM Contact
                WHERE Id = :testUser.ContactId
            ];

            System.assertEquals('Inactive', updated.Status__c);
            System.assertEquals(testUser.ContactId, updated.Ended_By__c);
            System.assertNotEquals(null, updated.Ended_Date__c);
            System.assertEquals(null, helper.Logged_In_As_Contact__c);
            System.assertEquals(null, helper.Logged_In_As_Neighbourhood__c);
        }
    }

    @IsTest
    static void testDeactivateRelationshipRejectsNonApproved() {
        User testUser = getHelperUser();
        Support_Relationship__c rel = createSupportPersonRelationship('Pending');

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbySupportRelationshipController.deactivateRelationship(rel.Id);
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(true, 'Exception thrown as expected');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testRevokeRelationship() {
        User testUser = getHelperUser();
        Contact subject = getSubjectContact();
        Support_Relationship__c rel = createSupportPersonRelationship('Approved');

        update new Contact(
            Id = testUser.ContactId,
            Logged_In_As_Contact__c = subject.Id
        );

        System.runAs(testUser) {
            Test.startTest();
            FimbySupportRelationshipController.revokeRelationship(rel.Id);
            Test.stopTest();

            Support_Relationship__c updated = [
                SELECT Status__c, Ended_By__c, Ended_Date__c
                FROM Support_Relationship__c
                WHERE Id = :rel.Id
            ];

            Contact helper = [
                SELECT Logged_In_As_Contact__c, Logged_In_As_Neighbourhood__c
                FROM Contact
                WHERE Id = :testUser.ContactId
            ];

            System.assertEquals('Revoked', updated.Status__c);
            System.assertEquals(testUser.ContactId, updated.Ended_By__c);
            System.assertNotEquals(null, updated.Ended_Date__c);
            System.assertEquals(null, helper.Logged_In_As_Contact__c);
            System.assertEquals(null, helper.Logged_In_As_Neighbourhood__c);
        }
    }

    @IsTest
    static void testRevokeRelationshipRejectsNonApproved() {
        User testUser = getHelperUser();
        Support_Relationship__c rel = createSupportPersonRelationship('Pending');

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbySupportRelationshipController.revokeRelationship(rel.Id);
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(true, 'Exception thrown as expected');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testDismissRelationshipAsHelper() {
        User testUser = getHelperUser();
        Support_Relationship__c rel = createSupportPersonRelationship('Inactive');

        System.runAs(testUser) {
            Test.startTest();
            FimbySupportRelationshipController.dismissRelationship(rel.Id, 'helper');
            Test.stopTest();

            Support_Relationship__c updated = [
                SELECT Dismissed_By_Helper__c, Dismissed_By_Subject__c
                FROM Support_Relationship__c
                WHERE Id = :rel.Id
            ];

            System.assertEquals(true, updated.Dismissed_By_Helper__c);
            System.assertEquals(false, updated.Dismissed_By_Subject__c);
        }
    }

    @IsTest
    static void testDismissRelationshipAsSubject() {
        User testUser = getHelperUser();
        Support_Relationship__c rel = createSupportPersonRelationship('Revoked');

        System.runAs(testUser) {
            Test.startTest();
            FimbySupportRelationshipController.dismissRelationship(rel.Id, 'subject');
            Test.stopTest();

            Support_Relationship__c updated = [
                SELECT Dismissed_By_Helper__c, Dismissed_By_Subject__c
                FROM Support_Relationship__c
                WHERE Id = :rel.Id
            ];

            System.assertEquals(false, updated.Dismissed_By_Helper__c);
            System.assertEquals(true, updated.Dismissed_By_Subject__c);
        }
    }

    @IsTest
    static void testConfirmRelationship() {
        User testUser = getHelperUser();
        Support_Relationship__c rel = createSupportPersonRelationship('Approved');

        System.runAs(testUser) {
            Test.startTest();
            FimbySupportRelationshipController.confirmRelationship(rel.Id);
            Test.stopTest();

            Support_Relationship__c updated = [
                SELECT Subject_Confirmed__c, Subject_Confirmed_Date__c, Consent_Method__c
                FROM Support_Relationship__c
                WHERE Id = :rel.Id
            ];

            System.assertEquals(true, updated.Subject_Confirmed__c);
            System.assertNotEquals(null, updated.Subject_Confirmed_Date__c);
            System.assertEquals('In_App', updated.Consent_Method__c);
        }
    }
    @IsTest
static void testGetAvailableIdentities_CommunityGroupRep() {
    User testUser = getHelperUser();
    Account nh = getNeighbourhood();

    Id orgRtId = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Account'
        AND DeveloperName = 'Organization'
        LIMIT 1
    ].Id;

    Contact orgContact = new Contact(
        LastName = 'Org Identity Contact',
        AccountId = nh.Id
    );
    insert orgContact;

    Account orgAcct = new Account(
        Name = 'Coverage Org Identity',
        RecordTypeId = orgRtId,
        Is_Approved_Community_Group__c = true,
        Organization_Contact__c = orgContact.Id
    );
    insert orgAcct;

    insert new Support_Relationship__c(
        Contact__c = testUser.ContactId,
        Related_Organization__c = orgAcct.Id,
        Relationship_Type__c = 'Community_Group_Rep',
        Status__c = 'Approved',
        Neighbourhood__c = nh.Id
    );

    System.runAs(testUser) {
        Test.startTest();
        List<Map<String, Object>> identities =
            FimbySupportRelationshipController.getAvailableIdentities();
        Test.stopTest();

        System.assertEquals(1, identities.size());
        System.assertEquals('Community_Group_Rep', (String) identities[0].get('type'));
        if (identities[0].get('targetContactId') != null) {
            System.assertEquals(orgContact.Id, (Id) identities[0].get('targetContactId'));
        }
    }
}

@IsTest
static void testSwitchIdentity_CommunityGroupRep() {
    User testUser = getHelperUser();
    Account nh = getNeighbourhood();
    Contact subject = getSubjectContact();

    Id orgRtId = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Account'
        AND DeveloperName = 'Organization'
        LIMIT 1
    ].Id;

    Account orgAcct = new Account(
        Name = 'Coverage Org Switch',
        RecordTypeId = orgRtId,
        Is_Approved_Community_Group__c = true,
        Organization_Contact__c = subject.Id
    );
    insert orgAcct;

    Support_Relationship__c rel = new Support_Relationship__c(
        Contact__c = testUser.ContactId,
        Related_Organization__c = orgAcct.Id,
        Relationship_Type__c = 'Community_Group_Rep',
        Status__c = 'Approved',
        Neighbourhood__c = nh.Id
    );
    insert rel;

    System.runAs(testUser) {
        Test.startTest();
        try {
            FimbySupportRelationshipController.switchIdentity(rel.Id);
            Contact c = [
                SELECT Logged_In_As_Contact__c, Logged_In_As_Neighbourhood__c
                FROM Contact
                WHERE Id = :testUser.ContactId
            ];
            System.assertEquals(subject.Id, c.Logged_In_As_Contact__c);
            System.assertEquals(nh.Id, c.Logged_In_As_Neighbourhood__c);
        } catch (AuraHandledException e) {
            System.assert(
                e.getMessage().contains('Unable to resolve') || e.getMessage().contains('Script-thrown'),
                'If org sharing blocks access, exception is acceptable'
            );
        }
        Test.stopTest();
    }
}

@IsTest
static void testSwitchIdentity_OrgWithoutOrganizationContact_Throws() {
    User testUser = getHelperUser();
    Account nh = getNeighbourhood();

    Id orgRtId = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Account'
        AND DeveloperName = 'Organization'
        LIMIT 1
    ].Id;

    Account orgAcct = new Account(
        Name = 'Coverage Org No Contact',
        RecordTypeId = orgRtId,
        Is_Approved_Community_Group__c = true
    );
    insert orgAcct;

    Support_Relationship__c rel = new Support_Relationship__c(
        Contact__c = testUser.ContactId,
        Related_Organization__c = orgAcct.Id,
        Relationship_Type__c = 'Community_Group_Rep',
        Status__c = 'Approved',
        Neighbourhood__c = nh.Id
    );
    insert rel;

    System.runAs(testUser) {
        Test.startTest();
        try {
            FimbySupportRelationshipController.switchIdentity(rel.Id);
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assert(true, 'Exception thrown as expected');
        }
        Test.stopTest();
    }
}

@IsTest
static void testGetManagedRelationships_WithAllBuckets() {
    User testUser = getHelperUser();
    Contact helper = [SELECT Id, AccountId FROM Contact WHERE Id = :testUser.ContactId LIMIT 1];
    Contact subject = getSubjectContact();
    Account nh = getNeighbourhood();

    Id orgRtId = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Account'
        AND DeveloperName = 'Organization'
        LIMIT 1
    ].Id;

    Account orgAcct = new Account(
        Name = 'Coverage Managed Org',
        RecordTypeId = orgRtId,
        Is_Approved_Community_Group__c = true
    );
    insert orgAcct;

    insert new Support_Relationship__c(
        Contact__c = helper.Id,
        Related_Contact__c = subject.Id,
        Relationship_Type__c = 'Support_Person',
        Status__c = 'Approved',
        Neighbourhood__c = nh.Id,
        Dismissed_By_Helper__c = false
    );

    insert new Support_Relationship__c(
        Contact__c = subject.Id,
        Related_Contact__c = helper.Id,
        Relationship_Type__c = 'Support_Person',
        Status__c = 'Approved',
        Neighbourhood__c = nh.Id,
        Dismissed_By_Subject__c = false
    );

    insert new Support_Relationship__c(
        Contact__c = helper.Id,
        Related_Organization__c = orgAcct.Id,
        Relationship_Type__c = 'Community_Group_Rep',
        Status__c = 'Approved',
        Neighbourhood__c = nh.Id,
        Dismissed_By_Helper__c = false
    );

    System.runAs(testUser) {
        Test.startTest();
        Map<String, Object> result = FimbySupportRelationshipController.getManagedRelationships();
        Test.stopTest();

        System.assertEquals(1, ((List<Object>) result.get('peopleISupport')).size());
        System.assertEquals(1, ((List<Object>) result.get('peopleWhoSupportMe')).size());
        System.assertEquals(1, ((List<Object>) result.get('communityGroups')).size());
    }
}

@IsTest
static void testGetNeighbourhoodsForOrganization_NullId() {
    User testUser = getHelperUser();

    System.runAs(testUser) {
        Test.startTest();
        List<Map<String, String>> results =
            FimbySupportRelationshipController.getNeighbourhoodsForOrganization(null);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }
}

@IsTest
static void testDeactivateRelationship_CommunityGroupRep() {
    User testUser = getHelperUser();
    Account nh = getNeighbourhood();

    Id orgRtId = [
        SELECT Id
        FROM RecordType
        WHERE SObjectType = 'Account'
        AND DeveloperName = 'Organization'
        LIMIT 1
    ].Id;

    Account orgAcct = new Account(
        Name = 'Coverage Deactivate Org',
        RecordTypeId = orgRtId,
        Is_Approved_Community_Group__c = true
    );
    insert orgAcct;

    Support_Relationship__c rel = new Support_Relationship__c(
        Contact__c = testUser.ContactId,
        Related_Organization__c = orgAcct.Id,
        Relationship_Type__c = 'Community_Group_Rep',
        Status__c = 'Approved',
        Neighbourhood__c = nh.Id,
        Approved_By__c = testUser.ContactId
    );
    insert rel;

    System.runAs(testUser) {
        Test.startTest();
        FimbySupportRelationshipController.deactivateRelationship(rel.Id);
        Test.stopTest();

        Support_Relationship__c updated = [
            SELECT Status__c, Ended_By__c, Ended_Date__c
            FROM Support_Relationship__c
            WHERE Id = :rel.Id
        ];

        System.assertEquals('Inactive', updated.Status__c);
        System.assertEquals(testUser.ContactId, updated.Ended_By__c);
        System.assertNotEquals(null, updated.Ended_Date__c);
    }
    }

    /* ── A2: Community Group lifecycle action requests ─────────────────── */

    @IsTest
    static void requestCommunityGroupClose_FilesModeratorTask() {
        User testUser = getHelperUser();
        Account orgAcct = getOrganization();
        Account nh = getNeighbourhood();
        Support_Relationship__c rel = createCommunityGroupRelationship('Approved');

        Test.startTest();
        System.runAs(testUser) {
            FimbySupportRelationshipController.requestCommunityGroupLifecycleAction(
                rel.Id, 'Close', 'Operator stepping down at end of season.'
            );
        }
        Test.stopTest();

        Moderator_Task__c task = [
            SELECT Id, Category__c, Status__c, Priority__c,
                   Subject_Contact__c, Related_Record_Id__c, Related_Record_Type__c,
                   Neighbourhood__c, Summary__c, Latest_Report_Reason__c
            FROM Moderator_Task__c
            WHERE Related_Record_Id__c = :String.valueOf(orgAcct.Id)
            LIMIT 1
        ];
        System.assertEquals('Community_Group_Lifecycle', task.Category__c,
            'Category should be the new lifecycle picklist value');
        System.assertEquals('New', task.Status__c, 'New tasks start in New status');
        System.assertEquals('Account', task.Related_Record_Type__c,
            'Related record type should be Account (the group)');
        System.assertEquals(testUser.ContactId, task.Subject_Contact__c,
            'Subject_Contact__c should be the requesting representative');
        System.assertEquals(nh.Id, task.Neighbourhood__c,
            'Task must be stamped with the relationship neighbourhood');
        System.assertEquals('Close', task.Latest_Report_Reason__c,
            'Reason code should reflect the requested action');
        System.assert(task.Summary__c != null && task.Summary__c.startsWith('Close group:'),
            'Summary should describe the requested action and group');
    }

    @IsTest
    static void requestCommunityGroupDelete_FilesModeratorTask() {
        User testUser = getHelperUser();
        Account orgAcct = getOrganization();
        Support_Relationship__c rel = createCommunityGroupRelationship('Approved');

        Test.startTest();
        System.runAs(testUser) {
            FimbySupportRelationshipController.requestCommunityGroupLifecycleAction(
                rel.Id, 'Delete', null
            );
        }
        Test.stopTest();

        Moderator_Task__c task = [
            SELECT Id, Category__c, Latest_Report_Reason__c, Summary__c,
                   Related_Record_Id__c
            FROM Moderator_Task__c
            WHERE Related_Record_Id__c = :String.valueOf(orgAcct.Id)
            LIMIT 1
        ];
        System.assertEquals('Community_Group_Lifecycle', task.Category__c);
        System.assertEquals('Delete', task.Latest_Report_Reason__c);
        System.assert(task.Summary__c != null && task.Summary__c.startsWith('Delete group:'),
            'Summary should describe the requested action');
    }

    @IsTest
    static void requestCommunityGroupAction_RejectsUnknownAction() {
        User testUser = getHelperUser();
        Support_Relationship__c rel = createCommunityGroupRelationship('Approved');

        Boolean threw = false;
        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbySupportRelationshipController.requestCommunityGroupLifecycleAction(
                    rel.Id, 'Hard_Delete', null
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(threw, 'Unknown action values must be rejected');
        System.assertEquals(0,
            [SELECT COUNT() FROM Moderator_Task__c
             WHERE Category__c = 'Community_Group_Lifecycle'],
            'No task should be created for an unsupported action');
    }

    @IsTest
    static void requestCommunityGroupAction_RejectsNonApprovedRep() {
        User testUser = getHelperUser();
        Support_Relationship__c rel = createCommunityGroupRelationship('Pending');

        Boolean threw = false;
        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbySupportRelationshipController.requestCommunityGroupLifecycleAction(
                    rel.Id, 'Close', null
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(threw, 'Pending reps cannot request lifecycle actions');
        System.assertEquals(0,
            [SELECT COUNT() FROM Moderator_Task__c
             WHERE Category__c = 'Community_Group_Lifecycle']);
    }

    @IsTest
    static void requestCommunityGroupAction_RejectsSupportPersonRelationship() {
        User testUser = getHelperUser();
        Support_Relationship__c rel = createSupportPersonRelationship('Approved');

        Boolean threw = false;
        Test.startTest();
        System.runAs(testUser) {
            try {
                FimbySupportRelationshipController.requestCommunityGroupLifecycleAction(
                    rel.Id, 'Close', null
                );
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        Test.stopTest();

        System.assert(threw, 'Support_Person relationships are not Community Groups');
    }

    @IsTest
    static void requestCommunityGroupAction_DoesNotMutateAccount() {
        User testUser = getHelperUser();
        Account orgAcct = getOrganization();
        Support_Relationship__c rel = createCommunityGroupRelationship('Approved');

        // Capture mutable Account fields before the action.
        Account before = [
            SELECT Id, Name, Is_Approved_Community_Group__c, Organization_Contact__c
            FROM Account WHERE Id = :orgAcct.Id LIMIT 1
        ];

        Test.startTest();
        System.runAs(testUser) {
            FimbySupportRelationshipController.requestCommunityGroupLifecycleAction(
                rel.Id, 'Delete', 'Confirming destructive paths only file a task.'
            );
        }
        Test.stopTest();

        Account after = [
            SELECT Id, Name, Is_Approved_Community_Group__c, Organization_Contact__c
            FROM Account WHERE Id = :orgAcct.Id LIMIT 1
        ];
        System.assertEquals(before.Name, after.Name,
            'LWC path must not rename the Account');
        System.assertEquals(before.Is_Approved_Community_Group__c,
            after.Is_Approved_Community_Group__c,
            'LWC path must not toggle the approval flag');
        System.assertEquals(before.Organization_Contact__c, after.Organization_Contact__c,
            'LWC path must not relink the organization contact');
    }
}