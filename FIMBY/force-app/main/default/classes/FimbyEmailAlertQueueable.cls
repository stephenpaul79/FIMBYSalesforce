/**
 * @description Queueable that renders and sends branded email alerts. Processes notifications
 * grouped by user (from FimbyEmailAlertBatchJob). Re-checks eligibility at send time (D8),
 * isolates per-user failures (D5), and respects the Include_Sundays__c opt-out.
 * Chains if more than 100 emails need sending per transaction.
 */
public without sharing class FimbyEmailAlertQueueable implements Queueable {

    private static final Integer SEND_CHUNK_SIZE = 100;

    private Map<Id, List<Notification__c>> notifsByContact;

    public class AlertCardEnrichment {
        public String actorImageUrl;
        public String actorFirstName;
        public String itemImageUrl;
    }

    public FimbyEmailAlertQueueable(Map<Id, List<Notification__c>> notifsByContact) {
        this.notifsByContact = notifsByContact;
    }

    public void execute(QueueableContext ctx) {
        if (notifsByContact == null || notifsByContact.isEmpty()) {
            return;
        }

        Set<Id> contactIds = notifsByContact.keySet();

        Map<Id, User> userByContactId = new Map<Id, User>();
        for (User u : [
            SELECT Id, ContactId, FirstName, Email, TimeZoneSidKey,
                   Quiet_Hours_Preference__c,
                   Email_Alerts_Enabled__c, Email_Alert_Messages__c,
                   Email_Alert_Needs_Offers__c, Email_Alert_Library__c,
                   Email_Alert_Stories__c, Email_Alert_Reminders__c,
                   Email_Alert_Bulk_Buy__c, Email_Alert_Events__c,
                   Include_Sundays__c,
                   Contact.HasOptedOutOfEmail, Contact.Account.Name
            FROM User
            WHERE ContactId IN :contactIds
              AND IsActive = true
              AND Email != null
        ]) {
            userByContactId.put(u.ContactId, u);
        }

        // Collect all notifications for enrichment
        List<Notification__c> allNotifs = new List<Notification__c>();
        for (List<Notification__c> notifs : notifsByContact.values()) {
            allNotifs.addAll(notifs);
        }
        Map<String, AlertCardEnrichment> enrichmentMap = enrichNotifications(allNotifs);

        Id oweaId = getOweaId();

        if (oweaId == null) {
            markAllFailed(notifsByContact, 'OWEA not found');
            return;
        }

        List<Notification__c> allUpdates = new List<Notification__c>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id contactId : notifsByContact.keySet()) {
            User u = userByContactId.get(contactId);
            List<Notification__c> notifs = notifsByContact.get(contactId);

            if (!isEligibleAtSendTime(u)) {
                for (Notification__c n : notifs) {
                    allUpdates.add(new Notification__c(
                        Id = n.Id, Email_Status__c = 'Suppressed'
                    ));
                }
                continue;
            }

            if (FimbyPushBatchJob.isInQuietHours(u)) {
                for (Notification__c n : notifs) {
                    allUpdates.add(new Notification__c(
                        Id = n.Id, Email_Status__c = 'Pending'
                    ));
                }
                continue;
            }

            // Per-type re-check honours toggle flips between create-time
            // (when Email_Status__c was first stamped) and now. The user
            // might have just opened the app and disabled an alert type;
            // suppress those without nuking the whole batch.
            List<Notification__c> eligibleNotifs = new List<Notification__c>();
            for (Notification__c n : notifs) {
                if (FimbyEmailAlertService.shouldSendEmail(n.Type__c, u) == 'Pending') {
                    eligibleNotifs.add(n);
                } else {
                    allUpdates.add(new Notification__c(
                        Id = n.Id, Email_Status__c = 'Suppressed'
                    ));
                }
            }
            if (eligibleNotifs.isEmpty()) {
                continue;
            }
            notifs = eligibleNotifs;

            try {
                String dynamicHtml = FimbyEmailHtmlBuilder.buildAlertCards(notifs, enrichmentMap, u.FirstName);
                // Alert emails are direct-action: subject + card already carry the story
                // for the recipient. The neighbourhood-summary intent lines belong to
                // digest emails. See lending_email_fix_plan_b4b7029a Phase 2.
                String intentLine = null;
                String neighbourhoodName = u.Contact?.Account?.Name;
                String subjectLine = buildSubject(notifs);

                String html = buildAlertHtml(dynamicHtml, intentLine, neighbourhoodName, subjectLine, notifs.size());

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(u.Id);
                email.setTreatTargetObjectAsRecipient(true);
                email.setSubject(subjectLine);
                email.setHtmlBody(html);
                email.setSaveAsActivity(false);
                email.setOrgWideEmailAddressId(oweaId);

                emails.add(email);

                Datetime now = Datetime.now();
                for (Notification__c n : notifs) {
                    allUpdates.add(new Notification__c(
                        Id = n.Id, Email_Status__c = 'Sent', Email_Sent_At__c = now
                    ));
                }
            } catch (Exception e) {
                for (Notification__c n : notifs) {
                    Integer retryCount = n.Email_Retry_Count__c != null ? (Integer) n.Email_Retry_Count__c : 0;
                    allUpdates.add(new Notification__c(
                        Id = n.Id,
                        Email_Status__c = 'Failed',
                        Email_Error__c = e.getMessage()?.abbreviate(255),
                        Email_Retry_Count__c = retryCount + 1
                    ));
                }
            }
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);
            } catch (Exception e) {
                FimbyLogger.error('FimbyEmailAlertQueueable', 'execute-sendEmail', e);
            }
        }

        if (!allUpdates.isEmpty()) {
            Database.update(allUpdates, false);
        }
    }

    private String buildAlertHtml(String dynamicHtml, String intentLine, String neighbourhoodName, String subjectLine, Integer notifCount) {
        Boolean singleDirectAlert = notifCount == 1;
        return FimbyEmailHtmlBuilder.wrapInBrandedShell(
            dynamicHtml, subjectLine, neighbourhoodName, intentLine, singleDirectAlert
        );
    }

    private Boolean isEligibleAtSendTime(User u) {
        if (u == null) { return false; }
        if (u.Email_Alerts_Enabled__c == false) { return false; }
        if (u.Contact?.HasOptedOutOfEmail == true) { return false; }
        return true;
    }

    // Hard cap to keep gmail-friendly preview pane and avoid awkward wraps. Subjects
    // longer than this are truncated with an ellipsis. iOS push title ceiling is 80 so
    // we sit just under for email and add room for "FIMBY: " prefix some clients add.
    private static final Integer SUBJECT_MAX_LENGTH = 78;

    @TestVisible
    private String buildSubject(List<Notification__c> notifs) {
        if (notifs.size() == 1) {
            Notification__c n = notifs[0];
            // Privacy: DM previews never reveal sender or content in the subject line.
            if (n.Type__c == FimbyConstants.NOTIF_MESSAGE) {
                return 'New message from a neighbour';
            }
            // Single-notification alerts: use Title__c in the inbox subject only. The
            // branded shell skips the in-body heading for single alerts so the card
            // title is not repeated a third time. Falls back to the coarse type-based
            // subject when Title__c is blank.
            if (String.isNotBlank(n.Title__c)) {
                return truncateSubject(n.Title__c);
            }
            return getSubjectForType(n.Type__c);
        }

        Boolean allDM = true;
        for (Notification__c n : notifs) {
            if (n.Type__c != FimbyConstants.NOTIF_MESSAGE) {
                allDM = false;
                break;
            }
        }
        if (allDM) {
            return notifs.size() + ' new messages';
        }
        return notifs.size() + ' new updates in your neighbourhood';
    }

    private String truncateSubject(String raw) {
        if (String.isBlank(raw)) { return raw; }
        String cleaned = raw.replaceAll('\\s+', ' ').trim();
        if (cleaned.length() <= SUBJECT_MAX_LENGTH) { return cleaned; }
        return cleaned.substring(0, SUBJECT_MAX_LENGTH - 1).trim() + '\u2026';
    }

    private String getSubjectForType(String notifType) {
        Map<String, String> subjects = new Map<String, String>{
            FimbyConstants.NOTIF_MESSAGE => 'New message from a neighbour',
            FimbyConstants.NOTIF_RESPONSE => 'Someone responded to your post',
            FimbyConstants.NOTIF_EVENT_CHAT => 'New message in an event chat',
            FimbyConstants.NOTIF_COMMENT => 'Someone commented on your story',
            FimbyConstants.NOTIF_LENDING_REQUEST => 'Someone wants to borrow your item',
            FimbyConstants.NOTIF_LOAN_APPROVED => 'Your borrow request was approved',
            FimbyConstants.NOTIF_EXTENSION_REQUEST => 'Extension requested on your item',
            FimbyConstants.NOTIF_EXTENSION_APPROVED => 'Your extension was approved',
            FimbyConstants.NOTIF_EXTENSION_DECLINED => 'Extension was declined',
            FimbyConstants.NOTIF_ITEM_RETURNED => 'Your item has been returned',
            FimbyConstants.NOTIF_OVERDUE_REMINDER => 'Reminder: item is overdue',
            FimbyConstants.NOTIF_EVENT_REMINDER => 'Reminder: upcoming event',
            FimbyConstants.NOTIF_BULK_BUY_RESERVATION => 'Someone reserved on your bulk buy',
            FimbyConstants.NOTIF_BULK_BUY_STATUS => 'Bulk buy update',
            FimbyConstants.NOTIF_BULK_BUY_PICKUP => 'Your bulk buy is ready for pickup'
        };
        return subjects.containsKey(notifType)
            ? subjects.get(notifType) : 'Update from your neighbourhood';
    }

    @TestVisible
    private static Id oweaCached;
    private static Id getOweaId() {
        if (oweaCached == null) {
            List<OrgWideEmailAddress> oweas = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE DisplayName = 'FIMBY' LIMIT 1
            ];
            oweaCached = oweas.isEmpty() ? null : oweas[0].Id;
        }
        return oweaCached;
    }

    private void markAllFailed(Map<Id, List<Notification__c>> notifsMap, String errorMsg) {
        List<Notification__c> updates = new List<Notification__c>();
        for (Id contactId : notifsMap.keySet()) {
            for (Notification__c n : notifsMap.get(contactId)) {
                updates.add(new Notification__c(
                    Id = n.Id, Email_Status__c = 'Failed', Email_Error__c = errorMsg
                ));
            }
        }
        if (!updates.isEmpty()) {
            Database.update(updates, false);
        }
    }

    @TestVisible
    static Map<String, AlertCardEnrichment> enrichNotifications(List<Notification__c> notifs) {
        Map<String, AlertCardEnrichment> result = new Map<String, AlertCardEnrichment>();
        if (notifs == null || notifs.isEmpty()) { return result; }

        Map<String, Set<String>> idsByType = new Map<String, Set<String>>();
        for (Notification__c n : notifs) {
            if (String.isBlank(n.Related_Record_Id__c) || String.isBlank(n.Related_Record_Type__c)) {
                continue;
            }
            if (!idsByType.containsKey(n.Related_Record_Type__c)) {
                idsByType.put(n.Related_Record_Type__c, new Set<String>());
            }
            idsByType.get(n.Related_Record_Type__c).add(n.Related_Record_Id__c);
        }

        if (idsByType.containsKey('Needs_Offers__c')) {
            Set<String> ids = idsByType.get('Needs_Offers__c');
            for (Needs_Offers__c p : [
                SELECT Id, Image_1_URL__c, Contact__r.Image_URL__c, Contact__r.FirstName
                FROM Needs_Offers__c WHERE Id IN :ids
            ]) {
                AlertCardEnrichment e = new AlertCardEnrichment();
                e.itemImageUrl = p.Image_1_URL__c;
                e.actorImageUrl = p.Contact__r?.Image_URL__c;
                e.actorFirstName = p.Contact__r?.FirstName;
                result.put(String.valueOf(p.Id), e);
            }
        }

        if (idsByType.containsKey('Response__c')) {
            Set<String> ids = idsByType.get('Response__c');
            for (Response__c r : [
                SELECT Id, Contact__r.Image_URL__c, Contact__r.FirstName,
                       Need_Offer_Responded_To__r.Image_1_URL__c
                FROM Response__c WHERE Id IN :ids
            ]) {
                AlertCardEnrichment e = new AlertCardEnrichment();
                e.itemImageUrl = r.Need_Offer_Responded_To__r?.Image_1_URL__c;
                e.actorImageUrl = r.Contact__r?.Image_URL__c;
                e.actorFirstName = r.Contact__r?.FirstName;
                result.put(String.valueOf(r.Id), e);
            }
        }

        if (idsByType.containsKey('Library_Item__c')) {
            Set<String> ids = idsByType.get('Library_Item__c');
            for (Library_Item__c li : [
                SELECT Id, Image_URL__c, Owner_Contact__r.Image_URL__c, Owner_Contact__r.FirstName
                FROM Library_Item__c WHERE Id IN :ids
            ]) {
                AlertCardEnrichment e = new AlertCardEnrichment();
                e.itemImageUrl = li.Image_URL__c;
                e.actorImageUrl = li.Owner_Contact__r?.Image_URL__c;
                e.actorFirstName = li.Owner_Contact__r?.FirstName;
                result.put(String.valueOf(li.Id), e);
            }
        }

        if (idsByType.containsKey('Lending_Request__c')) {
            Set<String> ids = idsByType.get('Lending_Request__c');
            for (Lending_Request__c lr : [
                SELECT Id, Library_Item__r.Image_URL__c,
                       Requested_By__r.Image_URL__c, Requested_By__r.FirstName
                FROM Lending_Request__c WHERE Id IN :ids
            ]) {
                AlertCardEnrichment e = new AlertCardEnrichment();
                e.itemImageUrl = lr.Library_Item__r?.Image_URL__c;
                e.actorImageUrl = lr.Requested_By__r?.Image_URL__c;
                e.actorFirstName = lr.Requested_By__r?.FirstName;
                result.put(String.valueOf(lr.Id), e);
            }
        }

        if (idsByType.containsKey('Loaned_Item__c')) {
            Set<String> ids = idsByType.get('Loaned_Item__c');
            for (Loaned_Item__c lo : [
                SELECT Id, Library_Item__r.Image_URL__c,
                       Loaned_To__r.Image_URL__c, Loaned_To__r.FirstName
                FROM Loaned_Item__c WHERE Id IN :ids
            ]) {
                AlertCardEnrichment e = new AlertCardEnrichment();
                e.itemImageUrl = lo.Library_Item__r?.Image_URL__c;
                e.actorImageUrl = lo.Loaned_To__r?.Image_URL__c;
                e.actorFirstName = lo.Loaned_To__r?.FirstName;
                result.put(String.valueOf(lo.Id), e);
            }
        }

        if (idsByType.containsKey('Story__c')) {
            Set<String> ids = idsByType.get('Story__c');
            for (Story__c s : [
                SELECT Id, Image_URL__c, Posted_By__r.Image_URL__c, Posted_By__r.FirstName
                FROM Story__c WHERE Id IN :ids
            ]) {
                AlertCardEnrichment e = new AlertCardEnrichment();
                e.itemImageUrl = s.Image_URL__c;
                e.actorImageUrl = s.Posted_By__r?.Image_URL__c;
                e.actorFirstName = s.Posted_By__r?.FirstName;
                result.put(String.valueOf(s.Id), e);
            }
        }

        if (idsByType.containsKey('Message__c')) {
            Set<String> ids = idsByType.get('Message__c');
            for (Message__c m : [
                SELECT Id, Sender__r.Image_URL__c, Sender__r.FirstName
                FROM Message__c WHERE Id IN :ids
            ]) {
                AlertCardEnrichment e = new AlertCardEnrichment();
                e.actorImageUrl = m.Sender__r?.Image_URL__c;
                e.actorFirstName = m.Sender__r?.FirstName;
                result.put(String.valueOf(m.Id), e);
            }
        }

        if (idsByType.containsKey('Conversation__c')) {
            Set<String> ids = idsByType.get('Conversation__c');
            for (Conversation__c cv : [
                SELECT Id, Last_Message_Sender__r.Image_URL__c, Last_Message_Sender__r.FirstName
                FROM Conversation__c WHERE Id IN :ids
            ]) {
                AlertCardEnrichment e = new AlertCardEnrichment();
                e.actorImageUrl = cv.Last_Message_Sender__r?.Image_URL__c;
                e.actorFirstName = cv.Last_Message_Sender__r?.FirstName;
                result.put(String.valueOf(cv.Id), e);
            }
        }

        return result;
    }
}
