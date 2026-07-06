/**
 * @description Builds the dynamic content portion of digest emails — card-style sections
 * for each content type. Output is wrapped in the Apex branded email shell.
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
    private static final Integer SNIPPET_LENGTH = 140;

    // Compact card layout (email real-estate efficiency): the badge + linked title and the body
    // snippet sit in the left column; a fixed 140x120 cropped thumbnail sits in the right column
    // (see FimbyEmailHtmlBuilder.buildDigestImageCell). A shared footer row carries the avatar +
    // first-name byline (left) and a single quiet "open ›" link (right) — the title, thumbnail
    // and open link all point at the record, so there is no per-type CTA button. Cards with no
    // image collapse to a single column with the same footer.
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
        return buildDigestContent(
            neighbourhoodId, neighbourhoodName, frequency,
            windowStart, windowEnd, new Set<Id>()
        );
    }

    /**
     * @description Per-viewer build: identical to the 5-arg build but excludes any feed card
     * whose represented owner OR real author is in excludedAuthorContactIds. Used by the batch
     * to hide blocked neighbours' content from recipients on either side of a block. The
     * 5-arg signature delegates here with an empty set (NOT IN :emptySet matches all rows).
     * The exclusion flows into each section's count query too, so "and N more" counts never
     * include hidden authors. Resolution + cross-FIMBY rollups and the anchor card stay
     * unfiltered by design — they are counts / evergreen content with no PII.
     */
    public static DigestResult buildDigestContent(
        Id neighbourhoodId, String neighbourhoodName,
        String frequency, Date windowStart, Date windowEnd,
        Set<Id> excludedAuthorContactIds
    ) {
        DigestResult result = new DigestResult();
        Set<Id> excluded = excludedAuthorContactIds != null ? excludedAuthorContactIds : new Set<Id>();
        Datetime windowStartDt = Datetime.newInstance(windowStart, Time.newInstance(0, 0, 0, 0));
        Datetime windowEndDt = Datetime.newInstance(windowEnd, Time.newInstance(23, 59, 59, 0));

        // Feed cards build first so feedCardCount is known before the resolution section —
        // the "Good things happening" rollup is gated against what this email already shows.
        String storiesHtml = buildStoriesSection(neighbourhoodId, windowStartDt, windowEndDt, excluded);
        String asksOffersHtml = buildAsksOffersSection(neighbourhoodId, windowStartDt, windowEndDt, excluded);
        String eventsHtml = buildEventsSection(neighbourhoodId, windowStartDt, windowEndDt, excluded);
        String bulkBuysHtml = buildBulkBuysSection(neighbourhoodId, windowStartDt, windowEndDt, excluded);
        String libraryHtml = buildLibrarySection(neighbourhoodId, windowStartDt, windowEndDt, excluded);

        Integer feedCardCount = countItems(storiesHtml) + countItems(asksOffersHtml)
            + countItems(eventsHtml) + countItems(bulkBuysHtml) + countItems(libraryHtml);

        result.itemCount = feedCardCount;
        result.isEmpty = (feedCardCount == 0);

        if (result.isEmpty) {
            result.html = '';
            return result;
        }

        String resolutionHtml = buildResolutionSection(neighbourhoodId, frequency, windowStartDt, windowEndDt, feedCardCount);
        String anchorHtml = buildAnchorCard();

        result.html = resolutionHtml + storiesHtml + asksOffersHtml + eventsHtml
            + bulkBuysHtml + libraryHtml + anchorHtml;
        return result;
    }

    public class DigestResult {
        public String html = '';
        public Integer itemCount = 0;
        public Boolean isEmpty = true;
        @TestVisible
        public List<String> selectedItemSummaries = new List<String>();
    }

    /* ---------------------------------------------------------------
     * By the numbers — local resolution + cross-FIMBY encouragement
     * --------------------------------------------------------------- */

    private static String buildResolutionSection(Id nhId, String frequency, Datetime startDt, Datetime endDt, Integer feedCardCount) {
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

        CrossFimbyStat cross = getCrossFimbyStat(frequency, startDt, endDt);
        Boolean showCross = shouldShowCrossFimby(cross.count, feedCardCount);

        List<String> lines = new List<String>();
        if (fulfilledAsks > 0) {
            lines.add(fulfilledAsks == 1
                ? '1 ask was answered by a neighbour.'
                : fulfilledAsks + ' asks were answered by neighbours.');
        }
        if (completedLoans > 0) {
            lines.add(completedLoans == 1
                ? '1 borrowed thing made its way home again.'
                : completedLoans + ' borrowed things made their way home again.');
        }
        if (showCross) {
            lines.add(cross.line);
        }

        if (lines.isEmpty()) {
            return '';
        }

        String timePhrase = resolveCrossFimbyTimePhrase(frequency, startDt, endDt);
        return buildSectionHeader('Good things happening ' + timePhrase, EARTH_SAGE)
            + buildResolutionProse(lines);
    }

    /**
     * @description Renders the "Good things happening" lines in a plain white card that matches
     * the other digest sections: a gentle italic intro caption followed by the count lines as
     * encouraging sentences. The dynamic timeframe lives in the section title, so the prose
     * carries no time reference of its own.
     */
    private static String buildResolutionProse(List<String> lines) {
        String body = '<p style="margin:0 0 10px;' + FimbyEmailHtmlBuilder.F
            + 'font-size:13px;font-style:italic;color:' + TEXT_SECONDARY + ';">small kindnesses, close to home</p>';
        for (String line : lines) {
            body += '<p style="margin:0 0 6px;' + FimbyEmailHtmlBuilder.F
                + 'font-size:14px;line-height:1.6;color:' + TEXT_BODY + ';">' + line + '</p>';
        }
        return '<table cellpadding="0" cellspacing="0" border="0" width="600" '
            + 'style="max-width:600px;width:100%;margin-bottom:12px;border-radius:8px;'
            + 'border:1px solid ' + BORDER_LIGHT + ';background-color:' + BG_CARD + ';">'
            + '<tr><td style="padding:14px 18px;">'
            + body
            + '</td></tr></table>';
    }

    /**
     * @description The platform-wide zoom-out line is only additive when it reflects MORE
     * activity than this email already shows as feed cards. When it doesn't, the line just
     * re-counts content already visible below it (e.g. "across FIMBY, 1 neighbour shared a
     * piece of their life" sitting next to that same single story), so it is suppressed.
     */
    @TestVisible
    private static Boolean shouldShowCrossFimby(Integer crossCount, Integer feedCardCount) {
        return crossCount != null && crossCount > feedCardCount;
    }

    /**
     * @description Carries the chosen cross-FIMBY metric's count alongside its formatted
     * line so the caller can compare the platform-wide count to the local tally before
     * deciding whether to render it.
     */
    @TestVisible
    private class CrossFimbyStat {
        @TestVisible Integer count;
        @TestVisible String line;
        CrossFimbyStat(Integer count, String line) {
            this.count = count;
            this.line = line;
        }
    }

    /**
     * @description Picks one of four cross-FIMBY aggregate metrics at random and returns its
     * count plus the formatted line. Count 0 / blank line when nothing happened. Counts are
     * platform-wide and contain no PII — cross-neighbourhood scoping is intentional.
     */
    @TestVisible
    private static CrossFimbyStat getCrossFimbyStat(String frequency, Datetime startDt, Datetime endDt) {
        try {
            Integer variant = Math.mod(Math.abs(Crypto.getRandomInteger()), 4);
            Integer count;

            if (variant == 0) {
                count = [
                    SELECT COUNT() FROM Needs_Offers__c
                    WHERE RecordType.DeveloperName = 'Offer'
                      AND CreatedDate >= :startDt AND CreatedDate <= :endDt
                ];
            } else if (variant == 1) {
                count = [
                    SELECT COUNT() FROM Needs_Offers__c
                    WHERE RecordType.DeveloperName = 'Need'
                      AND Status__c = 'Completed (Offer Accepted / Need Met)'
                      AND LastModifiedDate >= :startDt AND LastModifiedDate <= :endDt
                ];
            } else if (variant == 2) {
                count = [
                    SELECT COUNT() FROM Loaned_Item__c
                    WHERE CreatedDate >= :startDt AND CreatedDate <= :endDt
                ];
            } else {
                count = [
                    SELECT COUNT() FROM Story__c
                    WHERE CreatedDate >= :startDt AND CreatedDate <= :endDt
                ];
            }

            if (count == null || count == 0) {
                return new CrossFimbyStat(0, '');
            }
            return new CrossFimbyStat(count, formatCrossFimbyLine(variant, count));
        } catch (Exception e) {
            return new CrossFimbyStat(0, '');
        }
    }

    /**
     * @description Formats one cross-FIMBY aggregate line. The timeframe lives in the section
     * title, so the line carries none of its own. The real count is always shown (even for 1)
     * so it reads as a count, with singular/plural grammar so a value of 1 never reads
     * "1 stories were shared".
     */
    @TestVisible
    private static String formatCrossFimbyLine(Integer variant, Integer count) {
        Boolean isOne = (count == 1);
        String body;
        if (variant == 0) {
            body = isOne
                ? '{n} neighbour set something out for whoever needed it.'
                : '{n} neighbours set something out for whoever needed it.';
        } else if (variant == 1) {
            body = isOne
                ? '{n} ask was met by someone close by.'
                : '{n} asks were met by someone close by.';
        } else if (variant == 2) {
            body = isOne
                ? '{n} thing was passed from one neighbour to the next.'
                : '{n} things were passed from one neighbour to the next.';
        } else {
            body = isOne
                ? '{n} neighbour shared a piece of their life.'
                : '{n} neighbours shared a piece of their life.';
        }
        return ('across FIMBY, ' + body).replace('{n}', String.valueOf(count));
    }

    @TestVisible
    private static String resolveCrossFimbyTimePhrase(String frequency, Datetime startDt, Datetime endDt) {
        if (frequency == 'Weekly') {
            return 'this week';
        }
        if (startDt != null && endDt != null && startDt.date() != endDt.date()) {
            return 'this weekend';
        }
        return 'yesterday';
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
        html += '<table cellpadding="0" cellspacing="0" border="0" width="600" '
            + 'style="max-width:600px;width:100%;margin-bottom:12px;border-radius:8px;'
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

    private static String buildStoriesSection(Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded) {
        List<Story__c> stories = [
            SELECT Id, Name, Message__c, Type__c, Image_URL__c, Image_Ratio__c,
                   Posted_By__r.Name, Posted_By__r.Full_Name__c, Posted_By__r.FirstName,
                   Posted_By__r.Image_URL__c, Posted_By__r.Display_Avatar_URL__c,
                   Message_Preview__c, CreatedDate
            FROM Story__c
            WHERE Neighbourhood__c = :nhId
              AND CreatedDate >= :startDt AND CreatedDate <= :endDt
              AND Posted_By__c NOT IN :excluded
              AND Contact__c NOT IN :excluded
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

    private class TieredDigestResult {
        List<Needs_Offers__c> cards;
        Integer totalCount;
        TieredDigestResult(List<Needs_Offers__c> cards, Integer totalCount) {
            this.cards = cards;
            this.totalCount = totalCount;
        }
    }

    private static TieredDigestResult queryTieredAskOffers(Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded) {
        String selectClause = 'SELECT Id, Name, Details__c, Image_1_URL__c, Image_1_Ratio__c, Is_Urgent__c, Refresh_Count__c, ' +
            'Contact__r.Name, Contact__r.Full_Name__c, Contact__r.FirstName, Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c, ' +
            'RecordType.DeveloperName, Posted_Date__c, CreatedDate ';
        String baseWhere = 'FROM Needs_Offers__c ' +
            'WHERE Neighbourhood__c = :nhId ' +
            'AND RecordType.DeveloperName IN (\'Need\', \'Offer\') ' +
            'AND Type__c != \'Event\' ' +
            'AND Posted_Date__c >= :startDt AND Posted_Date__c <= :endDt ' +
            'AND Status__c IN (\'Posted\', \'Available\', \'Reply Received\') ' +
            'AND Contact__c NOT IN :excluded AND Posted_By__c NOT IN :excluded ';

        Integer max = MAX_CARDS_PER_SECTION;
        List<Needs_Offers__c> tier1 = Database.query(
            selectClause + baseWhere +
            'AND (Refresh_Count__c = null OR Refresh_Count__c = 0) ' +
            'ORDER BY Posted_Date__c DESC LIMIT :max'
        );

        Integer totalTier1 = Database.countQuery(
            'SELECT COUNT() ' + baseWhere + 'AND (Refresh_Count__c = null OR Refresh_Count__c = 0)'
        );
        Integer totalTier2 = Database.countQuery(
            'SELECT COUNT() ' + baseWhere + 'AND Refresh_Count__c > 0'
        );
        Integer totalCount = totalTier1 + totalTier2;

        List<Needs_Offers__c> cards = new List<Needs_Offers__c>(tier1);
        if (cards.size() < max) {
            Integer remainder = max - cards.size();
            List<Needs_Offers__c> tier2 = Database.query(
                selectClause + baseWhere +
                'AND Refresh_Count__c > 0 ' +
                'ORDER BY Posted_Date__c DESC LIMIT :remainder'
            );
            cards.addAll(tier2);
        }
        return new TieredDigestResult(cards, totalCount);
    }

    @TestVisible
    private static String formatRecurrenceFrequencyBadge(String frequency, Decimal interval) {
        if (String.isBlank(frequency)) {
            return null;
        }
        Integer n = (interval != null && interval.intValue() > 0) ? interval.intValue() : 1;
        if (frequency == 'Week') {
            return n == 1 ? 'WEEKLY' : 'EVERY ' + n + ' WEEKS';
        }
        if (frequency == 'Month') {
            return n == 1 ? 'MONTHLY' : 'EVERY ' + n + ' MONTHS';
        }
        if (frequency == 'Year') {
            return n == 1 ? 'YEARLY' : 'EVERY ' + n + ' YEARS';
        }
        return null;
    }

    private static TieredDigestResult queryTieredEvents(
        Id nhId,
        Datetime startDt,
        Datetime endDt,
        Set<Id> liveRecurringOccurrenceIds,
        Date today,
        Set<Id> excluded
    ) {
        String selectClause = 'SELECT Id, Name, Details__c, Image_1_URL__c, Image_1_Ratio__c, ' +
            'Contact__r.Name, Contact__r.Full_Name__c, Contact__r.FirstName, Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c, ' +
            'Event_Type__c, Start_Date__c, End_Date__c, Location__c, CreatedDate, ' +
            'Recurrence_Frequency__c, Recurrence_Interval__c, Series_Parent__c ';
        String baseWhere = 'FROM Needs_Offers__c ' +
            'WHERE Neighbourhood__c = :nhId ' +
            'AND Type__c = \'Event\' ' +
            'AND CreatedDate >= :startDt AND CreatedDate <= :endDt ' +
            'AND Status__c IN (\'Posted\', \'Available\') ' +
            'AND (End_Date__c >= :today OR (End_Date__c = null AND Start_Date__c >= :today)) ' +
            'AND ((Recurrence_Frequency__c = null AND Series_Parent__c = null) OR Id IN :liveRecurringOccurrenceIds) ' +
            'AND Contact__c NOT IN :excluded AND Posted_By__c NOT IN :excluded ';

        Integer max = MAX_CARDS_PER_SECTION;
        List<Needs_Offers__c> tier1 = Database.query(
            selectClause + baseWhere +
            'AND Series_Parent__c = null ' +
            'ORDER BY CreatedDate DESC LIMIT :max'
        );

        Integer totalTier1 = Database.countQuery(
            'SELECT COUNT() ' + baseWhere + 'AND Series_Parent__c = null'
        );
        Integer totalTier2 = Database.countQuery(
            'SELECT COUNT() ' + baseWhere + 'AND Series_Parent__c != null'
        );
        Integer totalCount = totalTier1 + totalTier2;

        List<Needs_Offers__c> cards = new List<Needs_Offers__c>(tier1);
        if (cards.size() < max) {
            Integer remainder = max - cards.size();
            List<Needs_Offers__c> tier2 = Database.query(
                selectClause + baseWhere +
                'AND Series_Parent__c != null ' +
                'ORDER BY CreatedDate DESC LIMIT :remainder'
            );
            cards.addAll(tier2);
        }
        return new TieredDigestResult(cards, totalCount);
    }

    private static String buildAsksOffersSection(Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded) {
        TieredDigestResult result = queryTieredAskOffers(nhId, startDt, endDt, excluded);
        if (result.cards.isEmpty()) { return ''; }

        String html = buildSectionHeader('Asks & Offers', EARTH_SAGE);
        for (Needs_Offers__c post : result.cards) {
            html += buildAskOfferCard(post);
        }
        if (result.totalCount > MAX_CARDS_PER_SECTION) {
            html += buildMoreLink(result.totalCount - MAX_CARDS_PER_SECTION, FIMBY_BASE_URL);
        }
        return html;
    }

    /**
     * @description Live occurrence per recurring series — mirrors FimbyHomeController feed filter.
     */
    @TestVisible
    private static Set<Id> resolveLiveRecurringOccurrenceIds(Id neighbourhoodId) {
        Set<Id> liveIds = new Set<Id>();
        for (Needs_Offers__c seriesParent : [
            SELECT Id, Current_Occurrence__c
            FROM Needs_Offers__c
            WHERE Neighbourhood__c = :neighbourhoodId
              AND Recurrence_Frequency__c != null
              AND Series_Parent__c = null
        ]) {
            liveIds.add(
                seriesParent.Current_Occurrence__c != null
                    ? seriesParent.Current_Occurrence__c
                    : seriesParent.Id
            );
        }
        return liveIds;
    }

    private static String buildEventsSection(Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded) {
        Date today = Date.today();
        Set<Id> liveRecurringOccurrenceIds = resolveLiveRecurringOccurrenceIds(nhId);
        TieredDigestResult result = queryTieredEvents(
            nhId, startDt, endDt, liveRecurringOccurrenceIds, today, excluded
        );
        if (result.cards.isEmpty()) { return ''; }

        String html = buildSectionHeader('Events', EARTH_TEAL);
        for (Needs_Offers__c evt : result.cards) {
            html += buildEventCard(evt);
        }
        if (result.totalCount > MAX_CARDS_PER_SECTION) {
            html += buildMoreLink(result.totalCount - MAX_CARDS_PER_SECTION, FIMBY_BASE_URL);
        }
        return html;
    }

    private static String buildBulkBuysSection(Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded) {
        List<Needs_Offers__c> bulkBuys = [
            SELECT Id, Name, Details__c, Image_1_URL__c, Image_1_Ratio__c,
                   Contact__r.Name, Contact__r.Full_Name__c, Contact__r.FirstName,
                   Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c,
                   Total_Quantity__c, Total_Reserved__c, Owner_Shares__c, Total_Available__c,
                   Allocation_Unit_Label__c, Estimated_Cost_Per_Share__c,
                   Posted_Date__c, CreatedDate
            FROM Needs_Offers__c
            WHERE Neighbourhood__c = :nhId
              AND RecordType.DeveloperName = 'Bulk_Buy'
              AND Posted_Date__c >= :startDt AND Posted_Date__c <= :endDt
              AND Status__c IN ('Posted', 'Available', 'Reply Received')
              AND Contact__c NOT IN :excluded
              AND Posted_By__c NOT IN :excluded
            ORDER BY Posted_Date__c DESC
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

    private static String buildLibrarySection(Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded) {
        List<Library_Item__c> items = [
            SELECT Id, Name, Description__c, Image_URL__c, Image_Ratio__c, Category__c,
                   Owner_Contact__r.Name, Owner_Contact__r.Full_Name__c, Owner_Contact__r.FirstName,
                   Owner_Contact__r.Image_URL__c, Owner_Contact__r.Display_Avatar_URL__c,
                   CreatedDate
            FROM Library_Item__c
            WHERE Neighbourhood__c = :nhId
              AND CreatedDate >= :startDt AND CreatedDate <= :endDt
              AND Owner_Contact__c NOT IN :excluded
              AND Listed_By__c NOT IN :excluded
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
        String ctaUrl = FimbySettings.getUrl('Asks_Offers', post.Id);

        String leftBody = badgeTitleRow(badgeLabel, rt, post.Name, ctaUrl)
            + snippetRow(post.Details__c);
        return buildCard(post.Image_1_URL__c, leftBody, post.Contact__r, ctaUrl);
    }

    private static String buildEventCard(Needs_Offers__c evt) {
        String evtType = String.isNotBlank(evt.Event_Type__c) ? evt.Event_Type__c : 'Gathering';
        String badgeLabel;
        if (evtType == 'Community_Event') {
            badgeLabel = 'COMMUNITY EVENT';
        } else if (evtType == 'Open_Event') {
            badgeLabel = 'EVENT';
        } else {
            badgeLabel = 'GATHERING';
        }
        String ctaUrl = FimbySettings.getUrl('Asks_Offers', evt.Id);
        String freqBadge = formatRecurrenceFrequencyBadge(
            evt.Recurrence_Frequency__c,
            evt.Recurrence_Interval__c
        );
        String recurrenceWord = String.isNotBlank(freqBadge) ? freqBadge.toLowerCase() : null;

        String leftBody = badgeTitleRow(badgeLabel, evtType, evt.Name, ctaUrl)
            + eventMetaLine(evt.Start_Date__c, evt.Location__c, recurrenceWord)
            + snippetRow(evt.Details__c);
        return buildCard(evt.Image_1_URL__c, leftBody, evt.Contact__r, ctaUrl);
    }

    private static String buildBulkBuyCard(Needs_Offers__c bb) {
        String ctaUrl = FimbySettings.getUrl('Asks_Offers', bb.Id);

        String leftBody = badgeTitleRow('BULK BUY', 'Bulk_Buy', bb.Name, ctaUrl)
            + snippetRow(bb.Details__c)
            + FimbyEmailHtmlBuilder.buildThermometer(
                bb.Total_Reserved__c, bb.Total_Quantity__c,
                bb.Allocation_Unit_Label__c, bb.Estimated_Cost_Per_Share__c
            );
        return buildCard(bb.Image_1_URL__c, leftBody, bb.Contact__r, ctaUrl);
    }

    private static String buildStoryCard(Story__c story) {
        String storyType = String.isNotBlank(story.Type__c) ? story.Type__c : 'Story';
        String badgeLabel = storyType == 'Neighbourhood Moment' ? 'NEIGHBOURHOOD' : storyType.toUpperCase();
        String ctaUrl = FimbySettings.getUrl('Story', story.Id);
        String body = String.isNotBlank(story.Message_Preview__c) ? story.Message_Preview__c : story.Message__c;

        String leftBody = badgeTitleRow(badgeLabel, storyType, story.Name, ctaUrl)
            + snippetRow(body);
        return buildCard(story.Image_URL__c, leftBody, story.Posted_By__r, ctaUrl);
    }

    private static String buildLibraryCard(Library_Item__c item) {
        String ctaUrl = FimbySettings.getUrl('Library_Item', item.Id);

        // Section heading already says "Library"; show the category as the single badge,
        // falling back to LIBRARY only when the item has no category.
        String badgeLabel = String.isNotBlank(item.Category__c) ? item.Category__c : 'LIBRARY';
        String leftBody = badgeTitleRow(badgeLabel, 'Library', item.Name, ctaUrl)
            + snippetRow(item.Description__c);
        return buildCard(item.Image_URL__c, leftBody, item.Owner_Contact__r, ctaUrl);
    }

    /* ---------------------------------------------------------------
     * Card Structure Helpers
     * --------------------------------------------------------------- */

    private static String openCard() {
        return '<table cellpadding="0" cellspacing="0" border="0" width="600" '
            + 'style="max-width:600px;width:100%;margin-bottom:12px;border-radius:8px;overflow:hidden;border:1px solid ' + BORDER_LIGHT + ';background-color:#FFFFFF;">';
    }

    /**
     * @description Assembles a compact feed card. The left column carries the badge + linked
     * title and the body snippet; the right column carries a fixed 140x120 cropped thumbnail
     * (both title and thumbnail link to the record). A shared full-width footer row carries the
     * avatar + first-name byline (left) and a single quiet "open ›" link (right) on one baseline,
     * so there is no per-type CTA button. Cards with no image collapse to a single column with
     * the same footer.
     */
    private static String buildCard(String imageUrl, String leftBodyHtml, SObject contactRef, String ctaUrl) {
        String imageCell = FimbyEmailHtmlBuilder.buildDigestImageCell(imageUrl, ctaUrl);
        String footer = bylineOpenFooter(contactRef, ctaUrl);

        if (String.isBlank(imageCell)) {
            return openCard()
                + '<tr><td style="padding:12px 16px 2px;">' + leftBodyHtml + '</td></tr>'
                + '<tr><td style="padding:0 16px 10px;">' + footer + '</td></tr>'
                + '</table>';
        }

        return openCard()
            + '<tr>'
            + '<td valign="top" style="padding:12px 6px 2px 16px;">' + leftBodyHtml + '</td>'
            + imageCell
            + '</tr>'
            + '<tr><td colspan="2" style="padding:0 16px 10px;">' + footer + '</td></tr>'
            + '</table>';
    }

    /**
     * @description Badge + linked title on one row. The badge is vertically centred against the
     * title and never wraps; the title is a link to the record (large, honest tap target).
     */
    private static String badgeTitleRow(String label, String typeKey, String title, String ctaUrl) {
        String badge = FimbyEmailHtmlBuilder.buildBadgePill(label,
            FimbyEmailHtmlBuilder.getBadgeColor(typeKey),
            FimbyEmailHtmlBuilder.getBadgeIcon(typeKey));
        String titleHtml = '';
        if (String.isNotBlank(title)) {
            titleHtml = '<a href="' + ctaUrl + '" style="' + FimbyEmailHtmlBuilder.F
                + 'font-size:16px;font-weight:700;color:' + TEXT_HEADING
                + ';text-decoration:none;vertical-align:middle;line-height:1.3;">' + escHtml(title) + '</a>';
        }
        return '<p style="margin:0 0 4px;line-height:1.3;">'
            + '<span style="white-space:nowrap;margin-right:8px;">' + badge + '</span>'
            + titleHtml + '</p>';
    }

    /**
     * @description Shared card footer: avatar + first-name byline on the left, a single quiet
     * "open ›" link on the right, both pointing at the record. First name only (per design) so
     * long full names never wrap the footer.
     */
    private static String bylineOpenFooter(SObject contactRef, String ctaUrl) {
        String leftHtml = '&nbsp;';
        if (contactRef != null) {
            String imageUrl = (String) contactRef.get('Display_Avatar_URL__c');
            String firstName = (String) contactRef.get('FirstName');
            leftHtml = FimbyEmailHtmlBuilder.buildAvatar(imageUrl, firstName, null)
                + '<span style="' + FimbyEmailHtmlBuilder.F + 'font-size:13px;color:' + TEXT_SECONDARY
                + ';vertical-align:middle;">' + escHtml(firstName) + '</span>';
        }
        String openHtml = '<a href="' + ctaUrl + '" style="' + FimbyEmailHtmlBuilder.F
            + 'font-size:13px;font-weight:700;letter-spacing:0.3px;color:' + CTA_BG
            + ';text-decoration:none;white-space:nowrap;">open &rsaquo;</a>';
        return '<table cellpadding="0" cellspacing="0" border="0" width="100%">'
            + '<tr>'
            + '<td style="vertical-align:middle;">' + leftHtml + '</td>'
            + '<td align="right" style="vertical-align:middle;">' + openHtml + '</td>'
            + '</tr></table>';
    }

    /**
     * @description Single event meta line: date · location · recurrence, in whatever combination
     * is present. Recurrence folds in here (lowercase) rather than a second badge so it never
     * stacks the header row on narrow phones.
     */
    private static String eventMetaLine(Date startDate, String location, String recurrenceWord) {
        List<String> parts = new List<String>();
        if (startDate != null) {
            Datetime dt = Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
            parts.add('&#128197; ' + dt.format('EEE, MMM d'));
        }
        if (String.isNotBlank(location)) {
            parts.add('&#128205; ' + escHtml(location));
        }
        if (String.isNotBlank(recurrenceWord)) {
            parts.add(escHtml(recurrenceWord));
        }
        if (parts.isEmpty()) { return ''; }
        return '<p style="margin:0 0 6px;' + FimbyEmailHtmlBuilder.F + 'font-size:13px;color:' + TEXT_SECONDARY + ';">'
            + String.join(parts, ' &middot; ') + '</p>';
    }

    private static String snippetRow(String description) {
        String snippet = truncate(description, SNIPPET_LENGTH);
        if (String.isBlank(snippet)) { return ''; }
        return '<p style="margin:0 0 6px;' + FimbyEmailHtmlBuilder.F + 'font-size:14px;color:' + TEXT_BODY + ';line-height:1.5;">'
            + escHtml(snippet) + '</p>';
    }

    private static String buildSectionHeader(String title, String accentColor) {
        return '<table cellpadding="0" cellspacing="0" border="0" width="600" style="max-width:600px;width:100%;margin-bottom:8px;margin-top:16px;">'
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
        String cut = text.substring(0, maxLen);
        Integer lastSpace = cut.lastIndexOf(' ');
        // Break on the last word boundary unless that would trim off more than ~20% of the
        // snippet (e.g. one very long token), in which case keep the hard cut.
        if (lastSpace > maxLen - (maxLen / 5)) {
            cut = cut.substring(0, lastSpace);
        }
        return cut.trim() + '\u2026';
    }

    private static String escHtml(String input) {
        return String.isBlank(input) ? '' : input.escapeHtml4();
    }

    private static Integer countItems(String html) {
        if (String.isBlank(html)) { return 0; }
        return html.countMatches('margin-bottom:12px;border-radius:8px');
    }

    /**
     * @description Capped mixed-type preview for the post-onboarding welcome email.
     * Round-robins across content types (asks/offers, events, bulk buys, stories, library)
     * so type diversity is prioritized when more than maxItems candidates exist.
     */
    public static DigestResult buildCappedMixedPreview(
        Id neighbourhoodId,
        Date windowStart,
        Date windowEnd,
        Integer maxItems,
        Set<Id> excludedAuthorContactIds
    ) {
        DigestResult result = new DigestResult();
        if (neighbourhoodId == null || maxItems == null || maxItems <= 0) {
            return result;
        }
        Set<Id> excluded = excludedAuthorContactIds != null ? excludedAuthorContactIds : new Set<Id>();
        Datetime startDt = Datetime.newInstance(windowStart, Time.newInstance(0, 0, 0, 0));
        Datetime endDt = Datetime.newInstance(windowEnd, Time.newInstance(23, 59, 59, 0));

        List<MixedPreviewItem> selected = selectMixedPreviewItems(
            neighbourhoodId, startDt, endDt, excluded, maxItems
        );
        if (selected.isEmpty()) {
            return result;
        }

        String html = buildSectionHeader('A peek at the last week on your street', EARTH_SAGE);
        for (MixedPreviewItem item : selected) {
            html += renderMixedPreviewItem(item);
            result.selectedItemSummaries.add(item.summaryLine);
        }
        result.html = html;
        result.itemCount = selected.size();
        result.isEmpty = false;
        return result;
    }

    private class MixedPreviewItem {
        String typeKey;
        String summaryLine;
        Needs_Offers__c needsOffer;
        Story__c story;
        Library_Item__c libraryItem;
    }

    private static List<MixedPreviewItem> selectMixedPreviewItems(
        Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded, Integer maxItems
    ) {
        Map<String, List<MixedPreviewItem>> buckets = new Map<String, List<MixedPreviewItem>>{
            'askOffer' => loadAskOfferPreviewItems(nhId, startDt, endDt, excluded),
            'event' => loadEventPreviewItems(nhId, startDt, endDt, excluded),
            'bulkBuy' => loadBulkBuyPreviewItems(nhId, startDt, endDt, excluded),
            'story' => loadStoryPreviewItems(nhId, startDt, endDt, excluded),
            'library' => loadLibraryPreviewItems(nhId, startDt, endDt, excluded)
        };
        List<String> typeOrder = new List<String>{
            'askOffer', 'event', 'bulkBuy', 'story', 'library'
        };
        Map<String, Integer> indices = new Map<String, Integer>{
            'askOffer' => 0, 'event' => 0, 'bulkBuy' => 0, 'story' => 0, 'library' => 0
        };

        List<MixedPreviewItem> selected = new List<MixedPreviewItem>();
        Boolean addedInPass = true;
        while (selected.size() < maxItems && addedInPass) {
            addedInPass = false;
            for (String typeKey : typeOrder) {
                List<MixedPreviewItem> bucket = buckets.get(typeKey);
                Integer idx = indices.get(typeKey);
                if (bucket == null || idx >= bucket.size()) {
                    continue;
                }
                selected.add(bucket[idx]);
                indices.put(typeKey, idx + 1);
                addedInPass = true;
                if (selected.size() >= maxItems) {
                    break;
                }
            }
        }
        return selected;
    }

    private static List<MixedPreviewItem> loadAskOfferPreviewItems(
        Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded
    ) {
        List<MixedPreviewItem> items = new List<MixedPreviewItem>();
        for (Needs_Offers__c post : [
            SELECT Id, Name, Details__c, Image_1_URL__c, Image_1_Ratio__c, Is_Urgent__c, Refresh_Count__c,
                   Contact__r.Name, Contact__r.Full_Name__c, Contact__r.FirstName,
                   Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c,
                   RecordType.DeveloperName, Posted_Date__c, CreatedDate
            FROM Needs_Offers__c
            WHERE Neighbourhood__c = :nhId
              AND RecordType.DeveloperName IN ('Need', 'Offer')
              AND Type__c != 'Event'
              AND Posted_Date__c >= :startDt AND Posted_Date__c <= :endDt
              AND Status__c IN ('Posted', 'Available', 'Reply Received')
              AND Contact__c NOT IN :excluded AND Posted_By__c NOT IN :excluded
            ORDER BY Posted_Date__c DESC
            LIMIT 10
        ]) {
            MixedPreviewItem item = new MixedPreviewItem();
            item.typeKey = 'askOffer';
            item.needsOffer = post;
            item.summaryLine = 'Ask/Offer: ' + post.Name;
            items.add(item);
        }
        return items;
    }

    /** Welcome-email mini-digest only — upcoming events by Start_Date, not digest CreatedDate window. */
    private static List<MixedPreviewItem> loadEventPreviewItems(
        Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded
    ) {
        Date today = Date.today();
        Set<Id> liveRecurringOccurrenceIds = resolveLiveRecurringOccurrenceIds(nhId);
        List<MixedPreviewItem> items = new List<MixedPreviewItem>();
        for (Needs_Offers__c evt : [
            SELECT Id, Name, Details__c, Image_1_URL__c, Image_1_Ratio__c,
                   Contact__r.Name, Contact__r.Full_Name__c, Contact__r.FirstName,
                   Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c,
                   Event_Type__c, Start_Date__c, End_Date__c, Location__c, CreatedDate,
                   Recurrence_Frequency__c, Recurrence_Interval__c, Series_Parent__c
            FROM Needs_Offers__c
            WHERE Neighbourhood__c = :nhId
              AND Type__c = 'Event'
              AND Status__c IN ('Posted', 'Available')
              AND Start_Date__c >= :today
              AND ((Recurrence_Frequency__c = null AND Series_Parent__c = null) OR Id IN :liveRecurringOccurrenceIds)
              AND Contact__c NOT IN :excluded AND Posted_By__c NOT IN :excluded
            ORDER BY Start_Date__c ASC
            LIMIT 10
        ]) {
            MixedPreviewItem item = new MixedPreviewItem();
            item.typeKey = 'event';
            item.needsOffer = evt;
            item.summaryLine = 'Event: ' + evt.Name;
            items.add(item);
        }
        return items;
    }

    private static List<MixedPreviewItem> loadBulkBuyPreviewItems(
        Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded
    ) {
        List<MixedPreviewItem> items = new List<MixedPreviewItem>();
        for (Needs_Offers__c bb : [
            SELECT Id, Name, Details__c, Image_1_URL__c, Image_1_Ratio__c,
                   Contact__r.Name, Contact__r.Full_Name__c, Contact__r.FirstName,
                   Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c,
                   Total_Quantity__c, Total_Reserved__c, Owner_Shares__c, Total_Available__c,
                   Allocation_Unit_Label__c, Estimated_Cost_Per_Share__c,
                   Posted_Date__c, CreatedDate
            FROM Needs_Offers__c
            WHERE Neighbourhood__c = :nhId
              AND RecordType.DeveloperName = 'Bulk_Buy'
              AND Posted_Date__c >= :startDt AND Posted_Date__c <= :endDt
              AND Status__c IN ('Posted', 'Available', 'Reply Received')
              AND Contact__c NOT IN :excluded AND Posted_By__c NOT IN :excluded
            ORDER BY Posted_Date__c DESC
            LIMIT 10
        ]) {
            MixedPreviewItem item = new MixedPreviewItem();
            item.typeKey = 'bulkBuy';
            item.needsOffer = bb;
            item.summaryLine = 'Bulk Buy: ' + bb.Name;
            items.add(item);
        }
        return items;
    }

    private static List<MixedPreviewItem> loadStoryPreviewItems(
        Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded
    ) {
        List<MixedPreviewItem> items = new List<MixedPreviewItem>();
        for (Story__c story : [
            SELECT Id, Name, Type__c, Message__c, Message_Preview__c, Image_URL__c,
                   Posted_By__r.Name, Posted_By__r.Full_Name__c, Posted_By__r.FirstName,
                   Posted_By__r.Image_URL__c, Posted_By__r.Display_Avatar_URL__c,
                   CreatedDate
            FROM Story__c
            WHERE Neighbourhood__c = :nhId
              AND CreatedDate >= :startDt AND CreatedDate <= :endDt
              AND Posted_By__c NOT IN :excluded
              AND Contact__c NOT IN :excluded
            ORDER BY CreatedDate DESC
            LIMIT 10
        ]) {
            MixedPreviewItem item = new MixedPreviewItem();
            item.typeKey = 'story';
            item.story = story;
            item.summaryLine = 'Shared Life: ' + story.Name;
            items.add(item);
        }
        return items;
    }

    private static List<MixedPreviewItem> loadLibraryPreviewItems(
        Id nhId, Datetime startDt, Datetime endDt, Set<Id> excluded
    ) {
        List<MixedPreviewItem> items = new List<MixedPreviewItem>();
        for (Library_Item__c lib : [
            SELECT Id, Name, Description__c, Image_URL__c, Image_Ratio__c, Category__c,
                   Owner_Contact__r.Name, Owner_Contact__r.Full_Name__c, Owner_Contact__r.FirstName,
                   Owner_Contact__r.Image_URL__c, Owner_Contact__r.Display_Avatar_URL__c,
                   CreatedDate
            FROM Library_Item__c
            WHERE Neighbourhood__c = :nhId
              AND CreatedDate >= :startDt AND CreatedDate <= :endDt
              AND Owner_Contact__c NOT IN :excluded
              AND Listed_By__c NOT IN :excluded
            ORDER BY CreatedDate DESC
            LIMIT 10
        ]) {
            MixedPreviewItem item = new MixedPreviewItem();
            item.typeKey = 'library';
            item.libraryItem = lib;
            item.summaryLine = 'Library: ' + lib.Name;
            items.add(item);
        }
        return items;
    }

    private static String renderMixedPreviewItem(MixedPreviewItem item) {
        if (item == null) {
            return '';
        }
        if (item.typeKey == 'story' && item.story != null) {
            return buildStoryCard(item.story);
        }
        if (item.typeKey == 'library' && item.libraryItem != null) {
            return buildLibraryCard(item.libraryItem);
        }
        if (item.needsOffer == null) {
            return '';
        }
        if (item.typeKey == 'askOffer') {
            return buildAskOfferCard(item.needsOffer);
        }
        if (item.typeKey == 'event') {
            return buildEventCard(item.needsOffer);
        }
        if (item.typeKey == 'bulkBuy') {
            return buildBulkBuyCard(item.needsOffer);
        }
        return '';
    }
}
