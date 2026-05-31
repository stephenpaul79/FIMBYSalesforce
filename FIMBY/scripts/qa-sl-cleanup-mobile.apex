Id mobileContact = '003OL00000bwBSSYA2';

List<Story__c> stories = [
    SELECT Id FROM Story__c WHERE Posted_By__c = :mobileContact
];
System.debug('DELETE_MOBILE_STORIES=' + stories.size());
if (!stories.isEmpty()) {
    delete stories;
}

Integer remaining = [SELECT COUNT() FROM Story__c WHERE Posted_By__c = :mobileContact];
System.debug('REMAINING=' + remaining);
