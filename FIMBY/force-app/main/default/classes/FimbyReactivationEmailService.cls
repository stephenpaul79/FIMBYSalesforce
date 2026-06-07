/**
 * @description Sends the transactional emails for the in-app delete-with-grace
 * flow:
 *   1. Delete-with-grace confirmation - sent immediately on tap. Contains a
 *      magic link valid for the full 30-day grace window so the neighbour can
 *      restore the account without re-entering their email.
 *   2. Reactivation magic link - sent when a neighbour visits /account-paused
 *      and asks for a fresh restore link. Shorter TTL (default 24h).
 *   3. Welcome back - sent after a successful token consume so the neighbour
 *      knows the account is restored.
 *
 * Why bodies are inline (matches FimbyDeletionEmailService convention):
 *   Keeping the protocol-bearing bodies in code keeps them auditable and
 *   prevents admins from editing a template in a way that breaks the
 *   reactivation link or omits the grace-window date. Copy changes go through
 *   a normal Apex deploy.
 *
 * Email shell:
 *   All three emails ride on FimbyEmailHtmlBuilder.wrapInBrandedShell so they
 *   match the look of digest / notification / contact-share emails. Delete and
 *   restore-link emails use minimalChrome=true (no notifications icon, no
 *   "Open FIMBY" / "Email preferences" footer links) because the recipient
 *   cannot log in. The welcome-back email uses the full chrome since the user
 *   is back in good standing. A plain-text body is set alongside the HTML for
 *   clients that don't render HTML.
 *
 * The delete confirmation and welcome-back emails target the User via
 * setTargetObjectId while the User is active/restored. The on-demand
 * restore-link email targets the linked Contact because the User is already
 * inactive, and Salesforce can reject inactive users as targetObjectId
 * recipients. The same FIMBY org-wide email address as FimbyDeletionEmailService
 * is used (DisplayName = 'FIMBY').
 */
public without sharing class FimbyReactivationEmailService {

    private static final String OWEA_DISPLAY_NAME = 'FIMBY';
    private static final String ACCENT_PAUSED = '#A8844E';   // amber / driftwood ochre — "scheduled"
    private static final String ACCENT_RESTORE = '#357280';  // fimby teal — "fresh link"
    private static final String ACCENT_WELCOME = '#5B8760';  // sage green — "back in"

    @TestVisible
    private static Integer testEmailsSent = 0;
    @TestVisible
    private static List<Messaging.SingleEmailMessage> testCapturedEmails =
        new List<Messaging.SingleEmailMessage>();

    private static final String GRACE_CONFIRMATION_SUBJECT =
        'Your account is scheduled for deletion';
    private static final String REACTIVATION_LINK_SUBJECT =
        'Restore your FIMBY account';
    private static final String WELCOME_BACK_SUBJECT =
        'Welcome back';

    /**
     * @description Sends the delete-with-grace confirmation immediately after
     * the neighbour taps Delete (with grace, the default). The body includes
     * the restore magic link, valid for the full grace window, plus the exact
     * scheduled-deletion date so they know when the safety net expires.
     * @param contactId Contact whose grace is starting (for token minting + log scope)
     * @param userId Target User for unlimited email delivery
     */
    public static void sendDeleteWithGraceConfirmation(Id contactId, Id userId) {
        if (contactId == null || userId == null) return;

        Integer windowDays = FimbySettings.defaultGraceWindowDays();
        DateTime expiresAt = System.now().addDays(windowDays);

        String token = FimbyReactivationTokenService.issueGraceWindowToken(
            contactId, expiresAt);
        String restoreUrl = buildRestoreUrl(token);
        String pausedUrl = buildPausedFallbackUrl();
        String deleteDocUrl = FimbyPublicWebsiteLinks.getUrl('Delete_Account_Docs');
        String scheduledDate = formatDate(expiresAt);

        String cardBody =
            '<p style="margin:0 0 10px;' + FimbyEmailHtmlBuilder.F + 'font-size:14px;color:#4A4A4A;">'
            + 'Your FIMBY account has been deactivated. Your login is already revoked, '
            + 'so nobody can see your posts or reach you while you decide.</p>'
            + '<p style="margin:0 0 10px;' + FimbyEmailHtmlBuilder.F + 'font-size:14px;color:#4A4A4A;">'
            + 'We hold onto your data for ' + windowDays + ' days in case you change your mind. '
            + 'After that date your posts, library items, messages, and personal data are '
            + 'permanently removed.</p>'
            + '<p style="margin:0 0 14px;' + FimbyEmailHtmlBuilder.F + 'font-size:14px;color:#2D2D2D;">'
            + '<strong>Scheduled deletion:</strong> ' + scheduledDate + '</p>'
            + FimbyEmailHtmlBuilder.buildCenteredCtaButton('Restore my account', restoreUrl)
            + '<p style="margin:14px 0 0;' + FimbyEmailHtmlBuilder.F + 'font-size:13px;color:#6B6B6B;">'
            + 'If you lose this email, you can ask for a fresh restore link at '
            + '<a href="' + pausedUrl + '" style="color:#3A7D8C;">' + displayHost(pausedUrl) + '</a>.</p>'
            + '<p style="margin:6px 0 0;' + FimbyEmailHtmlBuilder.F + 'font-size:13px;color:#6B6B6B;">'
            + 'For more on what happens when you delete your account, see '
            + '<a href="' + deleteDocUrl + '" style="color:#3A7D8C;">' + displayHost(deleteDocUrl) + '</a>.</p>';

        String firstName = lookupUserFirstName(userId);
        String card = FimbyEmailHtmlBuilder.buildTransactionalCard(
            'SCHEDULED', ACCENT_PAUSED, 'deactivation.png',
            'Your account is scheduled for deletion on ' + scheduledDate,
            cardBody,
            firstName, null, null, null, null);

        String html = FimbyEmailHtmlBuilder.wrapInBrandedShell(
            card, GRACE_CONFIRMATION_SUBJECT, null, null, true, true);

        String plain =
            FimbyEmailHtmlBuilder.buildRecipientGreetingPlain(firstName) +
            'Your FIMBY account has been deactivated. Your login is already revoked, ' +
            'so nobody can see your posts or reach you while you decide.\n\n' +
            'We hold onto your data for ' + windowDays + ' days in case you change your mind. ' +
            'After that date your posts, library items, messages, and personal data are ' +
            'permanently removed.\n\n' +
            '    Scheduled deletion: ' + scheduledDate + '\n\n' +
            'Changed your mind? Click here to restore your account anytime in the ' +
            'next ' + windowDays + ' days:\n\n' +
            '    ' + restoreUrl + '\n\n' +
            'If you lose this email, you can ask for a fresh restore link at ' +
            pausedUrl + '.\n\n' +
            'For more on what happens when you delete your account, see ' +
            deleteDocUrl + '.\n\n' +
            'With care,\n' +
            'FIMBY';

        send(userId, GRACE_CONFIRMATION_SUBJECT, plain, html);
    }

    /**
     * @description Sends a freshly-minted reactivation magic link to the
     * neighbour, in response to a request via /account-paused. TTL is the
     * shorter Reactivation_Token_TTL_Hours (default 24h), not the full grace
     * window - the assumption is they're actively trying to restore right now.
     * @param userId Target User for unlimited email delivery
     * @param token Token string already minted by FimbyReactivationTokenService
     */
    public static void sendReactivationLink(Id userId, String token) {
        if (userId == null || String.isBlank(token)) return;

        List<User> recipients = [
            SELECT ContactId, Contact.FirstName FROM User WHERE Id = :userId LIMIT 1
        ];
        if (recipients.isEmpty() || recipients[0].ContactId == null) {
            return;
        }

        String firstName = recipients[0].Contact?.FirstName;
        Integer ttlHours = FimbySettings.reactivationTokenTtlHours();
        String restoreUrl = buildRestoreUrl(token);

        String cardBody =
            '<p style="margin:0 0 10px;' + FimbyEmailHtmlBuilder.F + 'font-size:14px;color:#4A4A4A;">'
            + 'Someone (hopefully you) asked for a fresh link to restore your FIMBY account.</p>'
            + FimbyEmailHtmlBuilder.buildCenteredCtaButton('Restore my account', restoreUrl)
            + '<p style="margin:14px 0 0;' + FimbyEmailHtmlBuilder.F + 'font-size:13px;color:#6B6B6B;">'
            + 'This link is good for the next ' + ttlHours + ' hours.</p>'
            + '<p style="margin:6px 0 0;' + FimbyEmailHtmlBuilder.F + 'font-size:13px;color:#6B6B6B;">'
            + 'If you didn\u2019t request this, you can ignore this email and nothing will change. '
            + 'Your account stays scheduled for deletion until the end of your grace window.</p>';

        String card = FimbyEmailHtmlBuilder.buildTransactionalCard(
            'RESTORE LINK', ACCENT_RESTORE, 'key.png',
            'A fresh link to restore your account',
            cardBody,
            firstName, null, null, null, null);

        String html = FimbyEmailHtmlBuilder.wrapInBrandedShell(
            card, REACTIVATION_LINK_SUBJECT, null, null, true, true);

        String plain =
            FimbyEmailHtmlBuilder.buildRecipientGreetingPlain(firstName) +
            'Someone (hopefully you) asked for a fresh link to restore your FIMBY ' +
            'account. Click here to restore:\n\n' +
            '    ' + restoreUrl + '\n\n' +
            'This link is good for the next ' + ttlHours + ' hours.\n\n' +
            'If you didn\'t request this, you can ignore this email and nothing will ' +
            'change. Your account stays scheduled for deletion until the end of your ' +
            'grace window.\n\n' +
            'With care,\n' +
            'FIMBY';

        sendToContact(recipients[0].ContactId, REACTIVATION_LINK_SUBJECT, plain, html);
    }

    /**
     * @description Sends a welcome-back acknowledgement after a successful
     * token consume. Confirms the account is restored and the scheduled
     * deletion has been cancelled. Uses the full chrome (notifications icon,
     * email-preferences footer link) since the recipient can log in again.
     */
    public static void sendWelcomeBack(Id userId) {
        if (userId == null) return;

        String loginUrl = buildLoginUrl();

        String cardBody =
            '<p style="margin:0 0 10px;' + FimbyEmailHtmlBuilder.F + 'font-size:14px;color:#4A4A4A;">'
            + 'Welcome back! Your FIMBY account is restored.</p>'
            + '<p style="margin:0 0 14px;' + FimbyEmailHtmlBuilder.F + 'font-size:14px;color:#4A4A4A;">'
            + 'Your posts, library items, messages, and profile are all back where you '
            + 'left them. The scheduled deletion has been cancelled.</p>'
            + FimbyEmailHtmlBuilder.buildCenteredCtaButton('Log in', loginUrl);

        String firstName = lookupUserFirstName(userId);
        String card = FimbyEmailHtmlBuilder.buildTransactionalCard(
            'RESTORED', ACCENT_WELCOME, 'NeighborhoodActive.png',
            'You\u2019re back in your neighbourhood',
            cardBody,
            firstName, null, null, null, null);

        String html = FimbyEmailHtmlBuilder.wrapInBrandedShell(
            card, WELCOME_BACK_SUBJECT, null, null, true, false);

        String plain =
            FimbyEmailHtmlBuilder.buildRecipientGreetingPlain(firstName) +
            'Welcome back! Your FIMBY account is restored.\n\n' +
            'Your posts, library items, messages, and profile are all back where you ' +
            'left them. The scheduled deletion has been cancelled.\n\n' +
            'Log in anytime at ' + loginUrl + '.\n\n' +
            'With care,\n' +
            'FIMBY';

        send(userId, WELCOME_BACK_SUBJECT, plain, html);
    }

    /**
     * @description Builds the absolute restore URL. Uses the FIMBY_URL__mdt
     * pattern if a 'Reactivate' developer name exists; otherwise falls back to
     * the hardcoded production host. Either way the token is appended as a
     * query parameter so the landing page LWC can read it from URL.
     */
    private static String buildRestoreUrl(String token) {
        String base = FimbySettings.getUrl('Reactivate');
        if (String.isBlank(base)) {
            base = buildBaseUrl() + '/reactivate';
        }
        String separator = base.contains('?') ? '&' : '?';
        return base + separator + 'token=' + EncodingUtil.urlEncode(token, 'UTF-8');
    }

    private static String buildPausedFallbackUrl() {
        String base = FimbySettings.getUrl('Account_Paused');
        return String.isNotBlank(base) ? base : buildBaseUrl() + '/account-paused';
    }

    private static String buildLoginUrl() {
        String base = FimbySettings.getUrl('Login');
        return String.isNotBlank(base) ? base : buildBaseUrl() + '/login';
    }

    private static String buildBaseUrl() {
        String base = FimbySettings.getUrl('Site_Base');
        if (String.isBlank(base)) { return 'https://our.fimby.com'; }
        return base.endsWith('/') ? base.substring(0, base.length() - 1) : base;
    }

    private static String displayHost(String fullUrl) {
        if (String.isBlank(fullUrl)) { return ''; }
        String stripped = fullUrl.replaceFirst('^https?://', '');
        if (stripped.endsWith('/')) {
            stripped = stripped.substring(0, stripped.length() - 1);
        }
        return stripped;
    }

    private static String formatDate(DateTime dt) {
        return dt.format('MMMM d, yyyy', 'America/Vancouver');
    }

    private static String lookupUserFirstName(Id userId) {
        if (userId == null) {
            return null;
        }
        List<User> users = [SELECT FirstName FROM User WHERE Id = :userId LIMIT 1];
        return users.isEmpty() ? null : users[0].FirstName;
    }

    /**
     * @description Internal sender that targets a User record (unlimited email
     * path). Sets both HTML and plain-text bodies so legacy / text-only clients
     * still get a usable message. No setWhatId because this flow has no Case
     * to thread back into.
     */
    private static void send(Id userId, String subject, String plainBody, String htmlBody) {
        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(userId);
            email.setTreatTargetObjectAsRecipient(true);
            email.setSaveAsActivity(false);
            email.setSubject(subject);
            email.setPlainTextBody(plainBody);
            if (String.isNotBlank(htmlBody)) {
                email.setHtmlBody(htmlBody);
            }

            Id oweaId = getOweaId();
            if (oweaId != null) {
                email.setOrgWideEmailAddressId(oweaId);
            }

            if (Test.isRunningTest()) {
                testCapturedEmails.add(email);
                testEmailsSent++;
                return;
            }
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception e) {
            FimbyLogger.error('FimbyReactivationEmailService', 'send', e, userId);
        }
    }

    /**
     * @description Sends to the linked Contact. Used only for restore-link
     * requests after login has been revoked, where setTargetObjectId can fail
     * for inactive community users.
     */
    private static void sendToContact(Id contactId, String subject, String plainBody, String htmlBody) {
        try {
            if (contactId == null) {
                return;
            }

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(contactId);
            email.setTreatTargetObjectAsRecipient(true);
            email.setSaveAsActivity(false);
            email.setSubject(subject);
            email.setPlainTextBody(plainBody);
            if (String.isNotBlank(htmlBody)) {
                email.setHtmlBody(htmlBody);
            }

            Id oweaId = getOweaId();
            if (oweaId != null) {
                email.setOrgWideEmailAddressId(oweaId);
            }

            if (Test.isRunningTest()) {
                testCapturedEmails.add(email);
                testEmailsSent++;
                return;
            }
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception e) {
            FimbyLogger.error('FimbyReactivationEmailService', 'sendToContact', e, contactId);
        }
    }

    @TestVisible
    private static Id oweaCached;
    private static Id getOweaId() {
        if (oweaCached == null) {
            List<OrgWideEmailAddress> oweas = [
                SELECT Id FROM OrgWideEmailAddress
                WHERE DisplayName = :OWEA_DISPLAY_NAME LIMIT 1
            ];
            oweaCached = oweas.isEmpty() ? null : oweas[0].Id;
        }
        return oweaCached;
    }
}
