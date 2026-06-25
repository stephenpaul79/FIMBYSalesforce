/**
 * Dev Console — paste into Execute Anonymous.
 *
 * Set exactly one target (User Id preferred — matches what the queueable sends):
 *   TARGET_USER_ID   — from the User record URL (005...)
 *   TARGET_CONTACT_ID — fallback; picks the newest active User for that Contact
 *
 * Modes:
 *   PREVIEW_ONLY = true  — build HTML and debug only (default, safe)
 *   PREVIEW_ONLY = false — enqueue FimbyOnboardingWelcomeEmailQueueable (real send)
 *
 * Re-send on the same Contact (testing only):
 *   CLEAR_SEND_GUARD = true clears Contact.Welcome_Email_Sent_Date__c before enqueue.
 *
 * Subject / header (replaced removed SUBJECT constant):
 *   buildSubject(firstName)  → envelope subject
 *   HEADER_TITLE             → in-email H1
 */
Id TARGET_USER_ID = null; // e.g. '005OL00000xxxxxxx'
Id TARGET_CONTACT_ID = '003OL00000w5jcbYAA'; // e.g. '003OL00000xxxxxxx'

Boolean PREVIEW_ONLY = false;
Boolean CLEAR_SEND_GUARD = true;

Integer PREVIEW_MAX = 5;
Integer WINDOW_DAYS = 7;

User u;
if (TARGET_USER_ID != null) {
    List<User> users = [
        SELECT Id, FirstName, Email, ContactId,
               Contact.FirstName, Contact.AccountId, Contact.Account.Name,
               Contact.Welcome_Email_Sent_Date__c
        FROM User
        WHERE Id = :TARGET_USER_ID
        LIMIT 1
    ];
    if (users.isEmpty()) {
        System.debug(LoggingLevel.ERROR, 'No User found for Id ' + TARGET_USER_ID);
        return;
    }
    u = users[0];
} else if (TARGET_CONTACT_ID != null) {
    List<User> users = [
        SELECT Id, FirstName, Email, ContactId,
               Contact.FirstName, Contact.AccountId, Contact.Account.Name,
               Contact.Welcome_Email_Sent_Date__c
        FROM User
        WHERE ContactId = :TARGET_CONTACT_ID
          AND IsActive = true
        ORDER BY LastLoginDate DESC NULLS LAST, CreatedDate DESC
    ];
    if (users.isEmpty()) {
        System.debug(LoggingLevel.ERROR, 'No active User linked to Contact ' + TARGET_CONTACT_ID);
        return;
    }
    if (users.size() > 1) {
        System.debug(LoggingLevel.WARN,
            users.size() + ' active Users share this Contact — using ' + users[0].Id
            + ' (' + users[0].Email + '). Set TARGET_USER_ID to pin a specific recipient.');
    }
    u = users[0];
} else {
    System.debug(LoggingLevel.ERROR, 'Set TARGET_USER_ID or TARGET_CONTACT_ID before running.');
    return;
}

Id contactId = u.ContactId;
Id nhId = u.Contact.AccountId;
if (nhId == null) {
    System.debug(LoggingLevel.ERROR, 'User ' + u.Id + ' has no neighbourhood (Contact.AccountId is null).');
    return;
}

String firstName = String.isNotBlank(u.FirstName) ? u.FirstName : u.Contact.FirstName;
String neighbourhoodName = u.Contact.Account.Name;

Date windowEnd = Date.today();
Date windowStart = windowEnd.addDays(-WINDOW_DAYS);
Set<Id> excluded = FimbyBlockingHelper.getBidirectionalBlocks(contactId);

System.debug('=== Welcome email ' + (PREVIEW_ONLY ? 'preview' : 'SEND') + ' ===');
System.debug('User Id: ' + u.Id + ' | Contact Id: ' + contactId + ' | NH: ' + nhId);
System.debug('Recipient: ' + firstName + ' <' + u.Email + '> | Neighbourhood: ' + neighbourhoodName);
System.debug('Welcome_Email_Sent_Date__c: ' + u.Contact.Welcome_Email_Sent_Date__c);

if (!PREVIEW_ONLY && u.Contact.Welcome_Email_Sent_Date__c != null && !CLEAR_SEND_GUARD) {
    System.debug(LoggingLevel.ERROR,
        'Welcome email already sent for this Contact. Set CLEAR_SEND_GUARD = true to re-test, or pick another Contact.');
    return;
}

FimbyDigestEmailBuilder.DigestResult preview = FimbyDigestEmailBuilder.buildCappedMixedPreview(
    nhId, windowStart, windowEnd, PREVIEW_MAX, excluded
);

System.debug('Window: ' + windowStart + ' .. ' + windowEnd);
System.debug('Mini-digest itemCount: ' + preview.itemCount + ' | isEmpty: ' + preview.isEmpty);
if (!preview.selectedItemSummaries.isEmpty()) {
    System.debug('Selected items (type-mixed, max ' + PREVIEW_MAX + '):');
    for (String line : preview.selectedItemSummaries) {
        System.debug('  - ' + line);
    }
}

String cardHtml = FimbyOnboardingWelcomeEmailBuilder.buildFullBodyHtml(
    firstName, neighbourhoodName, preview
);
String envelopeSubject = FimbyOnboardingWelcomeEmailBuilder.buildSubject(firstName);
String headerTitle = FimbyOnboardingWelcomeEmailBuilder.HEADER_TITLE;

System.debug('Envelope subject: ' + envelopeSubject);
System.debug('Header title (H1): ' + headerTitle);

if (PREVIEW_ONLY) {
    System.debug('--- Inner HTML (card body) ---');
    Integer chunk = 4000;
    for (Integer i = 0; i < cardHtml.length(); i += chunk) {
        Integer endIdx = Math.min(i + chunk, cardHtml.length());
        System.debug(cardHtml.substring(i, endIdx));
    }
    String shell = FimbyEmailHtmlBuilder.wrapInBrandedShell(
        cardHtml, envelopeSubject, neighbourhoodName, null, false, false, null, false, headerTitle
    );
    System.debug('--- Full branded shell length: ' + shell.length() + ' chars ---');
    System.debug('Mini-digest included: ' + (!preview.isEmpty));
    System.debug('PREVIEW_ONLY is true — no email sent. Set PREVIEW_ONLY = false to enqueue the real send.');
    return;
}

if (CLEAR_SEND_GUARD && u.Contact.Welcome_Email_Sent_Date__c != null) {
    update new Contact(Id = contactId, Welcome_Email_Sent_Date__c = null);
    System.debug('Cleared Welcome_Email_Sent_Date__c for re-test.');
}

Id jobId = System.enqueueJob(new FimbyOnboardingWelcomeEmailQueueable(contactId, u.Id, nhId));
System.debug('Enqueued FimbyOnboardingWelcomeEmailQueueable — Job Id: ' + jobId);
System.debug('Check inbox at ' + u.Email + ' (may take a few seconds). Re-query Contact.Welcome_Email_Sent_Date__c after job completes.');
