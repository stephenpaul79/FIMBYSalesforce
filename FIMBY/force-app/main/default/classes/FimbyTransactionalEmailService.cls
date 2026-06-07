/**
 * @description Shared sender for one-off branded emails (contact share, thank-you, future types).
 * Uses the FIMBY_Transactional_Email Lightning Email Template + token replacement pattern.
 * Any controller can fire a branded one-off email with one call.
 */
public without sharing class FimbyTransactionalEmailService {

    private static final String DYNAMIC_PLACEHOLDER = '<!-- FIMBY_DYNAMIC_CONTENT -->';

    @TestVisible
    private static String testRenderedHtml;
    @TestVisible
    private static Integer testSendInvocationCount = 0;
    @TestVisible
    private static String testLastSubject;
    @TestVisible
    private static String testLastIntroText;
    @TestVisible
    private static String testLastCardHtml;
    private static final String INTRO_PLACEHOLDER = '<!-- FIMBY_INTRO_TEXT -->';
    private static final String INTENT_PLACEHOLDER = '<!-- FIMBY_INTENT_LINE -->';

    public class TransactionalEmailRequest {
        public Id recipientUserId;
        public String subject;
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
            testLastIntroText = request.introText;
            testLastCardHtml = request.cardHtml;
        }

        Id templateId = getTransactionalTemplateId();
        Id oweaId = getOweaId();

        if (templateId == null) {
            FimbyLogger.warn('FimbyTransactionalEmailService', 'send', 'Transactional template not found. Falling back to direct HTML.');
            sendDirectHtml(request, oweaId);
            return;
        }

        try {
            String html;
            if (Test.isRunningTest() && testRenderedHtml != null) {
                html = testRenderedHtml;
            } else {
                Messaging.SingleEmailMessage rendered =
                    Messaging.renderStoredEmailTemplate(templateId, request.recipientUserId, null);
                html = rendered.getHtmlBody();
            }

            String cardContent = request.cardHtml != null ? request.cardHtml : '';

            Map<String, String> replacements = new Map<String, String>{
                DYNAMIC_PLACEHOLDER => cardContent,
                INTRO_PLACEHOLDER => '',
                INTENT_PLACEHOLDER => ''
            };
            html = FimbyEmailHtmlBuilder.injectContent(html, replacements);

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

    private static void sendDirectHtml(TransactionalEmailRequest request, Id oweaId) {
        try {
            Boolean skip = request.skipSubjectBlock == true;
            String innerHtml = String.isNotBlank(request.cardHtml) ? request.cardHtml : '';

            String html = FimbyEmailHtmlBuilder.wrapInBrandedShell(innerHtml, request.subject, null, null, skip);

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
            FimbyLogger.error('FimbyTransactionalEmailService', 'sendDirectHtml', e);
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
    private static Id transactionalTemplateId;
    private static Id getTransactionalTemplateId() {
        if (transactionalTemplateId == null) {
            FIMBY_Email_Template__mdt mapping = FIMBY_Email_Template__mdt.getInstance('Transactional');
            if (mapping != null && mapping.Is_Active__c == true) {
                List<EmailTemplate> tmpl = [
                    SELECT Id FROM EmailTemplate
                    WHERE DeveloperName = :mapping.Template_DeveloperName__c
                    LIMIT 1
                ];
                transactionalTemplateId = tmpl.isEmpty() ? null : tmpl[0].Id;
            }
        }
        return transactionalTemplateId;
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
