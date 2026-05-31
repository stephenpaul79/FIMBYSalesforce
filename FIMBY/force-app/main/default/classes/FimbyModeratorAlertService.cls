public without sharing class FimbyModeratorAlertService {

    public static void alertModerators(Moderator_Task__c task) {
        List<Moderator_Assignment__c> assignments = [
            SELECT Contact__c FROM Moderator_Assignment__c
            WHERE Neighbourhood__c = :task.Neighbourhood__c AND Status__c = 'Active'
        ];
        if (assignments.isEmpty()) return;

        String actionUrl = FimbySettings.getUrl('Moderator_Dashboard');
        for (Moderator_Assignment__c ma : assignments) {
            FimbyNotificationService.createNotification(
                ma.Contact__c,
                FimbyConstants.NOTIF_MODERATOR,
                buildTitle(task),
                task.Summary__c,
                task.Id,
                'Moderator_Task__c',
                actionUrl,
                'Neighbourhood team'
            );
        }
    }

    public static void alertAdmin(Moderator_Task__c task, String reason) {
        if (task.Escalated_To__c == null) return;
        FimbyNotificationService.createNotification(
            task.Escalated_To__c,
            FimbyConstants.NOTIF_MODERATOR,
            'A moderator asked for help: ' + task.Category__c.replace('_', ' '),
            reason,
            task.Id,
            'Moderator_Task__c',
            FimbySettings.getUrl('Moderator_Dashboard'),
            'Neighbourhood team'
        );
    }

    private static String buildTitle(Moderator_Task__c task) {
        Map<String, String> categoryTitles = new Map<String, String>{
            'Flagged_Content' => 'Content flagged for review',
            'Content_Report' => 'New content report',
            'Bulk_Buy_Escalation' => 'Bulk buy escalation',
            'Blocked_Contact' => 'Block report filed',
            'New_Signup' => 'New neighbour signed up',
            'Feedback_Triage' => 'New feedback to triage',
            'Health_Alert' => 'Neighbourhood health alert',
            'Escalation_Received' => 'Escalation received',
            'Support_Relationship_Approval' => 'Support relationship request',
            'Organization_Approval' => 'Organization approval request',
            'Support_Person_Concern' => 'Support person concern',
            'Overdue_Loan' => 'Overdue library loan',
            'Stale_Post' => 'Stale post detected',
            'Vouch_Pending' => 'Vouch request stuck'
        };
        String title = categoryTitles.get(task.Category__c);
        return title != null ? title : 'New moderator task';
    }
}
