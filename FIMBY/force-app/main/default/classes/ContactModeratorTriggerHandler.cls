public without sharing class ContactModeratorTriggerHandler {

    public static void handleAfterUpdate(List<Contact> newRecords, Map<Id, Contact> oldMap) {
        for (Contact c : newRecords) {
            Contact oldC = oldMap.get(c.Id);
            if (c.Status__c == 'New Public Signup' && oldC.Status__c != 'New Public Signup') {
                if (c.AccountId == null) continue;

                FimbyModeratorTaskService.TaskRequest req = new FimbyModeratorTaskService.TaskRequest();
                req.neighbourhoodId = c.AccountId;
                req.category = 'New_Signup';
                req.priority = 'Standard';
                req.subjectContactId = c.Id;
                req.relatedRecordId = String.valueOf(c.Id);
                req.relatedRecordType = 'Contact';
                req.summary = 'New neighbour signed up: '
                    + (String.isNotBlank(c.Name) ? c.Name : 'New neighbour');
                req.sourceType = 'System_Alert';

                FimbyModeratorTaskService.createOrUpdateTask(req);
            }
        }
    }
}
