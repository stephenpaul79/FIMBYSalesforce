User mobileU = [SELECT Id FROM User WHERE Username = 'mobiletester@fimby.com' LIMIT 1];
User desktopU = [SELECT Id FROM User WHERE Username = 'desktop@fimby.com' LIMIT 1];
Id dStory = 'a1FOL0000041KLn2AM';
Id jStory = 'a1FOL0000041KLl2AM';
Id fStory = 'a1FOL0000041KLm2AM';
Id aStory = 'a1FOL0000041JZN2A2';
Id desktopC = '003OL00000pHdZEYA0';
Id mobileC = '003OL00000bwBSSYA2';

// D3: owner notification (no mention)
System.runAs(mobileU) {
    String payload = JSON.serialize(new Map<String, Object>{
        'storyId' => dStory,
        'commentText' => 'QA-SL-D3 mobiletester comment for owner notification',
        'mentionContactIds' => new List<Id>()
    });
    Map<String, Object> r = FimbyStoryCommentController.postStoryComment(payload);
    System.debug('D3=' + JSON.serialize(r));
}

// D1: mention desktop
System.runAs(mobileU) {
    String payload = JSON.serialize(new Map<String, Object>{
        'storyId' => dStory,
        'commentText' => 'QA-SL-D1 @Desktop Tester mention test',
        'mentionContactIds' => new List<Id>{ desktopC }
    });
    Map<String, Object> r = FimbyStoryCommentController.postStoryComment(payload);
    System.debug('D1=' + JSON.serialize(r));
}

// E3: edit comment on A story (use existing mobile comment)
Story_Comment__c toEdit = [
    SELECT Id FROM Story_Comment__c
    WHERE Story__c = :aStory AND Contact__c = :mobileC
    ORDER BY CreatedDate DESC LIMIT 1
];
if (toEdit != null) {
    System.runAs(mobileU) {
        String payload = JSON.serialize(new Map<String, Object>{
            'commentId' => toEdit.Id,
            'commentText' => 'QA-SL-E3 edited comment body',
            'mentionContactIds' => new List<Id>()
        });
        Map<String, Object> r = FimbyStoryCommentController.updateStoryComment(payload);
        System.debug('E3=' + JSON.serialize(r));
    }
}

// F1: soft-delete a comment on D story
Story_Comment__c f1 = [
    SELECT Id FROM Story_Comment__c
    WHERE Story__c = :dStory AND Contact__c = :mobileC AND Status__c = 'Active'
    ORDER BY CreatedDate ASC LIMIT 1
];
if (f1 != null) {
    System.runAs(mobileU) {
        Map<String, Object> r = FimbyStoryCommentController.softDeleteStoryComment(f1.Id);
        System.debug('F1=' + JSON.serialize(r));
    }
}

System.debug('DONE_TRACKS_APEX');
