/**
 * @description Sends paper-form lifecycle emails for Support_Relationship__c.
 * Touches three events:
 *   1. Day-0 email to the supporter — printable PDF + deep link to resume
 *      the upload step.
 *   2. Reminder emails on day 14 / 30 / 60 if the supporter has not yet
 *      uploaded the signed scan. Driven by FimbySupportRelationshipReminderBatch.
 *   3. Approval / rejection notifications to the supporter once an admin
 *      finishes verification (driven by FimbySupportRelationshipTrigger).
 *
 * The PDF is rendered from FimbyAuthorizedSupporterForm.page (Visualforce)
 * and attached to the email so the supporter can print and sign offline.
 *
 * The PDF render and email send are skipped during tests to keep deploys
 * fast; Day0_Email_Sent_Date__c / Last_Reminder_Sent_Date__c are still
 * stamped so the lifecycle logic can be exercised by tests.
 */
public without sharing class FimbySupportRelationshipEmailService {

    private static final String MANAGE_IDENTITIES_FALLBACK = 'https://our.fimby.com/manage-identities';
    private static final String SUPPORT_ACCENT = '#476B4C';

    /**
     * @description Day-0 send: triggered by createPaperDraft. Attaches the
     * Authorized Supporter Form PDF and deep-links the supporter back to
     * the upload step. Stamps Day0_Email_Sent_Date__c.
     */
    public static void sendDay0Email(Id srId) {
        if (srId == null) return;
        Support_Relationship__c rel = loadRelationship(srId);
        if (rel == null || rel.Contact__c == null) return;

        Id supporterUserId = lookupUserId(rel.Contact__c);
        String subject = 'Next steps for your FIMBY support relationship';
        String intro = 'Thanks for stepping up to support someone in your neighbourhood. ' +
            'Attached is the printable paper form your supportee will sign. Once you have it ' +
            'signed, return to FIMBY using the link below to upload a photo or scan.';
        String bodyHtml = buildFormInstructionsBody(rel, false);
        String ctaUrl = buildDeepLink(srId);

        sendEmailWithPdf(supporterUserId, subject, intro, bodyHtml, ctaUrl,
                         'Open in FIMBY', srId, rel.Name);

        rel.Day0_Email_Sent_Date__c = Datetime.now();
        update rel;
    }

    /**
     * @description Reminder send: triggered by the daily batch. dayCount is
     * the days-since-Day-0 bucket (14 / 30 / 60). Stamps Last_Reminder_Sent_Date__c.
     */
    public static void sendReminderEmail(Id srId, Integer dayCount) {
        if (srId == null) return;
        Support_Relationship__c rel = loadRelationship(srId);
        if (rel == null || rel.Contact__c == null) return;

        Id supporterUserId = lookupUserId(rel.Contact__c);
        String subject;
        String intro;
        if (dayCount != null && dayCount >= 60) {
            subject = 'Final reminder: your FIMBY support relationship form';
            intro = 'This is the last reminder for the support relationship paper form. If we do not ' +
                'receive the signed form soon, the request will be archived. You can re-start any time.';
        } else if (dayCount != null && dayCount >= 30) {
            subject = 'Still need a hand with your FIMBY support relationship form?';
            intro = 'Just a friendly nudge. Whenever you have the signed form ready, the upload link ' +
                'below will pick up right where you left off.';
        } else {
            subject = 'Reminder: your FIMBY support relationship form is waiting';
            intro = 'Your printable form is attached again in case you need another copy. The upload ' +
                'link below opens the same draft you already started.';
        }

        String bodyHtml = buildFormInstructionsBody(rel, true);
        String ctaUrl = buildDeepLink(srId);

        sendEmailWithPdf(supporterUserId, subject, intro, bodyHtml, ctaUrl,
                         'Open in FIMBY', srId, rel.Name);

        rel.Last_Reminder_Sent_Date__c = Datetime.now();
        update rel;
    }

    /**
     * @description Sent when an admin flips the SR to Approved. Lets the
     * supporter know identity-switching is now available and that an
     * activation letter has been mailed to the supportee.
     */
    public static void sendApprovalNotification(Id srId) {
        if (srId == null) return;
        Support_Relationship__c rel = loadRelationship(srId);
        if (rel == null || rel.Contact__c == null) return;

        Id supporterUserId = lookupUserId(rel.Contact__c);
        if (supporterUserId == null) return;

        String intro;
        if (rel.Relationship_Type__c == 'Community_Group_Rep') {
            String orgName = rel.Related_Organization__r != null
                    && String.isNotBlank(rel.Related_Organization__r.Name)
                ? rel.Related_Organization__r.Name
                : 'your organization';
            intro = 'Good news — the FIMBY team has verified your organization. You can now ' +
                'switch to ' + orgName + ' from Manage Identities and post, respond, and borrow on its ' +
                'behalf in your neighbourhood.';
        } else {
            String supporteeName = rel.Related_Contact__r != null && rel.Related_Contact__r.Name != null
                ? rel.Related_Contact__r.Name : 'your supportee';
            intro = 'Good news — the FIMBY team has verified your support relationship for ' +
                supporteeName + '. You can now switch identities from Manage Identities. We have also ' +
                'mailed a postal letter to the supportee so they know this relationship is active.';
        }

        String bodyHtml = '<p style="font-size:14px;color:#4A4A4A;margin:0;' + FimbyEmailHtmlBuilder.F + '">'
            + 'If anything looks off, please reply to this email or contact help@fimby.com.</p>';

        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = supporterUserId;
        req.cardHtml = buildSupportCard(
            FimbyTransactionalEmailService.lookupRecipientFirstName(supporterUserId),
            intro, null, bodyHtml, buildManageIdentitiesUrl(), 'Open Manage Identities');
        req.subject = rel.Relationship_Type__c == 'Community_Group_Rep'
            ? 'You\'re approved to represent ' + (rel.Related_Organization__r?.Name != null ? rel.Related_Organization__r.Name : 'your organization') + ' on FIMBY'
            : 'Your FIMBY support relationship is approved';

        FimbyTransactionalEmailService.send(req);
    }

    /**
     * @description Sent when an admin rejects the SR. Includes the rejection
     * reason and detail so the supporter understands next steps.
     */
    public static void sendRejectionNotification(Id srId) {
        if (srId == null) return;
        Support_Relationship__c rel = loadRelationship(srId);
        if (rel == null || rel.Contact__c == null) return;

        Id supporterUserId = lookupUserId(rel.Contact__c);
        if (supporterUserId == null) return;

        String reason = String.isNotBlank(rel.Rejection_Reason__c) ? rel.Rejection_Reason__c : 'Not specified';
        String detail = String.isNotBlank(rel.Rejection_Reason_Detail__c) ? rel.Rejection_Reason_Detail__c : '';

        String intro;
        if (rel.Relationship_Type__c == 'Community_Group_Rep') {
            intro = 'Thanks for applying to represent your organization on FIMBY. After review, ' +
                'we are not able to activate your representative access right now.';
        } else {
            intro = 'Thanks for taking the time to fill out the support relationship paper form. ' +
                'After review, we are not able to activate this relationship right now.';
        }

        String bodyHtml = '<p style="font-size:14px;color:#4A4A4A;margin:0 0 12px;' + FimbyEmailHtmlBuilder.F + '">'
            + '<strong>Reason:</strong> ' + reason.escapeHtml4() + '</p>';
        if (String.isNotBlank(detail)) {
            bodyHtml += '<p style="font-size:14px;color:#4A4A4A;margin:0 0 12px;' + FimbyEmailHtmlBuilder.F + '">'
                + detail.escapeHtml4().replace('\n', '<br/>') + '</p>';
        }
        bodyHtml += '<p style="font-size:14px;color:#4A4A4A;margin:0;' + FimbyEmailHtmlBuilder.F + '">'
            + 'If you would like to talk through this, reply to this email or contact help@fimby.com. '
            + 'We are happy to revisit if anything changes.</p>';

        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = supporterUserId;
        req.subject = rel.Relationship_Type__c == 'Community_Group_Rep'
            ? 'A note about your organization representative request'
            : 'A note about your FIMBY support relationship request';
        req.cardHtml = buildSupportCard(
            FimbyTransactionalEmailService.lookupRecipientFirstName(supporterUserId),
            intro, null, bodyHtml, null, null);

        FimbyTransactionalEmailService.send(req);
    }

    @TestVisible
    private static Support_Relationship__c loadRelationship(Id srId) {
        List<Support_Relationship__c> rels = [
            SELECT Id, Name, Status__c, Contact__c, Related_Contact__c,
                   Related_Contact__r.Name, Related_Contact__r.MailingCity,
                   Relationship_Type__c, Related_Organization__c,
                   Related_Organization__r.Name,
                   Day0_Email_Sent_Date__c, Last_Reminder_Sent_Date__c,
                   Rejection_Reason__c, Rejection_Reason_Detail__c
            FROM Support_Relationship__c
            WHERE Id = :srId
            LIMIT 1
        ];
        return rels.isEmpty() ? null : rels[0];
    }

    private static Id lookupUserId(Id contactId) {
        if (contactId == null) return null;
        List<User> users = [
            SELECT Id FROM User
            WHERE ContactId = :contactId AND IsActive = true
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].Id;
    }

    private static String buildFormInstructionsBody(Support_Relationship__c rel, Boolean isReminder) {
        String supporteeName = rel.Related_Contact__r != null && rel.Related_Contact__r.Name != null
            ? rel.Related_Contact__r.Name : 'your supportee';
        String header = isReminder ? 'Still ready when you are' : 'Your printable paper form is attached';
        String body = isReminder
            ? 'When you have the signed form, tap the link below to upload it.'
            : 'Print the attached PDF, walk it through with ' + supporteeName.escapeHtml4()
              + ', and once it is signed, come back to FIMBY to upload a photo.';

        return '<p style="margin:0 0 6px;' + FimbyEmailHtmlBuilder.F + 'font-size:16px;font-weight:600;color:#2D2D2D;">'
            + header.escapeHtml4() + '</p>'
            + '<p style="margin:0;' + FimbyEmailHtmlBuilder.F + 'font-size:14px;color:#4A4A4A;">' + body + '</p>';
    }

    @TestVisible
    private static String buildSupportCard(String firstName, String intro, String title, String bodyHtml,
            String ctaUrl, String ctaLabel) {
        String resolvedFirstName = firstName;
        return FimbyEmailHtmlBuilder.buildTransactionalCard(
            FimbyEmailHtmlBuilder.TXN_BADGE_SUPPORT,
            SUPPORT_ACCENT,
            'NeighborhoodActive.png',
            title,
            bodyHtml,
            resolvedFirstName,
            intro,
            ctaUrl,
            ctaLabel,
            'enter.png'
        );
    }

    @TestVisible
    private static String buildManageIdentitiesUrl() {
        String url = FimbySettings.getUrl('Manage_Identities');
        return String.isNotBlank(url) ? url : MANAGE_IDENTITIES_FALLBACK;
    }

    /** Resume link for paper-form upload flows (day-0 + reminders). */
    @TestVisible
    private static String buildDeepLink(Id srId) {
        String url = FimbySettings.getUrl('Manage_Identities', null, '?continueSr=' + srId);
        return String.isNotBlank(url) ? url : MANAGE_IDENTITIES_FALLBACK + '?continueSr=' + srId;
    }

    @TestVisible
    private static Blob renderPdf(Id srId) {
        if (Test.isRunningTest()) {
            return Blob.valueOf('test-pdf-bytes');
        }
        try {
            PageReference pr = Page.FimbyAuthorizedSupporterForm;
            pr.getParameters().put('id', String.valueOf(srId));
            return pr.getContentAsPDF();
        } catch (Exception e) {
            FimbyLogger.error('FimbySupportRelationshipEmailService', 'renderPdf', e, srId);
            return null;
        }
    }

    private static void sendEmailWithPdf(Id supporterUserId, String subject, String intro, String bodyHtml,
                                         String ctaUrl, String ctaLabel, Id srId, String relName) {
        if (supporterUserId == null) return;

        String firstName = FimbyTransactionalEmailService.lookupRecipientFirstName(supporterUserId);

        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = supporterUserId;
        req.subject = subject;
        req.cardHtml = buildSupportCard(firstName, intro, null, bodyHtml, ctaUrl, ctaLabel);
        FimbyTransactionalEmailService.send(req);

        Blob pdf = renderPdf(srId);
        if (pdf == null) return;

        try {
            Messaging.EmailFileAttachment attach = new Messaging.EmailFileAttachment();
            String fileName = 'FIMBY_Authorized_Supporter_Form_' +
                (String.isNotBlank(relName) ? relName : String.valueOf(srId)) + '.pdf';
            attach.setFileName(fileName);
            attach.setBody(pdf);
            attach.setContentType('application/pdf');

            String attachGreeting = FimbyEmailHtmlBuilder.buildRecipientGreetingPlain(firstName);

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(supporterUserId);
            email.setTreatTargetObjectAsRecipient(true);
            email.setSubject('[Form attached] ' + subject);
            email.setPlainTextBody(attachGreeting +
                'Attached: the printable Authorized Supporter Form for support ' +
                'relationship ' + relName + '. Open the previous email for the full instructions.');
            email.setSaveAsActivity(false);
            email.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attach });
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception e) {
            FimbyLogger.error('FimbySupportRelationshipEmailService', 'sendEmailWithPdf.attach', e, srId);
        }
    }
}
