// Sandbox smoke test (Phase 7) for the email render path:
// confirms CTA URLs are single-prefix absolute URLs after
// the centralization work. Run via:
//   sf apex run --file scripts/apex/verify-email-render.apex
//
// Builds 3 sample notification rows in memory (no DML) and
// prints the rendered alert-card HTML, then sanity-checks
// that every href starts with the FimbySettings Site_Base URL
// exactly once (no double http://, no relative leftovers).

Contact c = [SELECT Id FROM Contact WHERE Email != null LIMIT 1];
String baseUrl = FimbySettings.getUrl('Site_Base');
System.debug('Site_Base resolved: ' + baseUrl);

// Sample with relative Action_URL__c (the new norm after Phase 1c).
Notification__c relative = new Notification__c(
    Contact__c = c.Id,
    Type__c = FimbyConstants.NOTIF_LENDING_REQUEST,
    Title__c = 'Sam wants to borrow your drill',
    Body__c = 'Pick up Saturday morning works for them.',
    Action_URL__c = FimbySettings.getUrl('Library_Item', 'a005f000004XYZAAA4'),
    Actor_Name__c = 'Sam Rivera',
    Related_Record_Type__c = 'Lending_Request__c'
);

// Sample with an absolute URL already (should NOT be re-prefixed).
Notification__c absolute = new Notification__c(
    Contact__c = c.Id,
    Type__c = FimbyConstants.NOTIF_VOUCH_APPROVED,
    Title__c = 'You have been welcomed in',
    Body__c = 'The library is open.',
    Action_URL__c = 'https://our.fimby.com/library-list',
    Actor_Name__c = 'Sam Rivera',
    Related_Record_Type__c = 'Vouch_Record__c'
);

// Sample with blank Action_URL__c (should fall back to base + /notifications).
Notification__c blank = new Notification__c(
    Contact__c = c.Id,
    Type__c = FimbyConstants.NOTIF_RESPONSE,
    Title__c = 'Someone responded to your post',
    Body__c = '',
    Action_URL__c = null,
    Actor_Name__c = 'Alex Park',
    Related_Record_Type__c = 'Response__c'
);

String html = FimbyEmailHtmlBuilder.buildAlertCards(
    new List<Notification__c>{ relative, absolute, blank }
);

System.debug('--- Rendered HTML ---');
System.debug(html);

// Sanity checks.
Pattern p = Pattern.compile('href="([^"]+)"');
Matcher m = p.matcher(html);
Integer hrefCount = 0;
while (m.find()) {
    hrefCount++;
    String href = m.group(1);
    Boolean startsAbsolute = href.startsWith('http://') || href.startsWith('https://');
    Boolean noDoubleScheme = !href.substring(8).contains('http://') && !href.substring(8).contains('https://');
    System.debug('href[' + hrefCount + ']: ' + href
        + ' | absolute=' + startsAbsolute
        + ' | singlePrefix=' + noDoubleScheme);
    System.assert(startsAbsolute, 'Email href must be absolute: ' + href);
    System.assert(noDoubleScheme, 'Email href must have single scheme prefix: ' + href);
}
System.debug('Total hrefs scanned: ' + hrefCount);
System.assert(hrefCount >= 3, 'Expected at least one href per sample card');
