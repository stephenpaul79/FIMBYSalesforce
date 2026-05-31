/**
 * @description Builds the dynamic content portion of digest emails — card-style sections
 * for each content type. Output is injected into the rendered Lightning Email Template
 * via placeholder replacement.
 *
 * Structure (top to bottom):
 *   1. By the numbers (resolution + cross-FIMBY encouragement line)
 *   2. Feed cards (stories / asks / offers / events / bulk buys / library)
 *   3. Anchor card (single slot — OTD record when today matches, otherwise an
 *      evergreen reflection record cycled deterministically by dayOfYear)
 *
 * Send gate is feed-card-only: the resolution and anchor card never on their own
 * justify a send. When zero feed-card sections render the builder reports
 * isEmpty = true and the batch writes a Skipped log row instead of enqueuing
 * the queueable.
 */
public without sharing class FimbyDigestEmailBuilder {

    private static final Integer MAX_CARDS_PER_SECTION = 5;
    private static final Integer SNIPPET_LENGTH = 120;
    private static final String FIMBY_BASE_URL = stripTrailingSlash(FimbySettings.getUrl('Site_Base'));

    private static String stripTrailingSlash(String url) {
        if (String.isBlank(url)) { return ''; }
        return url.endsWith('/') ? url.substring(0, url.length() - 1) : url;
    }

    private static final String BG_CARD = '#FFFFFF';
    private static final String TEXT_HEADING = '#2D2D2D';
    private static final String TEXT_BODY = '#4A4A4A';
    private static final String TEXT_SECONDARY = '#6B6B6B';
    private static final String CTA_BG = '#3A7D8C';
    private static final String BORDER_LIGHT = '#E8E0D6';

    private static final String EARTH_SAGE = '#476B4C';
    private static final String EARTH_TEAL = '#357280';
    private static final String EARTH_DRIFTWOOD = '#6B5E50';
    private static final String EARTH_OCHRE = '#7D6234';

    /**
     * @description Builds all digest sections for a neighbourhood within the given time window.
     * @return DigestResult — html plus feed-card item count and isEmpty flag (true when there
     * are zero feed-card sections, which is the trigger for the batch to write a Skipped log row).
     */
    public static DigestResult buildDigestContent(
        Id neighbourhoodId, String neighbourhoodName,
        String frequency, Date windowStart, Date windowEnd
    ) {
        DigestResult result = new DigestResult();
        Datetime windowStartDt = Datetime.newInstance(windowStart, Time.newInstance(0, 0, 0, 0));
        Datetime windowEndDt = Datetime.newInstance(windowEnd, Time.newInstance(23, 59, 59, 0));

        String resolutionHtml = buildResolutionSection(neighbourhoodId, frequency, windowStartDt, windowEndDt);
        String storiesHtml = buildStoriesSection(neighbourhoodId, windowStartDt, windowEndDt);
        String asksOffersHtml = buildAsksOffersSection(neighbourhoodId, windowStartDt, windowEndDt);
        String eventsHtml = buildEventsSection(neighbourhoodId, windowStartDt, windowEndDt);
        String bulkBuysHtml = buildBulkBuysSection(neighbourhoodId, windowStartDt, windowEndDt);
        String libraryHtml = buildLibrarySection(neighbourhoodId, windowStartDt, windowEndDt);

        Integer feedCardCount = countItems(storiesHtml) + countItems(asksOffersHtml)
            + countItems(eventsHtml) + countItems(bulkBuysHtml) + countItems(libraryHtml);

        result.itemCount = feedCardCount;
        result.isEmpty = (feedCardCount == 0);

        if (result.isEmpty) {
            result.html = '';
            return result;
        }

        String anchorHtml = buildAnchorCard();

        result.html = resolutionHtml + storiesHtml + asksOffersHtml + eventsHtml
            + bulkBuysHtml + libraryHtml + anchorHtml;
        return result;
    }

    public class DigestResult {
        public String html = '';
        public Integer itemCount = 0;
        public Boolean isEmpty = true;
    }

    /* ---------------------------------------------------------------
     * By the numbers — local resolution + cross-FIMBY encouragement
     * --------------------------------------------------------------- */

    private static String buildResolutionSection(Id nhId, String frequency, Datetime startDt, Datetime endDt) {
        Integer fulfilledAsks = [
            SELECT COUNT() FROM Needs_Offers__c
            WHERE Neighbourhood__c = :nhId
              AND RecordType.DeveloperName = 'Need'
              AND Status__c = 'Completed (Offer Accepted / Need Met)'
              AND LastModifiedDate >= :startDt AND LastModifiedDate <= :endDt
        ];
        Integer completedLoans = [
            SELECT COUNT() FROM Loaned_Item__c
            WHERE Library_Item__r.Neighbourhood__c = :nhId
              AND Status__c = 'Returned'
              AND LastModifiedDate >= :startDt AND LastModifiedDate <= :endDt
        ];

        String crossFimbyLine = getCrossFimbyStat(frequency, startDt, endDt);

        Boolean hasLocal = (fulfilledAsks > 0 || completedLoans > 0);
        Boolean hasCross = String.isNotBlank(crossFimbyLine);
        if (!hasLocal && !hasCross) {
            return '';
        }

        String html = buildSectionHeader('Good things happening', EARTH_SAGE);
        if (fulfilledAsks > 0) {
            String label = fulfilledAsks + ' ask' + (fulfilledAsks > 1 ? 's were' : ' was') + ' fulfilled.';
            html += '<p style="margin:4px 0;font-size:14px;color:' + TEXT_BODY + ';padding-left:8px;">&#10003; ' + label + '</p>';
        }
        if (completedLoans > 0) {
            String label = completedLoans + ' library item' + (completedLoans > 1 ? 's found' : ' found') + ' a new home.';
            html += '<p style="margin:4px 0;font-size:14px;color:' + TEXT_BODY + ';padding-left:8px;">&#10003; ' + label + '</p>';
        }
        if (hasCross) {
            html += '<p style="margin:8px 0 0;font-size:13px;font-style:italic;color:' + TEXT_SECONDARY + ';padding-left:8px;">'
                + escHtml(crossFimbyLine) + '</p>';
        }
        html += '<div style="height:16px;"></div>';
        return html;
    }

    /**
     * @description Picks one of four cross-FIMBY aggregate metrics at random and returns
     * the formatted plain-text line. Empty string when the count is zero. Counts are
     * platform-wide and contain no PII — cross-neighbourhood scoping is intentional.
     */
    @TestVisible
    private static String getCrossFimbyStat(String frequency, Datetime startDt, Datetime endDt) {
        try {
            String windowWord = (frequency == 'Weekly') ? 'week' : 'day';
            Integer variant = Math.mod(Math.abs(Crypto.getRandomInteger()), 4);
            Integer count;
            String formatString;

            if (variant == 0) {
                count = [
                    SELECT COUNT() FROM Needs_Offers__c
                    WHERE RecordType.DeveloperName = 'Offer'
                      AND CreatedDate >= :startDt AND CreatedDate <= :endDt
                ];
                formatString = 'across FIMBY this {window}, {n} neighbours offered something.';
            } else if (variant == 1) {
                count = [
                    SELECT COUNT() FROM Needs_Offers__c
                    WHERE RecordType.DeveloperName = 'Need'
                      AND Status__c = 'Completed (Offer Accepted / Need Met)'
                      AND LastModifiedDate >= :startDt AND LastModifiedDate <= :endDt
                ];
                formatString = 'across FIMBY this {window}, {n} asks were met by someone close by.';
            } else if (variant == 2) {
                count = [
                    SELECT COUNT() FROM Loaned_Item__c
                    WHERE CreatedDate >= :startDt AND CreatedDate <= :endDt
                ];
                formatString = 'across FIMBY this {window}, {n} things changed hands and came back.';
            } else {
                count = [
                    SELECT COUNT() FROM Story__c
                    WHERE CreatedDate >= :startDt AND CreatedDate <= :endDt
                ];
                formatString = 'across FIMBY this {window}, {n} stories were shared.';
            }

            if (count == null || count == 0) {
                return '';
            }
            return formatString
                .replace('{window}', windowWord)
                .replace('{n}', String.valueOf(count));
        } catch (Exception e) {
            return '';
        }
    }

    /* ---------------------------------------------------------------
     * Anchor card — OTD when today matches, evergreen cycle otherwise.
     * Single slot rendered after the feed cards.
     * --------------------------------------------------------------- */

    @TestVisible
    private static String buildAnchorCard() {
        try {
            FIMBY_Digest_Anchor__mdt record = pickAnchorRecord(Date.today());
            if (record == null || String.isBlank(record.Body__c)) { return ''; }
            return renderAnchorCard(record);
        } catch (Exception e) {
            return '';
        }
    }

    @TestVisible
    private static FIMBY_Digest_Anchor__mdt pickAnchorRecord(Date today) {
        Integer todayMonth = today.month();
        Integer todayDay = today.day();

        List<FIMBY_Digest_Anchor__mdt> dated = [
            SELECT Title__c, Subtitle__c, Body__c, Type__c, Month__c, Day__c, Sort_Order__c
            FROM FIMBY_Digest_Anchor__mdt
            WHERE Active__c = true
              AND Month__c = :todayMonth
              AND Day__c = :todayDay
            LIMIT 1
        ];
        if (!dated.isEmpty()) {
            return dated[0];
        }

        List<FIMBY_Digest_Anchor__mdt> evergreen = [
            SELECT Title__c, Subtitle__c, Body__c, Type__c, Month__c, Day__c, Sort_Order__c
            FROM FIMBY_Digest_Anchor__mdt
            WHERE Active__c = true
              AND Month__c = null
              AND Day__c = null
            ORDER BY Sort_Order__c ASC NULLS LAST
        ];
        if (evergreen.isEmpty()) {
            return null;
        }
        // Apex Date.dayOfYear() is 1-based (Jan 1 = 1); subtract 1 for a zero-based cycle
        // so Jan 1 maps to evergreen[0] (the record with Sort_Order__c = 1).
        Integer index = Math.mod(today.dayOfYear() - 1, evergreen.size());
        return evergreen[index];
    }

    private static String renderAnchorCard(FIMBY_Digest_Anchor__mdt record) {
        String header = sectionHeaderForType(record.Type__c);
        String title = String.isNotBlank(record.Title__c) ? record.Title__c : '';
        String subtitle = String.isNotBlank(record.Subtitle__c) ? record.Subtitle__c : '';
        String body = String.isNotBlank(record.Body__c) ? record.Body__c : '';

        String html = buildSectionHeader(header, EARTH_DRIFTWOOD);
        html += '<table cellpadding="0" cellspacing="0" border="0" width="552" '
            + 'style="max-width:552px;width:100%;margin-bottom:12px;border-radius:8px;'
            + 'border:1px solid ' + BORDER_LIGHT + ';background-color:' + BG_CARD + ';">'
            + '<tr><td style="padding:14px 18px;">';

        if (String.isNotBlank(title)) {
            String titleLine = escHtml(title);
            if (String.isNotBlank(subtitle)) {
                titleLine += ' <span style="color:' + TEXT_SECONDARY + ';font-weight:400;">&middot; ' + escHtml(subtitle) + '</span>';
            }
            html += '<p style="margin:0 0 8px;' + FimbyEmailHtmlBuilder.F + 'font-size:16px;font-weight:600;color:' + TEXT_HEADING + ';">'
                + titleLine + '</p>';
        }

        html += '<p style="margin:0;' + FimbyEmailHtmlBuilder.F + 'font-size:15px;line-height:1.5;font-style:italic;color:' + TEXT_BODY + ';">'
            + escHtml(body) + '</p>';

        html += '</td></tr></table>';
        return html;
    }

    private static String sectionHeaderForType(String typeKey) {
        if (typeKey == 'Birth') { return 'today we celebrate the birth of'; }
        if (typeKey == 'Death') { return 'today we remember'; }
        if (typeKey == 'Feast_Day') { return 'feast day of'; }
        if (typeKey == 'Event') { return 'on this day'; }
        if (typeKey == 'Devotional') { return 'today\'s reflection'; }
        if (typeKey == 'Reflection') { return 'a question to sit with'; }
        if (typeKey == 'Neighbouring_Tip') { return 'a neighbouring tip'; }
        if (typeKey == 'How_To') { return 'how FIMBY works'; }
        return 'today';
    }

    /* ---------------------------------------------------------------
     * Feed-card sections
     * --------------------------------------------------------------- */

    private static String buildStoriesSection(Id nhId, Datetime startDt, Datetime endDt) {
        List<Story__c> stories = [
            SELECT Id, Name, Message__c, Type__c, Image_URL__c,
                   Posted_By__r.Name, Posted_By__r.FirstName, Posted_By__r.Image_URL__c,
                   Message_Preview__c, CreatedDate
            FROM Story__c
            WHERE Neighbourhood__c = :nhId
              AND CreatedDate >= :startDt AND CreatedDate <= :endDt
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
        if (stories.isEmpty()) { return ''; }

        String html = buildSectionHeader('Shared Life', EARTH_OCHRE);
        Integer count = Math.min(stories.size(), MAX_CARDS_PER_SECTION);
        for (Integer i = 0; i < count; i++) {
            html += buildStoryCard(stories[i]);
        }
        if (stories.size() > MAX_CARDS_PER_SECTION) {
            html += buildMoreLink(stories.size() - MAX_CARDS_PER_SECTION, FimbySettings.getUrl('Shared_Life_List'));
        }
        return html;
    }

    private static String buildAsksOffersSection(Id nhId, Datetime startDt, Datetime endDt) {
        List<Needs_Offers__c> posts = [
            SELECT Id, Name, Details__c, Image_1_URL__c, Is_Urgent__c,
                   Contact__r.Name, Contact__r.FirstName, Contact__r.Image_URL__c,
                   RecordType.DeveloperName, CreatedDate
            FROM Needs_Offers__c
            WHERE Neighbourhood__c = :nhId
              AND RecordType.DeveloperName IN ('Need', 'Offer')
              AND Type__c != 'Event'
              AND CreatedDate >= :startDt AND CreatedDate <= :endDt
              AND Status__c IN ('Posted', 'Available', 'Reply Received')
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
        if (posts.isEmpty()) { return ''; }

        String html = buildSectionHeader('Asks & Offers', EARTH_SAGE);
        Integer count = Math.min(posts.size(), MAX_CARDS_PER_SECTION);
        for (Integer i = 0; i < count; i++) {
            html += buildAskOfferCard(posts[i]);
        }
        if (posts.size() > MAX_CARDS_PER_SECTION) {
            html += buildMoreLink(posts.size() - MAX_CARDS_PER_SECTION, FIMBY_BASE_URL);
        }
        return html;
    }

    private static String buildEventsSection(Id nhId, Datetime startDt, Datetime endDt) {
        List<Needs_Offers__c> events = [
            SELECT Id, Name, Details__c, Image_1_URL__c,
                   Contact__r.Name, Contact__r.FirstName, Contact__r.Image_URL__c,
                   Event_Type__c, Start_Date__c, Location__c, CreatedDate
            FROM Needs_Offers__c
            WHERE Neighbourhood__c = :nhId
              AND Type__c = 'Event'
              AND CreatedDate >= :startDt AND CreatedDate <= :endDt
              AND Status__c IN ('Posted', 'Available')
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
        if (events.isEmpty()) { return ''; }

        String html = buildSectionHeader('Events', EARTH_TEAL);
        Integer count = Math.min(events.size(), MAX_CARDS_PER_SECTION);
        for (Integer i = 0; i < count; i++) {
            html += buildEventCard(events[i]);
        }
        if (events.size() > MAX_CARDS_PER_SECTION) {
            html += buildMoreLink(events.size() - MAX_CARDS_PER_SECTION, FIMBY_BASE_URL);
        }
        return html;
    }

    private static String buildBulkBuysSection(Id nhId, Datetime startDt, Datetime endDt) {
        List<Needs_Offers__c> bulkBuys = [
            SELECT Id, Name, Details__c, Image_1_URL__c,
                   Contact__r.Name, Contact__r.FirstName, Contact__r.Image_URL__c,
                   Total_Quantity__c, Total_Reserved__c, Owner_Shares__c, Total_Available__c,
                   Allocation_Unit_Label__c, Estimated_Cost_Per_Share__c,
                   CreatedDate
            FROM Needs_Offers__c
            WHERE Neighbourhood__c = :nhId
              AND RecordType.DeveloperName = 'Bulk_Buy'
              AND CreatedDate >= :startDt AND CreatedDate <= :endDt
              AND Status__c IN ('Posted', 'Available', 'Reply Received')
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
        if (bulkBuys.isEmpty()) { return ''; }

        String html = buildSectionHeader('Bulk Buys', EARTH_OCHRE);
        Integer count = Math.min(bulkBuys.size(), MAX_CARDS_PER_SECTION);
        for (Integer i = 0; i < count; i++) {
            html += buildBulkBuyCard(bulkBuys[i]);
        }
        if (bulkBuys.size() > MAX_CARDS_PER_SECTION) {
            html += buildMoreLink(bulkBuys.size() - MAX_CARDS_PER_SECTION, FIMBY_BASE_URL);
        }
        return html;
    }

    private static String buildLibrarySection(Id nhId, Datetime startDt, Datetime endDt) {
        List<Library_Item__c> items = [
            SELECT Id, Name, Description__c, Image_URL__c, Category__c,
                   Owner_Contact__r.Name, Owner_Contact__r.FirstName, Owner_Contact__r.Image_URL__c,
                   CreatedDate
            FROM Library_Item__c
            WHERE Neighbourhood__c = :nhId
              AND CreatedDate >= :startDt AND CreatedDate <= :endDt
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
        if (items.isEmpty()) { return ''; }

        String html = buildSectionHeader('Library', EARTH_DRIFTWOOD);
        Integer count = Math.min(items.size(), MAX_CARDS_PER_SECTION);
        for (Integer i = 0; i < count; i++) {
            html += buildLibraryCard(items[i]);
        }
        if (items.size() > MAX_CARDS_PER_SECTION) {
            html += buildMoreLink(items.size() - MAX_CARDS_PER_SECTION, FimbySettings.getUrl('Library_List'));
        }
        return html;
    }

    /* ---------------------------------------------------------------
     * Type-Specific Card Builders
     * --------------------------------------------------------------- */

    private static String buildAskOfferCard(Needs_Offers__c post) {
        String rt = post.RecordType != null ? post.RecordType.DeveloperName : 'Need';
        String badgeLabel = rt == 'Need' ? 'ASK' : 'OFFER';
        String ctaUrl = FimbySettings.getUrl('Needs_Offers', post.Id);

        String html = openCard();
        html += FimbyEmailHtmlBuilder.buildCardImage(post.Image_1_URL__c, 180);
        html += openCardBody();
        html += badgeAvatarRow(badgeLabel, rt, post.Contact__r);
        html += titleRow(post.Name);
        html += snippetRow(post.Details__c);
        html += FimbyEmailHtmlBuilder.buildCtaButton('Respond', ctaUrl, 'reply.png');
        html += closeCardBody();
        return html;
    }

    private static String buildEventCard(Needs_Offers__c evt) {
        String evtType = String.isNotBlank(evt.Event_Type__c) ? evt.Event_Type__c : 'Gathering';
        String badgeLabel;
        String ctaLabel;
        if (evtType == 'Community_Event') {
            badgeLabel = 'COMMUNITY EVENT';
            ctaLabel = 'I\'m Interested';
        } else if (evtType == 'Open_Event') {
            badgeLabel = 'EVENT';
            ctaLabel = 'I\'m Going';
        } else {
            badgeLabel = 'GATHERING';
            ctaLabel = 'RSVP';
        }
        String ctaUrl = FimbySettings.getUrl('Needs_Offers', evt.Id);

        String html = openCard();
        html += FimbyEmailHtmlBuilder.buildCardImage(evt.Image_1_URL__c, 180);
        html += openCardBody();
        html += badgeAvatarRow(badgeLabel, evtType, evt.Contact__r);
        html += titleRow(evt.Name);
        html += FimbyEmailHtmlBuilder.buildDateLocationLine(evt.Start_Date__c, evt.Location__c);
        html += snippetRow(evt.Details__c);
        html += FimbyEmailHtmlBuilder.buildCtaButton(ctaLabel, ctaUrl, FimbyEmailHtmlBuilder.getCtaIcon(evtType));
        html += closeCardBody();
        return html;
    }

    private static String buildBulkBuyCard(Needs_Offers__c bb) {
        String ctaUrl = FimbySettings.getUrl('Needs_Offers', bb.Id);

        String html = openCard();
        html += FimbyEmailHtmlBuilder.buildCardImage(bb.Image_1_URL__c, 180);
        html += openCardBody();
        html += badgeAvatarRow('BULK BUY', 'Bulk_Buy', bb.Contact__r);
        html += titleRow(bb.Name);
        html += snippetRow(bb.Details__c);
        html += FimbyEmailHtmlBuilder.buildThermometer(
            bb.Total_Reserved__c, bb.Total_Quantity__c,
            bb.Allocation_Unit_Label__c, bb.Estimated_Cost_Per_Share__c
        );
        html += FimbyEmailHtmlBuilder.buildCtaButton('Reserve-A-Share', ctaUrl, 'buy.png');
        html += closeCardBody();
        return html;
    }

    private static String buildStoryCard(Story__c story) {
        String storyType = String.isNotBlank(story.Type__c) ? story.Type__c : 'Story';
        String badgeLabel = storyType == 'Neighbourhood Moment' ? 'NEIGHBOURHOOD' : storyType.toUpperCase();
        String ctaUrl = FimbySettings.getUrl('Story', story.Id);
        String body = String.isNotBlank(story.Message_Preview__c) ? story.Message_Preview__c : story.Message__c;

        String html = openCard();
        html += FimbyEmailHtmlBuilder.buildCardImage(story.Image_URL__c, 180);
        html += openCardBody();
        html += badgeAvatarRow(badgeLabel, storyType, story.Posted_By__r);
        html += titleRow(story.Name);
        html += snippetRow(body);
        html += FimbyEmailHtmlBuilder.buildCtaButton('Read More', ctaUrl, 'comment.png');
        html += closeCardBody();
        return html;
    }

    private static String buildLibraryCard(Library_Item__c item) {
        String ctaUrl = FimbySettings.getUrl('Library_Item', item.Id);

        String html = openCard();
        html += FimbyEmailHtmlBuilder.buildCardImage(item.Image_URL__c, 180);
        html += openCardBody();
        String categoryPill = String.isNotBlank(item.Category__c)
            ? FimbyEmailHtmlBuilder.buildCategoryPill(item.Category__c, null) : null;
        html += badgeAvatarRow('LIBRARY', 'Library', categoryPill, item.Owner_Contact__r);
        html += titleRow(item.Name);
        html += snippetRow(item.Description__c);
        html += FimbyEmailHtmlBuilder.buildCtaButton('Borrow', ctaUrl, 'borrow.png');
        html += closeCardBody();
        return html;
    }

    /* ---------------------------------------------------------------
     * Card Structure Helpers
     * --------------------------------------------------------------- */

    private static String openCard() {
        return '<table cellpadding="0" cellspacing="0" border="0" width="552" '
            + 'style="max-width:552px;width:100%;margin-bottom:12px;border-radius:8px;overflow:hidden;border:1px solid ' + BORDER_LIGHT + ';background-color:#FFFFFF;">';
    }

    private static String openCardBody() {
        return '<tr><td style="padding:12px 16px;">';
    }

    private static String closeCardBody() {
        return '</td></tr></table>';
    }

    private static String badgeAvatarRow(String label, String typeKey, SObject contactRef) {
        return badgeAvatarRow(label, typeKey, null, contactRef);
    }

    private static String badgeAvatarRow(String label, String typeKey, String extraPillHtml, SObject contactRef) {
        String leftHtml = FimbyEmailHtmlBuilder.buildBadgePill(label,
            FimbyEmailHtmlBuilder.getBadgeColor(typeKey),
            FimbyEmailHtmlBuilder.getBadgeIcon(typeKey));
        if (String.isNotBlank(extraPillHtml)) {
            leftHtml += extraPillHtml;
        }

        String rightHtml = '';
        if (contactRef != null) {
            String imageUrl = (String) contactRef.get('Image_URL__c');
            String firstName = (String) contactRef.get('FirstName');
            String fullName = (String) contactRef.get('Name');
            rightHtml = FimbyEmailHtmlBuilder.buildAvatar(imageUrl, firstName, null)
                + '<span style="' + FimbyEmailHtmlBuilder.F + 'font-size:14px;color:' + TEXT_SECONDARY + ';vertical-align:middle;">'
                + escHtml(fullName) + '</span>';
        }

        return '<table cellpadding="0" cellspacing="0" border="0" width="100%" style="margin-bottom:8px;">'
            + '<tr>'
            + '<td style="vertical-align:middle;">' + leftHtml + '</td>'
            + '<td align="right" style="vertical-align:middle;">' + rightHtml + '</td>'
            + '</tr></table>';
    }

    private static String titleRow(String title) {
        if (String.isBlank(title)) { return ''; }
        return '<p style="margin:0 0 4px;' + FimbyEmailHtmlBuilder.F + 'font-size:17px;font-weight:600;color:' + TEXT_HEADING + ';">'
            + escHtml(title) + '</p>';
    }

    private static String snippetRow(String description) {
        String snippet = truncate(description, SNIPPET_LENGTH);
        if (String.isBlank(snippet)) { return ''; }
        return '<p style="margin:0 0 6px;' + FimbyEmailHtmlBuilder.F + 'font-size:15px;color:' + TEXT_BODY + ';line-height:1.5;">'
            + escHtml(snippet) + '</p>';
    }

    private static String buildSectionHeader(String title, String accentColor) {
        return '<table cellpadding="0" cellspacing="0" border="0" width="552" style="max-width:552px;width:100%;margin-bottom:8px;margin-top:16px;">'
            + '<tr><td style="background:' + accentColor + ';border-radius:8px;padding:8px 12px;">'
            + '<span style="' + FimbyEmailHtmlBuilder.F + 'color:#FFFFFF;font-size:15px;font-weight:600;">' + escHtml(title) + '</span>'
            + '</td></tr></table>';
    }

    private static String buildMoreLink(Integer remaining, String url) {
        return '<p style="' + FimbyEmailHtmlBuilder.F + 'text-align:center;font-size:14px;color:' + TEXT_SECONDARY + ';padding:4px 0;">'
            + 'and ' + remaining + ' more &mdash; <a href="' + url + '" style="' + FimbyEmailHtmlBuilder.F + 'color:' + CTA_BG + ';">see them all in FIMBY</a>'
            + '</p>';
    }

    private static String truncate(String text, Integer maxLen) {
        if (String.isBlank(text) || text.length() <= maxLen) { return text; }
        return text.substring(0, maxLen) + '...';
    }

    private static String escHtml(String input) {
        return String.isBlank(input) ? '' : input.escapeHtml4();
    }

    private static Integer countItems(String html) {
        if (String.isBlank(html)) { return 0; }
        return html.countMatches('margin-bottom:12px;border-radius:8px');
    }
}
