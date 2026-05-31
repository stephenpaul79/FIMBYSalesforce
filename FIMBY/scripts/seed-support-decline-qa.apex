Id nhId = '0015f00000DV5kUAAT';
Id desktopId = '003OL00000pHdZEYA0';
Id subjectId = '003OL00000rBHooYAG';

Support_Relationship__c sr = new Support_Relationship__c(
    Contact__c = desktopId,
    Related_Contact__c = subjectId,
    Relationship_Type__c = 'Support_Person',
    Status__c = 'Pending',
    Neighbourhood__c = nhId,
    Consent_Method__c = 'Verbal',
    Notes__c = 'QA seed support relationship for decline test'
);
insert sr;

List<Moderator_Task__c> tasks = [
    SELECT Id, Summary__c, Status__c
    FROM Moderator_Task__c
    WHERE Category__c = 'Support_Relationship_Approval'
      AND Related_Record_ID__c = :String.valueOf(sr.Id)
    LIMIT 1
];
System.debug('Decline seed task: ' + tasks);
