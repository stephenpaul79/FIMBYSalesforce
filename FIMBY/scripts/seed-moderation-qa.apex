Id nhId = '0015f00000DV5kUAAT';
Id desktopId = '003OL00000pHdZEYA0';
Id mobileId = '003OL00000bwBSSYA2';
Id storyId = 'a1FOL000003zSiP2AU';
Id story2Id = 'a1FOL000003z6rZ2AQ';

// Standard content report
FimbyModeratorTaskService.TaskRequest cr1 = new FimbyModeratorTaskService.TaskRequest();
cr1.neighbourhoodId = nhId;
cr1.category = 'Content_Report';
cr1.priority = 'Standard';
cr1.relatedRecordId = storyId;
cr1.relatedRecordType = 'Story__c';
cr1.summary = 'Content report: Spam or misleading on a sharedlife post';
cr1.sourceType = 'Content_Report';
cr1.reporterContactId = mobileId;
cr1.secondaryContactId = mobileId;
cr1.subjectContactId = desktopId;
cr1.reasonCode = 'spam';
cr1.details = 'QA seed - standard content report';
FimbyModeratorTaskService.createOrUpdateTask(cr1);

// Urgent content report
FimbyModeratorTaskService.TaskRequest cr2 = new FimbyModeratorTaskService.TaskRequest();
cr2.neighbourhoodId = nhId;
cr2.category = 'Content_Report';
cr2.priority = 'Urgent';
cr2.relatedRecordId = story2Id;
cr2.relatedRecordType = 'Story__c';
cr2.summary = 'Content report: Harassment or bullying on a sharedlife post';
cr2.sourceType = 'Content_Report';
cr2.reporterContactId = desktopId;
cr2.secondaryContactId = desktopId;
cr2.subjectContactId = mobileId;
cr2.reasonCode = 'harassment';
cr2.details = 'QA seed - urgent content report';
FimbyModeratorTaskService.createOrUpdateTask(cr2);

// Block report (mobile reports desktop)
Blocked_Contact__c bc = new Blocked_Contact__c(
    Blocker__c = mobileId,
    Blocked__c = desktopId,
    Reported__c = true,
    Report_Details__c = 'QA seed - block and report from moderation QA'
);
insert bc;

// Support relationship approval
Support_Relationship__c sr = new Support_Relationship__c(
    Contact__c = desktopId,
    Related_Contact__c = mobileId,
    Relationship_Type__c = 'Support_Person',
    Status__c = 'Pending',
    Neighbourhood__c = nhId,
    Consent_Method__c = 'Verbal',
    Notes__c = 'QA seed support relationship'
);
insert sr;

// Support person concern (no UI intake yet)
FimbyModeratorTaskService.TaskRequest concern = new FimbyModeratorTaskService.TaskRequest();
concern.neighbourhoodId = nhId;
concern.category = 'Support_Person_Concern';
concern.priority = 'Urgent';
concern.subjectContactId = mobileId;
concern.secondaryContactId = desktopId;
concern.summary = 'Support person concern - QA seed';
concern.sourceType = 'Manual_Note';
concern.reporterContactId = desktopId;
concern.reasonCode = 'concern';
concern.details = 'QA seed concern about support helper behaviour';
FimbyModeratorTaskService.createOrUpdateTask(concern);

// Feedback triage
Feedback__c fb = new Feedback__c(
    Name = 'QA seed feedback',
    Type__c = 'General Feedback',
    Details__c = 'Moderation QA seed feedback for triage tab',
    Contact__c = desktopId,
    Posted_By__c = desktopId,
    Neighbourhood__c = nhId
);
insert fb;
FimbyModeratorTaskService.TaskRequest fbReq = new FimbyModeratorTaskService.TaskRequest();
fbReq.neighbourhoodId = nhId;
fbReq.category = 'Feedback_Triage';
fbReq.priority = 'Low';
fbReq.subjectContactId = desktopId;
fbReq.relatedRecordId = String.valueOf(fb.Id);
fbReq.relatedRecordType = 'Feedback__c';
fbReq.summary = 'General Feedback: QA seed feedback';
fbReq.sourceType = 'Content_Report';
fbReq.sourceRecordId = String.valueOf(fb.Id);
fbReq.reporterContactId = desktopId;
FimbyModeratorTaskService.createOrUpdateTask(fbReq);

System.debug('Moderation QA seed complete');
