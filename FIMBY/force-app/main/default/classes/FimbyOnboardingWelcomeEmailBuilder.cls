/**
 * @description Builds the inner HTML for the one-time post-onboarding welcome email.
 * Educational cards explain digest, notifications, and Settings; optional mini-digest
 * HTML is appended when neighbourhood content exists in the preview window.
 */
public without sharing class FimbyOnboardingWelcomeEmailBuilder {

    public static final String SUBJECT = 'Welcome to FIMBY — a few things to help you settle in';

    public static String buildFullBodyHtml(
        String firstName,
        String neighbourhoodName,
        FimbyDigestEmailBuilder.DigestResult miniDigest
    ) {
        String settingsUrl = resolveSettingsUrl();
        String homeUrl = resolveHomeUrl();
        String greeting = String.isNotBlank(firstName) ? esc(firstName) : 'there';

        String html = buildIntroParagraph(greeting, neighbourhoodName)
            + buildStayingInLoopCard(settingsUrl)
            + buildNotificationsCard(settingsUrl)
            + FimbyEmailHtmlBuilder.buildCenteredCtaButton('Open FIMBY', homeUrl, 'enter.png');

        if (miniDigest != null && !miniDigest.isEmpty && String.isNotBlank(miniDigest.html)) {
            html += miniDigest.html;
        }
        return html;
    }

    @TestVisible
    private static String buildIntroParagraph(String firstName, String neighbourhoodName) {
        String nhPhrase = String.isNotBlank(neighbourhoodName)
            ? ' on <strong>' + esc(neighbourhoodName) + '</strong>'
            : '';
        return '<p style="margin:0 0 16px;' + FimbyEmailHtmlBuilder.F + 'font-size:15px;line-height:1.5;color:#4A4A4A;">'
            + 'Hi ' + firstName + ', welcome in' + nhPhrase + '. '
            + 'Here are a few things that help neighbours stay connected without living in the app.</p>';
    }

    @TestVisible
    private static String buildStayingInLoopCard(String settingsUrl) {
        return buildInfoCard(
            'Staying in the loop',
            'We send a daily roundup of what&rsquo;s happening on your street so you don&rsquo;t have to keep checking back. '
                + 'You can switch to weekly or turn it off anytime.',
            'Neighbourhood digest settings',
            settingsUrl,
            'email.png'
        );
    }

    @TestVisible
    private static String buildNotificationsCard(String settingsUrl) {
        return buildInfoCard(
            'Notifications &amp; quiet hours',
            'Push and email alerts are on by default for messages, asks &amp; offers, library, and more. '
                + 'Quiet hours are set to 10&nbsp;PM &ndash; 6&nbsp;AM so your street can rest overnight.',
            'Notification settings',
            settingsUrl,
            'BellActive.png'
        );
    }

    private static String buildInfoCard(
        String title, String body, String ctaLabel, String ctaUrl, String iconFile
    ) {
        return '<table cellpadding="0" cellspacing="0" border="0" width="600" '
            + 'style="max-width:600px;width:100%;margin-bottom:12px;border-radius:8px;overflow:hidden;'
            + 'border:1px solid #E8E0D6;background-color:#FFFFFF;">'
            + '<tr><td style="padding:16px 18px 8px;">'
            + '<p style="margin:0 0 8px;' + FimbyEmailHtmlBuilder.F + 'font-size:16px;font-weight:700;color:#2D2D2D;">'
            + title + '</p>'
            + '<p style="margin:0;' + FimbyEmailHtmlBuilder.F + 'font-size:14px;line-height:1.5;color:#4A4A4A;">'
            + body + '</p>'
            + '</td></tr>'
            + '<tr><td style="padding:4px 18px 16px;">'
            + FimbyEmailHtmlBuilder.buildCenteredCtaButton(ctaLabel, ctaUrl, iconFile)
            + '</td></tr></table>';
    }

    private static String resolveSettingsUrl() {
        String url = FimbySettings.getUrl('Settings');
        return String.isNotBlank(url) ? url : stripTrailingSlash(FimbySettings.getUrl('Site_Base')) + '/settings';
    }

    private static String resolveHomeUrl() {
        String url = FimbySettings.getUrl('Site_Base');
        return String.isNotBlank(url) ? url : '/';
    }

    private static String stripTrailingSlash(String url) {
        if (String.isBlank(url)) {
            return '';
        }
        return url.endsWith('/') ? url.substring(0, url.length() - 1) : url;
    }

    private static String esc(String input) {
        return String.isBlank(input) ? '' : input.escapeHtml4();
    }
}
