@IsTest
private class FimbyOrganizationProfileControllerTest {

    private static final String HELPER_CONTACT_NAME = 'OrgProfile Helper';
    private static final String ORG_NAME = 'OrgProfile Test Community Group';

    @TestSetup
    static void setupTestData() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);

        Contact helperContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        helperContact.LastName = HELPER_CONTACT_NAME;
        update helperContact;

        User helperUser = FimbyTestDataFactory.createCommunityUser(helperContact.Id, null, true);

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
            Type = 'Community Group',
            Description = 'Test org description',
            Website = 'https://example.org',
            Is_Approved_Community_Group__c = true
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

    private static Account getOrganization() {
        return [
            SELECT Id, Name, Description, Website, Logo_URL__c
            FROM Account
            WHERE Name = :ORG_NAME
            LIMIT 1
        ];
    }

    private static Support_Relationship__c createApprovedGroupRepRelationship() {
        User helperUser = getHelperUser();
        Contact helperContact = [
            SELECT AccountId
            FROM Contact
            WHERE Id = :helperUser.ContactId
            LIMIT 1
        ];
        Account orgAcct = getOrganization();

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = helperUser.ContactId,
            Related_Organization__c = orgAcct.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved',
            Neighbourhood__c = helperContact.AccountId,
            Dismissed_By_Helper__c = false
        );
        insert rel;
        return rel;
    }

    @IsTest
    static void testCanEditOrganizationNullId() {
        System.assertEquals(false, FimbyOrganizationProfileController.canEditOrganization(null));
    }

    @IsTest
    static void testCanEditOrganizationFalseWhenNoRelationship() {
        User testUser = getHelperUser();
        Account org = getOrganization();

        System.runAs(testUser) {
            Test.startTest();
            Boolean result = FimbyOrganizationProfileController.canEditOrganization(org.Id);
            Test.stopTest();

            System.assertEquals(false, result);
        }
    }

    @IsTest
    static void testCanEditOrganizationTrueWhenApproved() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();

        System.runAs(testUser) {
            Test.startTest();
            Boolean result = FimbyOrganizationProfileController.canEditOrganization(org.Id);
            Test.stopTest();

            System.assertEquals(true, result);
        }
    }

    @IsTest
    static void testGetOrganizationProfile() {
        User testUser = getHelperUser();
        Account org = getOrganization();

        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationProfileController.getOrganizationProfile(org.Id);
            Test.stopTest();

            System.assertEquals(true, result.get('success'));
            Map<String, Object> orgData = (Map<String, Object>) result.get('org');
            System.assertEquals(org.Name, orgData.get('Name'));
            System.assertEquals('Test org description', orgData.get('Description'));
            System.assertEquals('https://example.org', orgData.get('Website'));

            List<Object> neighbourhoods = (List<Object>) result.get('neighbourhoods');
            System.assert(neighbourhoods != null);
            List<Object> people = (List<Object>) result.get('people');
            System.assert(people != null);
        }
    }

    @IsTest
    static void testGetOrganizationProfileWithApprovedReps() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();

        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationProfileController.getOrganizationProfile(org.Id);
            Test.stopTest();

            List<Object> people = (List<Object>) result.get('people');
            System.assertEquals(1, people.size());
        }
    }

    @IsTest
    static void testUpdateOrganizationProfileWithoutPermission() {
        User testUser = getHelperUser();
        Account org = getOrganization();

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbyOrganizationProfileController.updateOrganizationProfile(
                    org.Id,
                    new Map<String, Object>{ 'Name' => 'Updated Name' }
                );
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null && (e.getMessage().contains('permission') || e.getMessage().contains('Script-thrown')), 'Expected permission error: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testUpdateOrganizationProfileWithPermission() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();

        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationProfileController.updateOrganizationProfile(
                org.Id,
                new Map<String, Object>{
                    'Name' => 'Updated Org Name',
                    'Description' => 'Updated description',
                    'Website' => 'https://updated.org'
                }
            );
            Test.stopTest();

            System.assertEquals(true, result.get('success'));
        }

        Account updated = [SELECT Name, Description, Website FROM Account WHERE Id = :org.Id];
        System.assertEquals('Updated Org Name', updated.Name);
        System.assertEquals('Updated description', updated.Description);
        System.assertEquals('https://updated.org', updated.Website);
    }

    @IsTest
    static void testUploadOrganizationLogoWithoutPermission() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        String base64 = 'data:image/jpeg;base64,/9j/4AAQSkZJRg==';

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbyOrganizationProfileController.uploadOrganizationLogo(
                    org.Id,
                    base64,
                    'logo.jpg',
                    100,
                    100
                );
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null && (e.getMessage().contains('permission') || e.getMessage().contains('Script-thrown')), 'Expected permission error: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testRemoveOrganizationLogoWithoutPermission() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        org.Logo_URL__c = 'https://example.com/logo.jpg';
        update org;

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbyOrganizationProfileController.removeOrganizationLogo(org.Id);
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null && (e.getMessage().contains('permission') || e.getMessage().contains('Script-thrown')), 'Expected permission error: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testGetOrganizationProfileNullId() {
        User testUser = getHelperUser();

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbyOrganizationProfileController.getOrganizationProfile(null);
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null && (e.getMessage().contains('required') || e.getMessage().contains('Script-thrown')), 'Expected required error: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testGetOrganizationProfileInvalidId() {
        User testUser = getHelperUser();
        Id contactId = testUser.ContactId;

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbyOrganizationProfileController.getOrganizationProfile(contactId);
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null && (e.getMessage().contains('Error loading') || e.getMessage().contains('Script-thrown')), 'Expected error: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testUpdateOrganizationProfileEmptyFieldValues() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();

        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationProfileController.updateOrganizationProfile(
                org.Id,
                new Map<String, Object>()
            );
            Test.stopTest();

            System.assertEquals(true, result.get('success'));
        }
    }

    @IsTest
    static void testUpdateOrganizationProfileDmlError() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();
        Id orgId = org.Id;
        delete [SELECT Id FROM Community_Group_Neighbourhood__c WHERE Organization__c = :orgId];
        delete [SELECT Id FROM Support_Relationship__c WHERE Related_Organization__c = :orgId];
        delete org;

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbyOrganizationProfileController.updateOrganizationProfile(
                    orgId,
                    new Map<String, Object>{ 'Name' => 'Updated' }
                );
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null && (e.getMessage().contains('Error updating') || e.getMessage().contains('Script-thrown')), 'Expected error: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testUpdateOrganizationProfileDisallowedField() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();

        System.runAs(testUser) {
            Test.startTest();
            try {
                FimbyOrganizationProfileController.updateOrganizationProfile(
                    org.Id,
                    new Map<String, Object>{ 'InvalidField__c' => 'value' }
                );
                System.assert(false, 'Expected AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null && (e.getMessage().toLowerCase().contains('allowed') || e.getMessage().contains('Script-thrown')), 'Expected allowed error: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testRemoveOrganizationLogoWithPermission() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();
        org.Logo_URL__c = 'https://example.com/logo.jpg';
        update org;

        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationProfileController.removeOrganizationLogo(org.Id);
            Test.stopTest();

            System.assertEquals(true, result.get('success'));
        }

        Account updated = [SELECT Logo_URL__c FROM Account WHERE Id = :org.Id];
        System.assertEquals(null, updated.Logo_URL__c);
    }

    @IsTest
    static void testUpdateOrganizationProfileNullId() {
        User testUser = getHelperUser();

        System.runAs(testUser) {
            try {
                FimbyOrganizationProfileController.updateOrganizationProfile(null, new Map<String, Object>{ 'Name' => 'X' });
                System.assert(false, 'Expected exception');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null);
            }
        }
    }

    @IsTest
    static void testRemoveOrganizationLogoNullId() {
        User testUser = getHelperUser();

        System.runAs(testUser) {
            try {
                FimbyOrganizationProfileController.removeOrganizationLogo(null);
                System.assert(false, 'Expected exception');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null);
            }
        }
    }

    @IsTest
    static void testUploadOrganizationLogoMissingFileData() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();

        System.runAs(testUser) {
            try {
                FimbyOrganizationProfileController.uploadOrganizationLogo(org.Id, '', 'logo.jpg', 100, 100);
                System.assert(false, 'Expected exception');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null);
            }
        }
    }

    @IsTest
    static void testUploadOrganizationLogoWithPermissionUsingOverride() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();

        FimbyOrganizationProfileController.testLogoUrlOverride =
            'https://test.example.com/logo_override.jpg';

        System.runAs(testUser) {
            Test.startTest();
            String url = FimbyOrganizationProfileController.uploadOrganizationLogo(
                org.Id,
                'data:image/jpeg;base64,/9j/4AAQSkZJRg==',
                'logo.jpg',
                100,
                100
            );
            Test.stopTest();

            System.assertEquals('https://test.example.com/logo_override.jpg', url);
        }

        Account updated = [SELECT Logo_URL__c FROM Account WHERE Id = :org.Id];
        System.assertEquals('https://test.example.com/logo_override.jpg', updated.Logo_URL__c);

        FimbyOrganizationProfileController.testLogoUrlOverride = null;
    }

    @IsTest
    static void testUploadOrganizationLogoWithPermissionUsesTestBypass() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();

        System.runAs(testUser) {
            Test.startTest();
            String url = FimbyOrganizationProfileController.uploadOrganizationLogo(
                org.Id,
                'data:image/jpeg;base64,/9j/4AAQSkZJRg==',
                'logo.jpg',
                100,
                100
            );
            Test.stopTest();

            System.assertEquals('https://test.example.com/logo_logo.jpg', url);
        }

        Account updated = [SELECT Logo_URL__c FROM Account WHERE Id = :org.Id];
        System.assertEquals('https://test.example.com/logo_logo.jpg', updated.Logo_URL__c);
    }

    @IsTest
    static void testExtractBase64DataViaHelper() {
        FimbyOrganizationProfileController.OrgLogoHelper helper = new FimbyOrganizationProfileController.OrgLogoHelper();
        System.assertEquals('ABC123==', helper.extractBase64Data('data:image/jpeg;base64,ABC123=='));
        System.assertEquals('ABC123==', helper.extractBase64Data('ABC123=='));
        System.assertEquals(null, helper.extractBase64Data(null));
    }

    @IsTest
    static void testCanEditOrganizationAsUserWithoutContact() {
        Account org = getOrganization();
        Test.startTest();
        Boolean result = FimbyOrganizationProfileController.canEditOrganization(org.Id);
        Test.stopTest();
        System.assertEquals(false, result);
    }

    @IsTest
    static void testGetOrganizationProfileWithLogoUrl() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        org.Logo_URL__c = 'https://example.com/org-logo.jpg';
        update org;

        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationProfileController.getOrganizationProfile(org.Id);
            Test.stopTest();

            Map<String, Object> orgData = (Map<String, Object>) result.get('org');
            System.assertEquals('https://example.com/org-logo.jpg', orgData.get('Logo_URL__c'));
        }
    }

    @IsTest
    static void testBuildDistributionUrl() {
        ContentVersion cv = new ContentVersion(
            Title = 'test',
            PathOnClient = 'test.txt',
            VersionData = Blob.valueOf('x'),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId, ContentBodyId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        ContentDistribution cd = new ContentDistribution(
            ContentVersionId = cv.Id,
            Name = 'test',
            PreferencesAllowViewInBrowser = true,
            PreferencesNotifyOnVisit = false,
            PreferencesPasswordRequired = false,
            PreferencesAllowOriginalDownload = true
        );
        insert cd;
        cd = [SELECT Id, DistributionPublicUrl FROM ContentDistribution WHERE Id = :cd.Id LIMIT 1];

        FimbyOrganizationProfileController.OrgLogoHelper helper = new FimbyOrganizationProfileController.OrgLogoHelper();
        String url = helper.buildDistributionUrl(cv, cd);

        System.assert(url.contains('rendition=ORIGINAL_Jpg'));
        System.assert(url.contains('versionId='));
        System.assert(url.contains('contentId='));
        System.assert(url.endsWith('&oid='));
    }

    @IsTest
    static void testGetOrganizationProfile_ReturnsNewFields() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        Contact helperContact = [SELECT AccountId FROM Contact WHERE Id = :testUser.ContactId];

        Contact orgRepContact = new Contact(
            FirstName = 'Org', LastName = 'ContactRep',
            AccountId = helperContact.AccountId,
            Email = 'orgrep@example.com'
        );
        insert orgRepContact;

        org.Phone = '0400111222';
        org.BillingStreet = '123 Main St';
        org.BillingCity = 'Springfield';
        org.BillingState = 'VIC';
        org.BillingPostalCode = '3000';
        org.Organization_Contact__c = orgRepContact.Id;
        update org;

        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationProfileController.getOrganizationProfile(org.Id);
            Test.stopTest();

            System.assertEquals(true, result.get('success'));
            Map<String, Object> orgData = (Map<String, Object>) result.get('org');
            System.assertEquals('0400111222', orgData.get('Phone'), 'Should return Phone');
            System.assertEquals('123 Main St', orgData.get('BillingStreet'), 'Should return BillingStreet');
            System.assertEquals('Springfield', orgData.get('BillingCity'), 'Should return BillingCity');
            System.assertEquals('VIC', orgData.get('BillingState'), 'Should return BillingState');
            System.assertEquals('3000', orgData.get('BillingPostalCode'), 'Should return BillingPostalCode');
            System.assertEquals(orgRepContact.Id, orgData.get('Organization_Contact__c'),
                'Should return Organization_Contact__c');
            System.assertEquals('orgrep@example.com', orgData.get('Email'),
                'Should return org contact email');
        }
    }

    @IsTest
    static void testUpdateOrganizationProfile_PhoneField() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();

        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationProfileController.updateOrganizationProfile(
                org.Id,
                new Map<String, Object>{ 'Phone' => '0400999888' }
            );
            Test.stopTest();

            System.assertEquals(true, result.get('success'));
        }

        Account updated = [SELECT Phone FROM Account WHERE Id = :org.Id];
        System.assertEquals('0400999888', updated.Phone, 'Phone should be updated');
    }

    @IsTest
    static void testUpdateOrganizationProfile_BillingFields() {
        User testUser = getHelperUser();
        Account org = getOrganization();
        createApprovedGroupRepRelationship();

        System.runAs(testUser) {
            Test.startTest();
            Map<String, Object> result = FimbyOrganizationProfileController.updateOrganizationProfile(
                org.Id,
                new Map<String, Object>{
                    'BillingStreet' => '456 Park Ave',
                    'BillingCity' => 'Melbourne',
                    'BillingState' => 'VIC',
                    'BillingPostalCode' => '3001'
                }
            );
            Test.stopTest();

            System.assertEquals(true, result.get('success'));
        }

        Account updated = [SELECT BillingStreet, BillingCity, BillingState, BillingPostalCode FROM Account WHERE Id = :org.Id];
        System.assertEquals('456 Park Ave', updated.BillingStreet);
        System.assertEquals('Melbourne', updated.BillingCity);
        System.assertEquals('VIC', updated.BillingState);
        System.assertEquals('3001', updated.BillingPostalCode);
    }
}
