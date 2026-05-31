Id dStory = 'a1FOL0000041KLn2AM';
Id mobileContact = '003OL00000bwBSSYA2';
Id desktopContact = '003OL00000pHdZEYA0';

String payload = JSON.serialize(new Map<String, Object>{
    'storyId' => dStory,
    'commentText' => 'QA D1 mention @Mobile Tester for notification matrix',
    'commentContactId' => desktopContact,
    'mentionContactIds' => new List<Id>{ mobileContact }
});

Map<String, Object> result = FimbyStoryCommentController.postStoryComment(payload);
System.debug('D1_POST=' + JSON.serialize(result));

Story_Comment__c row = [
    SELECT Mention_Contact_Ids__c
    FROM Story_Comment__c
    WHERE Story__c = :dStory
    ORDER BY CreatedDate DESC
    LIMIT 1
];
System.debug('D1_MENTION_FIELD=' + row.Mention_Contact_Ids__c);

List<Notification__c> mentions = [
    SELECT Id, Type__c, Title__c, Contact__c
    FROM Notification__c
    WHERE Type__c = 'Mention'
      AND Contact__c = :mobileContact
      AND CreatedDate = TODAY
    ORDER BY CreatedDate DESC
    LIMIT 3
];
System.debug('D1_NOTIF_COUNT=' + mentions.size());
