// ============================================================================
// SEND DIGEST EMAIL MANUALLY
// ============================================================================
// Sends the digest to ONE user so you can eyeball the new image layout
// without emailing every active neighbour. Does not write a digest log row.
//
// Run via: Salesforce Developer Console → Debug → Open Execute Anonymous
//          window, OR  `sf apex run --file scripts/apex/send-digest-email-manually.apex`
// ============================================================================

String targetEmail = 'stephen@strathconavineyard.com';            // <-- set the recipient
String frequency   = 'Weekly';                       // 'Daily' or 'Weekly'
Date windowStart   = Date.today().addDays(-8);      // widen (e.g. -7) if yesterday had no posts
Date windowEnd     = Date.today().addDays(-1);

User u = [
    SELECT Id, FirstName, Email, Contact.AccountId, Contact.Account.Name
    FROM User
    WHERE Email = :targetEmail AND IsActive = true
    LIMIT 1
];

if (u.Contact.AccountId == null) {
    System.debug('STOP: user has no Contact/neighbourhood: ' + targetEmail);
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
        String timeRange = (windowEnd > windowStart)
            ? windowStart.format() + ' - ' + windowEnd.format()
            : windowStart.format();
        String bodyContent =
            '<p style="margin:0 0 12px;font-family:Verdana, Geneva, sans-serif;font-size:13px;color:#6B6B6B;">'
            + timeRange.escapeHtml4() + '</p>' + content.html;

        String html = FimbyEmailHtmlBuilder.wrapInBrandedShell(
            bodyContent, subject, nhName,
            FimbyEmailHtmlBuilder.getRandomIntentLine(),
            false, false, u.FirstName
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
        System.debug('Sent test digest to ' + targetEmail + ' (' + content.itemCount + ' cards).');
    }
}
