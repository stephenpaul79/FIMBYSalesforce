/**
 * @description Tests for FimbyReactivationEmailService. Body assertions cover
 * the protocol-bearing wording (scheduled date, restore URL, grace window
 * number) that must not regress without an explicit deploy. Also asserts that
 * the branded HTML body is set and excludes the chrome we deliberately strip
 * for accounts that cannot log in (no notifications icon, no email-preferences
 * footer link), while welcome-back keeps the full chrome.
 */
@IsTest
private class FimbyReactivationEmailServiceTest {

    @TestSetup
    static void setup() {
        Account neighbourhood = FimbyTestDataFactory.createNeighbourhood(true);
        Contact contact = FimbyTestDataFactory.createNeighbourhoodContact(neighbourhood.Id, true);
        FimbyTestDataFactory.createCommunityUser(
            contact.Id, 'Customer Community User - Mobile App', true);
    }

    private static User communityUser() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        return [SELECT Id, ContactId FROM User WHERE ContactId = :c.Id LIMIT 1];
    }

    @IsTest
    static void sendDeleteWithGraceConfirmationIncludesRestoreLinkAndDate() {
        User u = communityUser();
        FimbyReactivationEmailService.testCapturedEmails =
            new List<Messaging.SingleEmailMessage>();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        FimbyReactivationEmailService.sendDeleteWithGraceConfirmation(u.ContactId, u.Id);
        Test.stopTest();

        System.assertEquals(1, FimbyReactivationEmailService.testEmailsSent);
        Messaging.SingleEmailMessage sent =
            FimbyReactivationEmailService.testCapturedEmails[0];

        System.assertEquals('Your account is scheduled for deletion', sent.getSubject(),
            'Subject should not be prefixed with [FIMBY]; sender name already says FIMBY');

        String plain = sent.getPlainTextBody();
        System.assert(plain.contains('30'),
            'Plain body should mention the 30-day grace window');
        System.assert(plain.contains('Scheduled deletion'),
            'Plain body should advertise the scheduled-deletion line');
        System.assert(plain.contains('/reactivate?token='),
            'Plain body should embed the restore URL with token query param');
        System.assert(plain.contains('account-paused'),
            'Plain body should mention the /account-paused fallback');

        String html = sent.getHtmlBody();
        System.assertNotEquals(null, html, 'Branded HTML body should be set');
        System.assert(html.contains('SCHEDULED'),
            'HTML body should render the SCHEDULED badge pill');
        System.assert(html.contains('Hi ') && html.contains(','),
            'HTML body should include a personal greeting line');
        System.assert(html.contains('/reactivate?token='),
            'HTML body should embed the restore URL');
        System.assert(!html.contains('/notifications'),
            'Deactivated-account email should not link to /notifications');
        System.assert(!html.contains('Email preferences'),
            'Deactivated-account email should not show Email preferences link');

        System.assertEquals(1,
            [SELECT COUNT() FROM Reactivation_Token__c WHERE Contact__c = :u.ContactId],
            'Confirmation should mint exactly one grace-window token');
    }

    @IsTest
    static void sendReactivationLinkIncludesTokenAndTtl() {
        User u = communityUser();
        FimbyReactivationEmailService.testCapturedEmails =
            new List<Messaging.SingleEmailMessage>();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        FimbyReactivationEmailService.sendReactivationLink(u.Id, 'abc-test-token');
        Test.stopTest();

        System.assertEquals(1, FimbyReactivationEmailService.testEmailsSent);
        Messaging.SingleEmailMessage sent =
            FimbyReactivationEmailService.testCapturedEmails[0];

        System.assertEquals(u.ContactId, sent.getTargetObjectId(),
            'Restore-link email should target the linked Contact, not the inactive User');
        System.assertEquals('Restore your FIMBY account', sent.getSubject(),
            'Subject should not be prefixed with [FIMBY]');

        String plain = sent.getPlainTextBody();
        System.assert(plain.contains('abc-test-token'),
            'Token should appear in the plain restore URL');
        System.assert(plain.contains('24'),
            'Default 24-hour TTL should appear in the body');

        String html = sent.getHtmlBody();
        System.assertNotEquals(null, html, 'Branded HTML body should be set');
        System.assert(html.contains('RESTORE LINK'),
            'HTML body should render the RESTORE LINK badge pill');
        System.assert(html.contains('abc-test-token'),
            'HTML body should embed the magic-link token');
        System.assert(!html.contains('Email preferences'),
            'Restore-link email should not show Email preferences link');
    }

    @IsTest
    static void sendWelcomeBackHasFriendlyCopyAndFullChrome() {
        User u = communityUser();
        FimbyReactivationEmailService.testCapturedEmails =
            new List<Messaging.SingleEmailMessage>();
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        FimbyReactivationEmailService.sendWelcomeBack(u.Id);
        Test.stopTest();

        System.assertEquals(1, FimbyReactivationEmailService.testEmailsSent);
        Messaging.SingleEmailMessage sent =
            FimbyReactivationEmailService.testCapturedEmails[0];

        System.assertEquals('Welcome back', sent.getSubject(),
            'Subject should not be prefixed with [FIMBY]');

        String plain = sent.getPlainTextBody();
        System.assert(plain.contains('Welcome back'),
            'Plain welcome-back body should greet the user');
        System.assert(plain.contains('/login'),
            'Plain body should point users to the login page');

        String html = sent.getHtmlBody();
        System.assertNotEquals(null, html, 'Branded HTML body should be set');
        System.assert(html.contains('RESTORED'),
            'HTML body should render the RESTORED badge pill');
        System.assert(html.contains('Email preferences'),
            'Welcome-back email should restore the full footer (user can log in again)');
    }

    @IsTest
    static void sendersTolerateNullArgs() {
        FimbyReactivationEmailService.testEmailsSent = 0;

        Test.startTest();
        FimbyReactivationEmailService.sendDeleteWithGraceConfirmation(null, null);
        FimbyReactivationEmailService.sendReactivationLink(null, null);
        FimbyReactivationEmailService.sendWelcomeBack(null);
        Test.stopTest();

        System.assertEquals(0, FimbyReactivationEmailService.testEmailsSent,
            'Null args should noop, not throw');
    }
}
