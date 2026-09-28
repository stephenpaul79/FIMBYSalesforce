/**
 * @description Sends the monthly Library email for one neighbourhood, one chunk of up to 50
 * recipients per execution, then enqueues at most one successor for the rest. Each async
 * transaction therefore stays inside Salesforce's one-enqueue limit.
 *
 * Within a chunk, recipients are grouped by what they are allowed to see: their
 * bidirectional blocks plus the adjacent-neighbourhood owners who currently share contact
 * info with them. Each group gets one render, sized so the fully wrapped email stays under
 * EMAIL_BYTE_CAP for the longest first name in that group.
 *
 * Logging: one Digest_Email_Log__c per neighbourhood per month (Cadence = Monthly). It stays
 * Partial while recipients remain and resolves to Sent / Partial / Failed on the final chunk.
 * A rerun skips users already listed in Recipients__c, and a Sent row stops the chain.
 */
public without sharing class FimbyMonthlyDirectorySendQueueable implements Queueable {

    public static final String SUBJECT = 'Your neighbourhood Library \u2014 Items & Skills';
    public static final String HEADER_TITLE = 'Items to borrow and skills on offer';
    public static final Integer EMAIL_BYTE_CAP = 95 * 1024;

    private static final Integer CHUNK_SIZE = 50;
    private static final Integer MAX_HTML_PREVIEW_CHARS = 130000;
    private static final String TEMPLATE_VERSION = 'FimbyMonthlyDirectoryEmailBuilder';

    // Tests can drain the whole chain synchronously, because Apex tests cannot run
    // chained queueables.
    @TestVisible
    private static Boolean runInlineForTest = false;
    @TestVisible
    private static Boolean testOweaUnavailable = false;
    @TestVisible
    private static Id oweaCached;

    private Id neighbourhoodId;
    private String neighbourhoodName;
    private Date windowDate;
    private List<Id> userIds;

    public class RenderedEmail {
        public Id userId;
        public String html;
        public Integer totalBytes;
        public FimbyMonthlyDirectoryEmailBuilder.DirectoryResult result;
    }

    public FimbyMonthlyDirectorySendQueueable(
        Id neighbourhoodId, String neighbourhoodName, Date windowDate, List<Id> userIds
    ) {
        this.neighbourhoodId = neighbourhoodId;
        this.neighbourhoodName = neighbourhoodName;
        this.windowDate = windowDate;
        this.userIds = userIds != null ? userIds : new List<Id>();
    }

    public static void dispatch(FimbyMonthlyDirectorySendQueueable job) {
        if (job == null) {
            return;
        }
        if (Test.isRunningTest() && runInlineForTest) {
            FimbyMonthlyDirectorySendQueueable next = job;
            while (next != null) {
                next = next.processStep();
            }
            return;
        }
        System.enqueueJob(job);
    }

    public void execute(QueueableContext ctx) {
        FimbyMonthlyDirectorySendQueueable next = processStep();
        if (next == null) {
            return;
        }
        try {
            System.enqueueJob(next);
        } catch (Exception e) {
            FimbyLogger.error('FimbyMonthlyDirectorySendQueueable', 'chain', e, neighbourhoodId);
        }
    }

    /**
     * @description Sends one chunk and returns the successor for the remaining recipients,
     * or null when the neighbourhood is done.
     */
    @TestVisible
    private FimbyMonthlyDirectorySendQueueable processStep() {
        if (userIds.isEmpty()) {
            return null;
        }

        String idempotencyKey = FimbyMonthlyDirectoryBatch.buildIdempotencyKey(neighbourhoodId, windowDate);
        Digest_Email_Log__c existingLog = loadExistingLog(idempotencyKey);
        if (existingLog != null && existingLog.Status__c == 'Sent') {
            return null;
        }

        Set<Id> alreadyDelivered = parseUserIds(existingLog != null ? existingLog.Recipients__c : null);
        Integer chunkEnd = Math.min(CHUNK_SIZE, userIds.size());
        List<Id> chunk = new List<Id>();
        List<Id> remaining = new List<Id>();
        for (Integer i = 0; i < userIds.size(); i++) {
            if (i >= chunkEnd) {
                remaining.add(userIds[i]);
            } else if (!alreadyDelivered.contains(userIds[i])) {
                chunk.add(userIds[i]);
            }
        }
        Boolean isFinalChunk = remaining.isEmpty();
        Boolean isFirstWrite = existingLog == null;

        if (chunk.isEmpty()) {
            if (isFinalChunk) {
                finalizeStatus(idempotencyKey);
            }
            return successor(remaining);
        }

        List<User> users = [SELECT Id, FirstName, LastName, ContactId FROM User WHERE Id IN :chunk];
        List<String> successLines = new List<String>();
        List<String> failureLines = new List<String>();

        Id oweaId = getOweaId();
        if (oweaId == null) {
            for (User u : users) {
                failureLines.add(buildRecipientLine(u));
            }
            persistChunkResult(idempotencyKey, isFirstWrite, successLines, failureLines,
                'OWEA not found', isFinalChunk, null, null);
            return successor(remaining);
        }

        FimbyMonthlyDirectoryEmailBuilder.Directory directory =
            FimbyMonthlyDirectoryEmailBuilder.loadDirectory(neighbourhoodId);
        Map<Id, RenderedEmail> renderedByUser = renderForUsers(directory, neighbourhoodName, users);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<User> emailUsers = new List<User>();
        String previewHtml = null;
        for (User u : users) {
            RenderedEmail rendered = renderedByUser.get(u.Id);
            if (rendered == null) {
                failureLines.add(buildRecipientLine(u));
                continue;
            }
            if (previewHtml == null) {
                previewHtml = rendered.html;
            }
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(u.Id);
            email.setTreatTargetObjectAsRecipient(true);
            email.setSubject(SUBJECT);
            email.setHtmlBody(rendered.html);
            email.setSaveAsActivity(false);
            email.setOrgWideEmailAddressId(oweaId);
            emails.add(email);
            emailUsers.add(u);
        }

        if (!emails.isEmpty()) {
            try {
                List<Messaging.SendEmailResult> results = Messaging.sendEmail(emails, false);
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        successLines.add(buildRecipientLine(emailUsers[i]));
                    } else {
                        failureLines.add(buildRecipientLine(emailUsers[i]));
                    }
                }
            } catch (Exception e) {
                for (User u : emailUsers) {
                    failureLines.add(buildRecipientLine(u));
                }
                FimbyLogger.error('FimbyMonthlyDirectorySendQueueable', 'sendEmail', e, neighbourhoodId);
            }
        }

        persistChunkResult(idempotencyKey, isFirstWrite, successLines, failureLines,
            null, isFinalChunk, previewHtml, directory.totalCount());
        return successor(remaining);
    }

    private FimbyMonthlyDirectorySendQueueable successor(List<Id> remaining) {
        if (remaining.isEmpty()) {
            return null;
        }
        return new FimbyMonthlyDirectorySendQueueable(neighbourhoodId, neighbourhoodName, windowDate, remaining);
    }

    /* ---------------------------------------------------------------
     * Rendering — shared by the scheduled send and the test script
     * --------------------------------------------------------------- */

    /**
     * @description Builds the exact email one recipient would get this month, applying their
     * blocks and adjacent-neighbourhood visibility. Used by the manual test-send script;
     * writes nothing.
     */
    public static RenderedEmail previewForRecipient(Id neighbourhoodId, String neighbourhoodName, Id userId) {
        List<User> users = [SELECT Id, FirstName, LastName, ContactId FROM User WHERE Id = :userId];
        if (users.isEmpty()) {
            return null;
        }
        FimbyMonthlyDirectoryEmailBuilder.Directory directory =
            FimbyMonthlyDirectoryEmailBuilder.loadDirectory(neighbourhoodId);
        return renderForUsers(directory, neighbourhoodName, users).get(userId);
    }

    @TestVisible
    private static Map<Id, RenderedEmail> renderForUsers(
        FimbyMonthlyDirectoryEmailBuilder.Directory directory, String neighbourhoodName, List<User> users
    ) {
        Map<Id, RenderedEmail> renderedByUser = new Map<Id, RenderedEmail>();
        Set<Id> contactIds = new Set<Id>();
        for (User u : users) {
            if (u.ContactId != null) {
                contactIds.add(u.ContactId);
            }
        }

        Map<Id, Set<Id>> blocksByContact = loadBidirectionalBlocks(contactIds);
        Set<Id> adjacentOwners = directory.adjacentOwnerIds();
        Map<Id, Set<Id>> sharersByContact = adjacentOwners.isEmpty()
            ? new Map<Id, Set<Id>>()
            : FimbySharedContactAccess.getActiveIncomingSharerIdsByRecipient(contactIds);

        Map<String, List<User>> usersBySignature = new Map<String, List<User>>();
        Map<String, Set<Id>> exclusionBySignature = new Map<String, Set<Id>>();
        Map<String, Set<Id>> sharersBySignature = new Map<String, Set<Id>>();
        for (User u : users) {
            Set<Id> excluded = blocksByContact.containsKey(u.ContactId)
                ? blocksByContact.get(u.ContactId) : new Set<Id>();
            Set<Id> relevantSharers = new Set<Id>();
            if (sharersByContact.containsKey(u.ContactId)) {
                relevantSharers.addAll(sharersByContact.get(u.ContactId));
                relevantSharers.retainAll(adjacentOwners);
            }
            String signature = joinSorted(excluded) + '|' + joinSorted(relevantSharers);
            if (!usersBySignature.containsKey(signature)) {
                usersBySignature.put(signature, new List<User>());
                exclusionBySignature.put(signature, excluded);
                sharersBySignature.put(signature, relevantSharers);
            }
            usersBySignature.get(signature).add(u);
        }

        for (String signature : usersBySignature.keySet()) {
            List<User> cohort = usersBySignature.get(signature);
            String longestName = '';
            for (User u : cohort) {
                String name = u.FirstName != null ? u.FirstName : '';
                if (Blob.valueOf(name.escapeHtml4()).size() > Blob.valueOf(longestName.escapeHtml4()).size()) {
                    longestName = name;
                }
            }

            FimbyMonthlyDirectoryEmailBuilder.DirectoryResult result = renderWithinCap(
                directory, neighbourhoodName, exclusionBySignature.get(signature),
                sharersBySignature.get(signature), longestName
            );

            for (User u : cohort) {
                RenderedEmail rendered = new RenderedEmail();
                rendered.userId = u.Id;
                rendered.result = result;
                rendered.html = wrap(result.html, neighbourhoodName, u.FirstName);
                rendered.totalBytes = FimbyMonthlyDirectoryEmailBuilder.byteSize(rendered.html);
                renderedByUser.put(u.Id, rendered);
            }
        }
        return renderedByUser;
    }

    /**
     * @description Gives the builder whatever the shell leaves of EMAIL_BYTE_CAP, then checks
     * the fully wrapped result and tightens once more if the estimate was short.
     */
    private static FimbyMonthlyDirectoryEmailBuilder.DirectoryResult renderWithinCap(
        FimbyMonthlyDirectoryEmailBuilder.Directory directory, String neighbourhoodName,
        Set<Id> excluded, Set<Id> sharers, String longestFirstName
    ) {
        Integer shellBytes = FimbyMonthlyDirectoryEmailBuilder.byteSize(wrap('', neighbourhoodName, longestFirstName));
        Integer budget = EMAIL_BYTE_CAP - shellBytes;
        FimbyMonthlyDirectoryEmailBuilder.DirectoryResult result =
            FimbyMonthlyDirectoryEmailBuilder.render(directory, excluded, sharers, budget);
        Integer overage = FimbyMonthlyDirectoryEmailBuilder.byteSize(
            wrap(result.html, neighbourhoodName, longestFirstName)
        ) - EMAIL_BYTE_CAP;
        if (overage > 0) {
            result = FimbyMonthlyDirectoryEmailBuilder.render(directory, excluded, sharers, budget - overage - 512);
        }
        return result;
    }

    private static String wrap(String innerHtml, String neighbourhoodName, String firstName) {
        return FimbyEmailHtmlBuilder.wrapInBrandedShell(
            innerHtml, SUBJECT, neighbourhoodName, null, false, false, firstName, true, HEADER_TITLE, true
        );
    }

    private static String joinSorted(Set<Id> ids) {
        List<String> values = new List<String>();
        for (Id value : ids) {
            values.add(String.valueOf(value));
        }
        values.sort();
        return String.join(values, ',');
    }

    /**
     * @description Batched bidirectional block lookup: if A blocks B, A hides B and B hides A.
     */
    private static Map<Id, Set<Id>> loadBidirectionalBlocks(Set<Id> contactIds) {
        Map<Id, Set<Id>> blocksByContact = new Map<Id, Set<Id>>();
        if (contactIds.isEmpty()) {
            return blocksByContact;
        }
        for (Blocked_Contact__c bc : [
            SELECT Blocker__c, Blocked__c
            FROM Blocked_Contact__c
            WHERE Blocker__c IN :contactIds OR Blocked__c IN :contactIds
        ]) {
            if (bc.Blocker__c == null || bc.Blocked__c == null) {
                continue;
            }
            if (contactIds.contains(bc.Blocker__c)) {
                addBlock(blocksByContact, bc.Blocker__c, bc.Blocked__c);
            }
            if (contactIds.contains(bc.Blocked__c)) {
                addBlock(blocksByContact, bc.Blocked__c, bc.Blocker__c);
            }
        }
        return blocksByContact;
    }

    private static void addBlock(Map<Id, Set<Id>> blocksByContact, Id viewer, Id hidden) {
        if (!blocksByContact.containsKey(viewer)) {
            blocksByContact.put(viewer, new Set<Id>());
        }
        blocksByContact.get(viewer).add(hidden);
    }

    /* ---------------------------------------------------------------
     * Persistence — single DML per chunk, upsert by idempotency key
     * --------------------------------------------------------------- */

    private void persistChunkResult(
        String idempotencyKey, Boolean isFirstWrite,
        List<String> successLines, List<String> failureLines,
        String preFlightError, Boolean isFinalChunk, String previewHtml, Integer contentCount
    ) {
        Digest_Email_Log__c log = new Digest_Email_Log__c(Idempotency_Key__c = idempotencyKey);
        Digest_Email_Log__c existing = loadExistingLog(idempotencyKey);
        if (existing != null) {
            log.Id = existing.Id;
            log.Recipients__c = existing.Recipients__c;
            log.Failed_Recipients__c = existing.Failed_Recipients__c;
            log.Recipient_Count__c = existing.Recipient_Count__c != null ? existing.Recipient_Count__c : 0;
        } else {
            log.Recipient_Count__c = 0;
        }

        if (isFirstWrite) {
            log.Neighbourhood__c = neighbourhoodId;
            log.Cadence__c = FimbyMonthlyDirectoryBatch.CADENCE_MONTHLY;
            log.Window_Date__c = windowDate;
            log.Template_Version__c = TEMPLATE_VERSION;
        }
        if (contentCount != null) {
            log.Content_Item_Count__c = contentCount;
        }
        if (String.isNotBlank(previewHtml) && (existing == null || String.isBlank(existing.Email_Body_Preview__c))) {
            log.Email_Body_Preview__c = previewHtml.length() > MAX_HTML_PREVIEW_CHARS
                ? previewHtml.substring(0, MAX_HTML_PREVIEW_CHARS)
                : previewHtml;
        }

        if (!successLines.isEmpty()) {
            log.Recipients__c = appendLines(log.Recipients__c, successLines, 131072);
            log.Recipient_Count__c = log.Recipient_Count__c + successLines.size();
        }
        if (!failureLines.isEmpty()) {
            log.Failed_Recipients__c = appendLines(log.Failed_Recipients__c, failureLines, 32768);
        }
        if (String.isNotBlank(preFlightError)) {
            log.Error_Message__c = preFlightError.abbreviate(255);
        }

        log.Status__c = computeStatus(log, isFinalChunk, preFlightError);
        if (log.Status__c == 'Sent' && (existing == null || existing.Sent_At__c == null)) {
            log.Sent_At__c = Datetime.now();
        }
        Database.upsert(log, Digest_Email_Log__c.Idempotency_Key__c, false);
    }

    private void finalizeStatus(String idempotencyKey) {
        Digest_Email_Log__c existing = loadExistingLog(idempotencyKey);
        if (existing == null) {
            return;
        }
        String newStatus = computeStatus(existing, true, null);
        if (newStatus == existing.Status__c) {
            return;
        }
        existing.Status__c = newStatus;
        if (newStatus == 'Sent' && existing.Sent_At__c == null) {
            existing.Sent_At__c = Datetime.now();
        }
        Database.update(existing, false);
    }

    /**
     * @description Only the final chunk can resolve to Sent. A mid-run row stays Partial so
     * the successor does not mistake it for a finished send and exit.
     */
    @TestVisible
    private static String computeStatus(Digest_Email_Log__c log, Boolean isFinalChunk, String preFlightError) {
        Boolean hasSuccess = String.isNotBlank(log.Recipients__c);
        Boolean hasFailure = String.isNotBlank(log.Failed_Recipients__c);
        if (!isFinalChunk) {
            return (hasSuccess || hasFailure) ? 'Partial' : 'Skipped';
        }
        if (String.isNotBlank(preFlightError) && !hasSuccess) { return 'Failed'; }
        if (!hasSuccess && hasFailure) { return 'Failed'; }
        if (hasSuccess && hasFailure) { return 'Partial'; }
        if (hasSuccess) { return 'Sent'; }
        return 'Skipped';
    }

    private static Digest_Email_Log__c loadExistingLog(String idempotencyKey) {
        List<Digest_Email_Log__c> rows = [
            SELECT Id, Status__c, Recipients__c, Failed_Recipients__c,
                   Recipient_Count__c, Email_Body_Preview__c, Sent_At__c
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
    private List<Id> userIdsForTest() {
        return userIds;
    }

    private static String appendLines(String existing, List<String> newLines, Integer maxLength) {
        String existingSafe = existing != null ? existing : '';
        String separator = String.isBlank(existingSafe) ? '' : '\n';
        String combined = existingSafe + separator + String.join(newLines, '\n');
        return combined.length() > maxLength ? combined.substring(0, maxLength) : combined;
    }

    private static String buildRecipientLine(User u) {
        String fullName = ((u.FirstName != null ? u.FirstName : '') + ' '
            + (u.LastName != null ? u.LastName : '')).replace('\r', ' ').replace('\n', ' ').trim();
        return (String.isBlank(fullName) ? '(unknown user)' : fullName) + ' - ' + String.valueOf(u.Id);
    }

    private static Set<Id> parseUserIds(String recipientsBlob) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(recipientsBlob)) {
            return ids;
        }
        for (String line : recipientsBlob.split('\n')) {
            Integer dashIdx = line.lastIndexOf(' - ');
            if (dashIdx <= 0) {
                continue;
            }
            String idPart = line.substring(dashIdx + 3).trim();
            if (idPart.length() != 15 && idPart.length() != 18) {
                continue;
            }
            try {
                ids.add(Id.valueOf(idPart));
            } catch (Exception e) {
                // Malformed id token; skip.
            }
        }
        return ids;
    }

    private static Id getOweaId() {
        if (Test.isRunningTest() && testOweaUnavailable) {
            return null;
        }
        if (oweaCached == null) {
            List<OrgWideEmailAddress> oweas = [
                SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = 'FIMBY' LIMIT 1
            ];
            oweaCached = oweas.isEmpty() ? null : oweas[0].Id;
        }
        return oweaCached;
    }
}
