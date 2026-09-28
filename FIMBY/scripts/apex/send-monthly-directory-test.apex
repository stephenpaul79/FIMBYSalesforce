// ============================================================================
// SEND MONTHLY LIBRARY EMAIL (TEST) - one neighbourhood, one recipient
// ============================================================================
// Builds this month's "Items To Borrow / Skills On Offer" email exactly as the
// scheduled job would for ONE recipient (their blocks and adjacent-neighbourhood
// visibility applied) and emails them a single copy.
//
// - Ignores the recipient's Library email toggle so you can test with it off.
// - Writes no Digest_Email_Log__c row, so the real monthly send is unaffected.
// - previewOnly = true builds and reports sizes without sending.
//
// Run via: Developer Console -> Debug -> Open Execute Anonymous Window, OR
//   sf apex run --file scripts/apex/send-monthly-directory-test.apex
// ============================================================================

String neighbourhoodName = 'Strathcona / DTES';    // Boundary_Account Name (0015f00000DV5kUAAT)
String targetUsername    = 'stephen@fimby.com';    // Stephen Rathjen experience user (005OL00000GyVpKYAV)
Boolean previewOnly      = false;                  // true = build + report size, don't send

List<Account> neighbourhoods = [
    SELECT Id, Name FROM Account
    WHERE Name = :neighbourhoodName AND RecordType.DeveloperName = 'Boundary_Account'
    LIMIT 1
];
List<User> users = [
    SELECT Id, FirstName, IsActive, ContactId, Contact.AccountId
    FROM User WHERE Username = :targetUsername LIMIT 1
];

if (neighbourhoods.isEmpty()) {
    System.debug('STOP: no Boundary_Account named "' + neighbourhoodName + '".');
} else if (users.isEmpty()) {
    System.debug('STOP: no User with Username ' + targetUsername + ' (Setup > Users).');
} else if (!users[0].IsActive) {
    System.debug('STOP: ' + targetUsername + ' is inactive and cannot receive email.');
} else if (users[0].ContactId == null) {
    System.debug('STOP: ' + targetUsername + ' has no Contact, so there is no neighbour view to build.');
} else {
    Account nh = neighbourhoods[0];
    User u = users[0];
    if (u.Contact.AccountId != nh.Id) {
        System.debug('NOTE: ' + targetUsername + ' lives in a different neighbourhood; '
            + 'building ' + nh.Name + ' as if they lived there.');
    }

    FimbyMonthlyDirectorySendQueueable.RenderedEmail email =
        FimbyMonthlyDirectorySendQueueable.previewForRecipient(nh.Id, nh.Name, u.Id);
    FimbyMonthlyDirectoryEmailBuilder.DirectoryResult r = email.result;
    Decimal kb = Decimal.valueOf(email.totalBytes).divide(1024, 1);
    Decimal capKb = Decimal.valueOf(FimbyMonthlyDirectorySendQueueable.EMAIL_BYTE_CAP).divide(1024, 0);

    System.debug('Full email size: ' + email.totalBytes + ' bytes (' + kb + ' KB) of a ' + capKb + ' KB budget');
    System.debug('Items shown: ' + r.itemsShown + ', left out: ' + r.itemsOmitted);
    System.debug('Skills shown: ' + r.skillsShown + ', left out: ' + r.skillsOmitted);
    System.debug('Owner initials dropped to save space: ' + r.droppedInitials);

    if (previewOnly) {
        System.debug('previewOnly = true, nothing sent.');
    } else {
        Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
        msg.setTargetObjectId(u.Id);
        msg.setTreatTargetObjectAsRecipient(true);
        msg.setSubject(FimbyMonthlyDirectorySendQueueable.SUBJECT + ' (test)');
        msg.setHtmlBody(email.html);
        msg.setSaveAsActivity(false);
        List<OrgWideEmailAddress> oweas = [
            SELECT Id FROM OrgWideEmailAddress WHERE DisplayName = 'FIMBY' LIMIT 1
        ];
        if (!oweas.isEmpty()) {
            msg.setOrgWideEmailAddressId(oweas[0].Id);
        }
        Messaging.SendEmailResult result = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ msg }, false
        )[0];
        System.debug(result.isSuccess()
            ? 'Sent test email to ' + targetUsername + '.'
            : 'Send failed: ' + result.getErrors()[0].getMessage());
    }
}
