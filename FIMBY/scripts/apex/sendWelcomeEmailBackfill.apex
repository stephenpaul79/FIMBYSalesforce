/**
 * Dev Console — one-off welcome email backfill for neighbours who signed up
 * before Welcome_Email_Sent_Date__c existed.
 *
 * Cohort: Profile.Name = 'Customer Community User - Mobile App',
 * minus anyone with Contact.Welcome_Email_Sent_Date__c already set.
 *
 * Uses FimbyOnboardingWelcomeEmailQueueable — sends email and stamps the guard on success.
 *
 * Governor limit: max 50 queueable jobs per Execute Anonymous run. Re-run until
 * "Eligible remaining: 0".
 */
Boolean DRY_RUN = true;   // true = list only; false = enqueue sends
Integer MAX_ENQUEUE = 50; // queueable cap per run (do not raise above 50)

String cohortBaseWhere =
    'FROM User '
    + 'WHERE Profile.Name = \'Customer Community User - Mobile App\' '
    + 'AND IsActive = true '
    + 'AND Email != null '
    + 'AND ContactId != null '
    + 'AND Contact.AccountId != null '
    + 'AND Contact.HasOptedOutOfEmail = false';

Integer alreadySent = Database.countQuery(
    'SELECT COUNT() ' + cohortBaseWhere + ' AND Contact.Welcome_Email_Sent_Date__c != null'
);

Integer totalEligible = Database.countQuery(
    'SELECT COUNT() ' + cohortBaseWhere + ' AND Contact.Welcome_Email_Sent_Date__c = null'
);

List<User> batch = Database.query(
    'SELECT Id, Email, FirstName, ContactId, '
    + 'Contact.FirstName, Contact.AccountId, Contact.Account.Name, '
    + 'Contact.Welcome_Email_Sent_Date__c '
    + cohortBaseWhere
    + ' AND Contact.Welcome_Email_Sent_Date__c = null '
    + 'ORDER BY LastLoginDate DESC NULLS LAST '
    + 'LIMIT :MAX_ENQUEUE'
);

System.debug('=== Welcome email backfill (Mobile App cohort) ===');
System.debug('DRY_RUN: ' + DRY_RUN + ' | MAX_ENQUEUE this run: ' + MAX_ENQUEUE);
System.debug('Already sent — skipped: ' + alreadySent + ' (Welcome_Email_Sent_Date__c is set)');
System.debug('Eligible remaining (welcome not yet sent): ' + totalEligible);

if (batch.isEmpty()) {
    System.debug('No eligible users — nothing to do.');
    return;
}

System.debug('Processing this run: ' + batch.size());
for (User u : batch) {
    String name = String.isNotBlank(u.FirstName) ? u.FirstName : u.Contact.FirstName;
    System.debug(
        '  User ' + u.Id + ' | Contact ' + u.ContactId + ' | ' + name
        + ' <' + u.Email + '> | NH: ' + u.Contact.Account.Name
    );
}

if (DRY_RUN) {
    System.debug('DRY_RUN is true — no jobs enqueued. Set DRY_RUN = false to send.');
    if (totalEligible > batch.size()) {
        System.debug('Note: ' + (totalEligible - batch.size()) + ' more eligible. Re-run after jobs finish.');
    }
    return;
}

Integer enqueued = 0;
Integer skippedAlreadySent = 0;
for (User u : batch) {
    if (u.Contact.Welcome_Email_Sent_Date__c != null) {
        skippedAlreadySent++;
        System.debug(LoggingLevel.WARN, 'Skip — welcome already sent: Contact ' + u.ContactId);
        continue;
    }
    System.enqueueJob(new FimbyOnboardingWelcomeEmailQueueable(
        u.ContactId, u.Id, u.Contact.AccountId
    ));
    enqueued++;
}

System.debug('Enqueued ' + enqueued + ' FimbyOnboardingWelcomeEmailQueueable job(s).');
if (skippedAlreadySent > 0) {
    System.debug('Skipped ' + skippedAlreadySent + ' row(s) — Welcome_Email_Sent_Date__c was set after query.');
}
System.debug('Each job sends one welcome email and sets Contact.Welcome_Email_Sent_Date__c on success.');
if (totalEligible > enqueued) {`1       `12q34e5
    System.debug('Still eligible: ~' + (totalEligible - enqueued) + '. Wait for jobs to finish, then run again.');
}
78yu95i ug4yfdrt4ew32Q  1` =;/>
L8okuj6g