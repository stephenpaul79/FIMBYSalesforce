// ============================================================================
// SEND DIGEST EMAIL MANUALLY
// ============================================================================
// Sends the digest to ONE user so you can eyeball the new image layout
// without emailing every active neighbour. Does not write a digest log row.
//
// Picks the recipient by USERNAME (Setup -> Users -> Username column), which is
// globally unique across the org, so you always know exactly who you selected.
// (Email addresses are NOT unique - the same email can sit on many Contacts and
// active/inactive Users, which is why the old email-based version was ambiguous.)
//
// Run via: Salesforce Developer Console -> Debug -> Open Execute Anonymous
//          window, OR  `sf apex run --file scripts/apex/send-digest-email-manually.apex`
// ============================================================================

String targetUsername = 'stephen@strathconavineyard.com';   // <-- set the exact Username (Setup > Users)
String frequency      = 'Weekly';                            // 'Daily' or 'Weekly'
Date windowStart      = Date.today().addDays(-8);            // widen if the window had no posts
Date windowEnd        = Date.today().addDays(-1);

List<User> users = [
    SELECT Id, FirstName, Username, IsActive, Contact.AccountId, Contact.Account.Name
    FROM User
    WHERE Username = :targetUsername
    LIMIT 1
];

if (users.isEmpty()) {
    System.debug('STOP: no User found with Username = ' + targetUsername
        + '. Check Setup > Users for the exact Username.');
} else {
    User u = users[0];

    if (!u.IsActive) {
        System.debug('STOP: User ' + targetUsername + ' is inactive - cannot receive email.');
    } else if (u.Contact.AccountId == null) {
        System.debug('STOP: User ' + targetUsername + ' has no Contact/neighbourhood, '
            + 'so there is no neighbourhood digest to build.');
    } else {
        Id nhId = u.Contact.AccountId;
        String nhName = u.Contact.Account.Name;

        FimbyDigestEmailBuilder.DigestResult content =
            FimbyDigestEmailBuilder.buildDigestContent(nhId, nhName, frequency, windowStart, windowEnd);

        if (content.isEmpty) {
            System.debug('No feed-card content for ' + nhName + ' in window '
                + windowStart + ' to ' + windowEnd + '. Widen the window and retry.');
        } else {
            String subject = 'Your ' + frequency.toLowerCase() + ' neighbourhood update (test)';
            String displaySubject = 'Here\'s your ' + frequency.toLowerCase() + ' neighbourhood update (test)';

            String html = FimbyEmailHtmlBuilder.wrapInBrandedShell(
                content.html, displaySubject, nhName,
                null,
                false, false, u.FirstName, true
            );

            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setTargetObjectId(u.Id);
            email.setTreatTargetObjectAsRecipient(true);
            email.setSubject(subject);
            email.setHtmlBody(html);
            email.setSaveAsActivity(false);

            List<OrgWideEmailAddress> oweas = [
                SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = 'FIMBY' LIMIT 1
            ];
            if (!oweas.isEmpty()) {
                email.setOrgWideEmailAddressId(oweas[0].Id);
            }

            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
            System.debug('Sent test digest to ' + targetUsername
                + ' (' + content.itemCount + ' cards).');
        }
    }
}
