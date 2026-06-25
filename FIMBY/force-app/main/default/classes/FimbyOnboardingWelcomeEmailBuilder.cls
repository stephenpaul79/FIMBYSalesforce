/**
 * @description Builds the inner HTML for the one-time post-onboarding welcome email.
 * Educational cards explain digest, notifications, and Settings; optional mini-digest
 * HTML is appended when neighbourhood content exists in the preview window.
 */
public without sharing class FimbyOnboardingWelcomeEmailBuilder {

    public static final String HEADER_TITLE = 'A few things to help you settle in';

    public static String buildSubject(String firstName) {
        String name = String.isNotBlank(firstName) ? firstName : 'there';
        return 'Welcome to FIMBY, ' + name;
    }

    public static String buildFullBodyHtml(
        String firstName,
        String neighbourhoodName,
        FimbyDigestEmailBuilder.DigestResult miniDigest
    ) {
        String settingsUrl = resolveSettingsUrl();
        Boolean hasPreview = miniDigest != null && !miniDigest.isEmpty && String.isNotBlank(miniDigest.html);

        String html = buildIntroParagraph()
            + buildStayingInLoopCard(settingsUrl, hasPreview)
            + buildNotificationsCard(settingsUrl);

        if (hasPreview) {
            html += miniDigest.html;
        }
        return html;
    }

    @TestVisible
    private static String buildIntroParagraph() {
        return '<p style="margin:0 0 16px;' + FimbyEmailHtmlBuilder.F + 'font-size:15px;line-height:1.5;color:#4A4A4A;">'
            + 'You&rsquo;re onboarded and ready to go. Here&rsquo;s how to keep up with your neighbours on your terms.</p>';
    }

    @TestVisible
    private static String buildStayingInLoopCard(String settingsUrl, Boolean hasPreview) {
        String body = 'We send a daily roundup of what&rsquo;s happening on your street so you don&rsquo;t have to keep checking back. '
            + 'You can switch to weekly or turn it off anytime.';
        if (hasPreview) {
            body += ' There&rsquo;s a preview of this week&rsquo;s roundup at the bottom of this email.';
        }
        return buildInfoCard(
            'Staying in the loop',
            body,
            'Email digest settings',
            settingsUrl,
            'email.png'
        );
    }

    @TestVisible
    private static String buildNotificationsCard(String settingsUrl) {
        String title = 'A doorbell, not a slot machine';
        String body = 'FIMBY taps you on the shoulder when a neighbour needs you, then gets out of the way. '
            + 'Alerts are on by default, and from 10&nbsp;PM to 6&nbsp;AM we go quiet so the whole street can sleep. '
            + 'Whatever comes in overnight will be waiting in the morning. '
            + 'Keep different hours? No problem! Adjustments welcome.';

        String pandaCell = '<td width="25%" valign="top" style="width:25%;padding:0 14px 0 0;">'
            + '<table cellpadding="0" cellspacing="0" border="0" width="100%"><tr>'
            + '<td style="background-color:#000000;border-radius:10px;padding:6px;font-size:0;line-height:0;">'
            + '<img src="' + esc(resolvePandaUrl()) + '" width="100%" alt="A sleeping panda" '
            + 'style="display:block;width:100%;height:auto;border:0;border-radius:6px;" />'
            + '</td></tr></table></td>';
        String textCell = '<td valign="top" style="padding:0;">'
            + '<p style="margin:0;' + FimbyEmailHtmlBuilder.F + 'font-size:14px;line-height:1.5;color:#4A4A4A;">'
            + body + '</p></td>';

        return '<table cellpadding="0" cellspacing="0" border="0" width="600" '
            + 'style="max-width:600px;width:100%;margin-bottom:12px;border-radius:8px;overflow:hidden;'
            + 'border:1px solid #E8E0D6;background-color:#FFFFFF;">'
            + '<tr><td style="padding:16px 18px 10px;">'
            + '<p style="margin:0;' + FimbyEmailHtmlBuilder.F + 'font-size:16px;font-weight:700;color:#2D2D2D;">'
            + title + '</p></td></tr>'
            + '<tr><td style="padding:0 18px 10px;">'
            + '<table cellpadding="0" cellspacing="0" border="0" width="100%"><tr>'
            + pandaCell + textCell
            + '</tr></table></td></tr>'
            + '<tr><td style="padding:4px 18px 16px;">'
            + FimbyEmailHtmlBuilder.buildCenteredCtaButton('Notification settings', settingsUrl, 'BellActive.png')
            + '</td></tr></table>';
    }

    private static String resolvePandaUrl() {
        String host = stripTrailingSlash(FimbySettings.getUrl('Experience_Site'));
        if (String.isBlank(host)) {
            host = stripTrailingSlash(FimbySettings.getUrl('Site_Base'));
        }
        return host + '/sfsites/c/resource/Icons/panda-sleeping.png';
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
