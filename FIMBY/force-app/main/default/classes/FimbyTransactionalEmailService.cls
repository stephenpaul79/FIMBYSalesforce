/**
 * @description Shared sender for one-off branded emails (contact share, thank-you, future types).
 * Wraps card HTML in the Apex branded shell via FimbyEmailHtmlBuilder.
 */
public without sharing class FimbyTransactionalEmailService {

    @TestVisible
    private static Integer testSendInvocationCount = 0;
    @TestVisible
    private static String testLastSubject;
    @TestVisible
    private static String testLastIntroText;
    @TestVisible
    private static String testLastHeaderTitle;
    @TestVisible
    private static String testLastCardHtml;

    public class TransactionalEmailRequest {
        public Id recipientUserId;
        public String subject;
        /** In-email H1; falls back to subject when blank. */
        public String headerTitle;
        public String neighbourhoodName;
        public String introText;
        public String cardHtml;
        public String replyToEmail;
        public String ctaUrl;
        public String ctaLabel;
        public String ctaIcon;
        public Boolean skipSubjectBlock = false;
    }

    public static void send(TransactionalEmailRequest request) {
        if (request == null || request.recipientUserId == null) {
            return;
        }

        if (Test.isRunningTest()) {
            testSendInvocationCount++;
            testLastSubject = request.subject;
            testLastHeaderTitle = request.headerTitle;
            testLastIntroText = request.introText;
            testLastCardHtml = request.cardHtml;
        }

        Id oweaId = getOweaId();

        try {
            Boolean skip = request.skipSubjectBlock == true;
            String innerHtml = String.isNotBlank(request.cardHtml) ? request.cardHtml : '';

            String html = FimbyEmailHtmlBuilder.wrapInBrandedShell(
                innerHtml,
                request.subject,
                request.neighbourhoodName,
                null,
                skip,
                false,
                null,
                false,
                request.headerTitle
            );

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(request.recipientUserId);
            email.setTreatTargetObjectAsRecipient(true);
            email.setSubject(request.subject);
            email.setHtmlBody(html);
            email.setSaveAsActivity(false);
            if (oweaId != null) {
                email.setOrgWideEmailAddressId(oweaId);
            }
            if (String.isNotBlank(request.replyToEmail)) {
                email.setReplyTo(request.replyToEmail);
            }

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception e) {
            FimbyLogger.error('FimbyTransactionalEmailService', 'send', e);
        }
    }

    @TestVisible
    public static String lookupRecipientFirstName(Id userId) {
        if (userId == null) {
            return null;
        }
        List<User> users = [SELECT FirstName FROM User WHERE Id = :userId LIMIT 1];
        return users.isEmpty() ? null : users[0].FirstName;
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
}
