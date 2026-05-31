List<Moderator_Task__c> tasks = [
    SELECT Id, Name, Category__c, Status__c, Priority__c, Related_Record_Id__c, Subject__c
    FROM Moderator_Task__c
    WHERE Status__c != 'Resolved'
    ORDER BY CreatedDate DESC
    LIMIT 20
];
for (Moderator_Task__c t : tasks) {
    System.debug(t.Id + ' | ' + t.Category__c + ' | ' + t.Status__c + ' | ' + t.Priority__c + ' | ' + t.Subject__c);
}
