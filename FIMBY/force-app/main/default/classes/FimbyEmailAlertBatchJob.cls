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
            SELECT Id, Type__c, Title__c, Body__c, Actor_Name__c, Actor_Contact__c,
                   Action_URL__c, Contact__c, Related_Record_Id__c,
                   Related_Record_Type__c, Email_Retry_Count__c, Delivery_State__c
            FROM Notification__c
            WHERE Email_Status__c = 'Pending'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT :batchCap
        ];
        if (pending.isEmpty()) {
            return;
        }

        Boolean isSunday = isSundayNow();

        Set<Id> inboxIds = new Set<Id>();
        for (Notification__c n : pending) {
            if (n.Contact__c != null) {
                inboxIds.add(n.Contact__c);
            }
        }

        // A Contact with no login of their own (elder supportee, organization
        // contact, parent-proxied child) is served by every neighbour approved to
        // act for them. Previously such rows found no User and were quietly marked
        // Suppressed, so the alert reached nobody at all.
        Map<Id, List<FimbySupportedIdentityDelivery.Target>> targetsByInbox =
            resolveTargets(inboxIds);

        // Mirror FimbyPushBatchJob: hold Pending through quiet hours (no outbound email).
        // Eligibility is now per RECIPIENT, since two guardians serving one inbox can
        // sit in different timezones and hold different Sunday preferences.
        Map<Id, List<Notification__c>> byRecipientContact = new Map<Id, List<Notification__c>>();
        Map<Id, Id> inboxByRecipientRow = new Map<Id, Id>();
        Set<Id> claimedRowIds = new Set<Id>();
        Map<Id, Set<Id>> recipientUsersByRow = new Map<Id, Set<Id>>();

        for (Notification__c n : pending) {
            if (n.Contact__c == null) {
                continue;
            }
            List<FimbySupportedIdentityDelivery.Target> targets = targetsByInbox.get(n.Contact__c);
            if (targets == null || targets.isEmpty()) {
                continue;
            }
            for (FimbySupportedIdentityDelivery.Target t : targets) {
                if (t.u == null) {
                    continue;
                }
                if (FimbyPushBatchJob.isInQuietHours(t.u)) {
                    continue;
                }
                if (isSunday) {
                    Boolean includesSundays = t.u.Include_Sundays__c == true;
                    Boolean isDirect = FimbyEmailAlertService.isDirectActionType(n.Type__c)
                        || n.Type__c == FimbyConstants.NOTIF_MESSAGE;
                    if (!includesSundays && !isDirect) {
                        continue;
                    }
                }
                Id recipientContactId = t.u.ContactId;
                if (recipientContactId == null) {
                    continue;
                }
                if (!byRecipientContact.containsKey(recipientContactId)) {
                    byRecipientContact.put(recipientContactId, new List<Notification__c>());
                }
                byRecipientContact.get(recipientContactId).add(n);
                claimedRowIds.add(n.Id);
                if (!recipientUsersByRow.containsKey(n.Id)) {
                    recipientUsersByRow.put(n.Id, new Set<Id>());
                }
                recipientUsersByRow.get(n.Id).add(t.u.Id);
                if (t.isProxy == true) {
                    inboxByRecipientRow.put(n.Id, n.Contact__c);
                }
            }
        }

        if (byRecipientContact.isEmpty()) {
            return;
        }

        claimRows(pending, claimedRowIds, recipientUsersByRow);

        try {
            System.enqueueJob(new FimbyEmailAlertQueueable(
                byRecipientContact, inboxByRecipientRow, queryInboxNames(inboxByRecipientRow)));
        } catch (Exception e) {
            FimbyLogger.error('FimbyEmailAlertBatchJob', 'execute', e);
        }
    }

    /**
     * Claim-then-send, extended to fan-out. A row delivered to several helpers
     * records each claim in its ledger and derives the row-level status from the
     * whole ledger, so one guardian's send can never mark the row done while the
     * other is still owed an email.
     */
    private void claimRows(
        List<Notification__c> pending, Set<Id> claimedRowIds, Map<Id, Set<Id>> recipientUsersByRow
    ) {
        List<Notification__c> updates = new List<Notification__c>();
        for (Notification__c n : pending) {
            if (!claimedRowIds.contains(n.Id)) {
                continue;
            }
            Set<Id> recipients = recipientUsersByRow.get(n.Id);
            if (recipients == null || recipients.size() <= 1) {
                updates.add(new Notification__c(Id = n.Id, Email_Status__c = 'Processing'));
                continue;
            }
            FimbySupportedIdentityDelivery.Ledger ledger =
                FimbySupportedIdentityDelivery.parseLedger(n.Delivery_State__c);
            if (ledger == null) {
                ledger = new FimbySupportedIdentityDelivery.Ledger(n.Contact__c);
            }
            for (Id userId : recipients) {
                FimbySupportedIdentityDelivery.Recipient rec = ledger.forUser(userId);
                if (rec == null) {
                    ledger.r.add(new FimbySupportedIdentityDelivery.Recipient(
                        userId, null, FimbySupportedIdentityDelivery.PROCESSING));
                } else {
                    rec.e = FimbySupportedIdentityDelivery.PROCESSING;
                }
            }
            updates.add(new Notification__c(
                Id = n.Id,
                Email_Status__c = ledger.emailAggregate(),
                Delivery_State__c = FimbySupportedIdentityDelivery.serializeLedger(ledger)
            ));
        }
        if (!updates.isEmpty()) {
            Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private Map<Id, List<FimbySupportedIdentityDelivery.Target>> resolveTargets(Set<Id> inboxIds) {
        Map<Id, User> ownUserByContact = queryEmailUsers(inboxIds);

        Set<Id> unbacked = FimbySupportedIdentityDelivery.unbackedContacts(
            inboxIds, ownUserByContact);
        Map<Id, Set<Id>> helpersBySupportee =
            FimbySupportedIdentityDelivery.resolveHelperContacts(unbacked);

        Set<Id> helperContactIds = new Set<Id>();
        for (Set<Id> helpers : helpersBySupportee.values()) {
            helperContactIds.addAll(helpers);
        }

        return FimbySupportedIdentityDelivery.buildTargets(
            inboxIds, ownUserByContact, helpersBySupportee, queryEmailUsers(helperContactIds));
    }

    private Map<Id, User> queryEmailUsers(Set<Id> contactIds) {
        Map<Id, User> byContact = new Map<Id, User>();
        if (contactIds == null || contactIds.isEmpty()) {
            return byContact;
        }
        for (User u : [
            SELECT Id, ContactId, Include_Sundays__c,
                   Quiet_Hours_Preference__c, TimeZoneSidKey
            FROM User
            WHERE ContactId IN :contactIds AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            byContact.put(u.ContactId, u);
        }
        return byContact;
    }

    /**
     * First names of the proxied inboxes, so a guardian's subject line can say who
     * the email is about instead of an unqualified "your item".
     */
    private Map<Id, String> queryInboxNames(Map<Id, Id> inboxByRecipientRow) {
        Map<Id, String> nameById = new Map<Id, String>();
        if (inboxByRecipientRow.isEmpty()) {
            return nameById;
        }
        Set<Id> inboxIds = new Set<Id>(inboxByRecipientRow.values());
        for (Contact c : [
            SELECT Id, FirstName, LastName
            FROM Contact
            WHERE Id IN :inboxIds
            WITH SYSTEM_MODE
        ]) {
            nameById.put(c.Id, String.isNotBlank(c.FirstName) ? c.FirstName : c.LastName);
        }
        return nameById;
    }

    @TestVisible
    static Boolean isSundayNow() {
        Date today = Date.today();
        Datetime dt = Datetime.newInstance(today.year(), today.month(), today.day());
        String dayOfWeek = dt.format('u');
        return dayOfWeek == '7';
    }
}
