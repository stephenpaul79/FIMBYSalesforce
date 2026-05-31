/**
 * @description Schedulable job for immediate email alerts. Runs every 15 minutes (offset 5min
 * from push batch). Claims Pending email notifications, groups by user, and enqueues
 * FimbyEmailAlertQueueable for rendering and sending. Uses claim-then-send pattern (D2)
 * for double-send prevention. Respects Sunday soft rest for broadcast categories (P5).
 *
 * Schedule: System.schedule('FIMBY Email Alert Batch', '0 5/15 * * * ?', new FimbyEmailAlertBatchJob());
 */
global without sharing class FimbyEmailAlertBatchJob implements Schedulable {

    global void execute(SchedulableContext ctx) {
        if (!FimbySettings.emailAlertsGlobalEnabled()) {
            return;
        }

        Integer batchCap = FimbySettings.emailAlertBatchCap();

        List<Notification__c> pending = [
            SELECT Id, Type__c, Title__c, Body__c, Actor_Name__c,
                   Action_URL__c, Contact__c, Related_Record_Id__c,
                   Related_Record_Type__c
            FROM Notification__c
            WHERE Email_Status__c = 'Pending'
            ORDER BY CreatedDate ASC
            LIMIT :batchCap
        ];
        if (pending.isEmpty()) {
            return;
        }

        Boolean isSunday = isSundayNow();

        Set<Id> contactIds = new Set<Id>();
        for (Notification__c n : pending) {
            if (n.Contact__c != null) {
                contactIds.add(n.Contact__c);
            }
        }

        Map<Id, User> userByContactId = new Map<Id, User>();
        if (!contactIds.isEmpty()) {
            for (User u : [
                SELECT ContactId, Include_Sundays__c,
                       Quiet_Hours_Preference__c, TimeZoneSidKey
                FROM User
                WHERE ContactId IN :contactIds AND IsActive = true
            ]) {
                userByContactId.put(u.ContactId, u);
            }
        }

        // Mirror FimbyPushBatchJob: hold Pending through quiet hours (no outbound email).
        List<Notification__c> toClaim = new List<Notification__c>();
        for (Notification__c n : pending) {
            User u = n.Contact__c != null ? userByContactId.get(n.Contact__c) : null;
            if (u != null && FimbyPushBatchJob.isInQuietHours(u)) {
                continue;
            }

            // On Sundays, users who have NOT opted into Sunday sends still get
            // direct-action notifications plus DMs; broadcast types wait until Monday.
            if (isSunday) {
                Boolean userIncludesSundays = n.Contact__c != null
                    && u != null && u.Include_Sundays__c == true;
                Boolean isDirect = FimbyEmailAlertService.isDirectActionType(n.Type__c)
                    || n.Type__c == FimbyConstants.NOTIF_MESSAGE;
                if (!userIncludesSundays && !isDirect) {
                    continue;
                }
            }
            toClaim.add(n);
        }
        if (toClaim.isEmpty()) {
            return;
        }

        List<Notification__c> updates = new List<Notification__c>();
        for (Notification__c n : toClaim) {
            updates.add(new Notification__c(Id = n.Id, Email_Status__c = 'Processing'));
        }
        update updates;

        Map<Id, List<Notification__c>> byContact = new Map<Id, List<Notification__c>>();
        for (Notification__c n : toClaim) {
            if (n.Contact__c == null) {
                continue;
            }
            if (!byContact.containsKey(n.Contact__c)) {
                byContact.put(n.Contact__c, new List<Notification__c>());
            }
            byContact.get(n.Contact__c).add(n);
        }

        try {
            System.enqueueJob(new FimbyEmailAlertQueueable(byContact));
        } catch (Exception e) {
            FimbyLogger.error('FimbyEmailAlertBatchJob', 'execute', e);
        }
    }

    @TestVisible
    static Boolean isSundayNow() {
        Date today = Date.today();
        Datetime dt = Datetime.newInstance(today.year(), today.month(), today.day());
        String dayOfWeek = dt.format('u');
        return dayOfWeek == '7';
    }
}
