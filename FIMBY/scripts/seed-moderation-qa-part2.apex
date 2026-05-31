Id nhId = '0015f00000DV5kUAAT';
Id mobileId = '003OL00000bwBSSYA2';

Contact signupContact = [
    SELECT Id, Status__c, Name, AccountId
    FROM Contact
    WHERE Id = :mobileId
    LIMIT 1
];
String priorStatus = signupContact.Status__c;
if (priorStatus != 'New Public Signup') {
    signupContact.Status__c = 'Active User';
    update signupContact;
    signupContact.Status__c = 'New Public Signup';
    update signupContact;
}

System.debug('New signup moderator task seed complete');
