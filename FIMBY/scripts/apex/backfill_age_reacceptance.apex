// =====================================================================
// Backfill: trigger Age Attestation reacceptance for active portal users
// =====================================================================
//
// What this does:
//   For every active portal User whose related Contact has not yet
//   confirmed the 19-or-older age attestation, set
//   Contact.Tos_Reacceptance_Required__c = true so the next time they log
//   in, Fimby_Tos_Acceptance_Login_Flow shows the combined TOS + age
//   reacceptance modal (fimbyTosFlowScreen).
//
// What this does NOT do:
//   - Does NOT stamp Age_Attestation_* fields directly. The user must
//     actively confirm the combined "Terms + 19-or-older" checkbox in
//     the modal; FimbyTosController.acceptTos then writes both fields
//     atomically. Stamping silently in this script would defeat the
//     consent record.
//   - Does NOT touch internal admin Users (no ContactId).
//   - Does NOT touch already-confirmed Contacts.
//
// Why we filter by User.IsActive = true:
//   Contact has no IsActive field. The active-user check belongs on the
//   User record. Joining via User.ContactId also automatically excludes
//   internal admins (no ContactId) and orphan Contacts (no User).
//
// DML chunking:
//   Anonymous Apex enforces a 10,000-row DML limit per transaction. We
//   chunk in 5,000-row batches to leave headroom. If population exceeds
//   what fits in a single anonymous transaction, convert to a one-shot
//   Database.Batchable and run via Database.executeBatch(new ..., 200).
//
// To run: Setup -> Developer Console -> Anonymous Apex window -> paste
// this file's contents -> Execute.
// =====================================================================

Set<Id> contactIds = new Set<Id>();
for (User u : [
    SELECT ContactId
    FROM User
    WHERE IsActive = true
      AND ContactId != null
      AND Contact.Age_Attestation_Confirmed__c != true
]) {
    contactIds.add(u.ContactId);
}

System.debug('[backfill_age_reacceptance] Contacts requiring reacceptance: ' + contactIds.size());

if (contactIds.isEmpty()) {
    System.debug('[backfill_age_reacceptance] Nothing to backfill — exiting.');
    return;
}

List<Id> contactIdList = new List<Id>(contactIds);
Integer chunkSize = 5000;
Integer totalUpdated = 0;
Integer totalFailed = 0;

for (Integer i = 0; i < contactIdList.size(); i += chunkSize) {
    Integer endIdx = Math.min(i + chunkSize, contactIdList.size());
    List<Contact> updates = new List<Contact>();
    for (Integer j = i; j < endIdx; j++) {
        updates.add(new Contact(
            Id = contactIdList[j],
            Tos_Reacceptance_Required__c = true
        ));
    }

    Database.SaveResult[] results = Database.update(updates, false);
    for (Database.SaveResult sr : results) {
        if (sr.isSuccess()) {
            totalUpdated++;
        } else {
            totalFailed++;
            for (Database.Error err : sr.getErrors()) {
                System.debug(LoggingLevel.WARN,
                    '[backfill_age_reacceptance] Failed Contact ' + sr.getId() +
                    ': ' + err.getStatusCode() + ' - ' + err.getMessage());
            }
        }
    }
    System.debug('[backfill_age_reacceptance] Chunk ' + (i / chunkSize + 1) +
        ' processed (' + (endIdx - i) + ' rows).');
}

System.debug('[backfill_age_reacceptance] Done. Updated: ' + totalUpdated +
    ', Failed: ' + totalFailed + ', Total candidates: ' + contactIds.size());
