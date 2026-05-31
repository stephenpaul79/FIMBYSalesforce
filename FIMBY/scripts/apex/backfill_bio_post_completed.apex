// =====================================================================
// Backfill: mark existing Contacts as Bio_Post_Completed = true
// =====================================================================
//
// What this does:
//   Sets Contact.Bio_Post_Completed__c = true on every existing Contact
//   that was created before this deploy. This prevents the new "Say hi"
//   home-feed banner and the Ask/Offer soft-gate from haunting long-time
//   members who already know the neighbourhood.
//
// What this does NOT do:
//   - Does NOT touch new Contacts created after the deploy. They start
//     with the default (false) and will see the bio-post nudge as part of
//     their first-time onboarding flow.
//   - Does NOT create or modify any Story__c records. Existing members
//     are simply marked as "decision made" — they can still post a bio
//     anytime via the regular Shared Life composer.
//
// Cut-over timestamp:
//   Update DEPLOY_TIMESTAMP below to the actual deploy time (UTC, ISO
//   8601) before running. Any Contact whose CreatedDate < this value is
//   treated as "existing." A small tolerance window (e.g. add a few
//   minutes) is fine — the bio post nudge is reversible by the user
//   posting a real bio later anyway.
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

// Set this to the deploy timestamp (UTC). Anything created strictly
// before this moment is treated as a pre-existing Contact.
DateTime DEPLOY_TIMESTAMP = DateTime.now();

List<Contact> existingContacts = [
    SELECT Id
    FROM Contact
    WHERE CreatedDate < :DEPLOY_TIMESTAMP
      AND Bio_Post_Completed__c != true
];

System.debug('[backfill_bio_post_completed] Candidates: ' + existingContacts.size());

if (existingContacts.isEmpty()) {
    System.debug('[backfill_bio_post_completed] Nothing to backfill - exiting.');
    return;
}

List<Id> contactIdList = new List<Id>();
for (Contact c : existingContacts) {
    contactIdList.add(c.Id);
}

Integer chunkSize = 5000;
Integer totalUpdated = 0;
Integer totalFailed = 0;

for (Integer i = 0; i < contactIdList.size(); i += chunkSize) {
    Integer endIdx = Math.min(i + chunkSize, contactIdList.size());
    List<Contact> updates = new List<Contact>();
    for (Integer j = i; j < endIdx; j++) {
        updates.add(new Contact(
            Id = contactIdList[j],
            Bio_Post_Completed__c = true
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
                    '[backfill_bio_post_completed] Failed Contact ' + sr.getId() +
                    ': ' + err.getStatusCode() + ' - ' + err.getMessage());
            }
        }
    }
    System.debug('[backfill_bio_post_completed] Chunk ' + (i / chunkSize + 1) +
        ' processed (' + (endIdx - i) + ' rows).');
}

System.debug('[backfill_bio_post_completed] Done. Updated: ' + totalUpdated +
    ', Failed: ' + totalFailed + ', Total candidates: ' + contactIdList.size());
