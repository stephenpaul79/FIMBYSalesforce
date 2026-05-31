/**
 * @description Replaces DLRS realtime rollups with inline +1/-1 counter management.
 * Updates Contact and Account counter fields in the same transaction as the
 * triggering action. The data retention batch must NOT call these methods
 * when deleting old records — counters reflect lifetime activity.
 */
public without sharing class FimbyCounterService {

    private static final Set<String> QUALIFYING_RESPONSE_STATUSES = new Set<String>{
        FimbyConstants.RESPONSE_ACCEPTED,
        FimbyConstants.RESPONSE_COMPLETED
    };

    /**
     * @description Called after inserting a Needs_Offers__c post.
     * @param postedByContactId Posted_By__c — the real author
     * @param recordTypeName DeveloperName of the post's RecordType (Need, Offer, Bulk_Buy)
     * @param isActingAsOther true when Posted_By__c != Contact__c (acting on behalf of someone else)
     */
    public static void onPostCreated(Id postedByContactId, String recordTypeName, Boolean isActingAsOther) {
        if (postedByContactId == null || String.isBlank(recordTypeName)) {
            return;
        }
        Map<String, Decimal> deltas = buildPostDeltas(recordTypeName, isActingAsOther, 1);
        applyContactAndAccountDeltas(postedByContactId, deltas);
    }

    /**
     * @description Called before/after deleting a Needs_Offers__c post.
     */
    public static void onPostDeleted(Id postedByContactId, String recordTypeName, Boolean isActingAsOther) {
        if (postedByContactId == null || String.isBlank(recordTypeName)) {
            return;
        }
        Map<String, Decimal> deltas = buildPostDeltas(recordTypeName, isActingAsOther, -1);
        applyContactAndAccountDeltas(postedByContactId, deltas);
    }

    /**
     * @description Called after inserting a Response__c.
     * @param responderContactId Contact__c on Response (real person)
     * @param parentRecordTypeName DeveloperName of the parent Needs_Offers__c RecordType
     * @param isActingAsOther true when On_Behalf_Of_Contact__c differs from Contact__c
     * @param initialStatus the Status__c value at insert time
     */
    public static void onResponseCreated(
        Id responderContactId, String parentRecordTypeName,
        Boolean isActingAsOther, String initialStatus
    ) {
        if (responderContactId == null) {
            return;
        }
        Map<String, Decimal> deltas = new Map<String, Decimal>{
            'Responses_Posted__c' => 1
        };
        if (QUALIFYING_RESPONSE_STATUSES.contains(initialStatus)) {
            deltas.putAll(buildResponseDeltas(parentRecordTypeName, isActingAsOther, 1));
        }
        applyContactAndAccountDeltas(responderContactId, deltas);
    }

    /**
     * @description Called after a Response__c status transition.
     * Handles entering/exiting the qualifying set (Accepted, Completed).
     */
    public static void onResponseStatusChanged(
        Id responderContactId, String parentRecordTypeName,
        Boolean isActingAsOther, String oldStatus, String newStatus
    ) {
        if (responderContactId == null) {
            return;
        }
        Boolean wasQualifying = QUALIFYING_RESPONSE_STATUSES.contains(oldStatus);
        Boolean isQualifying = QUALIFYING_RESPONSE_STATUSES.contains(newStatus);

        if (!wasQualifying && isQualifying) {
            Map<String, Decimal> deltas = buildResponseDeltas(parentRecordTypeName, isActingAsOther, 1);
            applyContactAndAccountDeltas(responderContactId, deltas);
        } else if (wasQualifying && !isQualifying) {
            Map<String, Decimal> deltas = buildResponseDeltas(parentRecordTypeName, isActingAsOther, -1);
            applyContactAndAccountDeltas(responderContactId, deltas);
        }
    }

    /**
     * @description Called when a Response__c is cancelled (which also decrements Responses_Posted).
     */
    public static void onResponseCancelled(
        Id responderContactId, String parentRecordTypeName,
        Boolean isActingAsOther, String oldStatus
    ) {
        if (responderContactId == null) {
            return;
        }
        Map<String, Decimal> deltas = new Map<String, Decimal>{
            'Responses_Posted__c' => -1
        };
        if (QUALIFYING_RESPONSE_STATUSES.contains(oldStatus)) {
            deltas.putAll(buildResponseDeltas(parentRecordTypeName, isActingAsOther, -1));
        }
        applyContactAndAccountDeltas(responderContactId, deltas);
    }

    /**
     * @description Increment/decrement boundary Account contact counts.
     * Called during onboarding (activation) and deactivation.
     * @param accountId the Boundary Account Id (Contact.AccountId)
     * @param delta +1 for activation, -1 for deactivation
     * @param isActiveUser whether this contact has Active_User__c = true
     */
    public static void onContactActivationChanged(Id accountId, Decimal delta, Boolean isActiveUser) {
        if (accountId == null) {
            return;
        }
        Account acct = new Account(Id = accountId);
        acct.put('All_Contacts_In_Boundary__c', delta);
        if (isActiveUser) {
            acct.put('Active_Users_In_Boundary__c', delta);
        }
        incrementAccountRecord(acct);
    }

    /* ---------------------------------------------------------------
     * Delta builders
     * --------------------------------------------------------------- */

    private static Map<String, Decimal> buildPostDeltas(String rtName, Boolean isActingAsOther, Integer direction) {
        Map<String, Decimal> deltas = new Map<String, Decimal>{
            'Need_Offers_Posted__c' => direction
        };
        if (rtName == FimbyConstants.RT_NEED) {
            deltas.put(isActingAsOther ? 'Need_Postings_For_Others__c' : 'Need_Postings_For_Self__c', direction);
        } else if (rtName == FimbyConstants.RT_OFFER) {
            deltas.put(isActingAsOther ? 'Offer_Postings_For_Others__c' : 'Offer_Postings_For_Self__c', direction);
        }
        return deltas;
    }

    private static Map<String, Decimal> buildResponseDeltas(String parentRtName, Boolean isActingAsOther, Integer direction) {
        Map<String, Decimal> deltas = new Map<String, Decimal>();
        if (parentRtName == FimbyConstants.RT_NEED) {
            deltas.put(isActingAsOther ? 'Need_Responses_For_Others__c' : 'Need_Responses_For_Self__c', direction);
        } else if (parentRtName == FimbyConstants.RT_OFFER) {
            deltas.put(isActingAsOther ? 'Offer_Responses_For_Others__c' : 'Offer_Responses_For_Self__c', direction);
        }
        return deltas;
    }

    /* ---------------------------------------------------------------
     * DML — applies deltas to Contact and its boundary Account
     * --------------------------------------------------------------- */

    private static final Set<String> CONTACT_ONLY_FIELDS = new Set<String>{
        'Need_Offers_Posted__c', 'Responses_Posted__c'
    };

    private static void applyContactAndAccountDeltas(Id contactId, Map<String, Decimal> deltas) {
        if (deltas.isEmpty()) {
            return;
        }

        Contact c = [SELECT AccountId FROM Contact WHERE Id = :contactId LIMIT 1];

        Contact contactUpd = new Contact(Id = contactId);
        Account accountUpd = (c.AccountId != null) ? new Account(Id = c.AccountId) : null;

        for (String field : deltas.keySet()) {
            Decimal delta = deltas.get(field);
            contactUpd.put(field, delta);
            if (accountUpd != null && !CONTACT_ONLY_FIELDS.contains(field)) {
                accountUpd.put(field, delta);
            }
        }

        incrementContactRecord(contactUpd);
        if (accountUpd != null) {
            incrementAccountRecord(accountUpd);
        }
    }

    /**
     * @description Reads the current field values and adds deltas, then updates.
     * Fields on the SObject parameter hold DELTA values (not absolute).
     */
    private static void incrementContactRecord(Contact stub) {
        Map<String, Object> populated = stub.getPopulatedFieldsAsMap();
        Set<String> counterFields = new Set<String>(populated.keySet());
        counterFields.remove('Id');
        if (counterFields.isEmpty()) {
            return;
        }

        String query = 'SELECT ' + String.join(new List<String>(counterFields), ', ')
            + ' FROM Contact WHERE Id = :stubId LIMIT 1';
        Id stubId = stub.Id;
        Contact current = Database.query(query);

        Contact toUpdate = new Contact(Id = stub.Id);
        for (String field : counterFields) {
            Decimal currentVal = current.get(field) != null ? (Decimal) current.get(field) : 0;
            Decimal delta = (Decimal) populated.get(field);
            Decimal newVal = currentVal + delta;
            toUpdate.put(field, newVal < 0 ? 0 : newVal);
        }

        try {
            Database.update(toUpdate, true);
        } catch (Exception e) {
            FimbyLogger.error('FimbyCounterService', 'incrementContactRecord', e);
        }
    }

    private static void incrementAccountRecord(Account stub) {
        Map<String, Object> populated = stub.getPopulatedFieldsAsMap();
        Set<String> counterFields = new Set<String>(populated.keySet());
        counterFields.remove('Id');
        if (counterFields.isEmpty()) {
            return;
        }

        String query = 'SELECT ' + String.join(new List<String>(counterFields), ', ')
            + ' FROM Account WHERE Id = :stubId LIMIT 1';
        Id stubId = stub.Id;
        Account current = Database.query(query);

        Account toUpdate = new Account(Id = stub.Id);
        for (String field : counterFields) {
            Decimal currentVal = current.get(field) != null ? (Decimal) current.get(field) : 0;
            Decimal delta = (Decimal) populated.get(field);
            Decimal newVal = currentVal + delta;
            toUpdate.put(field, newVal < 0 ? 0 : newVal);
        }

        try {
            Database.update(toUpdate, true);
        } catch (Exception e) {
            FimbyLogger.error('FimbyCounterService', 'incrementAccountRecord', e);
        }
    }
}
