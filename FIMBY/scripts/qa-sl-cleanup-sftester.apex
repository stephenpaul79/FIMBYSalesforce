Id modContact = '003OL00000rBHooYAG';

List<Story__c> stories = [
    SELECT Id FROM Story__c
    WHERE Contact__c = :modContact OR Posted_By__c = :modContact
];
System.debug('DELETE_STORIES=' + stories.size());
if (!stories.isEmpty()) {
    delete stories;
}

Integer remaining = [SELECT COUNT() FROM Story__c WHERE Contact__c = :modContact OR Posted_By__c = :modContact];
System.debug('REMAINING_STORIES=' + remaining);
