/**
 * @description Shared HTML builder for all FIMBY email types. Generates email-safe HTML
 * using inline CSS derived from FIMBY design tokens. All dynamic content (notification cards,
 * digest sections, transactional cards) is built here and wrapped in the branded shell.
 */
public without sharing class FimbyEmailHtmlBuilder {

    @TestVisible
    static final Integer MAX_HTML_SIZE = 80000;
    private static final Integer MAX_ALERT_CARDS = 10;
    private static final Integer MAX_DIGEST_CARDS_PER_SECTION = 5;
    private static final Integer DESCRIPTION_SNIPPET_LENGTH = 120;

    // Centralized token-derived email-safe theme map
    private static final String BG_PAGE       = '#F0EBE3';
    private static final String BG_SURFACE    = '#FAF7F2';
    private static final String BG_CARD       = '#FFFFFF';
    private static final String TEXT_HEADING   = '#2D2D2D';
    private static final String TEXT_BODY      = '#4A4A4A';
    private static final String TEXT_SECONDARY = '#6B6B6B';
    private static final String CTA_BG        = '#3A7D8C';
    private static final String CTA_TEXT       = '#FFFFFF';
    private static final String BORDER_LIGHT   = '#E8E0D6';
    private static final String FIMBY_TEAL     = '#357280';
    private static final String EARTH_SAGE     = '#476B4C';
    private static final String EARTH_TEAL     = '#357280';
    private static final String EARTH_DRIFTWOOD = '#6B5E50';
    private static final String EARTH_OCHRE    = '#7D6234';
    private static final String EARTH_TERRACOTTA = '#8A5936';
    private static final String FONT_STACK = 'Verdana, Geneva, sans-serif';
    public static final String F = 'font-family:Verdana, Geneva, sans-serif;';
    private static final String FIMBY_BASE_URL = stripTrailingSlash(FimbySettings.getUrl('Site_Base'));
    private static final String MARKETING_SITE_URL = resolveMarketingUrl();
    private static final String EXPERIENCE_ASSET_HOST = resolveExperienceAssetHost();
    @TestVisible
    static final String ICON_BASE_URL = EXPERIENCE_ASSET_HOST + '/sfsites/c/resource/Impact_Icons/';
    private static final String LOGO_ICON_URL = ICON_BASE_URL + 'FIMBYwGrass.png';
    private static final String ICON_BELL_URL = ICON_BASE_URL + 'BellActive.png';
    private static final String ICON_ENTER_URL = ICON_BASE_URL + 'enter.png';

    private static String stripTrailingSlash(String url) {
        if (String.isBlank(url)) { return ''; }
        return url.endsWith('/') ? url.substring(0, url.length() - 1) : url;
    }

    private static String resolveMarketingUrl() {
        String url = FimbyPublicWebsiteLinks.getUrl('Marketing_Home');
        return String.isBlank(url) ? 'https://fimby.com' : stripTrailingSlash(url);
    }

    /**
     * Experience Cloud serves static resources; app-link hosts (e.g. app.fimby.com) do not.
     * Email hyperlinks use Site_Base; icon img src must stay on the Experience site host.
     */
    private static String resolveExperienceAssetHost() {
        String host = stripTrailingSlash(FimbySettings.getUrl('Experience_Site'));
        return String.isNotBlank(host) ? host : FIMBY_BASE_URL;
    }

    @TestVisible
    static final Map<String, String> BADGE_COLORS = new Map<String, String>{
        'Need' => '#5B8760', 'Offer' => '#5B8760',
        'Gathering' => '#448E9E', 'Open_Event' => '#448E9E',
        'Community_Event' => '#715A9E',
        'Bulk_Buy' => '#A8844E',
        'God Story' => '#A38045', 'Thank You' => '#B07248',
        'Prayer' => '#7E7495', 'Lament' => '#5E7B92',
        'Bio' => '#6B7D54', 'Neighbourhood Moment' => '#AF827D',
        'Story' => '#A38045',
        'Library' => '#8D7B6A'
    };

    private static final Map<String, String> BADGE_ICONS = new Map<String, String>{
        'Need' => 'BulletinBoardActive.png', 'Offer' => 'BulletinBoardActive.png',
        'Gathering' => 'dining-table.png', 'Open_Event' => 'people.png',
        'Community_Event' => 'cityscape.png',
        'Bulk_Buy' => 'bulkbuy.png',
        'God Story' => 'GodStoryActive.png', 'Thank You' => 'ThankYouActive.png',
        'Prayer' => 'PrayActive.png', 'Lament' => 'LamentActive.png',
        'Bio' => 'BioActive.png', 'Neighbourhood Moment' => 'tulips.png',
        'Story' => 'StoriesActive.png',
        'Library' => 'ToolboxActive.png'
    };

    private static final Map<String, String> CTA_ICONS = new Map<String, String>{
        'Need' => 'reply.png', 'Offer' => 'reply.png',
        'Gathering' => 'dining-table.png', 'Open_Event' => 'people.png',
        'Community_Event' => 'cityscape.png',
        'Bulk_Buy' => 'buy.png',
        'Story' => 'comment.png',
        'Library' => 'borrow.png'
    };

    // Alert email card maps — keyed by Notification__c.Type__c
    @TestVisible
    static final Map<String, String> ALERT_BADGE_LABELS = new Map<String, String>{
        'Response' => 'RESPONSE', 'Comment' => 'COMMENT', 'Message' => 'MESSAGE',
        'Event_Chat' => 'EVENT CHAT', 'Event_Reminder' => 'EVENT',
        'Lending_Request' => 'LIBRARY', 'Loan_Approved' => 'LIBRARY',
        'Extension_Request' => 'LIBRARY', 'Extension_Approved' => 'LIBRARY',
        'Extension_Declined' => 'LIBRARY', 'Overdue_Reminder' => 'LIBRARY',
        'Item_Returned' => 'LIBRARY',
        'Bulk_Buy_Reservation' => 'BULK BUY', 'Bulk_Buy_Status' => 'BULK BUY',
        'Bulk_Buy_Pickup' => 'BULK BUY',
        'Not_Responding_Flag' => 'FOLLOW-UP', 'Not_Responding_Response' => 'FOLLOW-UP',
        'Not_Responding_Escalated' => 'FOLLOW-UP', 'Follow_Up_Resolved' => 'FOLLOW-UP'
    };

    private static final Map<String, String> ALERT_BADGE_ICONS = new Map<String, String>{
        'Response' => 'reply.png', 'Comment' => 'comment.png', 'Message' => 'reply.png',
        'Event_Chat' => 'reply.png', 'Event_Reminder' => 'dining-table.png',
        'Lending_Request' => 'ToolboxActive.png', 'Loan_Approved' => 'ToolboxActive.png',
        'Extension_Request' => 'ToolboxActive.png', 'Extension_Approved' => 'ToolboxActive.png',
        'Extension_Declined' => 'ToolboxActive.png', 'Overdue_Reminder' => 'ToolboxActive.png',
        'Item_Returned' => 'ToolboxActive.png',
        'Bulk_Buy_Reservation' => 'bulkbuy.png', 'Bulk_Buy_Status' => 'bulkbuy.png',
        'Bulk_Buy_Pickup' => 'bulkbuy.png',
        'Not_Responding_Flag' => 'BulletinBoardActive.png', 'Not_Responding_Response' => 'BulletinBoardActive.png',
        'Not_Responding_Escalated' => 'BulletinBoardActive.png', 'Follow_Up_Resolved' => 'BulletinBoardActive.png'
    };

    private static final Map<String, String> ALERT_CTA_ICONS = new Map<String, String>{
        'Response' => 'reply.png', 'Comment' => 'comment.png', 'Message' => 'reply.png',
        'Event_Chat' => 'reply.png', 'Event_Reminder' => 'dining-table.png',
        'Lending_Request' => 'borrow.png', 'Loan_Approved' => 'borrow.png',
        'Extension_Request' => 'borrow.png', 'Extension_Approved' => 'borrow.png',
        'Extension_Declined' => 'borrow.png', 'Overdue_Reminder' => 'borrow.png',
        'Item_Returned' => 'borrow.png',
        'Bulk_Buy_Reservation' => 'buy.png', 'Bulk_Buy_Status' => 'buy.png',
        'Bulk_Buy_Pickup' => 'buy.png',
        'Not_Responding_Flag' => 'enter.png', 'Not_Responding_Response' => 'enter.png',
        'Not_Responding_Escalated' => 'enter.png', 'Follow_Up_Resolved' => 'enter.png'
    };

    private static final Map<String, String> ALERT_CTA_LABELS = new Map<String, String>{
        'Response' => 'View Response', 'Comment' => 'View Comment', 'Message' => 'View Message',
        'Event_Chat' => 'View Message', 'Event_Reminder' => 'View Event',
        'Lending_Request' => 'View Item', 'Loan_Approved' => 'View Item',
        'Extension_Request' => 'View Item', 'Extension_Approved' => 'View Item',
        'Extension_Declined' => 'View Item', 'Overdue_Reminder' => 'View Item',
        'Item_Returned' => 'View Item',
        'Bulk_Buy_Reservation' => 'View Bulk Buy', 'Bulk_Buy_Status' => 'View Bulk Buy',
        'Bulk_Buy_Pickup' => 'View Bulk Buy',
        'Not_Responding_Flag' => 'View in FIMBY', 'Not_Responding_Response' => 'View in FIMBY',
        'Not_Responding_Escalated' => 'View in FIMBY', 'Follow_Up_Resolved' => 'View in FIMBY'
    };

    private static List<FIMBY_Loading_Message__mdt> intentLines;

    /* ---------------------------------------------------------------
     * Intent Line (P8)
     * --------------------------------------------------------------- */

    public static String getRandomIntentLine() {
        if (intentLines == null) {
            intentLines = [
                SELECT Message__c FROM FIMBY_Loading_Message__mdt
                WHERE Active__c = true AND Context__c = 'Email_Intent'
            ];
        }
        if (intentLines.isEmpty()) {
            return 'You asked us to keep you in the loop. Good call.';
        }
        Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), intentLines.size());
        return intentLines[idx].Message__c;
    }

    /* ---------------------------------------------------------------
     * Branded Shell — standalone email wrapper when no Lightning
     * Email Template is available (or as the standard fallback).
     * --------------------------------------------------------------- */

    public static String wrapInBrandedShell(String innerHtml, String subject, String neighbourhoodName) {
        return wrapInBrandedShell(innerHtml, subject, neighbourhoodName, null, false, false);
    }

    public static String wrapInBrandedShell(String innerHtml, String subject, String neighbourhoodName, String intentLine) {
        return wrapInBrandedShell(innerHtml, subject, neighbourhoodName, intentLine, false, false);
    }

    public static String wrapInBrandedShell(String innerHtml, String subject, String neighbourhoodName, String intentLine, Boolean skipSubjectBlock) {
        return wrapInBrandedShell(innerHtml, subject, neighbourhoodName, intentLine, skipSubjectBlock, false);
    }

    /**
     * @description Branded HTML shell. When `minimalChrome` is true the header
     * loses the bell + door action icons and the footer loses the
     * "Email preferences" / "Open FIMBY" links — used for emails sent to
     * accounts that cannot log in (e.g. delete-with-grace, reactivation link).
     * The logo, neighbourhood subject block, seasonal line, and "Family In My
     * Backyard" sign-off are kept so the email still feels like FIMBY.
     */
    public static String wrapInBrandedShell(String innerHtml, String subject, String neighbourhoodName, String intentLine, Boolean skipSubjectBlock, Boolean minimalChrome) {
        return wrapInBrandedShell(innerHtml, subject, neighbourhoodName, intentLine, skipSubjectBlock, minimalChrome, null);
    }

    public static String wrapInBrandedShell(String innerHtml, String subject, String neighbourhoodName, String intentLine, Boolean skipSubjectBlock, Boolean minimalChrome, String recipientFirstName) {
        String nhDisplay = String.isNotBlank(neighbourhoodName) ? escapeHtml(neighbourhoodName) : 'your neighbourhood';
        String safeSubject = String.isNotBlank(subject) ? escapeHtml(subject) : 'Update from FIMBY';
        Boolean minimal = minimalChrome == true;
        // skipSubjectBlock + minimalChrome: drop the whole intro block (transactional).
        // skipSubjectBlock alone: neighbourhood tag only — card carries the headline.
        Boolean fullSkipSubjectArea = skipSubjectBlock == true && minimal == true;
        Boolean neighbourhoodOnlyHeader = skipSubjectBlock == true && minimal != true;
        Boolean hasSubjectAreaBelowHeader = !fullSkipSubjectArea;
        String intentHtml = '';
        if (String.isNotBlank(intentLine)) {
            intentHtml = '<p style="margin:8px 0 0;' + F + 'font-size:14px;font-style:italic;color:' + TEXT_SECONDARY + ';">'
                + escapeHtml(intentLine) + '</p>';
        }
        String greetingHtml = String.isNotBlank(recipientFirstName)
            ? buildHeaderGreetingLine(recipientFirstName) : '';

        String seasonalLine = getSeasonalLine();
        String seasonalHtml = '';
        if (String.isNotBlank(seasonalLine)) {
            seasonalHtml = '<tr><td style="padding:12px 24px 0;text-align:center;">'
                + '<p style="' + F + 'color:' + TEXT_SECONDARY + ';font-size:14px;font-style:italic;margin:0;">'
                + escapeHtml(seasonalLine) + '</p></td></tr>';
        }

        String headerRightHtml = minimal
            ? ''
            : '<td align="right" style="vertical-align:middle;">'
                + '<table cellpadding="0" cellspacing="0" border="0"><tr>'
                + '<td style="padding-right:16px;">'
                + '<a href="' + FIMBY_BASE_URL + '/notifications" style="text-decoration:none;">'
                + '<img src="' + ICON_BELL_URL + '" width="24" height="24" alt="Notifications" style="border:0;vertical-align:middle;" /></a></td>'
                + '<td>'
                + '<a href="' + FIMBY_BASE_URL + '" style="text-decoration:none;">'
                + '<img src="' + ICON_ENTER_URL + '" width="24" height="24" alt="Open FIMBY" style="border:0;vertical-align:middle;" /></a></td>'
                + '</tr></table></td>';

        String brandLinkHtml =
            '<a href="' + MARKETING_SITE_URL + '" style="' + F + 'color:' + CTA_BG + ';text-decoration:none;">Family In My Backyard</a>';
        String footerRightHtml = minimal
            ? '<td align="right" style="' + F + 'font-size:13px;color:' + TEXT_SECONDARY + ';">&nbsp;</td>'
            : '<td align="right" style="' + F + 'font-size:13px;color:' + TEXT_SECONDARY + ';">'
                + '<a href="' + FIMBY_BASE_URL + '/settings" style="' + F + 'color:' + CTA_BG + ';text-decoration:none;">Email preferences</a>'
                + ' &middot; '
                + '<a href="' + FIMBY_BASE_URL + '" style="' + F + 'color:' + CTA_BG + ';text-decoration:none;">Open FIMBY</a>'
                + '</td>';

        return '<!DOCTYPE html>'
            + '<html lang="en" xmlns="http://www.w3.org/1999/xhtml">'
            + '<head><meta charset="UTF-8"/>'
            + '<meta name="viewport" content="width=device-width,initial-scale=1.0"/>'
            + '<title>' + safeSubject + '</title>'
            + '</head>'
            + '<body style="margin:0;padding:0;background-color:' + BG_PAGE + ';font-family:' + FONT_STACK + ';">'
            + '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="background-color:' + BG_PAGE + ';">'
            + '<tr><td align="center" style="padding:24px 12px;">'

            // Inner container — 600px max, no background (BG_PAGE shows through between sections)
            + '<table cellpadding="0" cellspacing="0" border="0" width="600" style="max-width:600px;width:100%;">'

            // Header bar — light surface with logo left, optional action icons right
            + '<tr><td style="background-color:' + BG_SURFACE + ';padding:14px 24px;border-radius:' + (hasSubjectAreaBelowHeader ? '8px 8px 0 0' : '8px') + ';border-bottom:' + (hasSubjectAreaBelowHeader ? '1px solid ' + BORDER_LIGHT : '0') + ';">'
            + '<table cellpadding="0" cellspacing="0" border="0" width="100%"><tr>'
            + '<td style="vertical-align:middle;">'
            + '<a href="' + FIMBY_BASE_URL + '" style="text-decoration:none;border:0;">'
            + '<img src="' + LOGO_ICON_URL + '" height="40" alt="FIMBY" style="border:0;display:block;" /></a></td>'
            + headerRightHtml
            + '</tr></table>'
            + '</td></tr>'

            + (fullSkipSubjectArea
                ? ''
                : neighbourhoodOnlyHeader
                    ? buildNeighbourhoodOnlyBlockHtml(nhDisplay)
                    : '<tr><td style="background-color:' + BG_SURFACE + ';padding:20px 24px 16px;border-radius:0 0 8px 8px;">'
                      + '<p style="margin:0 0 2px;' + F + 'font-size:13px;color:' + TEXT_SECONDARY + ';">' + nhDisplay + '</p>'
                      + greetingHtml
                      + '<p style="margin:0;' + F + 'font-size:20px;font-weight:600;color:' + TEXT_HEADING + ';">' + safeSubject + '</p>'
                      + intentHtml
                      + '</td></tr>')

            // Content area — no background, BG_PAGE shows between section groups
            + '<tr><td style="padding:16px 24px 20px;">'
            + (String.isNotBlank(innerHtml) ? innerHtml : '')
            + '</td></tr>'

            // Seasonal line
            + seasonalHtml

            // Footer (BG_SURFACE) — brand link left, optional secondary links right
            + '<tr><td style="background-color:' + BG_SURFACE + ';padding:16px 24px;border-radius:8px;border-top:1px solid ' + BORDER_LIGHT + ';">'
            + '<table cellpadding="0" cellspacing="0" border="0" width="100%"><tr>'
            + '<td style="' + F + 'font-size:13px;color:' + TEXT_SECONDARY + ';">' + brandLinkHtml + '</td>'
            + footerRightHtml
            + '</tr></table>'
            + '</td></tr>'

            + '</table>'  // End inner container
            + '</td></tr></table>'  // End outer
            + '</body></html>';
    }

    /**
     * @description Compact neighbourhood tag for single-alert emails. The inbox
     * subject and card title carry the story; this block anchors locale only.
     */
    @TestVisible
    static String buildNeighbourhoodOnlyBlockHtml(String nhDisplay) {
        return '<tr><td style="background-color:' + BG_SURFACE + ';padding:12px 24px 12px;border-radius:0 0 8px 8px;">'
            + '<p style="margin:0;' + F + 'font-size:13px;color:' + TEXT_SECONDARY + ';">' + nhDisplay + '</p>'
            + '</td></tr>';
    }

    @TestVisible
    static String getSeasonalLine() {
        try {
            Date today = Date.today();
            Integer todayMonth = today.month();
            Integer todayDay = today.day();
            for (FIMBY_Seasonal_Theme__mdt theme : [
                SELECT Title__c, Month__c, Day__c, Duration_Days__c
                FROM FIMBY_Seasonal_Theme__mdt
                WHERE Active__c = true
            ]) {
                Integer startMonth = (Integer) theme.Month__c;
                Integer startDay = (Integer) theme.Day__c;
                Integer duration = theme.Duration_Days__c != null ? (Integer) theme.Duration_Days__c : 1;
                Date startDate = Date.newInstance(today.year(), startMonth, startDay);
                if (today >= startDate && today <= startDate.addDays(duration - 1)) {
                    return theme.Title__c;
                }
            }
        } catch (Exception e) {
            // Seasonal greeting is non-critical
        }
        return null;
    }

    /* ---------------------------------------------------------------
     * Alert Cards
     * --------------------------------------------------------------- */

    public static String buildAlertCards(List<Notification__c> notifications) {
        return buildAlertCards(notifications, null, null);
    }

    public static String buildAlertCards(List<Notification__c> notifications, Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> enrichmentMap) {
        return buildAlertCards(notifications, enrichmentMap, null);
    }

    public static String buildAlertCards(List<Notification__c> notifications, Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> enrichmentMap, String recipientFirstName) {
        if (notifications == null || notifications.isEmpty()) {
            return '';
        }

        Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> safeMap =
            enrichmentMap != null ? enrichmentMap : new Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment>();
        Integer cardCount = Math.min(notifications.size(), MAX_ALERT_CARDS);
        String html = '';

        for (Integer i = 0; i < cardCount; i++) {
            Notification__c n = notifications[i];
            FimbyEmailAlertQueueable.AlertCardEnrichment enrich = String.isNotBlank(n.Related_Record_Id__c)
                ? safeMap.get(n.Related_Record_Id__c) : null;
            Boolean includeGreeting = (i == 0);
            html += buildNotificationCard(n, enrich, includeGreeting ? recipientFirstName : null);
        }

        if (notifications.size() > MAX_ALERT_CARDS) {
            Integer remaining = notifications.size() - MAX_ALERT_CARDS;
            html += '<p style="' + F + 'color:' + TEXT_SECONDARY + ';font-size:14px;text-align:center;padding:8px 0;">'
                + 'You have ' + remaining + ' more updates &mdash; '
                + '<a href="' + FIMBY_BASE_URL + '/notifications" style="' + F + 'color:' + CTA_BG + ';">check them in FIMBY</a>.'
                + '</p>';
        }

        return truncateIfNeeded(html);
    }

    private static String buildNotificationCard(Notification__c n, FimbyEmailAlertQueueable.AlertCardEnrichment enrich) {
        return buildNotificationCard(n, enrich, null);
    }

    private static String buildNotificationCard(Notification__c n, FimbyEmailAlertQueueable.AlertCardEnrichment enrich, String recipientFirstName) {
        String accentColor = getAccentColorForType(n.Type__c);
        String ctaUrl = buildCtaUrl(n);
        String notifType = n.Type__c != null ? n.Type__c : '';

        // Badge pill
        String badgeLabel = ALERT_BADGE_LABELS.containsKey(notifType) ? ALERT_BADGE_LABELS.get(notifType) : 'UPDATE';
        String badgeIcon = ALERT_BADGE_ICONS.containsKey(notifType) ? ALERT_BADGE_ICONS.get(notifType) : null;
        String badgeHtml = buildBadgePill(badgeLabel, accentColor, badgeIcon);

        // Avatar — prefer real image from enrichment, fall back to initials from Actor_Name__c.
        // For FIMBY system messages we omit the visible first-name pill since the badge/icon
        // already conveys system origin (avoids "FIMBY ... FIMBY ..." duplication).
        Boolean isSystemActor = String.isNotBlank(n.Actor_Name__c) && n.Actor_Name__c.equalsIgnoreCase('FIMBY');
        String avatarImageUrl = enrich != null ? enrich.actorImageUrl : null;
        String avatarFirstName = enrich != null && String.isNotBlank(enrich.actorFirstName)
            ? enrich.actorFirstName : extractFirstName(n.Actor_Name__c);
        String avatarHtml = buildAvatar(avatarImageUrl, avatarFirstName, accentColor);
        String avatarPillName = isSystemActor ? '' : (avatarFirstName != null ? avatarFirstName : '');

        // Actor sub-line under the title is redundant when Title__c already names the actor
        // (e.g. "Maya wants to borrow your item" + actor "Maya Smith") or when this is a
        // FIMBY system message. Notification-patterns rule: never name the actor twice.
        Boolean showActorSubLine = String.isNotBlank(n.Actor_Name__c)
            && !isSystemActor
            && !titleContainsActor(n.Title__c, n.Actor_Name__c, avatarFirstName);

        Boolean showBodyLine = String.isNotBlank(n.Body__c)
            && !isBodyRedundantWithTitle(n.Title__c, n.Body__c);

        // Item thumbnail (60x60 rounded)
        String thumbHtml = '';
        if (enrich != null && String.isNotBlank(enrich.itemImageUrl)) {
            String thumbUrl = completeImageUrl(enrich.itemImageUrl);
            if (String.isNotBlank(thumbUrl)) {
                thumbHtml = '<td width="72" style="vertical-align:top;padding-left:12px;">'
                    + '<img src="' + thumbUrl + '" width="60" height="60" alt="" '
                    + 'style="border-radius:8px;border:0;display:block;object-fit:cover;" />'
                    + '</td>';
            }
        }

        // CTA
        String ctaLabel = ALERT_CTA_LABELS.containsKey(notifType) ? ALERT_CTA_LABELS.get(notifType) : 'View in FIMBY';
        String ctaIcon = ALERT_CTA_ICONS.containsKey(notifType) ? ALERT_CTA_ICONS.get(notifType) : 'enter.png';

        // Build card
        String html = '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:12px;">'
            + '<tr><td style="background:' + BG_CARD + ';border-left:3px solid ' + accentColor
            + ';border-radius:8px;padding:14px 16px;border:1px solid ' + BORDER_LIGHT + ';border-left:3px solid ' + accentColor + ';">';

        // Badge + avatar row
        html += '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:8px;"><tr>'
            + '<td style="vertical-align:middle;">' + badgeHtml + '</td>'
            + '<td align="right" style="vertical-align:middle;">' + avatarHtml
            + '<span style="' + F + 'font-size:13px;color:' + TEXT_SECONDARY + ';vertical-align:middle;">'
            + escapeHtml(avatarPillName) + '</span></td>'
            + '</tr></table>';

        if (recipientFirstName != null) {
            html += buildInCardGreetingLine(recipientFirstName);
        }

        // Content area with optional thumbnail
        html += '<table cellpadding="0" cellspacing="0" border="0" width="100%"><tr>'
            + '<td style="vertical-align:top;">'
            + '<p style="margin:0 0 4px;' + F + 'font-size:16px;font-weight:600;color:' + TEXT_HEADING + ';">'
            + escapeHtml(n.Title__c) + '</p>'
            + (showActorSubLine ? '<p style="margin:0 0 4px;' + F + 'font-size:14px;color:' + TEXT_SECONDARY + ';">'
                + escapeHtml(n.Actor_Name__c) + '</p>' : '')
            + (showBodyLine ? '<p style="margin:0;' + F + 'font-size:15px;color:' + TEXT_BODY + ';">'
                + escapeHtml(truncateText(n.Body__c, DESCRIPTION_SNIPPET_LENGTH)) + '</p>' : '')
            + '</td>'
            + thumbHtml
            + '</tr></table>';

        // CTA button
        if (String.isNotBlank(ctaUrl)) {
            html += buildCtaButton(ctaLabel, ctaUrl, ctaIcon);
        }

        html += '</td></tr></table>';
        return html;
    }

    private static String extractFirstName(String fullName) {
        if (String.isBlank(fullName)) { return null; }
        Integer spaceIdx = fullName.indexOf(' ');
        return spaceIdx > 0 ? fullName.substring(0, spaceIdx) : fullName;
    }

    @TestVisible
    private static Boolean isBodyRedundantWithTitle(String title, String body) {
        if (String.isBlank(title) || String.isBlank(body)) {
            return false;
        }
        String normalizedTitle = normalizeForComparison(title);
        String normalizedBody = normalizeForComparison(body);
        if (normalizedTitle == normalizedBody) {
            return true;
        }
        if (normalizedTitle.contains(normalizedBody) || normalizedBody.contains(normalizedTitle)) {
            return true;
        }
        return false;
    }

    @TestVisible
    private static String normalizeForComparison(String text) {
        if (String.isBlank(text)) {
            return '';
        }
        return text.replaceAll('[^a-zA-Z0-9]', '').toLowerCase();
    }

    @TestVisible
    private static Boolean titleContainsActor(String title, String actorName, String actorFirstName) {
        if (String.isBlank(title)) { return false; }
        String lowerTitle = title.toLowerCase();
        if (String.isNotBlank(actorName) && lowerTitle.contains(actorName.toLowerCase())) {
            return true;
        }
        if (String.isNotBlank(actorFirstName) && lowerTitle.contains(actorFirstName.toLowerCase())) {
            return true;
        }
        return false;
    }

    /* ---------------------------------------------------------------
     * Recipient Greeting
     * --------------------------------------------------------------- */

    public static String resolveGreetingText(String firstName) {
        return 'Hi ' + (String.isNotBlank(firstName) ? escapeHtml(firstName) : 'neighbour') + ',';
    }

    public static String buildRecipientGreetingPlain(String firstName) {
        return resolveGreetingText(firstName) + '\n\n';
    }

    public static String buildInCardGreetingLine(String firstName) {
        return '<p style="margin:0 0 10px;' + F + 'font-size:14px;color:' + TEXT_BODY + ';line-height:1.55;">'
            + resolveGreetingText(firstName) + '</p>';
    }

    /**
     * @description Greeting line for digest header block (no card wrapper).
     */
    public static String buildHeaderGreetingLine(String firstName) {
        return '<p style="margin:0 0 6px;' + F + 'font-size:15px;color:' + TEXT_HEADING + ';line-height:1.4;">'
            + resolveGreetingText(firstName) + '</p>';
    }

    public static String buildInCardIntroParagraph(String introText) {
        if (String.isBlank(introText)) {
            return '';
        }
        return '<p style="margin:0 0 14px;' + F + 'font-size:14px;color:' + TEXT_BODY + ';line-height:1.55;">'
            + escapeHtml(introText) + '</p>';
    }

    /**
     * @description Compact white card with greeting only — prepended to digest content.
     */
    public static String buildGreetingCard(String firstName) {
        return '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:12px;">'
            + '<tr><td style="background:' + BG_CARD + ';border-radius:8px;padding:14px 16px;border:1px solid ' + BORDER_LIGHT
            + ';border-left:3px solid ' + CTA_BG + ';">'
            + buildInCardGreetingLine(firstName)
            + '</td></tr></table>';
    }

    /* ---------------------------------------------------------------
     * Transactional badge tokens (category pills)
     * --------------------------------------------------------------- */

    public static final String TXN_BADGE_SUPPORT = 'SUPPORT';
    public static final String TXN_BADGE_VOUCH = 'VOUCH';
    public static final String TXN_BADGE_CONTACT = 'CONTACT';
    public static final String TXN_BADGE_THANK_YOU = 'THANK YOU';

    /* ---------------------------------------------------------------
     * Transactional Cards
     * --------------------------------------------------------------- */

    /**
     * @description Generic transactional card: white surface, accent
     * border-left, optional badge pill at top, title, and free-form body HTML.
     */
    public static String buildTransactionalCard(String badgeLabel, String accentColor, String badgeIcon, String title, String bodyHtml) {
        return buildTransactionalCard(badgeLabel, accentColor, badgeIcon, title, bodyHtml, null, null, null, null, null);
    }

    /**
     * @description Full transactional card with greeting, intro, and in-card CTA.
     * Render order: badge → greeting → intro → title → bodyHtml → CTA.
     */
    public static String buildTransactionalCard(String badgeLabel, String accentColor, String badgeIcon, String title, String bodyHtml,
            String recipientFirstName, String introText, String ctaUrl, String ctaLabel, String ctaIcon) {
        String accent = String.isNotBlank(accentColor) ? accentColor : CTA_BG;
        String html = '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:12px;">'
            + '<tr><td style="background:' + BG_CARD + ';border-radius:8px;padding:14px 16px;border:1px solid ' + BORDER_LIGHT
            + ';border-left:3px solid ' + accent + ';">';
        if (String.isNotBlank(badgeLabel)) {
            html += '<div style="margin-bottom:8px;">' + buildBadgePill(badgeLabel, accent, badgeIcon) + '</div>';
        }
        html += buildInCardGreetingLine(recipientFirstName);
        html += buildInCardIntroParagraph(introText);
        if (String.isNotBlank(title)) {
            html += '<p style="margin:0 0 6px;' + F + 'font-size:16px;font-weight:600;color:' + TEXT_HEADING + ';">'
                + escapeHtml(title) + '</p>';
        }
        if (String.isNotBlank(bodyHtml)) {
            html += bodyHtml;
        }
        if (String.isNotBlank(ctaUrl)) {
            html += buildCtaButton(
                String.isNotBlank(ctaLabel) ? ctaLabel : 'View in FIMBY',
                ctaUrl,
                ctaIcon
            );
        }
        html += '</td></tr></table>';
        return html;
    }

    public static String buildContactShareCard(
        String senderName, String email, String phone, String street,
        String additionalInfo, String contextLabel
    ) {
        return buildContactShareCard(null, senderName, email, phone, street, additionalInfo, contextLabel, null, null, null);
    }

    public static String buildContactShareCard(
        String recipientFirstName, String senderName, String email, String phone, String street,
        String additionalInfo, String contextLabel, String ctaUrl, String ctaLabel, String ctaIcon
    ) {
        String html = '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:12px;">'
            + '<tr><td style="background:' + BG_CARD + ';border-left:3px solid ' + EARTH_TERRACOTTA
            + ';border-radius:8px;padding:14px 16px;border:1px solid ' + BORDER_LIGHT + ';border-left:3px solid ' + EARTH_TERRACOTTA + ';">'
            + '<div style="margin-bottom:8px;">' + buildBadgePill(TXN_BADGE_CONTACT, EARTH_TERRACOTTA, 'email.png') + '</div>'
            + buildInCardGreetingLine(recipientFirstName)
            + '<p style="margin:0 0 6px;' + F + 'font-size:15px;font-weight:600;color:' + TEXT_HEADING + ';">'
            + escapeHtml(senderName) + ' shared their contact info</p>';

        if (String.isNotBlank(contextLabel)) {
            html += '<p style="margin:0 0 10px;' + F + 'font-size:13px;color:' + TEXT_SECONDARY + ';">Regarding: '
                + escapeHtml(contextLabel) + '</p>';
        }

        if (String.isNotBlank(email)) {
            html += '<p style="margin:0 0 4px;' + F + 'font-size:14px;color:' + TEXT_BODY + ';">'
                + '<img src="' + ICON_BASE_URL + 'email.png" width="16" height="16" alt="" '
                + 'style="vertical-align:middle;margin-right:6px;border:0;" />' + escapeHtml(email) + '</p>';
        }
        if (String.isNotBlank(phone)) {
            html += '<p style="margin:0 0 4px;' + F + 'font-size:14px;color:' + TEXT_BODY + ';">'
                + '<img src="' + ICON_BASE_URL + 'telephone.png" width="16" height="16" alt="" '
                + 'style="vertical-align:middle;margin-right:6px;border:0;" />' + escapeHtml(phone) + '</p>';
        }
        if (String.isNotBlank(street)) {
            html += '<p style="margin:0 0 4px;' + F + 'font-size:14px;color:' + TEXT_BODY + ';">'
                + '<img src="' + ICON_BASE_URL + 'pin.png" width="16" height="16" alt="" '
                + 'style="vertical-align:middle;margin-right:6px;border:0;" />' + escapeHtml(street) + '</p>';
        }
        if (String.isNotBlank(additionalInfo)) {
            html += '<p style="margin:0 0 4px;' + F + 'font-size:13px;color:' + TEXT_SECONDARY + ';">' + escapeHtml(additionalInfo) + '</p>';
        }
        if (String.isNotBlank(ctaUrl)) {
            html += buildCtaButton(
                String.isNotBlank(ctaLabel) ? ctaLabel : 'View in FIMBY',
                ctaUrl,
                String.isNotBlank(ctaIcon) ? ctaIcon : 'enter.png'
            );
        }

        html += '</td></tr></table>';
        return html;
    }

    public static String buildThankYouCard(String senderName, String message, String postTitle) {
        return buildThankYouCard(null, senderName, message, postTitle, null, null, null);
    }

    public static String buildThankYouCard(String recipientFirstName, String senderName, String message, String postTitle,
            String ctaUrl, String ctaLabel, String ctaIcon) {
        String html = '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:12px;">'
            + '<tr><td style="background:' + BG_CARD + ';border-left:3px solid ' + EARTH_TERRACOTTA
            + ';border-radius:8px;padding:14px 16px;border:1px solid ' + BORDER_LIGHT + ';border-left:3px solid ' + EARTH_TERRACOTTA + ';">'
            + '<div style="margin-bottom:8px;">' + buildBadgePill(TXN_BADGE_THANK_YOU, EARTH_TERRACOTTA, 'ThankYouActive.png') + '</div>'
            + buildInCardGreetingLine(recipientFirstName)
            + '<p style="margin:0 0 6px;' + F + 'font-size:16px;font-weight:600;color:' + TEXT_HEADING + ';">'
            + 'Thank you from ' + escapeHtml(senderName) + '</p>';

        if (String.isNotBlank(postTitle)) {
            html += '<p style="margin:0 0 8px;' + F + 'font-size:14px;color:' + TEXT_SECONDARY + ';">For your response to: '
                + escapeHtml(postTitle) + '</p>';
        }

        if (String.isNotBlank(message)) {
            html += '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:10px;">'
                + '<tr><td style="border-left:2px solid ' + BORDER_LIGHT + ';padding:8px 12px;' + F + 'font-style:italic;'
                + 'font-size:14px;color:' + TEXT_BODY + ';">&ldquo;' + escapeHtml(message) + '&rdquo;</td></tr></table>';
        }
        if (String.isNotBlank(ctaUrl)) {
            html += buildCtaButton(
                String.isNotBlank(ctaLabel) ? ctaLabel : 'View Conversation',
                ctaUrl,
                String.isNotBlank(ctaIcon) ? ctaIcon : 'reply.png'
            );
        }

        html += '</td></tr></table>';
        return html;
    }

    /* ---------------------------------------------------------------
     * Digest Card Primitives
     * --------------------------------------------------------------- */

    public static String getBadgeColor(String postType) {
        return BADGE_COLORS.containsKey(postType) ? BADGE_COLORS.get(postType) : CTA_BG;
    }

    public static String getBadgeIcon(String postType) {
        return BADGE_ICONS.containsKey(postType) ? BADGE_ICONS.get(postType) : null;
    }

    public static String getCtaIcon(String postType) {
        return CTA_ICONS.containsKey(postType) ? CTA_ICONS.get(postType) : null;
    }

    public static String buildCardImage(String imageUrl, Integer height) {
        String url = completeImageUrl(imageUrl);
        if (String.isBlank(url)) { return ''; }
        Integer h = height != null ? height : 180;
        return '<tr><td style="padding:0;font-size:0;line-height:0;">'
            + '<img src="' + url + '" width="552" alt="" '
            + 'style="display:block;width:100%;height:' + h + 'px;object-fit:cover;" />'
            + '</td></tr>';
    }

    public static String buildBadgePill(String label, String bgColor, String iconFilename) {
        String bg = String.isNotBlank(bgColor) ? bgColor : CTA_BG;
        String html = '<span style="display:inline-block;background:' + bg
            + ';color:#FFFFFF;' + F + 'font-size:12px;font-weight:700;letter-spacing:0.5px;'
            + 'padding:4px 10px;border-radius:10px;line-height:1.2;vertical-align:middle;">';
        if (String.isNotBlank(iconFilename)) {
            html += '<img src="' + ICON_BASE_URL + iconFilename + '" width="14" height="14" alt="" '
                + 'style="vertical-align:middle;margin-right:4px;border:0;" />';
        }
        html += escapeHtml(label) + '</span>';
        return html;
    }

    public static String buildAvatar(String imageUrl, String firstName, String accentColor) {
        String color = String.isNotBlank(accentColor) ? accentColor : '#67BBD2';
        String initial = String.isNotBlank(firstName) ? escapeHtml(firstName.substring(0, 1).toUpperCase()) : '?';
        String url = completeImageUrl(imageUrl);
        if (String.isNotBlank(url)) {
            return '<img src="' + url + '" width="32" height="32" alt="" '
                + 'style="border-radius:50%;vertical-align:middle;margin-right:8px;border:0;" />';
        }
        return '<span style="display:inline-block;width:32px;height:32px;border-radius:50%;'
            + 'background:' + color + ';color:#FFFFFF;' + F + 'font-size:14px;font-weight:700;'
            + 'line-height:32px;text-align:center;vertical-align:middle;margin-right:8px;">'
            + initial + '</span>';
    }

    public static String buildThermometer(Decimal reserved, Decimal total, String unitLabel, Decimal costPerShare) {
        if (total == null || total <= 0) { return ''; }
        Decimal safeReserved = reserved != null ? reserved : 0;
        Integer pctReserved = (Integer) Math.min(100, (safeReserved / total) * 100);
        Integer pctAvailable = 100 - pctReserved;
        Integer avail = (Integer)(total - safeReserved);
        String unit = String.isNotBlank(unitLabel) ? unitLabel : 'shares';

        String html = '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:8px 0;">'
            + '<tr><td style="padding:0;">'
            + '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="border-radius:6px;overflow:hidden;">'
            + '<tr>';
        if (pctReserved > 0) {
            html += '<td width="' + pctReserved + '%" style="background:#4E6878;height:12px;font-size:0;">&nbsp;</td>';
        }
        if (pctAvailable > 0) {
            html += '<td width="' + pctAvailable + '%" style="background:#5B8760;height:12px;font-size:0;">&nbsp;</td>';
        }
        html += '</tr></table></td></tr>'
            + '<tr><td style="padding:4px 0 0;">'
            + '<table cellpadding="0" cellspacing="0" border="0" width="100%"><tr>'
            + '<td style="' + F + 'font-size:13px;color:' + TEXT_SECONDARY + ';">'
            + (Integer) safeReserved + ' reserved &middot; ' + avail + ' available</td>';
        if (costPerShare != null && costPerShare > 0) {
            String singularUnit = unit.length() > 1 && unit.endsWith('s') ? unit.substring(0, unit.length() - 1) : unit;
            html += '<td align="right" style="' + F + 'font-size:13px;font-weight:600;color:' + TEXT_HEADING + ';">'
                + '~$' + costPerShare.setScale(0) + '/' + escapeHtml(singularUnit) + '</td>';
        }
        html += '</tr></table></td></tr></table>';
        return html;
    }

    public static String buildDateLocationLine(Date startDate, String location) {
        if (startDate == null && String.isBlank(location)) { return ''; }
        String html = '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:4px 0 8px;">'
            + '<tr>';
        if (startDate != null) {
            Datetime dt = Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
            html += '<td style="' + F + 'font-size:14px;color:' + TEXT_SECONDARY + ';vertical-align:middle;padding-right:12px;">'
                + '&#128197; ' + dt.format('EEE, MMM d') + '</td>';
        }
        if (String.isNotBlank(location)) {
            html += '<td style="' + F + 'font-size:14px;color:' + TEXT_SECONDARY + ';vertical-align:middle;">'
                + '&#128205; ' + escapeHtml(location) + '</td>';
        }
        html += '</tr></table>';
        return html;
    }

    public static String buildCategoryPill(String category, String color) {
        if (String.isBlank(category)) { return ''; }
        String bg = String.isNotBlank(color) ? color : EARTH_DRIFTWOOD;
        return '<span style="display:inline-block;background:' + bg
            + ';color:#FFFFFF;' + F + 'font-size:12px;font-weight:600;padding:3px 8px;'
            + 'border-radius:8px;margin-left:8px;">' + escapeHtml(category) + '</span>';
    }

    /* ---------------------------------------------------------------
     * CTA Buttons
     * --------------------------------------------------------------- */

    public static String buildCtaButton(String label, String url) {
        return '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-top:8px;">'
            + '<tr><td align="right">'
            + '<table cellpadding="0" cellspacing="0" border="0">'
            + '<tr><td style="background:' + CTA_BG + ';border-radius:12px;padding:10px 20px;">'
            + '<a href="' + url + '" style="color:' + CTA_TEXT
            + ';text-decoration:none;font-size:15px;font-weight:600;font-family:' + FONT_STACK + ';">' + escapeHtml(label) + '</a>'
            + '</td></tr></table>'
            + '</td></tr></table>';
    }

    public static String buildCtaButton(String label, String url, String iconFilename) {
        String iconHtml = '';
        if (String.isNotBlank(iconFilename)) {
            iconHtml = '<img src="' + ICON_BASE_URL + iconFilename + '" width="20" height="20" alt="" '
                + 'style="vertical-align:middle;margin-right:6px;border:0;" />';
        }
        return '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-top:10px;">'
            + '<tr><td align="right">'
            + '<table cellpadding="0" cellspacing="0" border="0">'
            + '<tr><td style="background:' + CTA_BG + ';border-radius:12px;">'
            + '<a href="' + url + '" style="display:inline-block;padding:10px 20px;color:' + CTA_TEXT
            + ';font-size:15px;font-weight:600;font-family:' + FONT_STACK + ';text-decoration:none;">'
            + iconHtml + escapeHtml(label) + '</a>'
            + '</td></tr></table>'
            + '</td></tr></table>';
    }

    /**
     * @description Center-aligned CTA for transactional emails where the
     * button is the single primary action (e.g. account restore, magic-link
     * login). Notification / digest cards keep the right-aligned variant
     * because they typically stack multiple per-card actions.
     */
    public static String buildCenteredCtaButton(String label, String url) {
        return '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:14px 0;">'
            + '<tr><td align="center">'
            + '<table cellpadding="0" cellspacing="0" border="0">'
            + '<tr><td style="background:' + CTA_BG + ';border-radius:12px;padding:12px 28px;">'
            + '<a href="' + url + '" style="color:' + CTA_TEXT
            + ';text-decoration:none;font-size:15px;font-weight:600;font-family:' + FONT_STACK + ';">' + escapeHtml(label) + '</a>'
            + '</td></tr></table>'
            + '</td></tr></table>';
    }

    /* ---------------------------------------------------------------
     * Template Injection
     * --------------------------------------------------------------- */

    public static String injectContent(String templateHtml, Map<String, String> replacements) {
        if (String.isBlank(templateHtml)) {
            return templateHtml;
        }
        String result = templateHtml;
        for (String token : replacements.keySet()) {
            String value = replacements.get(token);
            if (value == null) {
                value = '';
            }
            result = result.replace(token, value);
        }
        return result;
    }

    public static Boolean hasRequiredPlaceholder(String html, String placeholder) {
        return String.isNotBlank(html) && html.contains(placeholder);
    }

    /* ---------------------------------------------------------------
     * Helpers
     * --------------------------------------------------------------- */

    private static String getAccentColorForType(String notifType) {
        if (notifType == FimbyConstants.NOTIF_MESSAGE) {
            return FIMBY_TEAL;
        }
        if (notifType == FimbyConstants.NOTIF_LENDING_REQUEST
            || notifType == FimbyConstants.NOTIF_LOAN_APPROVED
            || notifType == FimbyConstants.NOTIF_EXTENSION_REQUEST
            || notifType == FimbyConstants.NOTIF_EXTENSION_APPROVED
            || notifType == FimbyConstants.NOTIF_EXTENSION_DECLINED
            || notifType == FimbyConstants.NOTIF_ITEM_RETURNED
            || notifType == FimbyConstants.NOTIF_OVERDUE_REMINDER) {
            return EARTH_DRIFTWOOD;
        }
        if (notifType == FimbyConstants.NOTIF_COMMENT) {
            return EARTH_OCHRE;
        }
        if (notifType == FimbyConstants.NOTIF_BULK_BUY_RESERVATION
            || notifType == FimbyConstants.NOTIF_BULK_BUY_STATUS
            || notifType == FimbyConstants.NOTIF_BULK_BUY_PICKUP) {
            return EARTH_SAGE;
        }
        return FIMBY_TEAL;
    }

    private static String buildCtaUrl(Notification__c n) {
        if (String.isNotBlank(n.Action_URL__c)) {
            String raw = n.Action_URL__c;
            if (raw.startsWith('http://') || raw.startsWith('https://')) {
                return raw;
            }
            String path = raw.startsWith('/') ? raw : '/' + raw;
            return FIMBY_BASE_URL + path;
        }
        return FIMBY_BASE_URL + '/notifications';
    }

    @TestVisible
    static String completeImageUrl(String url) {
        if (String.isBlank(url)) { return url; }
        if (url.endsWith('&oid=')) {
            return url + UserInfo.getOrganizationId();
        }
        return url;
    }

    @TestVisible
    static String truncateText(String text, Integer maxLen) {
        if (String.isBlank(text) || text.length() <= maxLen) {
            return text;
        }
        return text.substring(0, maxLen) + '...';
    }

    @TestVisible
    static String escapeHtml(String input) {
        if (String.isBlank(input)) {
            return '';
        }
        return input.escapeHtml4();
    }

    private static String truncateIfNeeded(String html) {
        if (html != null && html.length() > MAX_HTML_SIZE) {
            return html.substring(0, MAX_HTML_SIZE)
                + '<p style="color:' + TEXT_SECONDARY + ';text-align:center;padding:8px;">'
                + '<a href="' + FIMBY_BASE_URL + '" style="color:' + CTA_BG + ';">See more in FIMBY</a></p>';
        }
        return html;
    }
}
