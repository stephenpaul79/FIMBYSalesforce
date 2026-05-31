// Shared Life QA test data setup (run as system)
Id nh = '0015f00000DV5kUAAT';
Id desktop = '003OL00000pHdZEYA0';
Id mobile = '003OL00000bwBSSYA2';

// Reset anchored stories for reuse
List<Story__c> reset = [
    SELECT Id, Moderation_Status__c, Hidden_Reason_Code__c, Hidden_By_Moderator__c, Hidden_Date__c
    FROM Story__c
    WHERE Id IN ('a1FOL0000041JZN2A2', 'a1FOL0000041Jcb2AE')
];
for (Story__c s : reset) {
    s.Moderation_Status__c = 'Visible';
    s.Hidden_Reason_Code__c = null;
    s.Hidden_By_Moderator__c = null;
    s.Hidden_Date__c = null;
}
update reset;

// Fresh visible stories for J/K/F tracks
List<Story__c> inserts = new List<Story__c>{
    new Story__c(
        Name = 'QA-SL-J-20260527-Report story anchor',
        Message__c = 'QA anchor for content report and moderator dashboard tests.',
        Type__c = 'Thank You',
        Neighbourhood__c = nh,
        Posted_By__c = desktop,
        Contact__c = desktop,
        Moderation_Status__c = 'Visible',
        Visibility_Scope__c = 'Neighbourhood'
    ),
    new Story__c(
        Name = 'QA-SL-F-20260527-Delete story anchor',
        Message__c = 'QA anchor for author delete story test.',
        Type__c = 'Prayer',
        Neighbourhood__c = nh,
        Posted_By__c = desktop,
        Contact__c = desktop,
        Moderation_Status__c = 'Visible',
        Visibility_Scope__c = 'Neighbourhood'
    ),
    new Story__c(
        Name = 'QA-SL-D-20260527-Notification anchor',
        Message__c = 'QA anchor for owner comment and mention notifications.',
        Type__c = 'God Story',
        Neighbourhood__c = nh,
        Posted_By__c = desktop,
        Contact__c = desktop,
        Moderation_Status__c = 'Visible',
        Visibility_Scope__c = 'Neighbourhood'
    )
};
insert inserts;

// Comment on D anchor for J2 comment report
Story_Comment__c jComment = new Story_Comment__c(
    Story__c = inserts[2].Id,
    Body__c = 'QA-SL-J2 comment to report',
    Posted_By__c = mobile,
    Contact__c = mobile,
    Status__c = 'Active',
    Moderation_Status__c = 'Visible'
);
insert jComment;

System.debug('J_STORY=' + inserts[0].Id);
System.debug('F_STORY=' + inserts[1].Id);
System.debug('D_STORY=' + inserts[2].Id);
System.debug('J_COMMENT=' + jComment.Id);
