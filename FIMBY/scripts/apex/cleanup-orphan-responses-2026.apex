/**
 * Remove Response__c threads left behind when a parent Needs_Offers__c was deleted
 * (Need_Offer_Responded_To__c is null). Scoped to CreatedDate >= 2026-01-01.
 *
 * Dry run: EXECUTE_DELETE = false (default)
 */
Boolean EXECUTE_DELETE = false;
Datetime CREATED_ON_OR_AFTER = Datetime.newInstanceGmt(2026, 1, 1, 0, 0, 0);

List<Response__c> orphans = [
    SELECT Id
    FROM Response__c
    WHERE Need_Offer_Responded_To__c = NULL AND CreatedDate >= :CREATED_ON_OR_AFTER
];
Set<Id> responseIds = new Map<Id, Response__c>(orphans).keySet();
Set<String> notificationRecordIdStrs = new Set<String>();
for (Id idVal : responseIds) {
    notificationRecordIdStrs.add((String) idVal);
}

System.debug('ORPHAN_RESPONSES=' + orphans.size());
System.debug(
    'RESPONSE_MESSAGES=' +
        (responseIds.isEmpty()
            ? 0
            : [SELECT COUNT() FROM Response_Message__c WHERE Response__c IN :responseIds])
);
System.debug(
    'NOTIFICATIONS=' +
        (notificationRecordIdStrs.isEmpty()
            ? 0
            : [
                  SELECT COUNT()
                  FROM Notification__c
                  WHERE Related_Record_Id__c IN :notificationRecordIdStrs
              ])
);

if (!EXECUTE_DELETE) {
    System.debug('DRY_RUN=true');
} else {
    if (!notificationRecordIdStrs.isEmpty()) {
        delete [
            SELECT Id
            FROM Notification__c
            WHERE Related_Record_Id__c IN :notificationRecordIdStrs
        ];
    }
    if (!responseIds.isEmpty()) {
        delete [SELECT Id FROM Response_Message__c WHERE Response__c IN :responseIds];
        delete [
            SELECT Id
            FROM Shared_Contact_Info__c
            WHERE Response__c IN :responseIds
        ];
        delete [
            SELECT Id
            FROM Response_Contact_Info__c
            WHERE Response__c IN :responseIds
        ];
        delete [
            SELECT Id
            FROM Bulk_Buy_Follow_Up__c
            WHERE Reservation__c IN :responseIds
        ];
    }
    if (!orphans.isEmpty()) {
        delete orphans;
    }
    System.debug('DELETE_COMPLETE=true');
}
