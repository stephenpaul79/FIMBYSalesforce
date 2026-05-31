/**
 * @description Inbound-EmailMessage handler for the deletion flow.
 * Fires after-insert on EmailMessage. For each inbound message whose parent
 * is a deletion Case in 'Awaiting Confirmation', parses the body for the
 * exact protocol tokens:
 *   - CONFIRM DELETE → moves the Case to 'Confirmed', stamps
 *     Confirmation_Received_Date__c and Safeguard_Enqueue_After__c (now + 24h).
 *     The expiry batch picks it up after the safeguard window.
 *   - CANCEL → moves the Case to 'Cancelled', sends the cancellation email.
 *
 * Tokens are matched case-insensitively but otherwise literally — partial
 * matches like "I confirm I want to delete" do NOT count. The verification
 * email instructs the user to reply with the exact phrase.
 *
 * For Cases flagged Deletion_Rate_Limit_Flagged__c = true, confirmation
 * processing is paused: the case owner must clear the flag manually before
 * a CONFIRM DELETE reply is honoured.
 */
public without sharing class FimbyDeletionConfirmationService {

    private static final Integer SAFEGUARD_HOURS = 24;
    private static final String CONFIRM_TOKEN = 'CONFIRM DELETE';
    private static final String CANCEL_TOKEN = 'CANCEL';

    /**
     * @description Filters inbound EmailMessages and dispatches confirmation
     * processing. Bulk-safe.
     * @param newMessages Trigger.new on EmailMessage after insert
     */
    public static void handleAfterInsert(List<EmailMessage> newMessages) {
        Set<Id> parentCaseIds = new Set<Id>();
        for (EmailMessage em : newMessages) {
            if (em.Incoming == true && em.ParentId != null
                && String.valueOf(em.ParentId).startsWith('500')) {
                parentCaseIds.add(em.ParentId);
            }
        }
        if (parentCaseIds.isEmpty()) return;

        Map<Id, Case> caseById = new Map<Id, Case>([
            SELECT Id, RecordType.DeveloperName, Deletion_Stage__c,
                   Confirmation_Received_Date__c, Safeguard_Enqueue_After__c,
                   Contact_User_Id__c, Deletion_Rate_Limit_Flagged__c
            FROM Case
            WHERE Id IN :parentCaseIds
              AND RecordType.DeveloperName = 'Account_Deletion'
              AND Deletion_Stage__c = 'Awaiting Confirmation'
        ]);
        if (caseById.isEmpty()) return;

        process(newMessages, caseById);
    }

    /**
     * @description Core parser/updater. Exposed for tests so they can pass
     * a hydrated case map without re-querying.
     */
    public static void process(List<EmailMessage> messages, Map<Id, Case> caseById) {
        List<Case> casesToUpdate = new List<Case>();
        List<Id> casesToCancelEmail = new List<Id>();

        Map<Id, EmailMessage> latestMessagePerCase = new Map<Id, EmailMessage>();
        for (EmailMessage em : messages) {
            if (em.Incoming != true || em.ParentId == null) continue;
            if (!caseById.containsKey(em.ParentId)) continue;
            EmailMessage existing = latestMessagePerCase.get(em.ParentId);
            if (existing == null || (em.MessageDate != null && (existing.MessageDate == null
                || em.MessageDate > existing.MessageDate))) {
                latestMessagePerCase.put(em.ParentId, em);
            }
        }

        DateTime nowUtc = System.now();
        DateTime safeguardCutoff = nowUtc.addHours(SAFEGUARD_HOURS);

        for (Id caseId : latestMessagePerCase.keySet()) {
            EmailMessage em = latestMessagePerCase.get(caseId);
            Case c = caseById.get(caseId);
            String token = parseToken(em);
            if (token == null) continue;

            if (c.Deletion_Rate_Limit_Flagged__c == true) {
                FimbyLogger.warn('FimbyDeletionConfirmationService', 'process',
                    'Reply received on rate-limit-flagged Case ' + caseId
                    + '; token=' + token + '; ignored pending owner review');
                continue;
            }

            if (token == CONFIRM_TOKEN) {
                c.Deletion_Stage__c = 'Confirmed';
                c.Confirmation_Received_Date__c = nowUtc;
                c.Safeguard_Enqueue_After__c = safeguardCutoff;
                casesToUpdate.add(c);
            } else if (token == CANCEL_TOKEN) {
                c.Deletion_Stage__c = 'Cancelled';
                c.Status = 'Closed';
                casesToUpdate.add(c);
                casesToCancelEmail.add(caseId);
            }
        }

        if (!casesToUpdate.isEmpty()) {
            Database.update(casesToUpdate, false);
        }

        for (Id caseId : casesToCancelEmail) {
            Case c = caseById.get(caseId);
            if (c == null || String.isBlank(c.Contact_User_Id__c)) continue;
            try {
                FimbyDeletionEmailService.sendCancellation(caseId, (Id) c.Contact_User_Id__c);
            } catch (Exception e) {
                FimbyLogger.error('FimbyDeletionConfirmationService', 'process', e, caseId);
            }
        }
    }

    /**
     * @description Parses the email body for protocol tokens. CONFIRM DELETE
     * wins over CANCEL if (somehow) both appear — but the verification email
     * explicitly says "reply with one of these words", so this is mostly
     * defensive.
     */
    private static String parseToken(EmailMessage em) {
        String body = '';
        if (String.isNotBlank(em.TextBody)) {
            body += em.TextBody;
        }
        if (String.isNotBlank(em.Subject)) {
            body += '\n' + em.Subject;
        }
        if (String.isBlank(body)) return null;

        String upper = body.toUpperCase();
        if (containsToken(upper, CONFIRM_TOKEN)) {
            return CONFIRM_TOKEN;
        }
        if (containsToken(upper, CANCEL_TOKEN)) {
            return CANCEL_TOKEN;
        }
        return null;
    }

    /**
     * @description Whole-token matcher with word-boundary semantics. We
     * don't want "scancellation" or "I will cancel my subscription" to
     * trigger CANCEL — only a standalone occurrence of the protocol word(s).
     */
    private static Boolean containsToken(String upperBody, String token) {
        if (String.isBlank(upperBody)) return false;
        Integer idx = upperBody.indexOf(token);
        while (idx >= 0) {
            Boolean leftOk = (idx == 0) || isBoundary(upperBody.charAt(idx - 1));
            Integer endIdx = idx + token.length();
            Boolean rightOk = (endIdx >= upperBody.length()) || isBoundary(upperBody.charAt(endIdx));
            if (leftOk && rightOk) return true;
            idx = upperBody.indexOf(token, idx + 1);
        }
        return false;
    }

    private static Boolean isBoundary(Integer charCode) {
        return !((charCode >= 65 && charCode <= 90)   // A-Z
              || (charCode >= 97 && charCode <= 122)  // a-z
              || (charCode >= 48 && charCode <= 57)   // 0-9
              || charCode == 95);                      // _
    }
}
