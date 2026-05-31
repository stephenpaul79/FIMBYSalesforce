List<Blocked_Contact__c> blocks = [
    SELECT Id FROM Blocked_Contact__c
    WHERE Blocker__c = '003OL00000pHdZEYA0'
      AND Blocked__c = '003OL00000bwBSSYA2'
    LIMIT 1
];
if (!blocks.isEmpty()) {
    delete blocks;
    System.debug('UNBLOCKED=1');
} else {
    System.debug('UNBLOCKED=0');
}
