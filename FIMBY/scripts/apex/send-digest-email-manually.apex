// ============================================================================
// SEND DIGEST EMAIL MANUALLY (controlled Testhood render test)
// ============================================================================
// Builds one real Testhood neighbourhood digest and sends it to ONE allowlisted
// inbox so you can eyeball the layout without emailing any neighbour.
//
// - The source User (exact Username) only selects the neighbourhood + greeting.
//   It must be active and belong to the Testhood account.
// - The email goes ONLY to DESTINATION_ADDRESS via setToAddresses, never to the
//   source User or any Contact (no setTargetObjectId).
// - Direct one-message send: no queueable, no batch, no Digest_Email_Log__c row,
//   so it cannot advance or collide with scheduled-digest checkpoints.
// - Fails loudly (throws) on any precondition or send error.
//
// Run from the Salesforce project root:
//   sf apex run --file "scripts/apex/send-digest-email-manually.apex"
// ============================================================================

String SOURCE_USERNAME        = 'reviewer@fimby.com';
String REQUIRED_NEIGHBOURHOOD = 'Testhood';
String DESTINATION_ADDRESS    = 'fimby@strathconavineyard.com';
String frequency              = 'Weekly';
Date windowEnd                = Date.today();
Date windowStart              = windowEnd.addDays(-14);

List<User> users = [
    SELECT Id, FirstName, Username, IsActive, Contact.AccountId, Contact.Account.Name
    FROM User
    WHERE Username = :SOURCE_USERNAME
    LIMIT 1
];
if (users.isEmpty()) {
    throw new IllegalArgumentException('STOP: no User with Username = ' + SOURCE_USERNAME);
}
User u = users[0];
if (!u.IsActive) {
    throw new IllegalArgumentException('STOP: source User ' + SOURCE_USERNAME + ' is inactive.');
}
if (u.Contact == null || u.Contact.AccountId == null || u.Contact.Account.Name != REQUIRED_NEIGHBOURHOOD) {
    throw new IllegalArgumentException('STOP: source User must belong to ' + REQUIRED_NEIGHBOURHOOD
        + ' (found: ' + (u.Contact == null ? 'no Contact' : u.Contact.Account?.Name) + ').');
}

List<OrgWideEmailAddress> oweas = [
    SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = 'FIMBY' LIMIT 1
];
if (oweas.isEmpty()) {
    throw new IllegalArgumentException('STOP: FIMBY Org-Wide Email Address not found.');
}

Id nhId = u.Contact.AccountId;
String nhName = u.Contact.Account.Name;

FimbyDigestEmailBuilder.DigestResult content =
    FimbyDigestEmailBuilder.buildDigestContent(nhId, nhName, frequency, windowStart, windowEnd);
if (content.isEmpty) {
    throw new IllegalArgumentException('STOP: no feed-card content for ' + nhName + ' in window '
        + windowStart + ' to ' + windowEnd + '.');
}

String subject = 'Your ' + frequency.toLowerCase() + ' neighbourhood update (test)';
String displaySubject = 'Here\'s your ' + frequency.toLowerCase() + ' neighbourhood update (test)';
String html = FimbyEmailHtmlBuilder.wrapInBrandedShell(
    content.html, displaySubject, nhName,
    null,
    false, false, u.FirstName, true
);

Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
email.setToAddresses(new List<String>{ DESTINATION_ADDRESS });
email.setSubject(subject);
email.setHtmlBody(html);
email.setSaveAsActivity(false);
email.setOrgWideEmailAddressId(oweas[0].Id);

List<Messaging.SendEmailResult> results =
    Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);
Messaging.SendEmailResult result = results[0];
if (!result.isSuccess()) {
    List<String> errors = new List<String>();
    for (Messaging.SendEmailError err : result.getErrors()) {
        errors.add(err.getStatusCode() + ': ' + err.getMessage());
    }
    throw new IllegalArgumentException('SEND FAILED: ' + String.join(errors, '; '));
}
System.debug('SENT test digest for ' + nhName + ' to ' + DESTINATION_ADDRESS
    + ' (' + content.itemCount + ' cards, window ' + windowStart + ' to ' + windowEnd + ').');
