/**
 * @description Sends one neighbourhood's digest to every recipient cohort, one step per
 * queueable execution. FimbyDigestEmailBatch hands over an ordered list of cohorts (the
 * clean cohort with its pre-built HTML first, then blocked-author variants that are built
 * lazily when reached). Each execution handles a single step — one chunk of up to 50
 * recipients, one empty-variant skip, or one already-sent cohort — then enqueues at most
 * one successor. That keeps every async transaction inside Salesforce's one-enqueue limit.
 *
 * Per-cohort logging (one Digest_Email_Log__c per neighbourhood + cadence + window + variant):
 *   - Idempotency_Key__c is {NeighbourhoodId}_{Cadence}_{WindowDate}, plus a _v{hash}
 *     suffix for filtered cohorts.
 *   - On the first chunk we initialize the row with Email_Body_Preview__c, Recipient_Count__c
 *     and a base Status__c.
 *   - Each subsequent chunk appends successful recipient lines to Recipients__c, failed
 *     recipient lines to Failed_Recipients__c, and keeps Status__c at Partial.
 *   - The final Status__c (Sent / Partial / Failed) resolves on the cohort's last chunk.
 *
 * Skip-already-sent: a cohort whose row already has Status='Sent' is skipped. A row with
 * Status='Partial' or 'Failed' is resumed on a rerun, and per-chunk we skip users already
 * listed in Recipients__c.
 */
public without sharing class FimbyDigestEmailSendQueueable implements Queueable {

    private static final Integer CHUNK_SIZE = 50;
    private static final Integer MAX_HTML_PREVIEW_CHARS = 130000;
    private static final String HTML_TRUNCATION_MARKER = '\n\n[truncated for storage]';

    // Tests can drain the whole chain synchronously, because Apex tests cannot run
    // chained queueables.
    @TestVisible
    private static Boolean runInlineForTest = false;

    private Id neighbourhoodId;
    private String neighbourhoodName;
    private String frequency;
    private Date windowStart;
    private Date windowEnd;
    private List<DispatchCohort> cohorts;
    private Integer cohortIndex = 0;

    /**
     * @description One group of recipients who receive the same digest HTML.
     * variantKey is null for the clean cohort and the exclusion signature for filtered
     * cohorts. contentHtml is null until the sender builds it on reaching the cohort.
     */
    public class DispatchCohort {
        public List<Id> userIds;
        public Set<Id> excludedContactIds;
        public String variantKey;
        public String contentHtml;
        public Integer contentItemCount;

        public DispatchCohort(
            List<Id> userIds, Set<Id> excludedContactIds, String variantKey,
            String contentHtml, Integer contentItemCount
        ) {
            this.userIds = userIds;
            this.excludedContactIds = excludedContactIds;
            this.variantKey = variantKey;
            this.contentHtml = contentHtml;
            this.contentItemCount = contentItemCount;
        }
    }

    public FimbyDigestEmailSendQueueable(
        Id neighbourhoodId, String neighbourhoodName, String frequency,
        Date windowStart, Date windowEnd, String contentHtml, Integer contentItemCount,
        List<Id> userIds
    ) {
        this(
            neighbourhoodId, neighbourhoodName, frequency, windowStart, windowEnd,
            contentHtml, contentItemCount, userIds, null
        );
    }

    public FimbyDigestEmailSendQueueable(
        Id neighbourhoodId, String neighbourhoodName, String frequency,
        Date windowStart, Date windowEnd, String contentHtml, Integer contentItemCount,
        List<Id> userIds, String variantKey
    ) {
        this(
            neighbourhoodId, neighbourhoodName, frequency, windowStart, windowEnd,
            new List<DispatchCohort>{
                new DispatchCohort(userIds, null, variantKey, contentHtml, contentItemCount)
            }
        );
    }

    public FimbyDigestEmailSendQueueable(
        Id neighbourhoodId, String neighbourhoodName, String frequency,
        Date windowStart, Date windowEnd, List<DispatchCohort> cohorts
    ) {
        this.neighbourhoodId = neighbourhoodId;
        this.neighbourhoodName = neighbourhoodName;
        this.frequency = frequency;
        this.windowStart = windowStart;
        this.windowEnd = windowEnd != null ? windowEnd : windowStart;
        this.cohorts = cohorts != null ? cohorts : new List<DispatchCohort>();
    }

    /**
     * @description Starts a sender chain. In production this is one System.enqueueJob call.
     */
    public static void dispatch(FimbyDigestEmailSendQueueable job) {
        if (job == null) {
            return;
        }
        if (Test.isRunningTest() && runInlineForTest) {
            FimbyDigestEmailSendQueueable next = job;
            while (next != null) {
                next = next.processStep();
            }
            return;
        }
        System.enqueueJob(job);
    }

    public void execute(QueueableContext ctx) {
        FimbyDigestEmailSendQueueable next = processStep();
        if (next == null) {
            return;
        }
        try {
            System.enqueueJob(next);
        } catch (Exception e) {
            FimbyLogger.error('FimbyDigestEmailSendQueueable', 'chain', e);
        }
    }

    /**
     * @description Performs one step for the current cohort and returns the successor that
     * should run next, or null when every cohort is done.
     */
    @TestVisible
    private FimbyDigestEmailSendQueueable processStep() {
        if (cohortIndex >= cohorts.size()) {
            return null;
        }

        DispatchCohort cohort = cohorts[cohortIndex];
        if (cohort == null || cohort.userIds == null || cohort.userIds.isEmpty()) {
            return advance();
        }

        String idempotencyKey = buildIdempotencyKey(
            neighbourhoodId, frequency, windowStart, windowEnd, cohort.variantKey
        );
        Digest_Email_Log__c existingLog = loadExistingLog(idempotencyKey);

        if (existingLog != null && existingLog.Status__c == 'Sent') {
            return advance();
        }

        if (cohort.contentHtml == null) {
            FimbyDigestEmailBuilder.DigestResult built = FimbyDigestEmailBuilder.buildDigestContent(
                neighbourhoodId, neighbourhoodName,
                FimbyDigestEmailBatch.resolveBuilderCadence(frequency),
                windowStart, windowEnd, cohort.excludedContactIds
            );
            if (built.isEmpty) {
                writeSkippedLog(idempotencyKey, existingLog, built.itemCount);
                return advance();
            }
            cohort.contentHtml = built.html;
            cohort.contentItemCount = built.itemCount;
        }

        sendChunk(cohort, idempotencyKey, existingLog);

        return cohort.userIds.isEmpty() ? advance() : successor();
    }

    private FimbyDigestEmailSendQueueable advance() {
        if (cohortIndex < cohorts.size() && cohorts[cohortIndex] != null) {
            cohorts[cohortIndex].contentHtml = null;
        }
        cohortIndex++;
        return cohortIndex < cohorts.size() ? successor() : null;
    }

    private FimbyDigestEmailSendQueueable successor() {
        FimbyDigestEmailSendQueueable next = new FimbyDigestEmailSendQueueable(
            neighbourhoodId, neighbourhoodName, frequency, windowStart, windowEnd, cohorts
        );
        next.cohortIndex = cohortIndex;
        return next;
    }

    /**
     * @description Sends the next chunk of the cohort and removes it from cohort.userIds.
     */
    private void sendChunk(DispatchCohort cohort, String idempotencyKey, Digest_Email_Log__c existingLog) {
        Set<Id> alreadyDeliveredIds = parseUserIds(existingLog != null ? existingLog.Recipients__c : null);

        Integer chunkEnd = Math.min(CHUNK_SIZE, cohort.userIds.size());
        List<Id> currentChunk = new List<Id>();
        List<Id> remaining = new List<Id>();
        for (Integer i = 0; i < cohort.userIds.size(); i++) {
            Id uid = cohort.userIds[i];
            if (i >= chunkEnd) {
                remaining.add(uid);
            } else if (!alreadyDeliveredIds.contains(uid)) {
                // Drop users already delivered in this build (resume after Partial / Failed).
                currentChunk.add(uid);
            }
        }
        cohort.userIds = remaining;
        Boolean isFinalChunk = remaining.isEmpty();
        Boolean isFirstWrite = (existingLog == null);

        Id oweaId = getOweaId();
        if (oweaId == null) {
            // Pre-flight failure: log all chunk users as failures.
            Map<Id, String> firstNameByUser = new Map<Id, String>();
            Map<Id, String> lastNameByUser = new Map<Id, String>();
            loadUserNames(currentChunk, firstNameByUser, lastNameByUser);
            List<String> failureLines = new List<String>();
            for (Id uid : currentChunk) {
                failureLines.add(buildRecipientLine(uid, firstNameByUser.get(uid), lastNameByUser.get(uid)));
            }
            persistChunkResult(idempotencyKey, cohort, isFirstWrite, new List<String>(), failureLines, 'OWEA not found', isFinalChunk);
            return;
        }

        if (currentChunk.isEmpty()) {
            // Everyone in this chunk was already delivered in a prior run. On the final
            // chunk, close out the row so a Partial row becomes Sent.
            if (isFinalChunk) {
                finalizeStatus(idempotencyKey);
            }
            return;
        }

        Map<Id, String> firstNameByUser = new Map<Id, String>();
        Map<Id, String> lastNameByUser = new Map<Id, String>();
        loadUserNames(currentChunk, firstNameByUser, lastNameByUser);

        Boolean isSaturday = isSaturdayNow();
        String saturdayFooter = isSaturday
            ? '<p style="color:#6B6B6B;font-size:13px;font-style:italic;text-align:center;padding:12px 0;">Tomorrow\'s Sunday, so we\'ll be quiet. See you Monday.</p>'
            : '';

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Id> emailUserIds = new List<Id>();
        List<String> failureLines = new List<String>();

        for (Id userId : currentChunk) {
            try {
                String digestSubject = 'From the neighbourhood';
                String headerTitle = resolveDigestHeaderTitle(frequency, cohort.contentItemCount);
                String firstName = firstNameByUser.get(userId);
                String fullContent = cohort.contentHtml + saturdayFooter;

                String html = buildDigestHtml(fullContent, digestSubject, headerTitle, firstName);

                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(userId);
                email.setTreatTargetObjectAsRecipient(true);
                email.setSubject(digestSubject);
                email.setHtmlBody(html);
                email.setSaveAsActivity(false);
                email.setOrgWideEmailAddressId(oweaId);

                emails.add(email);
                emailUserIds.add(userId);
            } catch (Exception e) {
                failureLines.add(buildRecipientLine(userId, firstNameByUser.get(userId), lastNameByUser.get(userId)));
                FimbyLogger.error('FimbyDigestEmailSendQueueable', 'render', e, userId);
            }
        }

        List<String> successLines = new List<String>();
        if (!emails.isEmpty()) {
            try {
                List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
                for (Integer i = 0; i < results.size(); i++) {
                    Id uid = emailUserIds[i];
                    String line = buildRecipientLine(uid, firstNameByUser.get(uid), lastNameByUser.get(uid));
                    if (results[i].isSuccess()) {
                        successLines.add(line);
                    } else {
                        failureLines.add(line);
                    }
                }
            } catch (Exception e) {
                // Whole-batch send failed: every queued user is a failure.
                for (Id uid : emailUserIds) {
                    failureLines.add(buildRecipientLine(uid, firstNameByUser.get(uid), lastNameByUser.get(uid)));
                }
                FimbyLogger.error('FimbyDigestEmailSendQueueable', 'sendEmail', e);
            }
        }

        persistChunkResult(idempotencyKey, cohort, isFirstWrite, successLines, failureLines, null, isFinalChunk);
    }

    /* ---------------------------------------------------------------
     * Persistence — single DML per chunk, upsert by idempotency key
     * --------------------------------------------------------------- */

    private void persistChunkResult(
        String idempotencyKey, DispatchCohort cohort, Boolean isFirstWrite,
        List<String> successLines, List<String> failureLines,
        String preFlightError, Boolean isFinalChunk
    ) {
        Digest_Email_Log__c log = new Digest_Email_Log__c(
            Idempotency_Key__c = idempotencyKey
        );
        // External-id upsert needs the matching field; everything else gets re-queried/merged.
        Digest_Email_Log__c existing = loadExistingLog(idempotencyKey);
        if (existing != null) {
            log.Id = existing.Id;
            log.Recipients__c = existing.Recipients__c;
            log.Failed_Recipients__c = existing.Failed_Recipients__c;
            log.Recipient_Count__c = existing.Recipient_Count__c != null ? existing.Recipient_Count__c : 0;
            log.Email_Body_Preview__c = existing.Email_Body_Preview__c;
        } else {
            log.Recipient_Count__c = 0;
        }

        if (isFirstWrite) {
            log.Neighbourhood__c = neighbourhoodId;
            log.Cadence__c = resolveLogCadence(frequency);
            log.Window_Date__c = windowStart;
            log.Content_Item_Count__c = cohort.contentItemCount;
            log.Template_Version__c = 'FimbyEmailHtmlBuilder';
            log.Email_Body_Preview__c = truncateHtml(cohort.contentHtml);
        }

        if (!successLines.isEmpty()) {
            log.Recipients__c = appendLines(log.Recipients__c, successLines, 131072);
            Decimal current = log.Recipient_Count__c != null ? log.Recipient_Count__c : 0;
            log.Recipient_Count__c = current + successLines.size();
        }
        if (!failureLines.isEmpty()) {
            log.Failed_Recipients__c = appendLines(log.Failed_Recipients__c, failureLines, 32768);
        }
        if (String.isNotBlank(preFlightError)) {
            log.Error_Message__c = preFlightError.abbreviate(255);
        }

        log.Status__c = computeStatus(log, isFinalChunk, preFlightError);
        if (log.Status__c == 'Sent' && log.Sent_At__c == null) {
            log.Sent_At__c = Datetime.now();
        }

        Database.upsert(log, Digest_Email_Log__c.Idempotency_Key__c, false);
    }

    /**
     * @description Skipped row for a filtered cohort whose build came back empty (everything
     * was hidden by blocks). Never overwrites a row that already recorded sends.
     */
    private void writeSkippedLog(String idempotencyKey, Digest_Email_Log__c existingLog, Integer itemCount) {
        if (existingLog != null && existingLog.Status__c != 'Skipped') {
            return;
        }
        Digest_Email_Log__c log = new Digest_Email_Log__c(
            Neighbourhood__c = neighbourhoodId,
            Cadence__c = resolveLogCadence(frequency),
            Window_Date__c = windowStart,
            Status__c = 'Skipped',
            Recipient_Count__c = 0,
            Content_Item_Count__c = itemCount,
            Template_Version__c = 'FimbyEmailHtmlBuilder',
            Error_Message__c = FimbyDigestEmailBatch.SKIP_REASON_NO_CONTENT.abbreviate(255),
            Idempotency_Key__c = idempotencyKey
        );
        Database.upsert(log, Digest_Email_Log__c.Idempotency_Key__c, false);
    }

    /**
     * @description Recompute and persist the final status when the final chunk had nothing
     * new to send (everyone was already delivered in a prior run). No new lines, just
     * close out the row so a Partial row becomes Sent.
     */
    private void finalizeStatus(String idempotencyKey) {
        Digest_Email_Log__c existing = loadExistingLog(idempotencyKey);
        if (existing == null) { return; }
        String newStatus = computeStatus(existing, true, null);
        if (newStatus == existing.Status__c) { return; }
        existing.Status__c = newStatus;
        if (newStatus == 'Sent' && existing.Sent_At__c == null) {
            existing.Sent_At__c = Datetime.now();
        }
        Database.update(existing, false);
    }

    /**
     * @description Only a cohort's final chunk can resolve to Sent. A mid-run row stays
     * Partial so the successor chunk does not mistake it for a finished build and exit.
     */
    @TestVisible
    private static String computeStatus(Digest_Email_Log__c log, Boolean isFinalChunk, String preFlightError) {
        Boolean hasSuccess = String.isNotBlank(log.Recipients__c);
        Boolean hasFailure = String.isNotBlank(log.Failed_Recipients__c);

        if (!isFinalChunk) {
            if (hasSuccess || hasFailure) { return 'Partial'; }
            return 'Skipped';
        }
        if (String.isNotBlank(preFlightError) && !hasSuccess) {
            return 'Failed';
        }
        if (!hasSuccess && hasFailure) { return 'Failed'; }
        if (hasSuccess && hasFailure) { return 'Partial'; }
        if (hasSuccess && !hasFailure) { return 'Sent'; }
        return 'Skipped';
    }

    private Digest_Email_Log__c loadExistingLog(String idempotencyKey) {
        List<Digest_Email_Log__c> rows = [
            SELECT Id, Status__c, Recipients__c, Failed_Recipients__c,
                   Recipient_Count__c, Email_Body_Preview__c, Sent_At__c,
                   Idempotency_Key__c
            FROM Digest_Email_Log__c
            WHERE Idempotency_Key__c = :idempotencyKey
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /* ---------------------------------------------------------------
     * Helpers
     * --------------------------------------------------------------- */

    @TestVisible
    private Integer cohortIndexForTest() {
        return cohortIndex;
    }

    @TestVisible
    private List<DispatchCohort> cohortsForTest() {
        return cohorts;
    }

    private String appendLines(String existing, List<String> newLines, Integer maxLength) {
        String existingSafe = existing != null ? existing : '';
        String separator = String.isBlank(existingSafe) ? '' : '\n';
        String additions = String.join(newLines, '\n');
        String combined = existingSafe + separator + additions;
        if (combined.length() > maxLength) {
            return combined.substring(0, maxLength);
        }
        return combined;
    }

    private String buildRecipientLine(Id userId, String firstName, String lastName) {
        String safeFirst = stripNewlines(firstName != null ? firstName : '');
        String safeLast = stripNewlines(lastName != null ? lastName : '');
        String fullName = (safeFirst + ' ' + safeLast).trim();
        if (String.isBlank(fullName)) {
            fullName = '(unknown user)';
        }
        return fullName + ' - ' + String.valueOf(userId);
    }

    private String stripNewlines(String input) {
        if (String.isBlank(input)) { return ''; }
        return input.replace('\r', ' ').replace('\n', ' ');
    }

    private void loadUserNames(List<Id> ids, Map<Id, String> firstNames, Map<Id, String> lastNames) {
        if (ids == null || ids.isEmpty()) { return; }
        for (User u : [SELECT Id, FirstName, LastName FROM User WHERE Id IN :ids]) {
            firstNames.put(u.Id, u.FirstName);
            lastNames.put(u.Id, u.LastName);
        }
    }

    private Set<Id> parseUserIds(String recipientsBlob) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(recipientsBlob)) { return ids; }
        for (String line : recipientsBlob.split('\n')) {
            Integer dashIdx = line.lastIndexOf(' - ');
            if (dashIdx <= 0) { continue; }
            String idPart = line.substring(dashIdx + 3).trim();
            if (idPart.length() != 15 && idPart.length() != 18) { continue; }
            try {
                ids.add(Id.valueOf(idPart));
            } catch (Exception e) {
                // Malformed id token; skip.
            }
        }
        return ids;
    }

    @TestVisible
    private static String truncateHtml(String html) {
        if (html == null) { return ''; }
        if (html.length() <= MAX_HTML_PREVIEW_CHARS) { return html; }
        return html.substring(0, MAX_HTML_PREVIEW_CHARS) + HTML_TRUNCATION_MARKER;
    }

    private String buildDigestHtml(
        String content, String subject, String headerTitle, String recipientFirstName
    ) {
        // No in-body date range (the mail client already shows the received date) and no
        // rotating intent line for digests. The envelope subject and HTML <title> use the
        // short "From the neighbourhood" line; headerTitle drives the warmer in-body H1.
        return FimbyEmailHtmlBuilder.wrapInBrandedShell(
            content, subject, neighbourhoodName, null, false, false, recipientFirstName, true, headerTitle
        );
    }

    public static String buildIdempotencyKey(Id nhId, String freq, Date windowStartDt) {
        return buildIdempotencyKey(nhId, freq, windowStartDt, windowStartDt);
    }

    public static String buildIdempotencyKey(Id nhId, String freq, Date windowStartDt, Date windowEndDt) {
        if (freq == FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST) {
            return String.valueOf(nhId) + '_DailySundayRest_' + String.valueOf(windowStartDt);
        }
        return String.valueOf(nhId) + '_' + freq + '_' + String.valueOf(windowStartDt);
    }

    /**
     * @description Variant-aware idempotency key. For the shared/base cohort (variantKey blank)
     * this is identical to the 4-arg base key. For a filtered cohort it appends a deterministic
     * _v{hash} suffix so the variant's log row never collides with the base row or another
     * variant. The same suffix must be used for that cohort's Skipped log, sends, and resume,
     * or skip-already-sent / resume would re-resolve under the wrong key.
     */
    public static String buildIdempotencyKey(Id nhId, String freq, Date windowStartDt, Date windowEndDt, String variantKey) {
        String base = buildIdempotencyKey(nhId, freq, windowStartDt, windowEndDt);
        if (String.isBlank(variantKey)) {
            return base;
        }
        return base + '_v' + String.valueOf(Math.abs(variantKey.hashCode()));
    }

    @TestVisible
    private static String resolveDisplayFrequency(String freq) {
        if (freq == FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST) {
            return 'daily';
        }
        return freq != null ? freq.toLowerCase() : 'daily';
    }

    /**
     * @description In-body H1 scales with feed-card count so a single-post digest does not read
     * like a roundup. Daily and weekly cadences use the same 1 / 2 / 3+ pattern.
     */
    @TestVisible
    private static String resolveDigestHeaderTitle(String frequency, Integer itemCount) {
        Integer n = itemCount != null && itemCount > 0 ? itemCount : 3;
        Boolean weekly = resolveDisplayFrequency(frequency) == 'weekly';
        String timePhrase = weekly ? 'this week' : 'yesterday';
        if (n == 1) {
            return 'Something your neighbour shared ' + timePhrase;
        }
        if (n == 2) {
            return 'A couple things your neighbours shared ' + timePhrase;
        }
        return 'A few things your neighbours shared ' + timePhrase;
    }

    @TestVisible
    private static String resolveLogCadence(String freq) {
        return FimbyDigestEmailBatch.resolveLogCadence(freq);
    }

    private static Boolean isSaturdayNow() {
        Date today = Date.today();
        Datetime dt = Datetime.newInstance(today.year(), today.month(), today.day());
        String dayOfWeek = dt.format('u');
        return dayOfWeek == '6';
    }

    @TestVisible
    private static Boolean testOweaUnavailable = false;
    @TestVisible
    private static Id oweaCached;
    private static Id getOweaId() {
        if (Test.isRunningTest() && testOweaUnavailable) {
            return null;
        }
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
