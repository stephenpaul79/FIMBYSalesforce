Id jComment = 'a1hOL000005DFsnYAG';
Id modContact = '003OL00000rBHooYAG';

FimbyModeratorActionService.flagContent(String.valueOf(jComment), 'Story_Comment__c', 'Moderator_Hidden', modContact);
Story_Comment__c c = [SELECT Moderation_Status__c FROM Story_Comment__c WHERE Id = :jComment];
System.debug('K5_STATUS=' + c.Moderation_Status__c);
