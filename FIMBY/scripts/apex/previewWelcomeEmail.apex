/**
 * Dev Console preview — paste into Execute Anonymous (does NOT send email).
 * Default persona: sarah@fimby.com — change TARGET_EMAIL to preview another neighbour.
 */
String TARGET_EMAIL = 'sarah@fimby.com';
Integer PREVIEW_MAX = 5;
Integer WINDOW_DAYS = 7;

List<User> users = [
    SELECT Id, FirstName, Email, ContactId, Contact.AccountId, Contact.Account.Name
    FROM User
    WHERE Email = :TARGET_EMAIL
      AND IsActive = true
    LIMIT 1
];
if (users.isEmpty()) {
    System.debug(LoggingLevel.ERROR, 'No active User found for ' + TARGET_EMAIL);
} else {
    User u = users[0];
    Id nhId = u.Contact.AccountId;
    Id contactId = u.ContactId;
    Date windowEnd = Date.today();
    Date windowStart = windowEnd.addDays(-WINDOW_DAYS);
    Set<Id> excluded = FimbyBlockingHelper.getBidirectionalBlocks(contactId);

    System.debug('=== Welcome email preview ===');
    System.debug('User: ' + u.Email + ' | Contact: ' + contactId + ' | NH: ' + nhId);
    System.debug('Window: ' + windowStart + ' .. ' + windowEnd);

    FimbyDigestEmailBuilder.DigestResult preview = FimbyDigestEmailBuilder.buildCappedMixedPreview(
        nhId, windowStart, windowEnd, PREVIEW_MAX, excluded
    );

    System.debug('Mini-digest itemCount: ' + preview.itemCount + ' | isEmpty: ' + preview.isEmpty);
    if (!preview.selectedItemSummaries.isEmpty()) {
        System.debug('Selected items (type-mixed, max ' + PREVIEW_MAX + '):');
        for (String line : preview.selectedItemSummaries) {
            System.debug('  - ' + line);
        }
    } else {
        System.debug('No neighbourhood content in window — email will omit mini-digest section.');
    }

    String cardHtml = FimbyOnboardingWelcomeEmailBuilder.buildFullBodyHtml(
        u.FirstName, u.Contact.Account.Name, preview
    );
    String subject = FimbyOnboardingWelcomeEmailBuilder.SUBJECT;

    System.debug('Subject: ' + subject);
    System.debug('--- Inner HTML (card body) ---');
    Integer chunk = 4000;
    for (Integer i = 0; i < cardHtml.length(); i += chunk) {
        Integer endIdx = Math.min(i + chunk, cardHtml.length());
        System.debug(cardHtml.substring(i, endIdx));
    }

    String shell = FimbyEmailHtmlBuilder.wrapInBrandedShell(
        cardHtml, subject, u.Contact.Account.Name, null, false, false, u.FirstName, false
    );
    System.debug('--- Full branded shell length: ' + shell.length() + ' chars ---');
    System.debug('Mini-digest included: ' + (!preview.isEmpty));
}
