/**
 * Test-data cleanup utility for the Playwright end-to-end suite.
 *
 * Records created by E2E specs are anchored with a `[E2E] <runId>` title prefix
 * on the user-visible name field. After each test, Node-side cleanup shells
 * `sf apex run` against this class.
 *
 * Safety rules (enforced here, not on the caller):
 *   1. Prefix must be at least `MIN_PREFIX_LENGTH` chars and contain a space, to
 *      prevent a typo from sweeping unrelated content.
 *   2. Cleanup never touches Account, Contact, User, or any standard object.
 *   3. Children are deleted before parents.
 *   4. allOrNone = false on deletes — partial cleanups are reported, not thrown.
 *   5. Per-call SOQL is bounded by `MAX_PER_OBJECT` to keep limits sane.
 *
 * Public surface:
 *   - cleanupRun(String runId)   -> deletes records anchored to a single run.
 *   - cleanupPrefix(String prefix) -> sweeps everything matching prefix.
 *   - dryRun(String prefix)      -> counts only, no deletes.
 */
public without sharing class FimbyTestDataCleanup {
    @TestVisible private static final String DEFAULT_PREFIX = '[E2E] ';
    @TestVisible private static final Integer MIN_PREFIX_LENGTH = 5;
    @TestVisible private static final Integer MAX_PER_OBJECT = 1000;

    public class CleanupResult {
        @AuraEnabled public Integer recordsDeleted;
        @AuraEnabled public Map<String, Integer> deletedByObject;
        @AuraEnabled public List<String> warnings;
        @AuraEnabled public Boolean dryRun;
        public CleanupResult() {
            this.recordsDeleted = 0;
            this.deletedByObject = new Map<String, Integer>();
            this.warnings = new List<String>();
            this.dryRun = false;
        }
    }

    public class CleanupException extends Exception {}

    public static CleanupResult cleanupRun(String runId) {
        if (String.isBlank(runId) || runId.length() < 4) {
            throw new CleanupException('cleanupRun rejected: runId must be at least 4 chars, got ' + runId);
        }
        return run(DEFAULT_PREFIX + runId, false);
    }

    public static CleanupResult cleanupPrefix(String prefix) {
        validatePrefix(prefix);
        return run(prefix, false);
    }

    public static CleanupResult dryRun(String prefix) {
        validatePrefix(prefix);
        return run(prefix, true);
    }

    private static void validatePrefix(String prefix) {
        if (String.isBlank(prefix)) {
            throw new CleanupException('Prefix is required');
        }
        if (prefix.length() < MIN_PREFIX_LENGTH) {
            throw new CleanupException('Prefix too short (min ' + MIN_PREFIX_LENGTH + '): ' + prefix);
        }
        if (!prefix.contains('[E2E]')) {
            throw new CleanupException('Prefix must contain [E2E] anchor: ' + prefix);
        }
    }

    private static CleanupResult run(String prefix, Boolean isDryRun) {
        CleanupResult result = new CleanupResult();
        result.dryRun = isDryRun;
        String pattern = String.escapeSingleQuotes(prefix) + '%';

        Set<Id> needOfferIds = collectIdsByName('Needs_Offers__c', pattern);
        Set<Id> libraryIds = collectIdsByName('Library_Item__c', pattern);
        Set<Id> storyIds = collectIdsByName('Story__c', pattern);
        Set<Id> responseIds = collectIdsByName('Response__c', pattern);
        Set<Id> loanedIds = collectIdsByName('Loaned_Item__c', pattern);
        Set<Id> historyIds = collectIdsByName('Lending_History__c', pattern);
        Set<Id> rciIds = collectIdsByName('Response_Contact_Info__c', pattern);
        Set<Id> sciIds = collectIdsByName('Shared_Contact_Info__c', pattern);
        Set<Id> feedbackIds = collectIdsByName('Feedback__c', pattern);

        Set<Id> childResponseIds = collectChildIds('Response__c', 'Need_Offer_Responded_To__c', needOfferIds);
        responseIds.addAll(childResponseIds);
        Set<Id> childLendingRequestIds = collectChildIds('Lending_Request__c', 'Library_Item__c', libraryIds);
        Set<Id> childLoanedIds = collectChildIds('Loaned_Item__c', 'Library_Item__c', libraryIds);
        loanedIds.addAll(childLoanedIds);
        Set<Id> childHistoryIds = collectChildIds('Lending_History__c', 'Library_Item__c', libraryIds);
        historyIds.addAll(childHistoryIds);

        Set<Id> conversationIds = new Set<Id>();
        conversationIds.addAll(collectLookupValues('Needs_Offers__c', 'Group_Conversation__c', needOfferIds));

        Set<Id> allAnchoredIds = new Set<Id>();
        allAnchoredIds.addAll(needOfferIds);
        allAnchoredIds.addAll(libraryIds);
        allAnchoredIds.addAll(storyIds);
        allAnchoredIds.addAll(responseIds);
        allAnchoredIds.addAll(loanedIds);
        allAnchoredIds.addAll(historyIds);
        allAnchoredIds.addAll(rciIds);
        allAnchoredIds.addAll(sciIds);
        allAnchoredIds.addAll(feedbackIds);
        allAnchoredIds.addAll(childLendingRequestIds);

        deleteWhereLookupIn(result, isDryRun, 'Notification__c', 'Related_Record_Id__c', allAnchoredIds, true);
        deleteWhereLookupIn(result, isDryRun, 'Response_Message__c', 'Response__c', responseIds, false);
        deleteWhereLookupIn(result, isDryRun, 'Bulk_Buy_Follow_Up__c', 'Bulk_Buy__c', needOfferIds, false);
        deleteWhereLookupIn(result, isDryRun, 'Bulk_Buy_Follow_Up__c', 'Reservation__c', responseIds, false);
        deleteByIds(result, isDryRun, 'Shared_Contact_Info__c', sciIds);
        deleteByIds(result, isDryRun, 'Response_Contact_Info__c', rciIds);
        deleteByIds(result, isDryRun, 'Lending_Request__c', childLendingRequestIds);
        deleteByIds(result, isDryRun, 'Lending_History__c', historyIds);
        deleteByIds(result, isDryRun, 'Loaned_Item__c', loanedIds);
        deleteByIds(result, isDryRun, 'Library_Item__c', libraryIds);
        deleteByIds(result, isDryRun, 'Response__c', responseIds);
        deleteByIds(result, isDryRun, 'Needs_Offers__c', needOfferIds);
        deleteByIds(result, isDryRun, 'Story__c', storyIds);
        deleteByIds(result, isDryRun, 'Feedback__c', feedbackIds);
        deleteWhereLookupIn(result, isDryRun, 'Conversation_Member__c', 'Conversation__c', conversationIds, false);
        deleteWhereLookupIn(result, isDryRun, 'Message__c', 'Conversation__c', conversationIds, false);
        deleteByIds(result, isDryRun, 'Conversation__c', conversationIds);

        return result;
    }

    private static Set<Id> collectIdsByName(String objectName, String pattern) {
        Set<Id> ids = new Set<Id>();
        if (!Schema.getGlobalDescribe().containsKey(objectName)) {
            return ids;
        }
        String soql = 'SELECT Id FROM ' + objectName + ' WHERE Name LIKE :pattern LIMIT ' + MAX_PER_OBJECT;
        for (SObject row : Database.query(soql)) {
            ids.add((Id) row.get('Id'));
        }
        return ids;
    }

    private static Set<Id> collectChildIds(String objectName, String lookupField, Set<Id> parentIds) {
        Set<Id> ids = new Set<Id>();
        if (parentIds == null || parentIds.isEmpty()) return ids;
        if (!Schema.getGlobalDescribe().containsKey(objectName)) return ids;
        String soql = 'SELECT Id FROM ' + objectName + ' WHERE ' + lookupField + ' IN :parentIds LIMIT ' + MAX_PER_OBJECT;
        for (SObject row : Database.query(soql)) {
            ids.add((Id) row.get('Id'));
        }
        return ids;
    }

    private static Set<Id> collectLookupValues(String objectName, String lookupField, Set<Id> parentIds) {
        Set<Id> values = new Set<Id>();
        if (parentIds == null || parentIds.isEmpty()) return values;
        if (!Schema.getGlobalDescribe().containsKey(objectName)) return values;
        String soql = 'SELECT ' + lookupField + ' FROM ' + objectName + ' WHERE Id IN :parentIds AND ' + lookupField + ' != null LIMIT ' + MAX_PER_OBJECT;
        for (SObject row : Database.query(soql)) {
            Object v = row.get(lookupField);
            if (v != null) values.add((Id) v);
        }
        return values;
    }

    private static void deleteByIds(CleanupResult result, Boolean isDryRun, String objectName, Set<Id> ids) {
        if (ids == null || ids.isEmpty()) return;
        if (isDryRun) {
            tally(result, objectName, ids.size());
            return;
        }
        List<SObject> rows = new List<SObject>();
        for (Id rid : ids) {
            SObject row = Schema.getGlobalDescribe().get(objectName).newSObject(rid);
            rows.add(row);
        }
        Database.DeleteResult[] dels = Database.delete(rows, false);
        Integer ok = 0;
        for (Integer i = 0; i < dels.size(); i++) {
            if (dels[i].isSuccess()) {
                ok++;
            } else {
                String err = dels[i].getErrors().isEmpty() ? 'unknown' : dels[i].getErrors()[0].getMessage();
                result.warnings.add(objectName + ' ' + dels[i].getId() + ': ' + err);
            }
        }
        tally(result, objectName, ok);
    }

    private static void deleteWhereLookupIn(CleanupResult result, Boolean isDryRun, String objectName, String lookupField, Set<Id> values, Boolean valueIsString) {
        if (values == null || values.isEmpty()) return;
        if (!Schema.getGlobalDescribe().containsKey(objectName)) return;
        String soql;
        if (valueIsString) {
            Set<String> stringValues = new Set<String>();
            for (Id v : values) stringValues.add((String) v);
            soql = 'SELECT Id FROM ' + objectName + ' WHERE ' + lookupField + ' IN :stringValues LIMIT ' + MAX_PER_OBJECT;
            List<SObject> rows = Database.query(soql);
            handleDelete(result, isDryRun, objectName, rows);
            return;
        }
        soql = 'SELECT Id FROM ' + objectName + ' WHERE ' + lookupField + ' IN :values LIMIT ' + MAX_PER_OBJECT;
        List<SObject> rows = Database.query(soql);
        handleDelete(result, isDryRun, objectName, rows);
    }

    private static void handleDelete(CleanupResult result, Boolean isDryRun, String objectName, List<SObject> rows) {
        if (rows.isEmpty()) return;
        if (isDryRun) {
            tally(result, objectName, rows.size());
            return;
        }
        Database.DeleteResult[] dels = Database.delete(rows, false);
        Integer ok = 0;
        for (Integer i = 0; i < dels.size(); i++) {
            if (dels[i].isSuccess()) {
                ok++;
            } else {
                String err = dels[i].getErrors().isEmpty() ? 'unknown' : dels[i].getErrors()[0].getMessage();
                result.warnings.add(objectName + ' ' + dels[i].getId() + ': ' + err);
            }
        }
        tally(result, objectName, ok);
    }

    private static void tally(CleanupResult result, String objectName, Integer count) {
        if (count <= 0) return;
        Integer existing = result.deletedByObject.containsKey(objectName) ? result.deletedByObject.get(objectName) : 0;
        result.deletedByObject.put(objectName, existing + count);
        result.recordsDeleted += count;
    }
}
