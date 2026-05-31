/**
 * @description One-time batch to reconcile Contact and Account counter fields
 * against actual record counts. Run this BEFORE removing DLRS to verify the
 * inline +1/-1 counters match. After data retention deletes old records,
 * reconciliation against deleted data is impossible — this is the last chance.
 *
 * Usage: Database.executeBatch(new FimbyCounterReconciliationBatch(), 50);
 *
 * Set dryRun = true to log discrepancies without updating records.
 */
public without sharing class FimbyCounterReconciliationBatch implements Database.Batchable<SObject> {

    @TestVisible private Boolean dryRun = false;
    @TestVisible private Integer discrepancyCount = 0;

    public FimbyCounterReconciliationBatch() {
        this(false);
    }

    public FimbyCounterReconciliationBatch(Boolean dryRun) {
        this.dryRun = dryRun;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, AccountId,
                   Need_Offers_Posted__c, Need_Postings_For_Self__c, Need_Postings_For_Others__c,
                   Offer_Postings_For_Self__c, Offer_Postings_For_Others__c,
                   Responses_Posted__c,
                   Need_Responses_For_Self__c, Need_Responses_For_Others__c,
                   Offer_Responses_For_Self__c, Offer_Responses_For_Others__c
            FROM Contact
            WHERE Is_Organization_Contact__c = false
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Contact> scope) {
        Set<Id> contactIds = new Set<Id>();
        for (Contact c : scope) {
            contactIds.add(c.Id);
        }

        Id needRtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName()
            .get(FimbyConstants.RT_NEED)?.getRecordTypeId();
        Id offerRtId = Schema.SObjectType.Needs_Offers__c.getRecordTypeInfosByDeveloperName()
            .get(FimbyConstants.RT_OFFER)?.getRecordTypeId();

        Map<Id, Map<String, Decimal>> actualCounts = new Map<Id, Map<String, Decimal>>();
        for (Id cId : contactIds) {
            actualCounts.put(cId, new Map<String, Decimal>{
                'Need_Offers_Posted__c' => 0, 'Need_Postings_For_Self__c' => 0,
                'Need_Postings_For_Others__c' => 0, 'Offer_Postings_For_Self__c' => 0,
                'Offer_Postings_For_Others__c' => 0, 'Responses_Posted__c' => 0,
                'Need_Responses_For_Self__c' => 0, 'Need_Responses_For_Others__c' => 0,
                'Offer_Responses_For_Self__c' => 0, 'Offer_Responses_For_Others__c' => 0
            });
        }

        for (AggregateResult ar : [
            SELECT Posted_By__c contactId, RecordTypeId, COUNT(Id) cnt
            FROM Needs_Offers__c
            WHERE Posted_By__c IN :contactIds
              AND RecordTypeId IN (:needRtId, :offerRtId)
            GROUP BY Posted_By__c, RecordTypeId
        ]) {
            Id cId = (Id) ar.get('contactId');
            Id rtId = (Id) ar.get('RecordTypeId');
            Integer cnt = ((Decimal) ar.get('cnt')).intValue();
            Map<String, Decimal> m = actualCounts.get(cId);
            m.put('Need_Offers_Posted__c', m.get('Need_Offers_Posted__c') + cnt);
            if (rtId == needRtId) {
                m.put('Need_Postings_For_Self__c', m.get('Need_Postings_For_Self__c') + cnt);
            } else if (rtId == offerRtId) {
                m.put('Offer_Postings_For_Self__c', m.get('Offer_Postings_For_Self__c') + cnt);
            }
        }

        for (AggregateResult ar : [
            SELECT Contact__c contactId, COUNT(Id) cnt
            FROM Response__c
            WHERE Contact__c IN :contactIds
            GROUP BY Contact__c
        ]) {
            Id cId = (Id) ar.get('contactId');
            Integer cnt = ((Decimal) ar.get('cnt')).intValue();
            actualCounts.get(cId).put('Responses_Posted__c', (Decimal) cnt);
        }

        for (AggregateResult ar : [
            SELECT Contact__c contactId, Need_Offer_Responded_To__r.RecordTypeId rtId, COUNT(Id) cnt
            FROM Response__c
            WHERE Contact__c IN :contactIds
              AND Status__c IN (:FimbyConstants.RESPONSE_ACCEPTED, :FimbyConstants.RESPONSE_COMPLETED)
              AND Need_Offer_Responded_To__r.RecordTypeId IN (:needRtId, :offerRtId)
            GROUP BY Contact__c, Need_Offer_Responded_To__r.RecordTypeId
        ]) {
            Id cId = (Id) ar.get('contactId');
            Id rtId = (Id) ar.get('rtId');
            Integer cnt = ((Decimal) ar.get('cnt')).intValue();
            Map<String, Decimal> m = actualCounts.get(cId);
            if (rtId == needRtId) {
                m.put('Need_Responses_For_Self__c', m.get('Need_Responses_For_Self__c') + cnt);
            } else if (rtId == offerRtId) {
                m.put('Offer_Responses_For_Self__c', m.get('Offer_Responses_For_Self__c') + cnt);
            }
        }

        List<Contact> toUpdate = new List<Contact>();
        for (Contact c : scope) {
            Map<String, Decimal> actual = actualCounts.get(c.Id);
            Contact upd = new Contact(Id = c.Id);
            Boolean needsUpdate = false;

            for (String field : actual.keySet()) {
                Decimal stored = c.get(field) != null ? (Decimal) c.get(field) : 0;
                Decimal expected = actual.get(field);
                if (stored != expected) {
                    needsUpdate = true;
                    discrepancyCount++;
                    upd.put(field, expected);
                }
            }
            if (needsUpdate) {
                toUpdate.add(upd);
            }
        }

        if (!toUpdate.isEmpty() && !dryRun) {
            Database.update(toUpdate, false);
        }
    }

    public void finish(Database.BatchableContext bc) {
        FimbyLogger.info('FimbyCounterReconciliationBatch',
            'finish',
            'Reconciliation complete. Discrepancies found: ' + discrepancyCount
            + (dryRun ? ' (DRY RUN — no updates applied)' : '')
        );
    }
}
