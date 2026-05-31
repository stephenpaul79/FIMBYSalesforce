public without sharing class FimbyModeratorTaskStalenessJob implements Schedulable {

    private static final Integer URGENT_REMINDER_HOURS = 12;
    private static final Integer URGENT_ESCALATE_HOURS = 24;
    private static final Integer SUPPORT_CONCERN_REMINDER_HOURS = 6;
    private static final Integer SUPPORT_CONCERN_ESCALATE_HOURS = 12;
    private static final Integer STANDARD_REMINDER_HOURS = 48;
    private static final Integer STANDARD_ESCALATE_HOURS = 120;
    private static final Integer LOW_REMINDER_HOURS = 120;
    private static final Integer LOW_ESCALATE_HOURS = 336;
    private static final Integer APPROVAL_REMINDER_HOURS = 96;
    private static final Integer APPROVAL_ESCALATE_HOURS = 168;

    @TestVisible
    private static Integer testReminderHoursOverride;
    @TestVisible
    private static Integer testEscalateHoursOverride;

    public void execute(SchedulableContext sc) {
        List<Moderator_Task__c> staleTasks = [
            SELECT Id, Status__c, Priority__c, Category__c, Summary__c,
                   Neighbourhood__c, Subject_Contact__c, CreatedDate,
                   Reminder_Sent_Date__c, Auto_Escalated__c
            FROM Moderator_Task__c
            WHERE Status__c = 'New'
            LIMIT 200
        ];

        if (staleTasks.isEmpty()) return;

        Datetime now = System.now();
        List<Moderator_Task__c> toUpdate = new List<Moderator_Task__c>();

        for (Moderator_Task__c task : staleTasks) {
            Long ageHours = (now.getTime() - task.CreatedDate.getTime()) / (1000 * 60 * 60);
            Integer reminderThreshold = getReminderThreshold(task);
            Integer escalateThreshold = getEscalateThreshold(task);

            if (ageHours >= escalateThreshold && task.Auto_Escalated__c != true) {
                task.Status__c = 'Escalated';
                task.Escalation_Reason__c = 'Auto-escalated: unactioned for ' + ageHours + ' hours';
                task.Escalated_Date__c = now;
                task.Auto_Escalated__c = true;
                if (task.Reminder_Sent_Date__c == null) {
                    task.Reminder_Sent_Date__c = now;
                }
                toUpdate.add(task);
                notifyAutoEscalation(task);
            } else if (ageHours >= reminderThreshold && task.Reminder_Sent_Date__c == null) {
                task.Reminder_Sent_Date__c = now;
                toUpdate.add(task);
                notifyReminder(task);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private Integer getReminderThreshold(Moderator_Task__c task) {
        if (Test.isRunningTest() && testReminderHoursOverride != null) {
            return testReminderHoursOverride;
        }
        if (isApprovalCategory(task.Category__c)) {
            return APPROVAL_REMINDER_HOURS;
        }
        if (task.Priority__c == 'Urgent' && task.Category__c == 'Support_Person_Concern') {
            return SUPPORT_CONCERN_REMINDER_HOURS;
        }
        if (task.Priority__c == 'Urgent') return URGENT_REMINDER_HOURS;
        if (task.Priority__c == 'Low') return LOW_REMINDER_HOURS;
        return STANDARD_REMINDER_HOURS;
    }

    private Integer getEscalateThreshold(Moderator_Task__c task) {
        if (Test.isRunningTest() && testEscalateHoursOverride != null) {
            return testEscalateHoursOverride;
        }
        if (isApprovalCategory(task.Category__c)) {
            return APPROVAL_ESCALATE_HOURS;
        }
        if (task.Priority__c == 'Urgent' && task.Category__c == 'Support_Person_Concern') {
            return SUPPORT_CONCERN_ESCALATE_HOURS;
        }
        if (task.Priority__c == 'Urgent') return URGENT_ESCALATE_HOURS;
        if (task.Priority__c == 'Low') return LOW_ESCALATE_HOURS;
        return STANDARD_ESCALATE_HOURS;
    }

    private static Boolean isApprovalCategory(String category) {
        return category == 'Organization_Approval'
            || category == 'Support_Relationship_Approval';
    }

    private void notifyReminder(Moderator_Task__c task) {
        try {
            FimbyModeratorAlertService.alertModerators(task);
        } catch (Exception e) {
            FimbyLogger.error('FimbyModeratorTaskStalenessJob', 'notifyReminder', e);
        }
    }

    private void notifyAutoEscalation(Moderator_Task__c task) {
        try {
            String reason = 'Auto-escalated: ' + task.Category__c.replace('_', ' ') +
                ' task unactioned for over ' + getEscalateThreshold(task) + ' hours: ' + task.Summary__c;
            FimbyModeratorAlertService.alertAdmin(task, reason);
            FimbyModeratorAlertService.alertModerators(task);
        } catch (Exception e) {
            FimbyLogger.error('FimbyModeratorTaskStalenessJob', 'notifyAutoEscalation', e);
        }
    }
}
