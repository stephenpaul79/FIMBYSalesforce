Id nh = '001OL00000q3enmYAA';
Id sarah = '003OL00000pHdZEYA0';
Id marcus = '003OL00000vaFpKYAU';
Id amir = '003OL00000tXhWNYA0';

FimbyModeratorTaskService.TaskRequest signup1 = new FimbyModeratorTaskService.TaskRequest();
signup1.neighbourhoodId = nh;
signup1.category = 'New_Signup';
signup1.subjectContactId = marcus;
signup1.relatedRecordType = 'Contact';
signup1.relatedRecordId = String.valueOf(marcus);
signup1.summary = 'New neighbour signed up: Marcus Bell';
signup1.priority = 'Standard';
signup1.sourceType = 'System_Alert';
FimbyModeratorTaskService.createOrUpdateTask(signup1);

FimbyModeratorTaskService.TaskRequest signup2 = new FimbyModeratorTaskService.TaskRequest();
signup2.neighbourhoodId = nh;
signup2.category = 'New_Signup';
signup2.subjectContactId = amir;
signup2.relatedRecordType = 'Contact';
signup2.relatedRecordId = String.valueOf(amir);
signup2.summary = 'New neighbour signed up: Amir Haddad';
signup2.priority = 'Standard';
signup2.sourceType = 'System_Alert';
FimbyModeratorTaskService.createOrUpdateTask(signup2);

FimbyModeratorTaskService.TaskRequest blockReq = new FimbyModeratorTaskService.TaskRequest();
blockReq.neighbourhoodId = nh;
blockReq.category = 'Blocked_Contact';
blockReq.subjectContactId = marcus;
blockReq.secondaryContactId = sarah;
blockReq.summary = 'Block report filed: Marcus Bell blocked Sarah Chen (QA mobile seed)';
blockReq.priority = 'Standard';
blockReq.sourceType = 'Block_Report';
FimbyModeratorTaskService.createOrUpdateTask(blockReq);
