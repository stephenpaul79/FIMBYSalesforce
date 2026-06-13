/**
 * @description Creates "New Signup" moderator welcome tasks for newly active
 * community users. Runs asynchronously because the triggering DML is on User (a
 * setup sObject) and Moderator_Task__c is a regular sObject — doing both in one
 * transaction throws MIXED_DML_OPERATION. A neighbour is only welcomed once: if a
 * New_Signup task already exists for the contact + neighbourhood (any status), it
 * is skipped, so deactivate/reactivate never re-welcomes.
 */
public without sharing class FimbyWelcomeTaskQueueable implements System.Queueable, System.Finalizer {

    private static final String CATEGORY_NEW_SIGNUP = 'New_Signup';
    private static final String RELATED_TYPE_CONTACT = 'Contact';

    private final Set<Id> contactIds;

    public FimbyWelcomeTaskQueueable(Set<Id> contactIds) {
        this.contactIds = contactIds;
    }

    public void execute(System.QueueableContext qc) {
        System.attachFinalizer(this);

        if (contactIds == null || contactIds.isEmpty()) {
            return;
        }

        List<Contact> contacts = [
            SELECT Id, Name, AccountId
            FROM Contact
            WHERE Id IN :contactIds
              AND AccountId != null
        ];
        if (contacts.isEmpty()) {
            return;
        }

        Map<String, Contact> contactByKey = new Map<String, Contact>();
        for (Contact c : contacts) {
            contactByKey.put(buildKey(c), c);
        }

        Set<String> existingKeys = new Set<String>();
        for (Moderator_Task__c task : [
            SELECT Task_Dedup_Key__c
            FROM Moderator_Task__c
            WHERE Task_Dedup_Key__c IN :contactByKey.keySet()
        ]) {
            existingKeys.add(task.Task_Dedup_Key__c);
        }

        for (String key : contactByKey.keySet()) {
            if (existingKeys.contains(key)) {
                continue;
            }
            FimbyModeratorTaskService.createOrUpdateTask(buildTaskRequest(contactByKey.get(key)));
        }
    }

    public void execute(System.FinalizerContext fc) {
        if (fc != null && fc.getResult() == System.ParentJobResult.UNHANDLED_EXCEPTION) {
            FimbyLogger.error(
                'FimbyWelcomeTaskQueueable',
                'execute',
                fc.getException()
            );
        }
    }

    private static String buildKey(Contact c) {
        FimbyModeratorTaskService.TaskRequest keyReq = new FimbyModeratorTaskService.TaskRequest();
        keyReq.neighbourhoodId = c.AccountId;
        keyReq.category = CATEGORY_NEW_SIGNUP;
        keyReq.relatedRecordType = RELATED_TYPE_CONTACT;
        keyReq.relatedRecordId = c.Id;
        return FimbyModeratorTaskService.buildDedupKey(keyReq);
    }

    private static FimbyModeratorTaskService.TaskRequest buildTaskRequest(Contact c) {
        FimbyModeratorTaskService.TaskRequest req = new FimbyModeratorTaskService.TaskRequest();
        req.neighbourhoodId = c.AccountId;
        req.category = CATEGORY_NEW_SIGNUP;
        req.priority = 'Standard';
        req.subjectContactId = c.Id;
        req.relatedRecordId = c.Id;
        req.relatedRecordType = RELATED_TYPE_CONTACT;
        req.summary = 'New neighbour signed up: '
            + (String.isNotBlank(c.Name) ? c.Name : 'New neighbour');
        req.sourceType = 'System_Alert';
        return req;
    }
}
