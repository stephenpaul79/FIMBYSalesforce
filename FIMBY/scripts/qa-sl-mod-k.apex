Id jStory = 'a1FOL0000041KLl2AM';
Id jComment = 'a1hOL000005DFsnYAG';
Id storyTask = 'a1eOL000007pNBRYA2';
Id commentTask = 'a1eOL000007pND3YAM';
Id modContact = '003OL00000rBHooYAG';

FimbyModeratorActionService.flagContent(String.valueOf(jStory), 'Story__c', 'Moderator_Hidden', modContact);
Story__c s1 = [SELECT Moderation_Status__c, Hidden_Reason_Code__c FROM Story__c WHERE Id = :jStory];
System.debug('K3_HIDE=' + s1.Moderation_Status__c + ' ' + s1.Hidden_Reason_Code__c);

FimbyModeratorActionService.flagContent(String.valueOf(jComment), 'Story_Comment__c', 'Moderator_Hidden', modContact);
Story_Comment__c c1 = [SELECT Moderation_Status__c FROM Story_Comment__c WHERE Id = :jComment];
System.debug('K5_HIDE=' + c1.Moderation_Status__c);

FimbyModeratorActionService.republishContent(String.valueOf(jStory), 'Story__c', storyTask);
Story__c s2 = [SELECT Moderation_Status__c FROM Story__c WHERE Id = :jStory];
System.debug('K6_REPUB_STORY=' + s2.Moderation_Status__c);

FimbyModeratorActionService.republishContent(String.valueOf(jComment), 'Story_Comment__c', commentTask);
Story_Comment__c c2 = [SELECT Moderation_Status__c FROM Story_Comment__c WHERE Id = :jComment];
System.debug('K7_REPUB_COMMENT=' + c2.Moderation_Status__c);
