Id desktop = '003OL00000pHdZEYA0';
Id mobile = '003OL00000bwBSSYA2';

List<Blocked_Contact__c> existing = [
    SELECT Id FROM Blocked_Contact__c
    WHERE Blocker__c = :desktop AND Blocked__c = :mobile
];
if (!existing.isEmpty()) {
    delete existing;
}

Blocked_Contact__c block = new Blocked_Contact__c(
    Blocker__c = desktop,
    Blocked__c = mobile,
    Reason__c = 'QA-SL-L block test'
);
insert block;
System.debug('BLOCK_CREATED=' + block.Id);
