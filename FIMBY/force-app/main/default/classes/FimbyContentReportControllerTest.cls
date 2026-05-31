/**
 * Test class for FimbyContentReportController
 */
@isTest
private class FimbyContentReportControllerTest {

    @TestSetup
    static void setupTestData() {
        // Use the standard test data factory
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact reporter = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        
        // Create a Story to report
        Story__c story = FimbyTestDataFactory.createStories(neighbourhood.Id, reporter.Id, 1, true)[0];
    }

    @isTest
    static void testSubmitContentReport_Success() {
        Story__c story = [SELECT Id FROM Story__c LIMIT 1];

        Map<String, Object> reportData = new Map<String, Object>{
            'contentId' => story.Id,
            'contentType' => 'Story',
            'reason' => 'inappropriate',
            'additionalInfo' => 'This content is inappropriate'
        };

        Test.startTest();
        Map<String, Object> result = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        System.assertNotEquals(null, result.get('reportId'), 'Should return a report ID');

        // Verify Feedback record was created
        List<Feedback__c> feedbacks = [SELECT Id, Type__c, Related_Record_ID__c FROM Feedback__c WHERE Type__c = 'Content Report'];
        System.assertEquals(1, feedbacks.size(), 'Should create one Feedback record');
        System.assertEquals(story.Id, feedbacks[0].Related_Record_ID__c, 'Should store the content ID');
    }

    @isTest
    static void testSubmitContentReport_AllReasons() {
        Story__c story = [SELECT Id FROM Story__c LIMIT 1];
        
        List<String> reasons = new List<String>{
            'inappropriate', 'spam', 'harassment', 'privacy', 'safety', 'other'
        };

        Test.startTest();
        for (String reason : reasons) {
            Map<String, Object> reportData = new Map<String, Object>{
                'contentId' => story.Id,
                'contentType' => 'Story',
                'reason' => reason,
                'additionalInfo' => ''
            };
            Map<String, Object> result = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
            System.assertEquals(true, result.get('success'), 'Should succeed for reason: ' + reason);
        }
        Test.stopTest();
    }

    @isTest
    static void testSubmitContentReport_DifferentContentTypes() {
        Story__c story = [SELECT Id FROM Story__c LIMIT 1];
        
        List<String> contentTypes = new List<String>{
            'Story', 'Need_Offer', 'Library_Item', 'Response'
        };

        Test.startTest();
        for (String contentType : contentTypes) {
            Map<String, Object> reportData = new Map<String, Object>{
                'contentId' => story.Id,
                'contentType' => contentType,
                'reason' => 'spam',
                'additionalInfo' => 'Test report for ' + contentType
            };
            Map<String, Object> result = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
            System.assertEquals(true, result.get('success'), 'Should succeed for content type: ' + contentType);
        }
        Test.stopTest();
    }

    @isTest
    static void testSubmitContentReport_DualStampsRealAndActingAs() {
        // Run as a real Community User to exercise the dual-stamping + moderator-task branches.
        Contact reporter = [SELECT Id, AccountId FROM Contact LIMIT 1];
        User communityUser = FimbyTestDataFactory.createCommunityUser(
            reporter.Id, 'Customer Community User - Mobile App', true
        );

        Story__c story = [SELECT Id FROM Story__c LIMIT 1];

        Map<String, Object> reportData = new Map<String, Object>{
            'contentId' => story.Id,
            'contentType' => 'Story__c',
            'reason' => 'safety',
            'additionalInfo' => 'Concerning behaviour'
        };

        Test.startTest();
        System.runAs(communityUser) {
            FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
        }
        Test.stopTest();

        Feedback__c report = [
            SELECT Id, Contact__c, Posted_By__c, Neighbourhood__c, Type__c
            FROM Feedback__c
            WHERE Type__c = 'Content Report'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(reporter.Id, report.Contact__c, 'Contact__c should be the real submitter');
        System.assertEquals(reporter.Id, report.Posted_By__c, 'Posted_By__c should be the acting-as identity (self here)');
        System.assertEquals(reporter.AccountId, report.Neighbourhood__c, 'Neighbourhood should be stamped');
    }

    @isTest
    static void testSubmitContentReport_TitleAndDetailsUseHumanLabels() {
        Contact reporter = [SELECT Id, AccountId FROM Contact LIMIT 1];
        User communityUser = FimbyTestDataFactory.createCommunityUser(
            reporter.Id, 'Customer Community User - Mobile App', true
        );
        Story__c story = [SELECT Id FROM Story__c LIMIT 1];

        Map<String, Object> reportData = new Map<String, Object>{
            'contentId' => story.Id,
            'contentType' => 'Story__c',
            'reason' => 'inappropriate',
            'additionalInfo' => ''
        };

        Test.startTest();
        System.runAs(communityUser) {
            FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
        }
        Test.stopTest();

        Feedback__c report = [
            SELECT Id, Name, Details__c FROM Feedback__c
            WHERE Type__c = 'Content Report' ORDER BY CreatedDate DESC LIMIT 1
        ];

        // The notification body comes from this title via the Moderator_Task__c.Summary__c
        // pipeline, so any API-name leak (e.g. "Story__c") in here will reach the bell.
        System.assert(!report.Name.contains('__c'),
            'Report title must not leak API names. Got: ' + report.Name);
        System.assert(report.Name.containsIgnoreCase('sharedlife'),
            'Story reports should surface the human "Sharedlife post" label. Got: ' + report.Name);

        Moderator_Task__c task = [
            SELECT Id, Summary__c FROM Moderator_Task__c
            WHERE Category__c = 'Content_Report' ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assert(!task.Summary__c.contains('__c'),
            'Moderator task summary (notification body) must not leak API names. Got: ' + task.Summary__c);

        // Details intentionally keep the API name in parentheses for moderator triage,
        // but the human label must lead.
        System.assert(report.Details__c.containsIgnoreCase('Sharedlife post'),
            'Report details should lead with the human label. Got: ' + report.Details__c);
    }

    @isTest
    static void testSubmitContentReport_ErrorHandling() {
        // Malformed JSON should surface as a wrapped AuraHandledException
        Boolean caught = false;
        Test.startTest();
        try {
            FimbyContentReportController.submitContentReport('not-json');
        } catch (Exception e) {
            caught = true;
        }
        Test.stopTest();
        System.assertEquals(true, caught, 'Malformed JSON should throw a handled exception');
    }

    @isTest
    static void testSubmitContentReport_StoryComment() {
        Contact reporter = [SELECT Id, AccountId FROM Contact LIMIT 1];
        User communityUser = FimbyTestDataFactory.createCommunityUser(
            reporter.Id, 'Customer Community User - Mobile App', true
        );
        Contact commentAuthor = FimbyTestDataFactory.createNeighbourhoodContact(reporter.AccountId, true);
        Story__c story = [SELECT Id FROM Story__c LIMIT 1];

        Story_Comment__c sc = new Story_Comment__c(
            Story__c = story.Id,
            Body__c = 'Comment to be reported',
            Status__c = 'Active',
            Moderation_Status__c = 'Visible',
            Contact__c = commentAuthor.Id,
            Posted_By__c = commentAuthor.Id,
            Neighbourhood__c = reporter.AccountId,
            Edit_Count__c = 0
        );
        insert sc;

        Map<String, Object> reportData = new Map<String, Object>{
            'contentId' => sc.Id,
            'contentType' => 'Story_Comment__c',
            'reason' => 'harassment',
            'additionalInfo' => 'Targeted personal attack'
        };

        Test.startTest();
        Map<String, Object> result;
        System.runAs(communityUser) {
            result = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
        }
        Test.stopTest();

        System.assertEquals(true, result.get('success'));

        Feedback__c report = [
            SELECT Id, Related_Record_ID__c, Type__c
            FROM Feedback__c
            WHERE Type__c = 'Content Report' ORDER BY CreatedDate DESC LIMIT 1
        ];
        System.assertEquals(sc.Id, report.Related_Record_ID__c,
            'Report should reference the Story_Comment__c id');
    }

    @isTest
    static void testSubmitContentReport_DuplicateSameReporterBlocked() {
        Contact reporter = [SELECT Id, AccountId FROM Contact LIMIT 1];
        User communityUser = FimbyTestDataFactory.createCommunityUser(
            reporter.Id, 'Customer Community User - Mobile App', true
        );
        Story__c story = [SELECT Id FROM Story__c LIMIT 1];

        Map<String, Object> reportData = new Map<String, Object>{
            'contentId' => story.Id,
            'contentType' => 'Story__c',
            'reason' => 'inappropriate',
            'additionalInfo' => 'First report'
        };

        Test.startTest();
        Map<String, Object> firstResult;
        Map<String, Object> secondResult;
        Map<String, Object> checkResult;
        System.runAs(communityUser) {
            firstResult = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
            secondResult = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
            checkResult = FimbyContentReportController.checkExistingReport(story.Id, 'Story__c');
        }
        Test.stopTest();

        System.assertEquals(true, firstResult.get('success'), 'First report should succeed');
        System.assertEquals(false, secondResult.get('success'), 'Duplicate report should be blocked');
        System.assertEquals(true, secondResult.get('alreadyReported'), 'Should flag alreadyReported');
        System.assertNotEquals(null, secondResult.get('message'), 'Should return friendly message');
        System.assertEquals(true, checkResult.get('alreadyReported'), 'Pre-flight check should detect duplicate');

        Integer feedbackCount = [
            SELECT COUNT()
            FROM Feedback__c
            WHERE Type__c = 'Content Report'
              AND Posted_By__c = :reporter.Id
              AND Related_Record_ID__c = :story.Id
        ];
        System.assertEquals(1, feedbackCount, 'Only one Feedback row for same represented reporter/content');

        Moderator_Task__c task = [
            SELECT Report_Count__c
            FROM Moderator_Task__c
            WHERE Category__c = 'Content_Report'
              AND Related_Record_Id__c = :story.Id
            LIMIT 1
        ];
        System.assertEquals(1, task.Report_Count__c, 'Report count should stay 1 for same reporter');
    }

    @isTest
    static void testSubmitContentReport_DuplicateBlockedWhenActingAsRepresentedIdentity() {
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact represented = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        Contact helper = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        Story__c story = [SELECT Id FROM Story__c LIMIT 1];

        insert new Support_Relationship__c(
            Contact__c = helper.Id,
            Related_Contact__c = represented.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Approved',
            Neighbourhood__c = neighbourhood.Id
        );

        User userRepresented = FimbyTestDataFactory.createCommunityUser(
            represented.Id, 'Customer Community User - Mobile App', true
        );
        User userHelper = FimbyTestDataFactory.createCommunityUser(
            helper.Id, 'Customer Community User - Mobile App', true
        );

        Map<String, Object> reportData = new Map<String, Object>{
            'contentId' => story.Id,
            'contentType' => 'Story__c',
            'reason' => 'spam',
            'additionalInfo' => 'First report as represented identity'
        };

        helper = [SELECT Id, Logged_In_As_Contact__c FROM Contact WHERE Id = :helper.Id];
        helper.Logged_In_As_Contact__c = represented.Id;
        update helper;

        Test.startTest();
        Map<String, Object> firstResult;
        Map<String, Object> secondResult;
        System.runAs(userRepresented) {
            FimbyIdentityRepository.clearCache();
            firstResult = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
        }
        System.runAs(userHelper) {
            FimbyIdentityRepository.clearCache();
            secondResult = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
        }
        Test.stopTest();

        System.assertEquals(true, firstResult.get('success'), 'First report as represented should succeed');
        System.assertEquals(false, secondResult.get('success'), 'Helper acting as represented should be blocked');
        System.assertEquals(true, secondResult.get('alreadyReported'), 'Should flag alreadyReported');

        Integer feedbackCount = [
            SELECT COUNT()
            FROM Feedback__c
            WHERE Type__c = 'Content Report'
              AND Posted_By__c = :represented.Id
              AND Related_Record_ID__c = :story.Id
        ];
        System.assertEquals(1, feedbackCount, 'Only one Feedback for represented reporter on content');
    }

    @isTest
    static void testCheckExistingReport_NoPriorReport() {
        Story__c story = [SELECT Id FROM Story__c LIMIT 1];

        Test.startTest();
        Map<String, Object> result = FimbyContentReportController.checkExistingReport(story.Id, 'Story');
        Test.stopTest();

        System.assertEquals(false, result.get('alreadyReported'), 'Should not flag when no prior report');
    }

    @isTest
    static void testSubmitContentReport_SecondReporterAppendsEvidence() {
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact reporterA = [SELECT Id FROM Contact LIMIT 1];
        Contact reporterB = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        Story__c story = [SELECT Id FROM Story__c LIMIT 1];

        User userA = FimbyTestDataFactory.createCommunityUser(
            reporterA.Id, 'Customer Community User - Mobile App', true
        );
        User userB = FimbyTestDataFactory.createCommunityUser(
            reporterB.Id, 'Customer Community User - Mobile App', true
        );

        Map<String, Object> reportData = new Map<String, Object>{
            'contentId' => story.Id,
            'contentType' => 'Story__c',
            'reason' => 'harassment',
            'additionalInfo' => 'First reporter'
        };

        Test.startTest();
        Map<String, Object> firstResult;
        Map<String, Object> secondResult;
        System.runAs(userA) {
            FimbyIdentityRepository.clearCache();
            firstResult = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
        }
        reportData.put('additionalInfo', 'Second reporter');
        System.runAs(userB) {
            FimbyIdentityRepository.clearCache();
            secondResult = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
        }
        Test.stopTest();

        System.assertEquals(true, firstResult.get('success'), 'First reporter should succeed');
        System.assertEquals(true, secondResult.get('success'), 'Second reporter should append evidence');

        Moderator_Task__c task = [
            SELECT Report_Count__c
            FROM Moderator_Task__c
            WHERE Category__c = 'Content_Report'
              AND Related_Record_Id__c = :story.Id
            LIMIT 1
        ];
        System.assertEquals(2, task.Report_Count__c, 'Both reporters should count on one task');

        Integer evidenceCount = [
            SELECT COUNT()
            FROM Moderator_Task_Evidence__c
            WHERE Moderator_Task__c = :task.Id
        ];
        System.assertEquals(2, evidenceCount, 'Each reporter should have evidence');
    }

    @isTest
    static void testSubmitContentReport_ReopensStaleResolvedTask() {
        Account neighbourhood = [SELECT Id FROM Account LIMIT 1];
        Contact reporterA = [SELECT Id FROM Contact LIMIT 1];
        Contact reporterB = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        Story__c story = [SELECT Id FROM Story__c LIMIT 1];

        User userA = FimbyTestDataFactory.createCommunityUser(
            reporterA.Id, 'Customer Community User - Mobile App', true
        );
        User userB = FimbyTestDataFactory.createCommunityUser(
            reporterB.Id, 'Customer Community User - Mobile App', true
        );

        Map<String, Object> reportData = new Map<String, Object>{
            'contentId' => story.Id,
            'contentType' => 'Story__c',
            'reason' => 'inappropriate',
            'additionalInfo' => 'Original report'
        };

        System.runAs(userA) {
            FimbyIdentityRepository.clearCache();
            FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
        }

        Moderator_Task__c task = [
            SELECT Id, Status__c, Resolved_Date__c
            FROM Moderator_Task__c
            WHERE Related_Record_Id__c = :story.Id
            LIMIT 1
        ];
        task.Status__c = 'Resolved';
        task.Resolved_Date__c = Datetime.now().addDays(-3);
        update task;

        Test.startTest();
        Map<String, Object> secondResult;
        System.runAs(userB) {
            FimbyIdentityRepository.clearCache();
            reportData.put('additionalInfo', 'After stale resolve');
            secondResult = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
        }
        Test.stopTest();

        System.assertEquals(true, secondResult.get('success'), 'Should reopen stale task instead of duplicate insert');

        Moderator_Task__c refreshed = [
            SELECT Status__c, Report_Count__c
            FROM Moderator_Task__c
            WHERE Id = :task.Id
        ];
        System.assertEquals('New', refreshed.Status__c, 'Stale resolved task should reopen');
        System.assertEquals(2, refreshed.Report_Count__c, 'Second reporter evidence should increment count');
    }

    @isTest
    static void testSubmitContentReport_WithAdditionalInfo() {
        Story__c story = [SELECT Id FROM Story__c LIMIT 1];

        String additionalInfo = 'This is detailed additional information about why this content is being reported.';
        
        Map<String, Object> reportData = new Map<String, Object>{
            'contentId' => story.Id,
            'contentType' => 'Story',
            'reason' => 'other',
            'additionalInfo' => additionalInfo
        };

        Test.startTest();
        Map<String, Object> result = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
        Test.stopTest();

        System.assertEquals(true, result.get('success'), 'Should return success');
        
        // Verify the details contain the additional info
        Feedback__c feedback = [SELECT Details__c FROM Feedback__c WHERE Type__c = 'Content Report' ORDER BY CreatedDate DESC LIMIT 1];
        System.assert(feedback.Details__c.contains(additionalInfo), 'Details should contain additional info');
    }
}