/**
 * @description Sends digest emails in recipient chunks for one neighbourhood-build per
 * cadence per window date. Receives pre-built neighbourhood content HTML from
 * FimbyDigestEmailBatch, wraps content in the Apex branded shell per user, and sends.
 * Chains to process remaining recipients.
 *
 * Per-build logging (one Digest_Email_Log__c per neighbourhood + cadence + window):
 *   - Idempotency_Key__c is {NeighbourhoodId}_{Cadence}_{WindowDate} (no user component).
 *   - On the first chunk we initialize the row with Email_Body_Preview__c, Recipient_Count__c
 *     and a base Status__c.
 *   - Each subsequent chunk appends successful recipient lines to Recipients__c, failed
 *     recipient lines to Failed_Recipients__c, and updates Status__c provisionally.
 *   - The final Status__c (Sent / Partial / Failed) resolves on the last chunk.
 *
 * Skip-already-sent: if the build's row already exists with Status='Sent', the queueable
 * exits immediately. If it exists with Status='Partial' or 'Failed' a manual rerun appends
 * to the existing row, and per-chunk we skip users already listed in Recipients__c.
 */
public without sharing class FimbyDigestEmailSendQueueable implements Queueable {

    private static final Integer CHUNK_SIZE = 50;
    private static final Integer MAX_HTML_PREVIEW_CHARS = 130000;
    private static final String HTML_TRUNCATION_MARKER = '\n\n[truncated for storage]';
    private Id neighbourhoodId;
    private String neighbourhoodName;
    private String frequency;
    private Date windowStart;
    private Date windowEnd;
    private String contentHtml;
    private Integer contentItemCount;
    private List<Id> userIds;

    public FimbyDigestEmailSendQueueable(
        Id neighbourhoodId, String neighbourhoodName, String frequency,
        Date windowStart, Date windowEnd, String contentHtml, Integer contentItemCount,
        List<Id> userIds
    ) {
        this.neighbourhoodId = neighbourhoodId;
        this.neighbourhoodName = neighbourhoodName;
        this.frequency = frequency;
        this.windowStart = windowStart;
        this.windowEnd = windowEnd != null ? windowEnd : windowStart;
        this.contentHtml = contentHtml;
        this.contentItemCount = contentItemCount;
        this.userIds = userIds;
    }

    public void execute(QueueableContext ctx) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }

        String idempotencyKey = buildIdempotencyKey(neighbourhoodId, frequency, windowStart, windowEnd);
        Digest_Email_Log__c existingLog = loadExistingLog(idempotencyKey);

        // Build-level early exit: a fully successful build never reruns.
        if (existingLog != null && existingLog.Status__c == 'Sent') {
            return;
        }

        Set<Id> alreadyDeliveredIds = parseUserIds(existingLog != null ? existingLog.Recipients__c : null);

        Integer chunkEnd = Math.min(CHUNK_SIZE, userIds.size());
        List<Id> currentChunkAll = new List<Id>();
        for (Integer i = 0; i < chunkEnd; i++) {
            currentChunkAll.add(userIds[i]);
        }

        // Drop users already delivered in this build (resume after Partial / Failed).
        List<Id> currentChunk = new List<Id>();
        for (Id uid : currentChunkAll) {
            if (!alreadyDeliveredIds.contains(uid)) {
                currentChunk.add(uid);
            }
        }

        Id oweaId = getOweaId();

        Boolean isFirstWrite = (existingLog == null);
        if (oweaId == null) {
            // Pre-flight failure: log all chunk users as failures and bail.
            Map<Id, String> firstNameByUser = new Map<Id, String>();
            Map<Id, String> lastNameByUser = new Map<Id, String>();
            loadUserNames(currentChunk, firstNameByUser, lastNameByUser);
            List<String> failureLines = new List<String>();
            for (Id uid : currentChunk) {
                failureLines.add(buildRecipientLine(uid, firstNameByUser.get(uid), lastNameByUser.get(uid)));
            }
            persistChunkResult(idempotencyKey, isFirstWrite, new List<String>(), failureLines, 'OWEA not found', false);
            chainIfNeeded(chunkEnd);
            return;
        }

        if (currentChunk.isEmpty()) {
            // Everyone in this chunk was already delivered in a prior run; nothing to do
            // beyond resolving the final status on the final chunk.
            chainIfNeeded(chunkEnd);
            // If this was the final chunk, run a no-op persist so the row reflects an
            // unchanged state but the Sent/Partial/Failed status is finalized correctly.
            if (chunkEnd >= userIds.size()) {
                finalizeStatus(idempotencyKey);
            }
            return;
        }

        Map<Id, String> firstNameByUser = new Map<Id, String>();
        Map<Id, String> lastNameByUser = new Map<Id, String>();
        loadUserNames(currentChunk, firstNameByUser, lastNameByUser);

        String timeRange = buildTimeRange(frequency, windowStart, windowEnd);

        Boolean isSaturday = isSaturdayNow();
        String saturdayFooter = isSaturday
            ? '<p style="color:#6B6B6B;font-size:13px;font-style:italic;text-align:center;padding:12px 0;">Tomorrow\'s Sunday, so we\'ll be quiet. See you Monday.</p>'
            : '';

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Id> emailUserIds = new List<Id>();
        List<String> failureLines = new List<String>();

        for (Id userId : currentChunk) {
            try {
                String intentLine = FimbyEmailHtmlBuilder.getRandomIntentLine();
                String digestSubject = 'Your ' + resolveDisplayFrequency(frequency) + ' neighbourhood update';
                String firstName = firstNameByUser.get(userId);
                String fullContent = contentHtml + saturdayFooter;

                String html = buildDigestHtml(
                    fullContent, intentLine, digestSubject, timeRange, firstName
                );

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

        Boolean isFinalChunk = (chunkEnd >= userIds.size());
        persistChunkResult(idempotencyKey, isFirstWrite, successLines, failureLines, null, isFinalChunk);

        chainIfNeeded(chunkEnd);
    }

    /* ---------------------------------------------------------------
     * Persistence — single DML per chunk, upsert by idempotency key
     * --------------------------------------------------------------- */

    private void persistChunkResult(
        String idempotencyKey, Boolean isFirstWrite,
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
            log.Content_Item_Count__c = contentItemCount;
            log.Template_Version__c = 'FimbyEmailHtmlBuilder';
            log.Email_Body_Preview__c = truncateHtml(contentHtml);
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

    private String computeStatus(Digest_Email_Log__c log, Boolean isFinalChunk, String preFlightError) {
        Boolean hasSuccess = String.isNotBlank(log.Recipients__c);
        Boolean hasFailure = String.isNotBlank(log.Failed_Recipients__c);

        if (!isFinalChunk) {
            // Mid-run: optimistic "Partial" until proven otherwise. Failed recipients alone with no
            // successes yet still reads as "Partial" until the final chunk; if the build ends with
            // zero successes the final chunk demotes it to Failed.
            if (hasSuccess && !hasFailure) { return 'Sent'; }
            if (hasSuccess && hasFailure) { return 'Partial'; }
            if (!hasSuccess && hasFailure) { return 'Failed'; }
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
        String content, String intentLine, String subjectLine,
        String timeRange, String recipientFirstName
    ) {
        String bodyContent = content;
        if (String.isNotBlank(timeRange)) {
            bodyContent = '<p style="margin:0 0 12px;font-family:Verdana, Geneva, sans-serif;font-size:13px;color:#6B6B6B;">'
                + timeRange.escapeHtml4() + '</p>' + content;
        }
        return FimbyEmailHtmlBuilder.wrapInBrandedShell(
            bodyContent, subjectLine, neighbourhoodName, intentLine, false, false, recipientFirstName
        );
    }

    private void chainIfNeeded(Integer processedCount) {
        if (processedCount < userIds.size()) {
            List<Id> remaining = new List<Id>();
            for (Integer i = processedCount; i < userIds.size(); i++) {
                remaining.add(userIds[i]);
            }
            try {
                System.enqueueJob(new FimbyDigestEmailSendQueueable(
                    neighbourhoodId, neighbourhoodName, frequency,
                    windowStart, windowEnd, contentHtml, contentItemCount, remaining
                ));
            } catch (Exception e) {
                FimbyLogger.error('FimbyDigestEmailSendQueueable', 'chainIfNeeded', e);
            }
        }
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

    @TestVisible
    public static String buildTimeRange(String freq, Date startDt, Date endDt) {
        Date safeEnd = endDt != null ? endDt : startDt;
        if (freq == FimbyDigestEmailBatch.CADENCE_WEEKLY) {
            return startDt.format() + ' - ' + startDt.addDays(6).format();
        }
        if (safeEnd > startDt) {
            return startDt.format() + ' - ' + safeEnd.format();
        }
        return startDt.format();
    }

    @TestVisible
    private static String resolveDisplayFrequency(String freq) {
        if (freq == FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST) {
            return 'daily';
        }
        return freq != null ? freq.toLowerCase() : 'daily';
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
