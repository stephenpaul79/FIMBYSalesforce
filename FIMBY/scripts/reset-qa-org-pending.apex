Account a = new Account(
    Id = '001OL00000oKAfxYAG',
    Verification_Status__c = 'Pending',
    Is_Approved_Community_Group__c = false
);
update a;
Map<String, Object> data = FimbyModeratorQueryService.getSupportReviewData('a1YOL000005Wuyf2AC');
System.debug('after reset orgVerified=' + data.get('orgVerified'));
