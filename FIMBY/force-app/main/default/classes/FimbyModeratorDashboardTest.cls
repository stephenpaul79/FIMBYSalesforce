@isTest
public class FimbyModeratorDashboardTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        List<Contact> contacts = FimbyTestDataFactory.createNeighbourhoodContacts(neighbourhood.Id, 3, true);

        User modUser = FimbyTestDataFactory.createCommunityUser(contacts[0].Id, 'Customer Community User', true);

        Moderator_Assignment__c assignment = new Moderator_Assignment__c(
            Contact__c = contacts[0].Id,
            Neighbourhood__c = neighbourhood.Id,
            Status__c = 'Active',
            Role__c = 'Primary',
            Assigned_Date__c = Datetime.now(),
            OwnerId = modUser.Id
        );
        insert assignment;
    }

    static Account getNeighbourhood() {
        return [SELECT Id FROM Account WHERE RecordType.DeveloperName = 'Boundary_Account' LIMIT 1];
    }

    static List<Contact> getContacts() {
        return [SELECT Id, Name, AccountId FROM Contact WHERE Account.RecordType.DeveloperName = 'Boundary_Account' ORDER BY CreatedDate LIMIT 3];
    }

    static Contact getModeratorContact() {
        return getContacts()[0];
    }

    static User getModeratorUser() {
        Contact mod = getModeratorContact();
        return [SELECT Id FROM User WHERE ContactId = :mod.Id LIMIT 1];
    }

    static Moderator_Task__c insertPreClaimedTask(Id nhId, String category, String dedupSuffix) {
        User modUser = getModeratorUser();
        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nhId,
            Category__c = category,
            Priority__c = 'Standard',
            Status__c = 'In_Progress',
            Summary__c = 'Test ' + dedupSuffix,
            Report_Count__c = 1,
            Claimed_Date__c = Datetime.now(),
            OwnerId = modUser.Id,
            Task_Dedup_Key__c = nhId + ':' + category + ':' + dedupSuffix
        );
        insert task;
        return task;
    }

    // ── TaskService Tests ──

    @isTest
    static void testCreateTask() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        FimbyModeratorTaskService.TaskRequest req = new FimbyModeratorTaskService.TaskRequest();
        req.neighbourhoodId = nh.Id;
        req.category = 'Content_Report';
        req.priority = 'Standard';
        req.subjectContactId = contacts[1].Id;
        req.relatedRecordId = 'fakeRecordId123456';
        req.relatedRecordType = 'Needs_Offers__c';
        req.summary = 'Test content report';
        req.sourceType = 'Content_Report';
        req.reporterContactId = contacts[2].Id;
        req.reasonCode = 'spam';
        req.details = 'Test details';

        Test.startTest();
        Moderator_Task__c task = FimbyModeratorTaskService.createOrUpdateTask(req);
        Test.stopTest();

        System.assertNotEquals(null, task.Id, 'Task should be created');
        System.assertEquals('New', task.Status__c, 'Status should be New');
        System.assertEquals(1, task.Report_Count__c, 'Report count should be 1');

        List<Moderator_Task_Evidence__c> evidence = [
            SELECT Id FROM Moderator_Task_Evidence__c WHERE Moderator_Task__c = :task.Id
        ];
        System.assertEquals(1, evidence.size(), 'Should have 1 evidence record');
    }

    @isTest
    static void testDedupAppendEvidence() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        FimbyModeratorTaskService.TaskRequest req = new FimbyModeratorTaskService.TaskRequest();
        req.neighbourhoodId = nh.Id;
        req.category = 'Content_Report';
        req.priority = 'Standard';
        req.subjectContactId = contacts[1].Id;
        req.relatedRecordId = 'fakeRecordId123456';
        req.relatedRecordType = 'Needs_Offers__c';
        req.summary = 'First report';
        req.sourceType = 'Content_Report';
        req.reporterContactId = contacts[2].Id;

        Moderator_Task__c first = FimbyModeratorTaskService.createOrUpdateTask(req);

        FimbyModeratorTaskService.TaskRequest req2 = new FimbyModeratorTaskService.TaskRequest();
        req2.neighbourhoodId = nh.Id;
        req2.category = 'Content_Report';
        req2.priority = 'Urgent';
        req2.subjectContactId = contacts[1].Id;
        req2.relatedRecordId = 'fakeRecordId123456';
        req2.relatedRecordType = 'Needs_Offers__c';
        req2.summary = 'Second report';
        req2.sourceType = 'Content_Report';
        req2.reporterContactId = contacts[0].Id;
        req2.reasonCode = 'harassment';

        Test.startTest();
        Moderator_Task__c updated = FimbyModeratorTaskService.createOrUpdateTask(req2);
        Test.stopTest();

        System.assertEquals(first.Id, updated.Id, 'Should reuse the same task');
        Moderator_Task__c refreshed = [SELECT Report_Count__c, Priority__c FROM Moderator_Task__c WHERE Id = :first.Id];
        System.assertEquals(2, refreshed.Report_Count__c, 'Report count should be 2');
        System.assertEquals('Urgent', refreshed.Priority__c, 'Priority should upgrade to Urgent');
    }

    @isTest
    static void testBuildDedupKey() {
        FimbyModeratorTaskService.TaskRequest req = new FimbyModeratorTaskService.TaskRequest();
        req.neighbourhoodId = '001000000000001';
        req.category = 'Content_Report';
        req.relatedRecordId = 'a0y000000000001';
        req.relatedRecordType = 'Needs_Offers__c';

        String key = FimbyModeratorTaskService.buildDedupKey(req);
        System.assert(key.contains(':Content_Report:'), 'Key should contain category');
    }

    @isTest
    static void testBuildDedupKeyBySubject() {
        FimbyModeratorTaskService.TaskRequest req = new FimbyModeratorTaskService.TaskRequest();
        req.neighbourhoodId = '001000000000001';
        req.category = 'New_Signup';
        req.subjectContactId = '003000000000001';

        String key = FimbyModeratorTaskService.buildDedupKey(req);
        System.assert(key.contains(':New_Signup:'), 'Key should contain category');
        System.assert(key.contains('003000000000001'), 'Key should contain subject contact');
    }

    @isTest
    static void testReopenResolvedTask() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        FimbyModeratorTaskService.TaskRequest req = new FimbyModeratorTaskService.TaskRequest();
        req.neighbourhoodId = nh.Id;
        req.category = 'Content_Report';
        req.priority = 'Standard';
        req.subjectContactId = contacts[1].Id;
        req.relatedRecordId = 'reopenRec123';
        req.relatedRecordType = 'Needs_Offers__c';
        req.summary = 'Will resolve then reopen';
        req.sourceType = 'Content_Report';
        req.reporterContactId = contacts[2].Id;

        Moderator_Task__c task = FimbyModeratorTaskService.createOrUpdateTask(req);
        task.Status__c = 'Resolved';
        task.Resolved_Date__c = Datetime.now();
        update task;

        FimbyModeratorTaskService.TaskRequest req2 = new FimbyModeratorTaskService.TaskRequest();
        req2.neighbourhoodId = nh.Id;
        req2.category = 'Content_Report';
        req2.priority = 'Standard';
        req2.subjectContactId = contacts[1].Id;
        req2.relatedRecordId = 'reopenRec123';
        req2.relatedRecordType = 'Needs_Offers__c';
        req2.summary = 'Reopened report';
        req2.sourceType = 'Content_Report';
        req2.reporterContactId = contacts[0].Id;

        Test.startTest();
        Moderator_Task__c reopened = FimbyModeratorTaskService.createOrUpdateTask(req2);
        Test.stopTest();

        System.assertEquals(task.Id, reopened.Id, 'Should reuse resolved task');
        Moderator_Task__c refreshed = [SELECT Status__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('New', refreshed.Status__c, 'Should be reopened');
    }

    // ── QueryService Tests ──

    @isTest
    static void testDashboardSummary() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'New_Signup',
            Priority__c = 'Standard',
            Status__c = 'New',
            Subject_Contact__c = contacts[1].Id,
            Summary__c = 'Test signup',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':New_Signup:' + contacts[1].Id
        );
        insert task;

        Test.startTest();
        Map<String, Object> summary = FimbyModeratorQueryService.getDashboardSummary(nh.Id);
        Test.stopTest();

        System.assertEquals(1, (Integer) summary.get('totalCount'));
    }

    @isTest
    static void testGetTasksByCategory() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'New_Signup',
            Priority__c = 'Standard',
            Status__c = 'New',
            Subject_Contact__c = contacts[1].Id,
            Summary__c = 'Test',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':New_Signup:taskcat'
        );
        insert task;

        Test.startTest();
        List<Moderator_Task__c> tasks = FimbyModeratorQueryService.getTasksByCategory(nh.Id, 'New_Signup', 20, 0);
        List<Moderator_Task__c> allTasks = FimbyModeratorQueryService.getTasksByCategory(nh.Id, 'All', 20, 0);
        Test.stopTest();

        System.assertEquals(1, tasks.size());
        System.assert(allTasks.size() >= 1);
    }

    @isTest
    static void testGetEscalatedTasks() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Content_Report',
            Priority__c = 'Standard',
            Status__c = 'Escalated',
            Escalated_To__c = contacts[2].Id,
            Escalated_Date__c = Datetime.now(),
            Summary__c = 'Escalated task',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Content_Report:escalatedquery'
        );
        insert task;

        Test.startTest();
        List<Moderator_Task__c> tasks = FimbyModeratorQueryService.getEscalatedTasks(nh.Id, 20, 0);
        Test.stopTest();

        System.assertEquals(1, tasks.size());
    }

    @isTest
    static void testGetContentReviewData() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Content Review Test',
            Contact__c = contacts[1].Id,
            Posted_By__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Posted',
            Type__c = 'Goods - Unperishable'
        );
        insert post;

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getContentReviewData(String.valueOf(post.Id), 'Needs_Offers__c', null);
        Map<String, Object> empty = FimbyModeratorQueryService.getContentReviewData('fakeId123456789', 'Unknown__c', null);
        Test.stopTest();

        System.assertNotEquals(null, data.get('contentTitle'), 'Should have contentTitle');
        System.assertEquals('Needs_Offers__c', data.get('recordType'));
        System.assertEquals(null, empty.get('contentTitle'), 'Unknown type should have no content fields');
    }

    @isTest
    static void testGetContentReviewDataStory() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Story__c story = new Story__c(
            Name = 'Story Review Test',
            Posted_By__c = contacts[1].Id,
            Contact__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Message__c = 'A test story message'
        );
        insert story;

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getContentReviewData(String.valueOf(story.Id), 'Story__c', null);
        Test.stopTest();

        System.assertEquals('Story__c', data.get('recordType'));
        System.assertNotEquals(null, data.get('contentTitle'));
        System.assertEquals('A test story message', data.get('contentBody'));
    }

    @isTest
    static void testGetContentReviewDataResponse() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Parent Post',
            Contact__c = contacts[1].Id,
            Posted_By__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Posted',
            Type__c = 'Goods - Unperishable'
        );
        insert post;

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = contacts[2].Id,
            Response__c = 'I can help with that',
            Status__c = 'New'
        );
        insert resp;

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getContentReviewData(String.valueOf(resp.Id), 'Response__c', null);
        Test.stopTest();

        System.assertEquals('Response__c', data.get('recordType'));
        System.assertNotEquals(null, data.get('contentTitle'));
    }

    @isTest
    static void testGetContentReviewDataLibraryItem() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Library_Item__c item = new Library_Item__c(
            Name = 'Library Review Test',
            Owner_Contact__c = contacts[1].Id,
            Listed_By__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Description__c = 'A test library item',
            Status__c = 'Available'
        );
        insert item;

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getContentReviewData(String.valueOf(item.Id), 'Library_Item__c', null);
        Test.stopTest();

        System.assertEquals('Library_Item__c', data.get('recordType'));
        System.assertNotEquals(null, data.get('contentTitle'));
    }

    @isTest
    static void testGetFollowUpReviewData() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Needs_Offers__c bulkBuy = new Needs_Offers__c(
            Name = 'Test Bulk Buy',
            Contact__c = contacts[0].Id,
            Posted_By__c = contacts[0].Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Posted',
            Type__c = 'Goods - Unperishable',
            RecordTypeId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName().get('Bulk_Buy').getRecordTypeId()
        );
        insert bulkBuy;

        Bulk_Buy_Follow_Up__c fu = new Bulk_Buy_Follow_Up__c(
            Bulk_Buy__c = bulkBuy.Id,
            Reported_User__c = contacts[1].Id,
            Reporter__c = contacts[2].Id,
            Status__c = 'Pending'
        );
        insert fu;

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getFollowUpReviewData(fu.Id);
        Test.stopTest();

        System.assertNotEquals(null, data.get('bulkBuyName'));
        System.assertNotEquals(null, data.get('reportedUserName'));
        System.assertEquals(false, (Boolean) data.get('isBlocked'));
    }

    @isTest
    static void testGetBlockReviewData() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Blocked_Contact__c bc = new Blocked_Contact__c(
            Blocker__c = contacts[1].Id,
            Blocked__c = contacts[2].Id,
            Reported__c = true,
            Report_Details__c = 'Test block for review'
        );
        insert bc;

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getBlockReviewData(bc.Id);
        Test.stopTest();

        System.assertNotEquals(null, data.get('blockerName'));
        System.assertNotEquals(null, data.get('blockedName'));
        System.assertEquals('Test block for review', data.get('reportDetails'));
    }

    @isTest
    static void testGetBlockReviewData_missingRecord() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Blocked_Contact__c bc = new Blocked_Contact__c(
            Blocker__c = contacts[1].Id,
            Blocked__c = contacts[2].Id,
            Reported__c = true
        );
        insert bc;
        Id blockId = bc.Id;
        delete bc;

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getBlockReviewData(blockId);
        Test.stopTest();

        System.assertEquals(true, data.get('recordMissing'));
        System.assertEquals('', data.get('blockerName'));
    }

    @isTest
    static void testGetFeedbackReviewData() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Feedback__c fb = new Feedback__c(
            Name = 'Review Test',
            Type__c = 'Bug',
            Details__c = 'Test details',
            Neighbourhood__c = nh.Id,
            Posted_By__c = contacts[1].Id
        );
        insert fb;

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getFeedbackReviewData(fb.Id);
        Test.stopTest();

        System.assertEquals('Bug', data.get('type'));
        System.assertEquals('Review Test', data.get('title'));
        System.assertEquals('Test details', data.get('description'));
        System.assertEquals(contacts[1].Id, data.get('submitterContactId'));
    }

    @isTest
    static void testGetSupportReviewData() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Support_Relationship__c sr = new Support_Relationship__c(
            Contact__c = contacts[1].Id,
            Related_Contact__c = contacts[2].Id,
            Neighbourhood__c = nh.Id,
            Relationship_Type__c = 'Support_Person',
            Consent_Method__c = 'Verbal',
            Notes__c = 'Support review notes',
            Status__c = 'Pending'
        );
        insert sr;

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getSupportReviewData(sr.Id);
        Test.stopTest();

        System.assertEquals(contacts[1].Id, data.get('helperContactId'));
        System.assertEquals(contacts[2].Id, data.get('subjectContactId'));
        System.assertEquals('Support_Person', data.get('relationshipType'));
        System.assertEquals('Support review notes', data.get('notes'));
    }

    @isTest
    static void testGetSupportConcernData() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Support_Person_Concern',
            Priority__c = 'Standard',
            Status__c = 'New',
            Subject_Contact__c = contacts[1].Id,
            Secondary_Contact__c = contacts[2].Id,
            Summary__c = 'Support concern',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Support_Person_Concern:concern1'
        );
        insert task;

        Moderator_Task_Evidence__c ev = new Moderator_Task_Evidence__c(
            Moderator_Task__c = task.Id,
            Source_Type__c = 'Content_Report',
            Reporter__c = contacts[2].Id,
            Reported_Date__c = Datetime.now(),
            Reason_Code__c = 'concern',
            Details__c = 'Details here'
        );
        insert ev;

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getSupportConcernData(task.Id);
        Test.stopTest();

        System.assertEquals('Support concern', data.get('concernSummary'));
        System.assertEquals(contacts[2].Id, data.get('helperContactId'));
        System.assertEquals(contacts[1].Id, data.get('subjectContactId'));
        System.assertEquals(1, ((List<Object>) data.get('helperRecentActivity')).size());
        System.assertEquals(1, ((List<Object>) data.get('evidenceItems')).size());
    }

    @isTest
    static void testGetEscalationDetail() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Content_Report',
            Priority__c = 'Urgent',
            Status__c = 'Escalated',
            Escalated_To__c = contacts[2].Id,
            Escalated_Date__c = Datetime.now(),
            Escalation_Reason__c = 'Needs admin',
            Summary__c = 'Escalation detail',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Content_Report:escaldetail'
        );
        insert task;

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getEscalationDetail(task.Id);
        Test.stopTest();

        System.assertEquals('Needs admin', data.get('escalationReason'));
        System.assertEquals(contacts[2].Id, data.get('escalatedToContactId'));
        System.assertEquals(false, data.get('isResolved'));
    }

    @isTest
    static void testGetWelcomeReviewData() {
        List<Contact> contacts = getContacts();

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getWelcomeReviewData(contacts[1].Id);
        Test.stopTest();

        System.assertEquals(contacts[1].Id, data.get('contactId'));
        System.assertNotEquals(null, data.get('contactName'));
        System.assertNotEquals(null, data.get('welcomeTemplate'));
    }

    @isTest
    static void testModeratorHeaderData() {
        Contact mod = getModeratorContact();

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getModeratorHeaderData(mod.Id);
        Test.stopTest();

        System.assertEquals(true, (Boolean) data.get('isModerator'));
    }

    @isTest
    static void testModeratorHeaderDataNonModerator() {
        List<Contact> contacts = getContacts();

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getModeratorHeaderData(contacts[1].Id);
        Test.stopTest();

        System.assertEquals(false, (Boolean) data.get('isModerator'));
    }

    @isTest
    static void testGetModeratorAssignments() {
        Contact mod = getModeratorContact();

        Test.startTest();
        List<Moderator_Assignment__c> assignments = FimbyModeratorQueryService.getModeratorAssignments(mod.Id);
        Test.stopTest();

        System.assertEquals(1, assignments.size());
    }

    @isTest
    static void testSubjectHistory() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Test.startTest();
        Map<String, Object> history = FimbyModeratorQueryService.getSubjectHistory(contacts[1].Id, nh.Id, null);
        Test.stopTest();

        System.assertNotEquals(null, history.get('subject'));
    }

    @isTest
    static void testGetStaleExpiredPosts() {
        Account nh = getNeighbourhood();

        Test.startTest();
        List<Needs_Offers__c> posts = FimbyModeratorQueryService.getStaleExpiredPosts(nh.Id);
        Test.stopTest();

        System.assertNotEquals(null, posts);
    }

    @isTest
    static void testGetInactiveMembers() {
        Account nh = getNeighbourhood();

        Test.startTest();
        List<Contact> inactive = FimbyModeratorQueryService.getInactiveMembers(nh.Id);
        Test.stopTest();

        System.assertNotEquals(null, inactive);
    }

    @isTest
    static void testGetOverdueLoans() {
        Account nh = getNeighbourhood();

        Test.startTest();
        List<Library_Item__c> items = FimbyModeratorQueryService.getOverdueLoans(nh.Id);
        Test.stopTest();

        System.assertNotEquals(null, items);
    }

    @isTest
    static void testGetNeighbourhoodHealthData() {
        Account nh = getNeighbourhood();

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getNeighbourhoodHealthData(nh.Id);
        Test.stopTest();

        System.assertNotEquals(null, data.get('overdueLoans'));
        System.assertNotEquals(null, data.get('stalePosts'));
        System.assertNotEquals(null, data.get('inactiveMembers'));
    }

    @isTest
    static void testGetContentReviewDataWithEvidence() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Evidence Review Test',
            Contact__c = contacts[1].Id,
            Posted_By__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Posted',
            Type__c = 'Goods - Unperishable'
        );
        insert post;

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Content_Report',
            Priority__c = 'Standard',
            Status__c = 'New',
            Related_Record_Id__c = String.valueOf(post.Id),
            Related_Record_Type__c = 'Needs_Offers__c',
            Secondary_Contact__c = contacts[2].Id,
            Summary__c = 'Content report test',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Content_Report:Needs_Offers__c:' + post.Id
        );
        insert task;

        insert new Moderator_Task_Evidence__c(
            Moderator_Task__c = task.Id,
            Source_Type__c = 'Content_Report',
            Reporter__c = contacts[2].Id,
            Reported_Date__c = Datetime.now(),
            Reason_Code__c = 'spam',
            Details__c = 'Looks like spam'
        );

        Test.startTest();
        Map<String, Object> data = FimbyModeratorQueryService.getContentReviewData(
            String.valueOf(post.Id), 'Needs_Offers__c', task.Id
        );
        Test.stopTest();

        List<Object> evidence = (List<Object>) data.get('evidenceItems');
        System.assertEquals(1, evidence.size(), 'Should return evidence timeline items');
    }

    // ── ActionService Tests ──

    @isTest
    static void testResolveTask() {
        Account nh = getNeighbourhood();
        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Feedback_Triage', 'resolvetest');

        Test.startTest();
        FimbyModeratorActionService.resolveTask(task.Id, 'Resolved', 'Done', getModeratorContact().Id);
        Test.stopTest();

        Moderator_Task__c updated = [SELECT Status__c, Resolved_Date__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('Resolved', updated.Status__c);
        System.assertNotEquals(null, updated.Resolved_Date__c);
    }

    @isTest
    static void testResolveTaskAlreadyClosedThrows() {
        Account nh = getNeighbourhood();
        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Feedback_Triage', 'closedguard');
        Datetime originalResolved = Datetime.now().addDays(-2);
        Id modContactId = getModeratorContact().Id;

        FimbyModeratorActionService.resolveTask(task.Id, 'Resolved', 'Done', modContactId);

        Moderator_Task__c closed = [
            SELECT Status__c, Resolved_Date__c, Resolved_By__c
            FROM Moderator_Task__c WHERE Id = :task.Id
        ];
        System.assertEquals('Resolved', closed.Status__c);
        System.assertNotEquals(null, closed.Resolved_Date__c);
        System.assertEquals(modContactId, closed.Resolved_By__c);

        Boolean threw = false;
        try {
            FimbyModeratorActionService.resolveTask(task.Id, 'Dismissed', 'Again', modContactId);
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Should throw when resolving an already-closed task');

        Moderator_Task__c unchanged = [
            SELECT Status__c, Resolved_Date__c, Resolved_By__c
            FROM Moderator_Task__c WHERE Id = :task.Id
        ];
        System.assertEquals('Resolved', unchanged.Status__c);
        System.assertEquals(closed.Resolved_Date__c, unchanged.Resolved_Date__c);
        System.assertEquals(modContactId, unchanged.Resolved_By__c);
    }

    @isTest
    static void testReopenResolvedTaskRoundTrip() {
        Account nh = getNeighbourhood();
        Id modContactId = getModeratorContact().Id;
        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Content_Report', 'reopenroundtrip');

        FimbyModeratorActionService.resolveTask(task.Id, 'Resolved', 'First close', modContactId);

        Test.startTest();
        FimbyModeratorActionService.reopenTask(task.Id);
        Moderator_Task__c reopened = [
            SELECT Status__c, Resolved_Date__c, Resolved_By__c
            FROM Moderator_Task__c WHERE Id = :task.Id
        ];
        System.assertEquals('In_Progress', reopened.Status__c);
        System.assertEquals(null, reopened.Resolved_Date__c);
        System.assertEquals(null, reopened.Resolved_By__c);

        FimbyModeratorActionService.resolveTask(task.Id, 'Resolved', 'Second close', modContactId);
        Test.stopTest();

        Moderator_Task__c finalTask = [
            SELECT Status__c, Resolved_Date__c
            FROM Moderator_Task__c WHERE Id = :task.Id
        ];
        System.assertEquals('Resolved', finalTask.Status__c);
        System.assertNotEquals(null, finalTask.Resolved_Date__c);
    }

    @isTest
    static void testGetClosedTasksFiltersAndPagination() {
        Account nh = getNeighbourhood();
        Id modContactId = getModeratorContact().Id;

        Moderator_Task__c openTask = insertPreClaimedTask(nh.Id, 'New_Signup', 'openarchive');
        openTask.Status__c = 'New';
        update openTask;

        Moderator_Task__c resolvedContent = insertPreClaimedTask(nh.Id, 'Content_Report', 'resolvedarchive');
        FimbyModeratorActionService.resolveTask(resolvedContent.Id, 'Resolved', 'Done', modContactId);

        Moderator_Task__c dismissedFeedback = insertPreClaimedTask(nh.Id, 'Feedback_Triage', 'dismissedarchive');
        FimbyModeratorActionService.resolveTask(dismissedFeedback.Id, 'Dismissed', 'No action', modContactId);

        Moderator_Task__c escalated = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Blocked_Contact',
            Priority__c = 'Standard',
            Status__c = 'Escalated',
            Escalated_Date__c = Datetime.now(),
            Summary__c = 'Escalated task',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Blocked_Contact:escarchive'
        );
        insert escalated;

        Test.startTest();
        Map<String, Object> allClosed = FimbyModeratorQueryService.getClosedTasks(nh.Id, 'All', 'All', 20, 0);
        Map<String, Object> resolvedOnly = FimbyModeratorQueryService.getClosedTasks(nh.Id, 'All', 'Resolved', 20, 0);
        Map<String, Object> contentOnly = FimbyModeratorQueryService.getClosedTasks(nh.Id, 'Content_Report', 'All', 20, 0);
        Test.stopTest();

        List<Moderator_Task__c> allItems = (List<Moderator_Task__c>) allClosed.get('items');
        System.assertEquals(2, allClosed.get('totalCount'), 'Should count only Resolved and Dismissed');
        System.assertEquals(2, allItems.size());
        for (Moderator_Task__c t : allItems) {
            System.assert(
                t.Status__c == 'Resolved' || t.Status__c == 'Dismissed',
                'Archive should exclude open and escalated tasks'
            );
        }

        List<Moderator_Task__c> resolvedItems = (List<Moderator_Task__c>) resolvedOnly.get('items');
        System.assertEquals(1, resolvedOnly.get('totalCount'));
        System.assertEquals(1, resolvedItems.size());
        System.assertEquals('Resolved', resolvedItems[0].Status__c);

        List<Moderator_Task__c> contentItems = (List<Moderator_Task__c>) contentOnly.get('items');
        System.assertEquals(1, contentOnly.get('totalCount'));
        System.assertEquals('Content_Report', contentItems[0].Category__c);
    }

    @isTest
    static void testGetClosedTasksControllerRequiresModerator() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User nonModUser = FimbyTestDataFactory.createCommunityUser(contacts[1].Id, 'Customer Community User', true);

        Boolean threw = false;
        System.runAs(nonModUser) {
            try {
                FimbyModeratorDashboardController.getClosedTasks(nh.Id, 'All', 'All', 20, 0);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assertEquals(true, threw, 'Non-moderator should be denied');
    }

    @isTest
    static void testEscalateTask() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Blocked_Contact', 'escalatetest');

        Test.startTest();
        FimbyModeratorActionService.escalateTask(task.Id, 'Need admin help', contacts[0].Id, contacts[2].Id);
        Test.stopTest();

        Moderator_Task__c updated = [SELECT Status__c, Escalated_To__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('Escalated', updated.Status__c);
        System.assertEquals(contacts[2].Id, updated.Escalated_To__c);
    }

    @isTest
    static void testReopenTask() {
        Account nh = getNeighbourhood();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Content_Report',
            Priority__c = 'Standard',
            Status__c = 'Escalated',
            Escalated_Date__c = Datetime.now(),
            Summary__c = 'Test',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Content_Report:reopentest'
        );
        insert task;

        Test.startTest();
        FimbyModeratorActionService.reopenTask(task.Id);
        Test.stopTest();

        Moderator_Task__c updated = [SELECT Status__c, Escalated_To__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('In_Progress', updated.Status__c);
    }

    @isTest
    static void testReleaseTask() {
        Account nh = getNeighbourhood();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Feedback_Triage',
            Priority__c = 'Low',
            Status__c = 'In_Progress',
            Summary__c = 'Test release',
            Report_Count__c = 1,
            Claimed_Date__c = Datetime.now(),
            Task_Dedup_Key__c = nh.Id + ':Feedback_Triage:releasetest'
        );
        insert task;

        Test.startTest();
        FimbyModeratorActionService.releaseTask(task.Id);
        Test.stopTest();

        Moderator_Task__c released = [SELECT Claimed_Date__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals(null, released.Claimed_Date__c);
    }

    @isTest
    static void testReassignTask() {
        Account nh = getNeighbourhood();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Content_Report',
            Priority__c = 'Standard',
            Status__c = 'In_Progress',
            Summary__c = 'Reassign test',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Content_Report:reassign'
        );
        insert task;

        Test.startTest();
        FimbyModeratorActionService.reassignTask(task.Id, UserInfo.getUserId());
        Test.stopTest();

        Moderator_Task__c updated = [SELECT OwnerId FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals(UserInfo.getUserId(), updated.OwnerId);
    }

    @isTest
    static void testRequestMoreInfo() {
        Account nh = getNeighbourhood();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Content_Report',
            Priority__c = 'Standard',
            Status__c = 'In_Progress',
            Summary__c = 'More info test',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Content_Report:moreinfo'
        );
        insert task;

        Test.startTest();
        FimbyModeratorActionService.requestMoreInfo(task.Id);
        Test.stopTest();

        Moderator_Task__c updated = [SELECT Status__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('Awaiting_Info', updated.Status__c);
    }

    @isTest
    static void testRequestReReview() {
        Account nh = getNeighbourhood();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Content_Report',
            Priority__c = 'Standard',
            Status__c = 'Resolved',
            Resolved_Date__c = Datetime.now(),
            Summary__c = 'Test',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Content_Report:reviewtest'
        );
        insert task;

        Test.startTest();
        FimbyModeratorActionService.requestReReview(task.Id);
        Test.stopTest();

        Moderator_Task__c updated = [SELECT Status__c, Re_Review_Requested__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('New', updated.Status__c);
        System.assertEquals(true, updated.Re_Review_Requested__c);
    }

    @isTest
    static void testFlagAndRepublishContent() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Test Post',
            Contact__c = contacts[1].Id,
            Posted_By__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Posted',
            Type__c = 'Goods - Unperishable'
        );
        insert post;

        Test.startTest();
        FimbyModeratorActionService.flagContent(String.valueOf(post.Id), 'Needs_Offers__c', 'Spam', contacts[0].Id);

        Needs_Offers__c hidden = [SELECT Moderation_Status__c, Hidden_By_Moderator__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Hidden_By_Moderator', hidden.Moderation_Status__c);
        System.assertEquals(contacts[0].Id, hidden.Hidden_By_Moderator__c);

        FimbyModeratorActionService.republishContent(String.valueOf(post.Id), 'Needs_Offers__c', null);

        Needs_Offers__c visible = [SELECT Moderation_Status__c, Hidden_By_Moderator__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Visible', visible.Moderation_Status__c);
        System.assertEquals(null, visible.Hidden_By_Moderator__c);
        Test.stopTest();
    }

    @isTest
    static void testFlagStory_ModeratorReview_SetsUnderReview() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Story__c story = new Story__c(
            Name = 'Story Under Review',
            Posted_By__c = contacts[1].Id,
            Contact__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Message__c = 'Body'
        );
        insert story;

        Test.startTest();
        FimbyModeratorActionService.flagContent(String.valueOf(story.Id), 'Story__c', 'Moderator_Review', contacts[0].Id);
        Test.stopTest();

        Story__c reviewed = [
            SELECT Moderation_Status__c, Hidden_By_Moderator__c, Hidden_Reason_Code__c
            FROM Story__c WHERE Id = :story.Id
        ];
        System.assertEquals('Under_Review', reviewed.Moderation_Status__c);
        System.assertEquals(null, reviewed.Hidden_By_Moderator__c);
        System.assertEquals(null, reviewed.Hidden_Reason_Code__c);
    }

    @isTest
    static void testFlagContent_ModeratorReview_OtherRecordTypes() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Review Post',
            Contact__c = contacts[1].Id,
            Posted_By__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Posted',
            Type__c = 'Goods - Unperishable'
        );
        insert post;

        Response__c resp = new Response__c(
            Need_Offer_Responded_To__c = post.Id,
            Contact__c = contacts[1].Id,
            On_Behalf_Of_Contact__c = contacts[1].Id,
            Neighbourhood__c = nh.Id
        );
        insert resp;

        Test.startTest();
        FimbyModeratorActionService.flagContent(String.valueOf(post.Id), 'Needs_Offers__c', 'Moderator_Review', contacts[0].Id);
        FimbyModeratorActionService.flagContent(String.valueOf(resp.Id), 'Response__c', 'Moderator_Review', contacts[0].Id);
        Test.stopTest();

        Needs_Offers__c hiddenPost = [
            SELECT Moderation_Status__c, Hidden_Reason_Code__c FROM Needs_Offers__c WHERE Id = :post.Id
        ];
        System.assertEquals('Under_Review', hiddenPost.Moderation_Status__c);
        System.assertEquals(null, hiddenPost.Hidden_Reason_Code__c);

        Response__c hiddenResp = [
            SELECT Moderation_Status__c FROM Response__c WHERE Id = :resp.Id
        ];
        System.assertEquals('Under_Review', hiddenResp.Moderation_Status__c);
    }

    @isTest
    static void testFlagStory_ModeratorHidden_SetsHiddenReason() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Story__c story = new Story__c(
            Name = 'Story To Hide',
            Posted_By__c = contacts[1].Id,
            Contact__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Message__c = 'Body'
        );
        insert story;

        Test.startTest();
        FimbyModeratorActionService.flagContent(String.valueOf(story.Id), 'Story__c', 'Moderator_Hidden', contacts[0].Id);
        Test.stopTest();

        Story__c hidden = [
            SELECT Moderation_Status__c, Hidden_By_Moderator__c, Hidden_Reason_Code__c
            FROM Story__c WHERE Id = :story.Id
        ];
        System.assertEquals('Hidden_By_Moderator', hidden.Moderation_Status__c);
        System.assertEquals(contacts[0].Id, hidden.Hidden_By_Moderator__c);
        System.assertEquals('Moderator_Hidden', hidden.Hidden_Reason_Code__c);
    }

    @isTest
    static void testFlagAndRepublishStory() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Story__c story = new Story__c(
            Name = 'Story To Be Flagged',
            Posted_By__c = contacts[1].Id,
            Contact__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Message__c = 'Body of the story'
        );
        insert story;

        Test.startTest();
        FimbyModeratorActionService.flagContent(String.valueOf(story.Id), 'Story__c', 'Inappropriate_Content', contacts[0].Id);

        Story__c hidden = [
            SELECT Moderation_Status__c, Hidden_By_Moderator__c, Hidden_Date__c, Hidden_Reason_Code__c
            FROM Story__c WHERE Id = :story.Id
        ];
        System.assertEquals('Hidden_By_Moderator', hidden.Moderation_Status__c);
        System.assertEquals(contacts[0].Id, hidden.Hidden_By_Moderator__c);
        System.assertNotEquals(null, hidden.Hidden_Date__c);

        FimbyModeratorActionService.republishContent(String.valueOf(story.Id), 'Story__c', null);

        Story__c visible = [
            SELECT Moderation_Status__c, Hidden_By_Moderator__c, Hidden_Date__c, Hidden_Reason_Code__c
            FROM Story__c WHERE Id = :story.Id
        ];
        System.assertEquals('Visible', visible.Moderation_Status__c);
        System.assertEquals(null, visible.Hidden_By_Moderator__c);
        Test.stopTest();
    }

    @isTest
    static void testKeepContentHidden() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Keep Hidden Test',
            Contact__c = contacts[1].Id,
            Posted_By__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Posted',
            Type__c = 'Goods - Unperishable'
        );
        insert post;
        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Content_Report', 'keephidden');
        task.Related_Record_Id__c = String.valueOf(post.Id);
        task.Related_Record_Type__c = 'Needs_Offers__c';
        update task;

        Test.startTest();
        FimbyModeratorActionService.keepContentHidden(task.Id, 'Harassment', 'Content violates guidelines', 'Review notes', getModeratorContact().Id);
        Test.stopTest();

        Moderator_Task__c updated = [SELECT Status__c, Decision_Reason_Code__c FROM Moderator_Task__c WHERE Id = :task.Id];
        Needs_Offers__c hidden = [SELECT Moderation_Status__c, Hidden_Reason_Code__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Resolved', updated.Status__c);
        System.assertEquals('Harassment', updated.Decision_Reason_Code__c);
        System.assertEquals('Hidden_By_Moderator', hidden.Moderation_Status__c);
        System.assertEquals('Harassment', hidden.Hidden_Reason_Code__c);
    }

    @isTest
    static void testIssueCheckIn() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Content_Report', 'checkin');

        Test.startTest();
        FimbyModeratorActionService.issueCheckIn(task.Id, contacts[1].Id, 'Safety_Concern', 'Checking in', contacts[0].Id);
        Test.stopTest();

        Moderator_Task__c updated = [
            SELECT Enforcement_Level__c, Decision_Statement__c, Subject_Contact__c
            FROM Moderator_Task__c WHERE Id = :task.Id
        ];
        System.assertEquals('Check_In', updated.Enforcement_Level__c);
        System.assertEquals('Checking in', updated.Decision_Statement__c);
        System.assertEquals(contacts[1].Id, updated.Subject_Contact__c);
    }

    @isTest
    static void testRecordConcern() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Content_Report', 'concern');

        Test.startTest();
        FimbyModeratorActionService.recordConcern(task.Id, contacts[1].Id, 'Accountability_Concern', 'Pattern of behaviour', contacts[0].Id);
        Test.stopTest();

        Moderator_Task__c updated = [SELECT Enforcement_Level__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('Recorded_Concern', updated.Enforcement_Level__c);
    }

    @isTest
    static void testSendWelcomeMessage() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'New_Signup', 'welcome');

        Test.startTest();
        FimbyModeratorActionService.sendWelcomeMessage(contacts[1].Id, 'Welcome neighbour!', task.Id, contacts[0].Id);
        Test.stopTest();

        Contact updated = [SELECT Welcomed_By__c FROM Contact WHERE Id = :contacts[1].Id];
        System.assertEquals(contacts[0].Id, updated.Welcomed_By__c);
    }

    @isTest
    static void testMarkWelcomed() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'New_Signup', 'markwelcome');

        Test.startTest();
        FimbyModeratorActionService.markWelcomed(contacts[2].Id, task.Id, 'Already welcomed in person', contacts[0].Id);
        Test.stopTest();

        Contact updated = [SELECT Welcomed_By__c FROM Contact WHERE Id = :contacts[2].Id];
        System.assertEquals(contacts[0].Id, updated.Welcomed_By__c);
    }

    @isTest
    static void testTriageFeedback() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Feedback__c fb = new Feedback__c(
            Name = 'Test Feedback',
            Type__c = 'General Feedback',
            Details__c = 'Test',
            Neighbourhood__c = nh.Id,
            Posted_By__c = contacts[1].Id
        );
        insert fb;

        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Feedback_Triage', 'triage_' + fb.Id);

        Test.startTest();
        FimbyModeratorActionService.triageFeedback(fb.Id, 'Enhancement_Flagged', task.Id, contacts[0].Id);
        Test.stopTest();

        Feedback__c updated = [SELECT Triage_Status__c, Status__c FROM Feedback__c WHERE Id = :fb.Id];
        System.assertEquals('Enhancement_Flagged', updated.Triage_Status__c);
        System.assertEquals('Roadmap', updated.Status__c);
    }

    @isTest
    static void testGetOrCreateModeratorConversation() {
        List<Contact> contacts = getContacts();

        Test.startTest();
        Id convId = FimbyModeratorActionService.getOrCreateModeratorConversation(contacts[0].Id, contacts[1].Id);
        Id convId2 = FimbyModeratorActionService.getOrCreateModeratorConversation(contacts[0].Id, contacts[1].Id);
        Test.stopTest();

        System.assertNotEquals(null, convId);
        System.assertEquals(convId, convId2, 'Should return existing conversation');
    }

    @isTest
    static void testApproveSupportRelationship() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Support_Relationship__c sr = new Support_Relationship__c(
            Contact__c = contacts[1].Id,
            Related_Contact__c = contacts[2].Id,
            Neighbourhood__c = nh.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Pending'
        );
        insert sr;

        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Support_Relationship_Approval', 'approve');

        Test.startTest();
        FimbyModeratorActionService.approveSupportRelationship(sr.Id, task.Id, contacts[0].Id);
        Test.stopTest();

        Support_Relationship__c updated = [SELECT Status__c, Approved_By__c FROM Support_Relationship__c WHERE Id = :sr.Id];
        System.assertEquals('Approved', updated.Status__c);
        System.assertEquals(contacts[0].Id, updated.Approved_By__c);
    }

    @isTest
    static void testDeclineSupportRelationship() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Support_Relationship__c sr = new Support_Relationship__c(
            Contact__c = contacts[1].Id,
            Related_Contact__c = contacts[2].Id,
            Neighbourhood__c = nh.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Pending'
        );
        insert sr;

        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Support_Relationship_Approval', 'decline');

        Test.startTest();
        FimbyModeratorActionService.declineSupportRelationship(sr.Id, 'Safety_Concern', 'Unable to verify', task.Id, contacts[0].Id);
        Test.stopTest();

        Support_Relationship__c updated = [SELECT Status__c FROM Support_Relationship__c WHERE Id = :sr.Id];
        System.assertEquals('Declined', updated.Status__c);
    }

    @isTest
    static void testRepublishWithTaskResolution() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Republish Task Test',
            Contact__c = contacts[1].Id,
            Posted_By__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Posted',
            Type__c = 'Goods - Unperishable',
            Moderation_Status__c = 'Hidden_By_Moderator',
            Hidden_By_Moderator__c = contacts[0].Id,
            Hidden_Date__c = Datetime.now(),
            Hidden_Reason_Code__c = 'Spam'
        );
        insert post;

        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Content_Report', 'republish_resolve');

        Test.startTest();
        FimbyModeratorActionService.republishContent(String.valueOf(post.Id), 'Needs_Offers__c', task.Id);
        Test.stopTest();

        Moderator_Task__c updated = [SELECT Status__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('Resolved', updated.Status__c);
    }

    // ── Controller Tests (via System.runAs) ──

    @isTest
    static void testControllerGetModeratorHeaderData() {
        User modUser = getModeratorUser();

        Test.startTest();
        Map<String, Object> data;
        System.runAs(modUser) {
            data = FimbyModeratorDashboardController.getModeratorHeaderData();
        }
        Test.stopTest();

        System.assertEquals(true, (Boolean) data.get('isModerator'));
    }

    @isTest
    static void testControllerGetModeratorAssignments() {
        User modUser = getModeratorUser();

        Test.startTest();
        List<Moderator_Assignment__c> assignments;
        System.runAs(modUser) {
            assignments = FimbyModeratorDashboardController.getModeratorAssignments();
        }
        Test.stopTest();

        System.assertEquals(1, assignments.size());
    }

    @isTest
    static void testControllerDashboardSummary() {
        Account nh = getNeighbourhood();
        User modUser = getModeratorUser();

        Test.startTest();
        Map<String, Object> summary;
        System.runAs(modUser) {
            summary = FimbyModeratorDashboardController.getDashboardSummary(nh.Id);
        }
        Test.stopTest();

        System.assertNotEquals(null, summary);
    }

    @isTest
    static void testControllerGetTasksByCategory() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'New_Signup',
            Priority__c = 'Standard',
            Status__c = 'New',
            Subject_Contact__c = contacts[1].Id,
            Summary__c = 'Controller test',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':New_Signup:ctrlcat'
        );
        insert task;

        Test.startTest();
        List<Moderator_Task__c> tasks;
        System.runAs(modUser) {
            tasks = FimbyModeratorDashboardController.getTasksByCategory(nh.Id, 'New_Signup', 20, 0);
        }
        Test.stopTest();

        System.assert(tasks.size() >= 1);
    }

    @isTest
    static void testControllerIsModeratorForNeighbourhood() {
        Account nh = getNeighbourhood();
        User modUser = getModeratorUser();

        Test.startTest();
        Boolean isMod;
        System.runAs(modUser) {
            isMod = FimbyModeratorDashboardController.isModeratorForNeighbourhood(nh.Id);
        }
        Test.stopTest();

        System.assertEquals(true, isMod);
    }

    @isTest
    static void testControllerResolveTask() {
        Account nh = getNeighbourhood();
        User modUser = getModeratorUser();
        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Feedback_Triage', 'ctrlresolve');

        Test.startTest();
        System.runAs(modUser) {
            FimbyModeratorDashboardController.resolveTask(task.Id, 'Resolved', 'Done');
        }
        Test.stopTest();

        Moderator_Task__c updated = [SELECT Status__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('Resolved', updated.Status__c);
    }

    @isTest
    static void testControllerEscalateAndReopen() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();
        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Content_Report', 'ctrlescalate');

        Test.startTest();
        System.runAs(modUser) {
            FimbyModeratorDashboardController.escalateTask(task.Id, 'Need help', contacts[2].Id);
        }

        Moderator_Task__c escalated = [SELECT Status__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('Escalated', escalated.Status__c);

        System.runAs(modUser) {
            FimbyModeratorDashboardController.reopenTask(task.Id);
        }
        Test.stopTest();

        Moderator_Task__c reopened = [SELECT Status__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('In_Progress', reopened.Status__c);
    }

    @isTest
    static void testControllerClaimReleaseReassign() {
        Account nh = getNeighbourhood();
        User modUser = getModeratorUser();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Content_Report',
            Priority__c = 'Standard',
            Status__c = 'New',
            Summary__c = 'Controller claim test',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Content_Report:ctrlclaim'
        );
        insert task;

        Test.startTest();
        System.runAs(modUser) {
            FimbyModeratorDashboardController.claimTask(task.Id);
        }

        Moderator_Task__c claimed = [SELECT Status__c, Claimed_Date__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('In_Progress', claimed.Status__c);

        System.runAs(modUser) {
            FimbyModeratorDashboardController.releaseTask(task.Id);
        }

        FimbyModeratorDashboardController.reassignTask(task.Id, UserInfo.getUserId());
        Test.stopTest();
    }

    @isTest
    static void testControllerRequestInfoAndReReview() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Content_Report',
            Priority__c = 'Standard',
            Status__c = 'In_Progress',
            Summary__c = 'Controller info test',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Content_Report:ctrlinfo'
        );
        insert task;

        Test.startTest();
        System.runAs(modUser) {
            FimbyModeratorDashboardController.requestMoreInfo(task.Id, contacts[1].Id);
        }

        Moderator_Task__c waiting = [SELECT Status__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('Awaiting_Info', waiting.Status__c);

        task.Status__c = 'Resolved';
        task.Resolved_Date__c = Datetime.now();
        update task;

        System.runAs(modUser) {
            FimbyModeratorDashboardController.requestReReview(task.Id);
        }
        Test.stopTest();

        Moderator_Task__c reviewed = [SELECT Status__c, Re_Review_Requested__c FROM Moderator_Task__c WHERE Id = :task.Id];
        System.assertEquals('New', reviewed.Status__c);
    }

    @isTest
    static void testControllerFlagRepublishKeepHidden() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Controller Flag Test',
            Contact__c = contacts[1].Id,
            Posted_By__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Posted',
            Type__c = 'Goods - Unperishable'
        );
        insert post;

        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'Content_Report', 'ctrlflag');

        Test.startTest();
        System.runAs(modUser) {
            FimbyModeratorDashboardController.flagContent(String.valueOf(post.Id), 'Needs_Offers__c', 'Spam');
        }

        Needs_Offers__c hidden = [SELECT Moderation_Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Hidden_By_Moderator', hidden.Moderation_Status__c);

        System.runAs(modUser) {
            FimbyModeratorDashboardController.keepContentHidden(task.Id, 'spam', 'Verified spam', 'Notes');
        }

        System.runAs(modUser) {
            FimbyModeratorDashboardController.republishContent(String.valueOf(post.Id), 'Needs_Offers__c', null);
        }
        Test.stopTest();

        Needs_Offers__c visible = [SELECT Moderation_Status__c FROM Needs_Offers__c WHERE Id = :post.Id];
        System.assertEquals('Visible', visible.Moderation_Status__c);
    }

    @isTest
    static void testControllerCheckInAndConcern() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();

        Moderator_Task__c task1 = insertPreClaimedTask(nh.Id, 'Content_Report', 'ctrlcheckin');
        Moderator_Task__c task2 = insertPreClaimedTask(nh.Id, 'Content_Report', 'ctrlconcern');

        Test.startTest();
        System.runAs(modUser) {
            FimbyModeratorDashboardController.issueCheckIn(task1.Id, contacts[1].Id, 'Safety_Concern', 'Checking in');
            FimbyModeratorDashboardController.recordConcern(task2.Id, contacts[1].Id, 'Accountability_Concern', 'Pattern noted');
        }
        Test.stopTest();

        Moderator_Task__c updated1 = [SELECT Enforcement_Level__c, Decision_Statement__c FROM Moderator_Task__c WHERE Id = :task1.Id];
        System.assertEquals('Check_In', updated1.Enforcement_Level__c);
        System.assertEquals('Checking in', updated1.Decision_Statement__c);
    }

    @isTest
    static void testControllerWelcomeAndTriage() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();

        Moderator_Task__c welcomeTask = insertPreClaimedTask(nh.Id, 'New_Signup', 'ctrlwelcome');

        Feedback__c fb = new Feedback__c(
            Name = 'Ctrl Triage Test',
            Type__c = 'Bug',
            Details__c = 'Test bug',
            Neighbourhood__c = nh.Id,
            Posted_By__c = contacts[1].Id
        );
        insert fb;

        Moderator_Task__c triageTask = insertPreClaimedTask(nh.Id, 'Feedback_Triage', 'ctrltriage');

        Test.startTest();
        System.runAs(modUser) {
            FimbyModeratorDashboardController.sendWelcomeMessage(contacts[1].Id, 'Welcome!', welcomeTask.Id);
            FimbyModeratorDashboardController.triageFeedback(fb.Id, 'Enhancement_Flagged', triageTask.Id);
        }
        Test.stopTest();

        Contact welcomed = [SELECT Welcomed_By__c FROM Contact WHERE Id = :contacts[1].Id];
        System.assertNotEquals(null, welcomed.Welcomed_By__c);
    }

    @isTest
    static void testControllerMarkWelcomed() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();

        Moderator_Task__c task = insertPreClaimedTask(nh.Id, 'New_Signup', 'ctrlmarkwelc');

        Test.startTest();
        System.runAs(modUser) {
            FimbyModeratorDashboardController.markWelcomed(contacts[2].Id, task.Id, 'Met in person');
        }
        Test.stopTest();

        Contact updated = [SELECT Welcomed_By__c FROM Contact WHERE Id = :contacts[2].Id];
        System.assertNotEquals(null, updated.Welcomed_By__c);
    }

    @isTest
    static void testControllerGetEscalatedTasks() {
        Account nh = getNeighbourhood();
        User modUser = getModeratorUser();

        Test.startTest();
        List<Moderator_Task__c> tasks;
        System.runAs(modUser) {
            tasks = FimbyModeratorDashboardController.getEscalatedTasks(nh.Id, 20, 0);
        }
        Test.stopTest();

        System.assertNotEquals(null, tasks);
    }

    @isTest
    static void testControllerReviewDataMethods() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Review Data Test',
            Contact__c = contacts[1].Id,
            Posted_By__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Posted',
            Type__c = 'Goods - Unperishable'
        );
        insert post;

        Feedback__c feedback = new Feedback__c(
            Name = 'Controller Review Feedback',
            Type__c = 'Bug',
            Details__c = 'Needs review',
            Neighbourhood__c = nh.Id,
            Posted_By__c = contacts[1].Id
        );
        insert feedback;

        Support_Relationship__c supportRelationship = new Support_Relationship__c(
            Contact__c = contacts[1].Id,
            Related_Contact__c = contacts[2].Id,
            Neighbourhood__c = nh.Id,
            Relationship_Type__c = 'Support_Person',
            Status__c = 'Pending'
        );
        insert supportRelationship;

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Content_Report',
            Priority__c = 'Standard',
            Status__c = 'Escalated',
            Escalated_To__c = contacts[2].Id,
            Escalated_Date__c = Datetime.now(),
            Summary__c = 'Review test',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Content_Report:ctrlreview'
        );
        insert task;

        Test.startTest();
        System.runAs(modUser) {
            FimbyModeratorDashboardController.getContentReviewData(String.valueOf(post.Id), 'Needs_Offers__c', task.Id);
            FimbyModeratorDashboardController.getFeedbackReviewData(feedback.Id);
            FimbyModeratorDashboardController.getSupportReviewData(supportRelationship.Id);
            FimbyModeratorDashboardController.getSupportConcernData(task.Id);
            FimbyModeratorDashboardController.getEscalationDetail(task.Id);
            FimbyModeratorDashboardController.getWelcomeReviewData(contacts[1].Id);
            FimbyModeratorDashboardController.getOrCreateModeratorConversation(contacts[1].Id);
        }
        Test.stopTest();
    }

    // ── Trigger Tests ──

    @isTest
    static void testBlockedContactTriggerCreatesTask() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Test.startTest();
        Blocked_Contact__c bc = new Blocked_Contact__c(
            Blocker__c = contacts[1].Id,
            Blocked__c = contacts[2].Id,
            Reported__c = true,
            Report_Details__c = 'Test block report'
        );
        insert bc;
        Test.stopTest();

        List<Moderator_Task__c> tasks = [
            SELECT Id, Category__c, Subject_Contact__c
            FROM Moderator_Task__c
            WHERE Category__c = 'Blocked_Contact'
              AND Subject_Contact__c = :contacts[2].Id
              AND Neighbourhood__c = :nh.Id
        ];
        System.assertEquals(1, tasks.size(), 'Should create a moderator task for reported block');
    }

    @isTest
    static void testBlockedContactTriggerSkipsUnreported() {
        List<Contact> contacts = getContacts();

        Test.startTest();
        Blocked_Contact__c bc = new Blocked_Contact__c(
            Blocker__c = contacts[1].Id,
            Blocked__c = contacts[2].Id,
            Reported__c = false
        );
        insert bc;
        Test.stopTest();

        List<Moderator_Task__c> tasks = [
            SELECT Id FROM Moderator_Task__c WHERE Category__c = 'Blocked_Contact'
        ];
        System.assertEquals(0, tasks.size(), 'Should NOT create task when Reported is false');
    }

    @isTest
    static void testContactTriggerNewSignup() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        Contact signupContact = contacts[1];

        signupContact.Status__c = 'Active User';
        update signupContact;

        Test.startTest();
        signupContact.Status__c = 'New Public Signup';
        update signupContact;
        Test.stopTest();

        List<Moderator_Task__c> tasks = [
            SELECT Id, Category__c, Subject_Contact__c
            FROM Moderator_Task__c
            WHERE Category__c = 'New_Signup'
              AND Subject_Contact__c = :signupContact.Id
              AND Neighbourhood__c = :nh.Id
        ];
        System.assertEquals(1, tasks.size(), 'Should create task for new public signup');
    }

    @isTest
    static void testControllerSubjectHistory() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();

        Test.startTest();
        Map<String, Object> history;
        System.runAs(modUser) {
            history = FimbyModeratorDashboardController.getSubjectHistory(contacts[1].Id, nh.Id, null);
        }
        Test.stopTest();

        System.assertNotEquals(null, history);
    }

    @isTest
    static void testContentReportCreatesModeratorTask() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();

        Needs_Offers__c post = new Needs_Offers__c(
            Name = 'Reportable Post',
            Contact__c = contacts[1].Id,
            Posted_By__c = contacts[1].Id,
            Neighbourhood__c = nh.Id,
            Status__c = 'Posted',
            Type__c = 'Goods - Unperishable'
        );
        insert post;

        Map<String, Object> reportData = new Map<String, Object>{
            'contentId' => String.valueOf(post.Id),
            'contentType' => 'Needs_Offers__c',
            'reason' => 'harassment',
            'additionalInfo' => 'Test harassment report'
        };

        Test.startTest();
        System.runAs(modUser) {
            Map<String, Object> result = FimbyContentReportController.submitContentReport(JSON.serialize(reportData));
            System.assertEquals(true, result.get('success'));
        }
        Test.stopTest();

        List<Moderator_Task__c> tasks = [
            SELECT Id, Priority__c FROM Moderator_Task__c
            WHERE Category__c = 'Content_Report'
              AND Neighbourhood__c = :nh.Id
        ];
        System.assert(!tasks.isEmpty(), 'Should create moderator task from content report');
        System.assertEquals('Urgent', tasks[0].Priority__c, 'Harassment reports should be Urgent');
    }

    @isTest
    static void testAlertService() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();

        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = nh.Id,
            Category__c = 'Content_Report',
            Priority__c = 'Urgent',
            Status__c = 'New',
            Summary__c = 'Alert test',
            Report_Count__c = 1,
            Task_Dedup_Key__c = nh.Id + ':Content_Report:alerttest'
        );
        insert task;

        Test.startTest();
        FimbyModeratorAlertService.alertModerators(task);
        FimbyModeratorAlertService.alertAdmin(task, 'Admin escalation reason');
        Test.stopTest();

        List<Notification__c> notifs = [
            SELECT Id, Type__c FROM Notification__c WHERE Type__c = 'Moderator'
        ];
        System.assert(!notifs.isEmpty(), 'Should create moderator notifications');
    }

    @isTest
    static void testGetNeighbourhoodModerator() {
        User modUser = getModeratorUser();

        Test.startTest();
        Map<String, Object> result;
        System.runAs(modUser) {
            result = FimbyModeratorDashboardController.getNeighbourhoodModerator();
        }
        Test.stopTest();
    }

    @isTest
    static void testIsModeratorContact() {
        List<Contact> contacts = getContacts();
        Contact moderator = contacts[0];

        Test.startTest();
        Boolean isMod = FimbyModeratorDashboardController.isModeratorContact(moderator.Id);
        Boolean notMod = FimbyModeratorDashboardController.isModeratorContact(contacts.size() > 1 ? contacts[1].Id : null);
        Test.stopTest();

        System.assertEquals(true, isMod, 'Contact with active assignment should be moderator');
    }

    @isTest
    static void testIsModeratorContactNullId() {
        Test.startTest();
        Boolean result = FimbyModeratorDashboardController.isModeratorContact(null);
        Test.stopTest();
        System.assertEquals(false, result, 'Null contact should return false');
    }

    @isTest
    static void testGetOrganizationReviewData() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Account org = new Account(
            Name = 'Review Data Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending',
            Is_Registered_Charity__c = true,
            Charity_Verification_URL__c = 'https://www.canada.ca/example',
            Submitted_By__c = contacts[1].Id
        );
        insert org;

        Test.startTest();
        Map<String, Object> data;
        System.runAs(modUser) {
            data = FimbyModeratorDashboardController.getOrganizationReviewData(org.Id, null);
        }
        Test.stopTest();

        System.assertEquals('Review Data Org', data.get('orgName'));
        System.assertEquals(true, data.get('isRegisteredCharity'));
    }

    @isTest
    static void testGetOrganizationReviewData_verificationDocOnAccount() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Account org = new Account(
            Name = 'Review Doc Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending',
            Submitted_By__c = contacts[1].Id
        );
        insert org;

        ContentVersion cv = new ContentVersion(
            Title = 'Org Proof',
            PathOnClient = 'proof.jpg',
            VersionData = Blob.valueOf('fake-image'),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId, ContentBodyId FROM ContentVersion WHERE Id = :cv.Id];
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = org.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );
        insert new ContentDistribution(
            ContentVersionId = cv.Id,
            Name = 'Org Proof',
            PreferencesAllowViewInBrowser = true,
            PreferencesNotifyOnVisit = false,
            PreferencesPasswordRequired = false,
            PreferencesAllowOriginalDownload = true
        );

        insert new Support_Relationship__c(
            Contact__c = contacts[1].Id,
            Related_Organization__c = org.Id,
            Neighbourhood__c = nh.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Pending'
        );

        Test.startTest();
        Map<String, Object> data;
        System.runAs(modUser) {
            data = FimbyModeratorDashboardController.getOrganizationReviewData(org.Id, null);
        }
        Test.stopTest();

        List<Object> versionIds = (List<Object>) data.get('verificationContentVersionIds');
        System.assertEquals(1, versionIds.size(), 'Verification doc should be read from the org Account');
        List<Object> docs = (List<Object>) data.get('verificationDocs');
        System.assertEquals(1, docs.size(), 'Verification doc URL should be built for moderator review');
    }

    @isTest
    static void testGetOrganizationReviewData_legacyVerificationDocOnRep() {
        Account nh = getNeighbourhood();
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Account org = new Account(
            Name = 'Legacy Doc Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending',
            Submitted_By__c = contacts[1].Id
        );
        insert org;

        Support_Relationship__c sr = new Support_Relationship__c(
            Contact__c = contacts[1].Id,
            Related_Organization__c = org.Id,
            Neighbourhood__c = nh.Id,
            Relationship_Type__c = 'Community_Group_Rep',
            Status__c = 'Pending'
        );
        insert sr;

        ContentVersion cv = new ContentVersion(
            Title = 'Legacy Rep Proof',
            PathOnClient = 'legacy.jpg',
            VersionData = Blob.valueOf('legacy-image'),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        insert new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId = sr.Id,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        Test.startTest();
        Map<String, Object> data;
        System.runAs(modUser) {
            data = FimbyModeratorDashboardController.getOrganizationReviewData(org.Id, null);
        }
        Test.stopTest();

        List<Object> versionIds = (List<Object>) data.get('verificationContentVersionIds');
        System.assertEquals(1, versionIds.size(), 'Legacy rep-linked doc should still surface until re-uploaded on org');
    }

    @isTest
    static void testApproveOrganizationController() {
        Account nh = getNeighbourhood();
        User modUser = getModeratorUser();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Account org = new Account(
            Name = 'Controller Approve Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending'
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
            Summary__c = 'New organization: Controller Approve Org',
            Task_Dedup_Key__c = nh.Id + ':Organization_Approval:Account:' + org.Id
        );
        insert task;

        Test.startTest();
        System.runAs(modUser) {
            FimbyModeratorDashboardController.approveOrganization(org.Id, task.Id);
        }
        Test.stopTest();

        Account updated = [
            SELECT Verification_Status__c, Organization_Contact__c
            FROM Account WHERE Id = :org.Id
        ];
        System.assertEquals('Verified', updated.Verification_Status__c);
        System.assertNotEquals(null, updated.Organization_Contact__c);
    }

    @isTest
    static void testRejectOrganizationController() {
        List<Contact> contacts = getContacts();
        User modUser = getModeratorUser();
        Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization').getRecordTypeId();
        Account org = new Account(
            Name = 'Controller Reject Org',
            RecordTypeId = orgRtId,
            Verification_Status__c = 'Pending',
            Submitted_By__c = contacts[1].Id
        );
        insert org;

        Test.startTest();
        System.runAs(modUser) {
            FimbyModeratorDashboardController.rejectOrganization(org.Id, 'Other', 'Unable to verify', null);
        }
        Test.stopTest();

        Account updated = [SELECT Verification_Status__c FROM Account WHERE Id = :org.Id];
        System.assertEquals('Rejected', updated.Verification_Status__c);
    }
}
