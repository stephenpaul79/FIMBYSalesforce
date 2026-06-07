/**
 * @description Smoke coverage for the paper-form support relationship code path:
 *   - FimbySupportRelationshipController.createPaperDraft / submitPaperUpload /
 *     getMyPaperRelationships
 *   - FimbySupportRelationshipEmailService (Day-0, reminder, approval, rejection)
 *   - FimbySupportRelationshipTrigger + FimbySupportRelationshipTriggerHandler
 *     (Approved / Rejected / Pending Paper Review status transitions)
 *   - FimbySupportRelationshipReminderBatch (schedulable + batchable scaffolding)
 *   - FimbyAuthorizedSupporterFormController + FimbySupporteeActivationLetterController
 */
@IsTest
private class FimbySupportRelationshipPaperFlowTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact supporterContact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(supporterContact.Id, null, true);
    }

    private static User getSupporterUser() {
        return [SELECT Id, ContactId FROM User WHERE ContactId != null AND IsActive = true LIMIT 1];
    }

    private static Account getNeighbourhood() {
        return [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' LIMIT 1];
    }

    @IsTest
    static void createPaperDraftAndUploadFlow() {
        User supporter = getSupporterUser();
        FimbySupportRelationshipController.PaperDraftInput input =
            new FimbySupportRelationshipController.PaperDraftInput();
        input.firstName = 'Patty';
        input.lastName = 'Paper';
        input.mailingStreet = '123 Test St';
        input.mailingCity = 'Vancouver';
        input.phone = '604-555-0001';
        input.email = 'patty.paper@example.invalid';
        input.supporteeRelationship = 'Neighbour';

        Id srId;
        Test.startTest();
        System.runAs(supporter) {
            srId = FimbySupportRelationshipController.createPaperDraft(input);
            FimbySupportRelationshipController.getMyPaperRelationships();
        }

        ContentVersion cv = new ContentVersion(
            Title = 'Signed Form',
            PathOnClient = 'signed.pdf',
            VersionData = Blob.valueOf('signed-bytes'),
            IsMajorVersion = true
        );
        insert cv;
        ContentVersion fresh = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];

        System.runAs(supporter) {
            FimbySupportRelationshipController.submitPaperUpload(srId, fresh.Id);
        }
        Test.stopTest();

        Support_Relationship__c rel = [
            SELECT Status__c, Day0_Email_Sent_Date__c
            FROM Support_Relationship__c WHERE Id = :srId
        ];
        System.assertEquals('Pending Paper Review', rel.Status__c,
            'Upload should advance status from Draft');
        System.assertNotEquals(null, rel.Day0_Email_Sent_Date__c,
            'Day-0 email should have stamped sent date');
    }

    @IsTest
    static void submitRelationshipRequestRequiresCgaAcceptedForCgr() {
        User supporter = getSupporterUser();
        Account nh = getNeighbourhood();
        Account orgAcct = new Account(
            Name = 'Sample Org',
            RecordTypeId = [SELECT Id FROM RecordType
                            WHERE SObjectType = 'Account' AND DeveloperName = 'Organization' LIMIT 1].Id
        );
        insert orgAcct;

        Map<String, Object> params = new Map<String, Object>{
            'relationshipType' => 'Community_Group_Rep',
            'relatedContactId' => null,
            'relatedOrganizationId' => orgAcct.Id,
            'neighbourhoodId' => nh.Id,
            'authorizationImageUrl' => null,
            'notes' => 'Org rep request'
        };

        Test.startTest();
        System.runAs(supporter) {
            Boolean threw = false;
            try {
                FimbySupportRelationshipController.submitRelationshipRequest(params);
            } catch (AuraHandledException e) { threw = true; }
            System.assert(threw, 'CGR submit without cgaAccepted should raise');
        }
        Test.stopTest();
    }

    @IsTest
    static void createPaperDraftValidationErrors() {
        User supporter = getSupporterUser();
        FimbySupportRelationshipController.PaperDraftInput blank =
            new FimbySupportRelationshipController.PaperDraftInput();

        Test.startTest();
        System.runAs(supporter) {
            Boolean threwNullInput = false;
            try {
                FimbySupportRelationshipController.createPaperDraft(null);
            } catch (AuraHandledException e) { threwNullInput = true; }
            System.assert(threwNullInput, 'Null input should raise');

            Boolean threwBlank = false;
            try {
                FimbySupportRelationshipController.createPaperDraft(blank);
            } catch (AuraHandledException e) { threwBlank = true; }
            System.assert(threwBlank, 'Blank first/last name should raise');
        }
        Test.stopTest();
    }

    @IsTest
    static void submitPaperUploadValidationErrors() {
        User supporter = getSupporterUser();
        Test.startTest();
        System.runAs(supporter) {
            Boolean nullSr = false;
            try {
                FimbySupportRelationshipController.submitPaperUpload(null, null);
            } catch (AuraHandledException e) { nullSr = true; }
            System.assert(nullSr, 'Null srId should raise');
        }
        Test.stopTest();
    }

    @IsTest
    static void emailServiceMethodsRunCleanly() {
        User supporter = getSupporterUser();
        Account nh = getNeighbourhood();
        Contact supportee = new Contact(
            FirstName = 'Sam', LastName = 'Supportee', AccountId = nh.Id,
            MailingCity = 'Vancouver', Email = 'sam@example.invalid');
        insert supportee;

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = supporter.ContactId,
            Related_Contact__c = supportee.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Draft',
            Neighbourhood__c = nh.Id,
            Consent_Method__c = 'Written'
        );
        insert rel;

        Test.startTest();
        FimbySupportRelationshipEmailService.sendDay0Email(rel.Id);
        FimbySupportRelationshipEmailService.sendReminderEmail(rel.Id, 14);
        FimbySupportRelationshipEmailService.sendReminderEmail(rel.Id, 30);
        FimbySupportRelationshipEmailService.sendReminderEmail(rel.Id, 60);
        rel.Rejection_Reason__c = 'Form invalid';
        rel.Rejection_Reason_Detail__c = 'Block C blank';
        update rel;
        FimbySupportRelationshipEmailService.sendRejectionNotification(rel.Id);
        FimbySupportRelationshipEmailService.sendApprovalNotification(rel.Id);
        Test.stopTest();

        Support_Relationship__c reloaded = [
            SELECT Day0_Email_Sent_Date__c, Last_Reminder_Sent_Date__c
            FROM Support_Relationship__c WHERE Id = :rel.Id
        ];
        System.assertNotEquals(null, reloaded.Day0_Email_Sent_Date__c);
        System.assertNotEquals(null, reloaded.Last_Reminder_Sent_Date__c);
    }

    @IsTest
    static void triggerHandlesPaperReviewAndRejection() {
        User supporter = getSupporterUser();
        Account nh = getNeighbourhood();
        Contact supportee = new Contact(
            FirstName = 'Sam', LastName = 'Supportee', AccountId = nh.Id);
        insert supportee;

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = supporter.ContactId,
            Related_Contact__c = supportee.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Draft',
            Neighbourhood__c = nh.Id,
            Consent_Method__c = 'Written'
        );
        insert rel;

        Test.startTest();
        rel.Status__c = 'Pending Paper Review';
        update rel;

        rel.Status__c = 'Rejected';
        rel.Rejection_Reason__c = 'Form invalid';
        update rel;
        Test.stopTest();

        Support_Relationship__c reloaded = [
            SELECT Status__c FROM Support_Relationship__c WHERE Id = :rel.Id
        ];
        System.assertEquals('Rejected', reloaded.Status__c);
    }

    @IsTest
    static void reminderBatchExecutes() {
        User supporter = getSupporterUser();
        Account nh = getNeighbourhood();
        List<Contact> supportees = new List<Contact>{
            new Contact(FirstName = 'D14', LastName = 'Supportee', AccountId = nh.Id),
            new Contact(FirstName = 'D30', LastName = 'Supportee', AccountId = nh.Id),
            new Contact(FirstName = 'D60', LastName = 'Supportee', AccountId = nh.Id),
            new Contact(FirstName = 'Exp', LastName = 'Supportee', AccountId = nh.Id)
        };
        insert supportees;

        List<Support_Relationship__c> rels = new List<Support_Relationship__c>{
            buildPaperRel(supporter.ContactId, supportees[0].Id, nh.Id, -14),
            buildPaperRel(supporter.ContactId, supportees[1].Id, nh.Id, -30),
            buildPaperRel(supporter.ContactId, supportees[2].Id, nh.Id, -60),
            buildPaperRel(supporter.ContactId, supportees[3].Id, nh.Id, -91)
        };
        insert rels;

        Test.startTest();
        Database.executeBatch(new FimbySupportRelationshipReminderBatch(), 50);
        FimbySupportRelationshipReminderBatch sched = new FimbySupportRelationshipReminderBatch();
        sched.execute(null);
        Test.stopTest();
    }

    private static Support_Relationship__c buildPaperRel(Id supporter, Id supportee, Id nhId, Integer dayOffset) {
        return new Support_Relationship__c(
            Contact__c = supporter,
            Related_Contact__c = supportee,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Draft',
            Neighbourhood__c = nhId,
            Consent_Method__c = 'Written',
            Day0_Email_Sent_Date__c = Datetime.now().addDays(dayOffset)
        );
    }

    @IsTest
    static void supporterFormVfControllerLoads() {
        User supporter = getSupporterUser();
        Account nh = getNeighbourhood();
        Contact supportee = new Contact(
            FirstName = 'Sam', LastName = 'Supportee', AccountId = nh.Id,
            Birthdate = Date.newInstance(1950, 1, 1),
            MailingStreet = '1 Main', MailingCity = 'Vancouver',
            MailingState = 'BC', MailingPostalCode = 'V0V0V0',
            Phone = '604-555-0002', Email = 's@example.invalid');
        insert supportee;

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = supporter.ContactId,
            Related_Contact__c = supportee.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Pending Paper Review',
            Neighbourhood__c = nh.Id,
            Supportee_Relationship__c = 'Neighbour'
        );
        insert rel;

        Test.startTest();
        PageReference pr = Page.FimbyAuthorizedSupporterForm;
        pr.getParameters().put('id', rel.Id);
        Test.setCurrentPage(pr);
        FimbyAuthorizedSupporterFormController ctrl = new FimbyAuthorizedSupporterFormController();
        Test.stopTest();

        System.assertEquals(false, ctrl.hasError, 'Form controller should load without error');
        System.assertNotEquals(null, ctrl.getSupporteeFullAddress());
        System.assertNotEquals(null, ctrl.getSupporterFullAddress());
    }

    @IsTest
    static void activationLetterVfControllerErrorPaths() {
        Test.startTest();
        Test.setCurrentPage(Page.FimbySupporteeActivationLetter);
        FimbySupporteeActivationLetterController noId = new FimbySupporteeActivationLetterController();
        System.assertEquals(true, noId.hasError, 'Missing id should set hasError');

        PageReference badPr = Page.FimbySupporteeActivationLetter;
        badPr.getParameters().put('id', 'badId123');
        Test.setCurrentPage(badPr);
        FimbySupporteeActivationLetterController bad = new FimbySupporteeActivationLetterController();
        System.assertEquals(true, bad.hasError, 'Invalid id should set hasError');
        Test.stopTest();
    }

    @IsTest
    static void supporterFormVfControllerErrorPaths() {
        Test.startTest();
        Test.setCurrentPage(Page.FimbyAuthorizedSupporterForm);
        FimbyAuthorizedSupporterFormController noId = new FimbyAuthorizedSupporterFormController();
        System.assertEquals(true, noId.hasError, 'Missing id should set hasError');
        Test.stopTest();
    }

    @IsTest
    static void activationLetterVfControllerLoads() {
        User supporter = getSupporterUser();
        Account nh = getNeighbourhood();
        Contact supportee = new Contact(
            FirstName = 'Sam', LastName = 'Supportee', AccountId = nh.Id,
            MailingStreet = '1 Main', MailingCity = 'Vancouver',
            MailingState = 'BC', MailingPostalCode = 'V0V0V0');
        insert supportee;

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = supporter.ContactId,
            Related_Contact__c = supportee.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Approved_Date__c = Datetime.now(),
            Neighbourhood__c = nh.Id
        );
        insert rel;

        Test.startTest();
        PageReference pr = Page.FimbySupporteeActivationLetter;
        pr.getParameters().put('id', rel.Id);
        Test.setCurrentPage(pr);
        FimbySupporteeActivationLetterController ctrl = new FimbySupporteeActivationLetterController();
        Test.stopTest();

        System.assertEquals(false, ctrl.hasError);
        System.assertNotEquals(null, ctrl.getSupporteeAddressBlock());
        System.assertNotEquals(null, ctrl.getApprovedDateLabel());
    }

    @IsTest
    static void emailDeepLinks_useAbsoluteManageIdentitiesUrl() {
        Id srId = UserInfo.getUserId();

        String resumeUrl = FimbySupportRelationshipEmailService.buildDeepLink(srId);
        System.assert(resumeUrl.startsWith('https://'), 'Resume link must be absolute: ' + resumeUrl);
        System.assert(resumeUrl.contains('/manage-identities?continueSr='), resumeUrl);

        String approvalUrl = FimbySupportRelationshipEmailService.buildManageIdentitiesUrl();
        System.assert(approvalUrl.startsWith('https://'), 'Approval link must be absolute: ' + approvalUrl);
        System.assert(approvalUrl.contains('/manage-identities'), approvalUrl);
        System.assert(!approvalUrl.contains('continueSr='), 'Approval link should not open upload modal');
    }

    @IsTest
    static void approvalEmail_usesCommunityRepCopy() {
        User supporter = getSupporterUser();
        Account nh = getNeighbourhood();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Account org = new Account(
            Name = 'Strathcona Vineyard',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Verified'
        );
        insert org;

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = supporter.ContactId,
            Related_Organization__c = org.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Approved',
            Neighbourhood__c = nh.Id
        );
        insert rel;

        FimbyTransactionalEmailService.testLastSubject = null;
        FimbyTransactionalEmailService.testLastCardHtml = null;

        Test.startTest();
        FimbySupportRelationshipEmailService.sendApprovalNotification(rel.Id);
        Test.stopTest();

        System.assert(
            FimbyTransactionalEmailService.testLastSubject.contains('Strathcona Vineyard'),
            FimbyTransactionalEmailService.testLastSubject
        );
        System.assert(
            !FimbyTransactionalEmailService.testLastCardHtml.contains('supportee'),
            FimbyTransactionalEmailService.testLastCardHtml
        );
        System.assert(
            FimbyTransactionalEmailService.testLastCardHtml.contains('Manage Identities'),
            FimbyTransactionalEmailService.testLastCardHtml
        );
        System.assert(
            FimbyTransactionalEmailService.testLastCardHtml.contains('SUPPORT'),
            'Approval email should use SUPPORT badge'
        );
    }

    @IsTest
    static void rejectionEmail_usesCommunityRepCopy() {
        User supporter = getSupporterUser();
        Account nh = getNeighbourhood();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Account org = new Account(
            Name = 'Declined Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Verified'
        );
        insert org;

        Support_Relationship__c rel = new Support_Relationship__c(
            Contact__c = supporter.ContactId,
            Related_Organization__c = org.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Declined',
            Neighbourhood__c = nh.Id,
            Rejection_Reason__c = 'Other'
        );
        insert rel;

        FimbyTransactionalEmailService.testLastSubject = null;
        FimbyTransactionalEmailService.testLastCardHtml = null;

        Test.startTest();
        FimbySupportRelationshipEmailService.sendRejectionNotification(rel.Id);
        Test.stopTest();

        System.assert(
            FimbyTransactionalEmailService.testLastSubject.contains('organization representative'),
            FimbyTransactionalEmailService.testLastSubject
        );
        System.assert(
            !FimbyTransactionalEmailService.testLastCardHtml.contains('paper form'),
            FimbyTransactionalEmailService.testLastCardHtml
        );
    }
}
