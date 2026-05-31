public without sharing class BlockedContactModeratorTriggerHandler {

    public static void handleAfterInsert(List<Blocked_Contact__c> newRecords) {
        List<FimbyModeratorTaskService.TaskRequest> requests = new List<FimbyModeratorTaskService.TaskRequest>();

        Set<Id> contactIds = new Set<Id>();
        for (Blocked_Contact__c bc : newRecords) {
            if (bc.Reported__c == true) {
                contactIds.add(bc.Blocker__c);
                contactIds.add(bc.Blocked__c);
            }
        }
        if (contactIds.isEmpty()) return;

        Map<Id, Contact> contacts = new Map<Id, Contact>([
            SELECT Id, AccountId FROM Contact WHERE Id IN :contactIds
        ]);

        for (Blocked_Contact__c bc : newRecords) {
            if (bc.Reported__c != true) continue;

            Contact blocker = contacts.get(bc.Blocker__c);
            if (blocker == null || blocker.AccountId == null) continue;

            FimbyModeratorTaskService.TaskRequest req = new FimbyModeratorTaskService.TaskRequest();
            req.neighbourhoodId = blocker.AccountId;
            req.category = 'Blocked_Contact';
            req.priority = 'Standard';
            req.subjectContactId = bc.Blocked__c;
            req.secondaryContactId = bc.Blocker__c;
            req.relatedRecordId = String.valueOf(bc.Id);
            req.relatedRecordType = 'Blocked_Contact__c';
            req.summary = 'Block report filed';
            req.sourceType = 'Block_Report';
            req.sourceRecordId = String.valueOf(bc.Id);
            req.reporterContactId = bc.Blocker__c;
            req.reasonCode = 'Block_Report';
            req.details = bc.Report_Details__c;

            requests.add(req);
        }

        for (FimbyModeratorTaskService.TaskRequest req : requests) {
            FimbyModeratorTaskService.createOrUpdateTask(req);
        }
    }
}
