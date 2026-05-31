/**
 * @description Intake handler for new Email-to-Case deletion requests.
 * Runs after-insert on Case for records whose RecordType is Account_Deletion.
 *
 * Steps for each new deletion Case:
 *   1. Resolve the active User behind Case.ContactId. If the sender's email
 *      didn't match a Contact, skip — Email-to-Case only sets ContactId on
 *      auto-match, so a missing ContactId means the sender isn't a known
 *      neighbour. Send a polite "no account found" reply.
 *   2. Detect rate-limit abuse: more than 3 deletion Cases for the same
 *      ContactId in 24h. If flagged, mark all matching Cases (this one and
 *      the prior set) and stop — do NOT send the verification email. The
 *      Account Deletion queue owner reviews these manually.
 *   3. Otherwise, send the verification email to User.Email, set
 *      Deletion_Stage__c = 'Awaiting Confirmation', stamp
 *      Confirmation_Sent_Date__c.
 *
 * Threaded back to the Case via Messaging.SingleEmailMessage.setWhatId so
 * that Email-to-Case Thread Email Headers append the user's reply to the
 * same Case (which the EmailMessage trigger then picks up).
 */
public without sharing class FimbyDeletionIntakeService {

    private static final Integer RATE_LIMIT_MAX_PER_24H = 3;
    private static final String DELETION_RT_DEVELOPER_NAME = 'Account_Deletion';

    @TestVisible
    private static final Set<String> DELETION_SUBJECT_KEYWORDS = new Set<String>{
        'delete my account',
        'delete account',
        'close my account'
    };

    /**
     * @description Stamps the Account_Deletion RecordType on inbound
     * Email-to-Case records whose subject contains any of the deletion
     * keywords. Runs in before-insert so the assignment rule (which can only
     * route by RecordType, not parse subject text) routes the Case to the
     * Account Deletion queue. Email-to-Case sets Origin = 'Email', which is
     * how we distinguish inbound mail from manually-created Cases that may
     * legitimately mention "delete my account" in their subject without
     * meaning to trigger the deletion flow.
     * @param newCases Trigger.new on Case before insert
     */
    public static void handleBeforeInsert(List<Case> newCases) {
        if (newCases == null || newCases.isEmpty()) return;

        Id deletionRtId = getDeletionRecordTypeId();
        if (deletionRtId == null) return;

        for (Case c : newCases) {
            if (c.RecordTypeId == deletionRtId) continue;
            if (c.Origin != 'Email') continue;
            if (String.isBlank(c.Subject)) continue;

            String lower = c.Subject.toLowerCase();
            for (String keyword : DELETION_SUBJECT_KEYWORDS) {
                if (lower.contains(keyword)) {
                    c.RecordTypeId = deletionRtId;
                    break;
                }
            }
        }
    }

    /**
     * @description Filters new Cases to deletion-flow Cases and dispatches
     * each through the intake pipeline. Bulk-safe.
     * @param newCases Trigger.new on Case after insert
     */
    public static void handleAfterInsert(List<Case> newCases) {
        Id deletionRtId = getDeletionRecordTypeId();
        if (deletionRtId == null) {
            return;
        }

        List<Id> caseIdsToProcess = new List<Id>();
        for (Case c : newCases) {
            if (c.RecordTypeId == deletionRtId) {
                caseIdsToProcess.add(c.Id);
            }
        }
        if (caseIdsToProcess.isEmpty()) {
            return;
        }

        process(caseIdsToProcess);
    }

    /**
     * @description Core intake logic, exposed for the trigger and for
     * direct invocation from tests.
     * @param caseIds Case Ids of newly-inserted deletion Cases
     */
    public static void process(List<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) return;

        List<Case> cases = [
            SELECT Id, ContactId, SuppliedEmail, Subject, RecordTypeId,
                   Deletion_Stage__c, Contact_User_Id__c,
                   Confirmation_Sent_Date__c, Deletion_Rate_Limit_Flagged__c
            FROM Case
            WHERE Id IN :caseIds
        ];
        if (cases.isEmpty()) return;

        Set<Id> contactIds = new Set<Id>();
        for (Case c : cases) {
            if (c.ContactId != null) contactIds.add(c.ContactId);
        }

        Map<Id, Id> contactToUserId = resolveActiveUsers(contactIds);
        Map<Id, Integer> contactRecentCount = countRecentDeletionCases(contactIds);

        List<Case> casesToUpdate = new List<Case>();
        DateTime nowUtc = System.now();

        for (Case c : cases) {
            if (c.ContactId == null) {
                handleSenderNotMatched(c, casesToUpdate);
                continue;
            }

            Id userId = contactToUserId.get(c.ContactId);
            if (userId == null) {
                handleNoActiveUser(c, casesToUpdate);
                continue;
            }

            Integer recent = contactRecentCount.get(c.ContactId);
            if (recent != null && recent > RATE_LIMIT_MAX_PER_24H) {
                handleRateLimited(c, casesToUpdate);
                continue;
            }

            c.Contact_User_Id__c = String.valueOf(userId);
            c.Deletion_Stage__c = 'Awaiting Confirmation';
            c.Confirmation_Sent_Date__c = nowUtc;
            casesToUpdate.add(c);

            FimbyDeletionEmailService.sendVerification(c.Id, userId);
        }

        if (!casesToUpdate.isEmpty()) {
            Database.update(casesToUpdate, false);
        }
    }

    private static void handleSenderNotMatched(Case c, List<Case> casesToUpdate) {
        c.Deletion_Stage__c = 'Cancelled';
        c.Status = 'Closed';
        casesToUpdate.add(c);
        if (String.isNotBlank(c.SuppliedEmail)) {
            FimbyDeletionEmailService.sendNoActiveAccount(c.Id, c.SuppliedEmail);
        }
    }

    private static void handleNoActiveUser(Case c, List<Case> casesToUpdate) {
        c.Deletion_Stage__c = 'Cancelled';
        c.Status = 'Closed';
        casesToUpdate.add(c);
        if (String.isNotBlank(c.SuppliedEmail)) {
            FimbyDeletionEmailService.sendNoActiveAccount(c.Id, c.SuppliedEmail);
        }
        FimbyLogger.info('FimbyDeletionIntakeService', 'handleNoActiveUser',
            'No active User for Contact on Case ' + c.Id);
    }

    private static void handleRateLimited(Case c, List<Case> casesToUpdate) {
        c.Deletion_Rate_Limit_Flagged__c = true;
        c.Deletion_Stage__c = 'Awaiting Confirmation';
        casesToUpdate.add(c);
        FimbyLogger.warn('FimbyDeletionIntakeService', 'handleRateLimited',
            'Rate-limit exceeded for Contact ' + c.ContactId +
            ' on Case ' + c.Id + ' — verification email suppressed for owner review');
    }

    private static Map<Id, Id> resolveActiveUsers(Set<Id> contactIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (contactIds.isEmpty()) return result;
        for (User u : [
            SELECT Id, ContactId FROM User
            WHERE ContactId IN :contactIds AND IsActive = true
        ]) {
            result.put(u.ContactId, u.Id);
        }
        return result;
    }

    private static Map<Id, Integer> countRecentDeletionCases(Set<Id> contactIds) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        if (contactIds.isEmpty()) return result;

        Id deletionRtId = getDeletionRecordTypeId();
        if (deletionRtId == null) return result;

        DateTime windowStart = System.now().addHours(-24);
        for (AggregateResult ar : [
            SELECT ContactId, COUNT(Id) cnt
            FROM Case
            WHERE RecordTypeId = :deletionRtId
              AND ContactId IN :contactIds
              AND CreatedDate >= :windowStart
            GROUP BY ContactId
        ]) {
            Id cid = (Id) ar.get('ContactId');
            Integer cnt = (Integer) ar.get('cnt');
            result.put(cid, cnt);
        }
        return result;
    }

    @TestVisible
    private static Id deletionRtIdCached;
    private static Id getDeletionRecordTypeId() {
        if (deletionRtIdCached == null) {
            Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
            Map<String, Schema.RecordTypeInfo> infos = d.getRecordTypeInfosByDeveloperName();
            Schema.RecordTypeInfo info = infos.get(DELETION_RT_DEVELOPER_NAME);
            deletionRtIdCached = (info == null) ? null : info.getRecordTypeId();
        }
        return deletionRtIdCached;
    }
}
