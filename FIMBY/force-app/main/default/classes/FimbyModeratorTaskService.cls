public without sharing class FimbyModeratorTaskService {

    public static Moderator_Task__c createOrUpdateTask(TaskRequest req) {
        String dedupKey = buildDedupKey(req);

        List<Moderator_Task__c> existing = [
            SELECT Id, Status__c, Report_Count__c, Priority__c,
                   Latest_Reported_Date__c, Resolved_Date__c, Neighbourhood__c,
                   Category__c, Summary__c
            FROM Moderator_Task__c
            WHERE Task_Dedup_Key__c = :dedupKey
            LIMIT 1
            FOR UPDATE
        ];

        if (!existing.isEmpty()) {
            Moderator_Task__c task = existing[0];
            Set<String> openStatuses = new Set<String>{'New', 'In_Progress', 'Awaiting_Info'};

            if (openStatuses.contains(task.Status__c)) {
                return appendEvidence(task, req);
            }

            // Reuse the dedup row for any closed task — unique key prevents a second insert.
            return reopenWithEvidence(task, req);
        }

        return createNewTask(req, dedupKey);
    }

    /**
     * @description True when this reporter already filed on an open Content_Report task
     *              for the same neighbourhood + content record.
     */
    public static Boolean hasReporterFiledContentReport(
        Id neighbourhoodId,
        Id reporterContactId,
        String relatedRecordId,
        String relatedRecordType
    ) {
        if (neighbourhoodId == null || reporterContactId == null || String.isBlank(relatedRecordId)) {
            return false;
        }

        TaskRequest keyReq = new TaskRequest();
        keyReq.neighbourhoodId = neighbourhoodId;
        keyReq.category = 'Content_Report';
        keyReq.relatedRecordId = relatedRecordId;
        keyReq.relatedRecordType = relatedRecordType;
        String dedupKey = buildDedupKey(keyReq);

        List<Moderator_Task__c> tasks = [
            SELECT Id
            FROM Moderator_Task__c
            WHERE Task_Dedup_Key__c = :dedupKey
            LIMIT 1
        ];
        if (tasks.isEmpty()) {
            return false;
        }

        return ![
            SELECT Id
            FROM Moderator_Task_Evidence__c
            WHERE Moderator_Task__c = :tasks[0].Id
              AND Reporter__c = :reporterContactId
            LIMIT 1
        ].isEmpty();
    }

    private static Moderator_Task__c appendEvidence(Moderator_Task__c task, TaskRequest req) {
        if (req.reporterContactId != null && hasReporterEvidenceOnTask(task.Id, req.reporterContactId)) {
            return task;
        }
        createEvidenceRecord(task.Id, req);
        task.Report_Count__c = (task.Report_Count__c != null ? task.Report_Count__c : 0) + 1;
        task.Latest_Reported_Date__c = Datetime.now();
        if (String.isNotBlank(req.reasonCode)) {
            task.Latest_Report_Reason__c = req.reasonCode;
        }
        if (req.priority != null && isPriorityHigher(req.priority, task.Priority__c)) {
            task.Priority__c = req.priority;
        }
        if (task.Status__c == 'Awaiting_Info') {
            task.Status__c = 'In_Progress';
        }
        update task;
        return task;
    }

    private static Moderator_Task__c reopenWithEvidence(Moderator_Task__c task, TaskRequest req) {
        if (req.reporterContactId != null && hasReporterEvidenceOnTask(task.Id, req.reporterContactId)) {
            return task;
        }
        task.Status__c = 'New';
        task.Resolved_Date__c = null;
        task.Resolved_By__c = null;
        createEvidenceRecord(task.Id, req);
        task.Report_Count__c = (task.Report_Count__c != null ? task.Report_Count__c : 0) + 1;
        task.Latest_Reported_Date__c = Datetime.now();
        if (String.isNotBlank(req.reasonCode)) {
            task.Latest_Report_Reason__c = req.reasonCode;
        }
        update task;
        FimbyModeratorAlertService.alertModerators(task);
        return task;
    }

    private static Moderator_Task__c createNewTask(TaskRequest req, String dedupKey) {
        Moderator_Task__c task = new Moderator_Task__c(
            Neighbourhood__c = req.neighbourhoodId,
            Category__c = req.category,
            Priority__c = req.priority != null ? req.priority : 'Standard',
            Status__c = 'New',
            Subject_Contact__c = req.subjectContactId,
            Secondary_Contact__c = req.secondaryContactId,
            Related_Record_Id__c = req.relatedRecordId,
            Related_Record_Type__c = req.relatedRecordType,
            Summary__c = req.summary,
            Report_Count__c = 1,
            Latest_Reported_Date__c = Datetime.now(),
            Latest_Report_Reason__c = req.reasonCode,
            Task_Dedup_Key__c = dedupKey
        );
        insert task;
        createEvidenceRecord(task.Id, req);
        FimbyModeratorAlertService.alertModerators(task);
        return task;
    }

    private static Boolean hasReporterEvidenceOnTask(Id taskId, Id reporterContactId) {
        return ![
            SELECT Id
            FROM Moderator_Task_Evidence__c
            WHERE Moderator_Task__c = :taskId
              AND Reporter__c = :reporterContactId
            LIMIT 1
        ].isEmpty();
    }

    private static void createEvidenceRecord(Id taskId, TaskRequest req) {
        Moderator_Task_Evidence__c evidence = new Moderator_Task_Evidence__c(
            Moderator_Task__c = taskId,
            Source_Type__c = req.sourceType != null ? req.sourceType : 'Content_Report',
            Source_Record_Id__c = req.sourceRecordId,
            Reporter__c = req.reporterContactId,
            Reported_Date__c = Datetime.now(),
            Reason_Code__c = req.reasonCode,
            Details__c = req.details
        );
        insert evidence;
    }

    public static String buildDedupKey(TaskRequest req) {
        if (String.isNotBlank(req.relatedRecordId)) {
            return req.neighbourhoodId + ':' + req.category + ':'
                + req.relatedRecordType + ':' + req.relatedRecordId;
        }
        return req.neighbourhoodId + ':' + req.category + ':' + req.subjectContactId;
    }

    private static Boolean isPriorityHigher(String newPriority, String currentPriority) {
        Map<String, Integer> rank = new Map<String, Integer>{
            'Urgent' => 3, 'Standard' => 2, 'Low' => 1
        };
        Integer newRank = rank.containsKey(newPriority) ? rank.get(newPriority) : 0;
        Integer curRank = rank.containsKey(currentPriority) ? rank.get(currentPriority) : 0;
        return newRank > curRank;
    }

    public class TaskRequest {
        public Id neighbourhoodId;
        public String category;
        public String priority;
        public Id subjectContactId;
        public Id secondaryContactId;
        public String relatedRecordId;
        public String relatedRecordType;
        public String summary;
        public String sourceType;
        public String sourceRecordId;
        public Id reporterContactId;
        public String reasonCode;
        public String details;
    }
}
