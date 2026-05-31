List<Blocked_Contact__c> blocks = [
    SELECT Id FROM Blocked_Contact__c
    WHERE Blocker__c = '003OL00000pHdZEYA0' AND Blocked__c = '003OL00000bwBSSYA2'
];
System.debug('Deleting ' + blocks.size() + ' block(s)');
delete blocks;
