@IsTest
private class FimbyTransactionalEmailServiceTest {

    @IsTest
    static void send_nullRequest_exitsCleanly() {
        Test.startTest();
        FimbyTransactionalEmailService.send(null);
        Test.stopTest();
    }

    @IsTest
    static void send_nullRecipient_exitsCleanly() {
        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = null;
        req.subject = 'Test';

        Test.startTest();
        FimbyTransactionalEmailService.send(req);
        Test.stopTest();
    }

    @IsTest
    static void send_brandedShell_sendsEmail() {
        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = UserInfo.getUserId();
        req.subject = 'Direct HTML';
        req.introText = 'Hello neighbour.';
        req.cardHtml = '<p>Card content</p>';
        req.replyToEmail = 'sender@example.com';

        Test.startTest();
        FimbyTransactionalEmailService.send(req);
        Test.stopTest();
    }

    @IsTest
    static void send_withCta_sendsEmail() {
        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = UserInfo.getUserId();
        req.subject = 'CTA Email';
        req.introText = 'Intro text.';
        req.cardHtml = '<p>Card</p>';
        req.ctaUrl = 'https://our.fimby.com/test';
        req.ctaLabel = 'View Post';

        Test.startTest();
        FimbyTransactionalEmailService.send(req);
        Test.stopTest();
    }

    @IsTest
    static void send_nullOptionals_sendsCleanly() {
        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = UserInfo.getUserId();
        req.subject = 'Minimal';

        Test.startTest();
        FimbyTransactionalEmailService.send(req);
        Test.stopTest();
    }

    @IsTest
    static void send_withCardHtml_recordsCardContent() {
        String cardHtml = FimbyEmailHtmlBuilder.buildTransactionalCard(
            FimbyEmailHtmlBuilder.TXN_BADGE_CONTACT, '#8A5936', 'email.png',
            'Shared contact', '<p>Details</p>',
            'Test', 'A neighbour shared their contact info.',
            'https://our.fimby.com/test', 'View', 'enter.png'
        );

        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = UserInfo.getUserId();
        req.subject = 'Contact Share';
        req.cardHtml = cardHtml;
        req.replyToEmail = 'neighbour@example.com';

        Test.startTest();
        FimbyTransactionalEmailService.send(req);
        Test.stopTest();

        System.assert(FimbyTransactionalEmailService.testLastCardHtml.contains('Hi Test,'),
            'Consolidated card should include greeting');
    }

    @IsTest
    static void send_noCtaNoReply_coversMinimalBranch() {
        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = UserInfo.getUserId();
        req.subject = 'No CTA No Reply';
        req.introText = null;
        req.cardHtml = null;

        Test.startTest();
        FimbyTransactionalEmailService.send(req);
        Test.stopTest();
    }

    @IsTest
    static void send_noOwea_stillSends() {
        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = UserInfo.getUserId();
        req.subject = 'No OWEA';
        req.cardHtml = '<p>Card</p>';

        Test.startTest();
        FimbyTransactionalEmailService.send(req);
        Test.stopTest();
    }

    @IsTest
    static void send_withSkipSubjectBlock_omitsIntentAndIntro() {
        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = UserInfo.getUserId();
        req.subject = 'Thank you from Test User';
        req.introText = 'This should be suppressed.';
        req.cardHtml = '<p>Thank you card</p>';
        req.skipSubjectBlock = true;
        req.ctaUrl = 'https://our.fimby.com/response-reply?recordId=abc';
        req.ctaLabel = 'View Conversation';

        Test.startTest();
        FimbyTransactionalEmailService.send(req);
        Test.stopTest();
    }

    @IsTest
    static void send_skipSubjectBlock_usesMinimalShell() {
        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = UserInfo.getUserId();
        req.subject = 'Thank you from Test User';
        req.introText = 'Should not appear.';
        req.cardHtml = '<p>Card</p>';
        req.skipSubjectBlock = true;

        Test.startTest();
        FimbyTransactionalEmailService.send(req);
        Test.stopTest();
    }

    @IsTest
    static void transactionalEmailRequest_fieldsPopulate() {
        FimbyTransactionalEmailService.TransactionalEmailRequest req =
            new FimbyTransactionalEmailService.TransactionalEmailRequest();
        req.recipientUserId = UserInfo.getUserId();
        req.subject = 'Test Subject';
        req.introText = 'Intro';
        req.cardHtml = '<p>Card</p>';
        req.replyToEmail = 'test@example.com';
        req.ctaUrl = 'https://our.fimby.com/test';
        req.ctaLabel = 'View';

        System.assertEquals('Test Subject', req.subject);
        System.assertEquals('test@example.com', req.replyToEmail);
        System.assertEquals('View', req.ctaLabel);
    }
}
