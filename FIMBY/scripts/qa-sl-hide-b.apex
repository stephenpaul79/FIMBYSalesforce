Id bStory = 'a1FOL0000041Jcb2AE';
Id modContact = '003OL00000rBHooYAG';
FimbyModeratorActionService.flagContent(String.valueOf(bStory), 'Story__c', 'Moderator_Hidden', modContact);
Story__c s = [SELECT Moderation_Status__c FROM Story__c WHERE Id = :bStory];
System.debug('B_HIDE=' + s.Moderation_Status__c);
