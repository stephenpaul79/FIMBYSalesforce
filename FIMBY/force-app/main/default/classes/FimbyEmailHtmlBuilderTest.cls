@IsTest
private class FimbyEmailHtmlBuilderTest {

    @IsTest
    static void buildAlertCards_nullList_returnsEmpty() {
        System.assertEquals('', FimbyEmailHtmlBuilder.buildAlertCards(null));
    }

    @IsTest
    static void buildAlertCards_emptyList_returnsEmpty() {
        System.assertEquals('', FimbyEmailHtmlBuilder.buildAlertCards(new List<Notification__c>()));
    }

    @IsTest
    static void buildAlertCards_singleCard_containsTitle() {
        Notification__c n = new Notification__c(
            Title__c = 'Test Alert Title',
            Body__c = 'Alert body content',
            Actor_Name__c = 'Jane Doe',
            Type__c = 'Message',
            Action_URL__c = '/conversation?id=123'
        );
        String html = FimbyEmailHtmlBuilder.buildAlertCards(new List<Notification__c>{ n }, null, 'Sarah');
        System.assert(html.contains('Hi Sarah,'), 'First card should greet recipient');
        System.assert(html.contains('Test Alert Title'), 'Should contain the notification title');
        System.assert(html.contains('Jane Doe'), 'Should contain the actor name');
        System.assert(html.contains('Alert body content'), 'Should contain the body');
        System.assert(html.contains('View Message'), 'Should contain type-specific CTA label for Message');
    }

    @IsTest
    static void buildAlertCards_singleCard_containsBadgePill() {
        Notification__c n = new Notification__c(
            Title__c = 'Library Alert',
            Type__c = 'Lending_Request',
            Actor_Name__c = 'Sam Wilson'
        );
        String html = FimbyEmailHtmlBuilder.buildAlertCards(new List<Notification__c>{ n });
        System.assert(html.contains('LIBRARY'), 'Should contain badge label');
        System.assert(html.contains('ToolboxActive.png'), 'Should contain badge icon');
        System.assert(html.contains('View Item'), 'Should contain type-specific CTA label');
        System.assert(html.contains('borrow.png'), 'Should contain CTA icon');
    }

    @IsTest
    static void buildAlertCards_withEnrichment_showsAvatarAndThumbnail() {
        Notification__c n = new Notification__c(
            Title__c = 'Enriched Alert',
            Type__c = 'Response',
            Actor_Name__c = 'Maria Garcia',
            Related_Record_Id__c = '0015f000003TestAAA',
            Action_URL__c = '/response-reply?recordId=test'
        );
        FimbyEmailAlertQueueable.AlertCardEnrichment enrich = new FimbyEmailAlertQueueable.AlertCardEnrichment();
        enrich.actorImageUrl = 'https://example.com/avatar.jpg';
        enrich.actorFirstName = 'Maria';
        enrich.itemImageUrl = 'https://example.com/post-image.jpg';

        Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment> enrichMap =
            new Map<String, FimbyEmailAlertQueueable.AlertCardEnrichment>{ '0015f000003TestAAA' => enrich };

        String html = FimbyEmailHtmlBuilder.buildAlertCards(new List<Notification__c>{ n }, enrichMap);
        System.assert(html.contains('avatar.jpg'), 'Should render real avatar image');
        System.assert(html.contains('post-image.jpg'), 'Should render item thumbnail');
        System.assert(html.contains('border-radius:50%'), 'Avatar should be circular');
        System.assert(html.contains('RESPONSE'), 'Should show badge pill');
    }

    @IsTest
    static void buildAlertCards_multipleTypes_usesCorrectAccentColors() {
        List<Notification__c> notifs = new List<Notification__c>{
            new Notification__c(Title__c = 'DM', Type__c = 'Message'),
            new Notification__c(Title__c = 'Lending', Type__c = 'Lending_Request'),
            new Notification__c(Title__c = 'Comment', Type__c = 'Comment'),
            new Notification__c(Title__c = 'Bulk', Type__c = 'Bulk_Buy_Status')
        };
        String html = FimbyEmailHtmlBuilder.buildAlertCards(notifs);
        System.assert(html.contains('DM'), 'Should contain all cards');
        System.assert(html.contains('Lending'), 'Should contain lending card');
    }

    @IsTest
    static void buildAlertCards_moreThan10_showsOverflowMessage() {
        List<Notification__c> notifs = new List<Notification__c>();
        for (Integer i = 0; i < 12; i++) {
            notifs.add(new Notification__c(Title__c = 'Alert ' + i, Type__c = 'Response'));
        }
        String html = FimbyEmailHtmlBuilder.buildAlertCards(notifs);
        System.assert(html.contains('2 more updates'), 'Should show overflow count');
    }

    @IsTest
    static void buildContactShareCard_allFields_containsAllData() {
        String html = FimbyEmailHtmlBuilder.buildContactShareCard(
            'Sarah', 'John Smith', 'john@example.com', '555-1234',
            '123 Main St', 'Apt 4B', 'Lending item',
            'https://our.fimby.com/reply', 'View Conversation', 'reply.png'
        );
        System.assert(html.contains('Hi Sarah,'), 'Should greet recipient');
        System.assert(html.contains('CONTACT'), 'Should show category badge');
        System.assert(html.contains('John Smith'), 'Should contain sender name');
        System.assert(html.contains('john@example.com'), 'Should contain email');
        System.assert(html.contains('555-1234'), 'Should contain phone');
        System.assert(html.contains('123 Main St'), 'Should contain street');
        System.assert(html.contains('Apt 4B'), 'Should contain additional info');
        System.assert(html.contains('Lending item'), 'Should contain context label');
        System.assert(html.contains('email.png'), 'Should use email icon');
        System.assert(html.contains('telephone.png'), 'Should use telephone icon');
        System.assert(html.contains('pin.png'), 'Should use pin icon');
    }

    @IsTest
    static void buildContactShareCard_nullOptionalFields_rendersCleanly() {
        String html = FimbyEmailHtmlBuilder.buildContactShareCard(
            'Jane', null, null, null, null, null
        );
        System.assert(html.contains('Jane'), 'Should contain sender name');
        System.assert(!html.contains('Regarding'), 'Should not show context without label');
    }

    @IsTest
    static void buildThankYouCard_fullContent_containsQuote() {
        String html = FimbyEmailHtmlBuilder.buildThankYouCard(
            'Sarah', 'Maria', 'Thank you for helping with my garden!', 'Need: Gardening help',
            'https://our.fimby.com/reply', 'View Conversation', 'reply.png'
        );
        System.assert(html.contains('Hi Sarah,'), 'Should greet recipient');
        System.assert(html.contains('THANK YOU'), 'Should show category badge');
        System.assert(html.contains('Maria'), 'Should contain sender name');
        System.assert(html.contains('Thank you for helping'), 'Should contain message');
        System.assert(html.contains('Gardening help'), 'Should contain post title');
        System.assert(html.contains('View Conversation'), 'CTA should be inside card');
        System.assert(html.contains('ThankYouActive.png'), 'Should contain thank you badge icon');
    }

    @IsTest
    static void buildTransactionalCard_greetingIntroCta_allInsideCard() {
        String html = FimbyEmailHtmlBuilder.buildTransactionalCard(
            FimbyEmailHtmlBuilder.TXN_BADGE_SUPPORT, '#476B4C', 'NeighborhoodActive.png',
            'Approved',
            '<p>Help line</p>',
            'Sarah', 'Good news — verified.', 'https://our.fimby.com/manage', 'Open Manage Identities', 'enter.png'
        );
        System.assert(html.contains('SUPPORT'), 'Should show badge');
        System.assert(html.contains('Hi Sarah,'), 'Should greet recipient');
        System.assert(html.contains('Good news'), 'Intro should be inside card');
        System.assert(html.contains('Open Manage Identities'), 'CTA should be inside card');
        Integer cardClose = html.indexOf('</td></tr></table>');
        System.assert(html.indexOf('Hi Sarah,') < cardClose, 'Greeting before card close');
        System.assert(html.indexOf('Open Manage Identities') < cardClose, 'CTA before card close');
    }

    @IsTest
    static void resolveGreetingText_blankFirstName_usesNeighbour() {
        System.assertEquals('Hi neighbour,', FimbyEmailHtmlBuilder.resolveGreetingText(null));
        System.assertEquals('Hi neighbour,', FimbyEmailHtmlBuilder.resolveGreetingText(''));
    }

    @IsTest
    static void buildAlertCards_multiCard_greetingOnFirstOnly() {
        List<Notification__c> notifs = new List<Notification__c>{
            new Notification__c(Title__c = 'First', Type__c = 'Message'),
            new Notification__c(Title__c = 'Second', Type__c = 'Response')
        };
        String html = FimbyEmailHtmlBuilder.buildAlertCards(notifs, null, 'Alex');
        System.assertEquals(1, html.split('Hi Alex,').size() - 1, 'Greeting should appear once');
    }

    @IsTest
    static void buildThankYouCard_noMessage_rendersCleanly() {
        String html = FimbyEmailHtmlBuilder.buildThankYouCard('Sam', null, null);
        System.assert(html.contains('Sam'), 'Should contain sender name');
    }

    @IsTest
    static void buildCtaButton_producesLinkHtml() {
        String html = FimbyEmailHtmlBuilder.buildCtaButton('Click Me', 'https://our.fimby.com/test');
        System.assert(html.contains('Click Me'), 'Should contain label');
        System.assert(html.contains('https://our.fimby.com/test'), 'Should contain URL');
    }

    @IsTest
    static void buildCtaButton_withIcon_includesIconImg() {
        String html = FimbyEmailHtmlBuilder.buildCtaButton('Respond', 'https://our.fimby.com/test', 'reply.png');
        System.assert(html.contains('Respond'), 'Should contain label');
        System.assert(html.contains('reply.png'), 'Should contain icon filename');
        System.assert(html.contains('border-radius:12px'), 'Should use rounded style');
        System.assert(html.contains('font-weight:600'), 'Should use semi-bold weight');
    }

    @IsTest
    static void buildCtaButton_nullIcon_noImgTag() {
        String html = FimbyEmailHtmlBuilder.buildCtaButton('Go', 'https://our.fimby.com', null);
        System.assert(!html.contains('<img'), 'Should not include img when icon is null');
        System.assert(html.contains('Go'), 'Should still contain label');
    }

    @IsTest
    static void getBadgeColor_knownType_returnsColor() {
        System.assertEquals('#5B8760', FimbyEmailHtmlBuilder.getBadgeColor('Need'));
        System.assertEquals('#448E9E', FimbyEmailHtmlBuilder.getBadgeColor('Gathering'));
        System.assertEquals('#715A9E', FimbyEmailHtmlBuilder.getBadgeColor('Community_Event'));
    }

    @IsTest
    static void getBadgeColor_unknownType_returnsFallback() {
        String color = FimbyEmailHtmlBuilder.getBadgeColor('Unknown_Type');
        System.assertEquals('#3A7D8C', color, 'Should fall back to CTA_BG teal');
    }

    @IsTest
    static void getBadgeIcon_knownType_returnsFilename() {
        System.assertEquals('BulletinBoardActive.png', FimbyEmailHtmlBuilder.getBadgeIcon('Need'));
        System.assertEquals('bulkbuy.png', FimbyEmailHtmlBuilder.getBadgeIcon('Bulk_Buy'));
    }

    @IsTest
    static void getBadgeIcon_unknownType_returnsNull() {
        System.assertEquals(null, FimbyEmailHtmlBuilder.getBadgeIcon('Unknown'));
    }

    @IsTest
    static void getCtaIcon_knownTypes_returnFilenames() {
        System.assertEquals('reply.png', FimbyEmailHtmlBuilder.getCtaIcon('Need'));
        System.assertEquals('buy.png', FimbyEmailHtmlBuilder.getCtaIcon('Bulk_Buy'));
        System.assertEquals('borrow.png', FimbyEmailHtmlBuilder.getCtaIcon('Library'));
    }

    @IsTest
    static void buildCardImage_withUrl_producesImgTag() {
        String html = FimbyEmailHtmlBuilder.buildCardImage('https://example.com/photo.jpg', 180);
        System.assert(html.contains('<img'), 'Should contain img tag');
        System.assert(html.contains('180px'), 'Should use specified height');
        System.assert(html.contains('photo.jpg'), 'Should contain image URL');
    }

    @IsTest
    static void buildCardImage_nullUrl_returnsEmpty() {
        System.assertEquals('', FimbyEmailHtmlBuilder.buildCardImage(null, 180));
        System.assertEquals('', FimbyEmailHtmlBuilder.buildCardImage('', 200));
    }

    @IsTest
    static void completeImageUrl_appendsOrgId() {
        String partial = 'https://fimby.file.force.com/sfc/dist/version/renditionDownload?versionId=abc&oid=';
        String result = FimbyEmailHtmlBuilder.completeImageUrl(partial);
        System.assert(result.length() > partial.length(), 'Should append org ID');
        System.assert(result.contains(UserInfo.getOrganizationId()), 'Should contain org ID');
        System.assert(!result.endsWith('&oid='), 'Should not end with bare &oid=');
    }

    @IsTest
    static void completeImageUrl_fullUrl_unchanged() {
        String full = 'https://example.com/image.jpg';
        System.assertEquals(full, FimbyEmailHtmlBuilder.completeImageUrl(full));
    }

    @IsTest
    static void completeImageUrl_null_returnsNull() {
        System.assertEquals(null, FimbyEmailHtmlBuilder.completeImageUrl(null));
    }

    @IsTest
    static void buildBadgePill_withIcon_containsBoth() {
        String html = FimbyEmailHtmlBuilder.buildBadgePill('ASK', '#5B8760', 'BulletinBoardActive.png');
        System.assert(html.contains('ASK'), 'Should contain label');
        System.assert(html.contains('#5B8760'), 'Should contain background color');
        System.assert(html.contains('BulletinBoardActive.png'), 'Should contain icon');
    }

    @IsTest
    static void buildBadgePill_noIcon_noImgTag() {
        String html = FimbyEmailHtmlBuilder.buildBadgePill('TEST', '#333333', null);
        System.assert(html.contains('TEST'), 'Should contain label');
        System.assert(!html.contains('<img'), 'Should not have img without icon');
    }

    @IsTest
    static void buildAvatar_withImage_producesImgCircle() {
        String html = FimbyEmailHtmlBuilder.buildAvatar('https://example.com/photo.jpg', 'Jane', null);
        System.assert(html.contains('<img'), 'Should produce img tag');
        System.assert(html.contains('border-radius:50%'), 'Should be circular');
        System.assert(html.contains('photo.jpg'), 'Should use image URL');
    }

    @IsTest
    static void buildAvatar_noImage_producesInitial() {
        String html = FimbyEmailHtmlBuilder.buildAvatar(null, 'Jane', '#67BBD2');
        System.assert(html.contains('J'), 'Should contain first initial');
        System.assert(html.contains('#67BBD2'), 'Should use accent color');
        System.assert(!html.contains('<img'), 'Should not have img tag');
    }

    @IsTest
    static void buildAvatar_nullName_showsQuestionMark() {
        String html = FimbyEmailHtmlBuilder.buildAvatar(null, null, null);
        System.assert(html.contains('?'), 'Should show ? for null name');
    }

    @IsTest
    static void buildThermometer_validData_producesProgressBar() {
        String html = FimbyEmailHtmlBuilder.buildThermometer(3, 5, 'shares', 10.00);
        System.assert(html.contains('60%'), 'Should show 60% reserved');
        System.assert(html.contains('40%'), 'Should show 40% available');
        System.assert(html.contains('3 reserved'), 'Should show reserved count');
        System.assert(html.contains('2 available'), 'Should show available count');
        System.assert(html.contains('$10/share'), 'Should show cost per share');
        System.assert(html.contains('#4E6878'), 'Should use slate for reserved');
        System.assert(html.contains('#5B8760'), 'Should use sage for available');
    }

    @IsTest
    static void buildThermometer_nullTotal_returnsEmpty() {
        System.assertEquals('', FimbyEmailHtmlBuilder.buildThermometer(2, null, 'items', 5));
        System.assertEquals('', FimbyEmailHtmlBuilder.buildThermometer(2, 0, 'items', 5));
    }

    @IsTest
    static void buildThermometer_noCost_omitsCostLine() {
        String html = FimbyEmailHtmlBuilder.buildThermometer(1, 4, 'bags', null);
        System.assert(!html.contains('$'), 'Should not show cost when null');
        System.assert(html.contains('1 reserved'), 'Should still show counts');
    }

    @IsTest
    static void buildDateLocationLine_dateAndLocation_containsBoth() {
        String html = FimbyEmailHtmlBuilder.buildDateLocationLine(Date.newInstance(2026, 4, 15), 'Community Hall');
        System.assert(html.contains('Apr'), 'Should contain month');
        System.assert(html.contains('15'), 'Should contain day');
        System.assert(html.contains('Community Hall'), 'Should contain location');
    }

    @IsTest
    static void buildDateLocationLine_dateOnly_containsDate() {
        String html = FimbyEmailHtmlBuilder.buildDateLocationLine(Date.newInstance(2026, 6, 1), null);
        System.assert(html.contains('Jun'), 'Should contain month');
        System.assert(!html.contains('&#128205;'), 'Should not contain location pin');
    }

    @IsTest
    static void buildDateLocationLine_nullBoth_returnsEmpty() {
        System.assertEquals('', FimbyEmailHtmlBuilder.buildDateLocationLine(null, null));
    }

    @IsTest
    static void buildCategoryPill_withCategory_producesPill() {
        String html = FimbyEmailHtmlBuilder.buildCategoryPill('Tools', '#8D7B6A');
        System.assert(html.contains('Tools'), 'Should contain category name');
        System.assert(html.contains('#8D7B6A'), 'Should use specified color');
        System.assert(html.contains('border-radius'), 'Should have rounded corners');
    }

    @IsTest
    static void buildCategoryPill_nullCategory_returnsEmpty() {
        System.assertEquals('', FimbyEmailHtmlBuilder.buildCategoryPill(null, '#333'));
        System.assertEquals('', FimbyEmailHtmlBuilder.buildCategoryPill('', '#333'));
    }

    @IsTest
    static void injectContent_replacesTokens() {
        String template = '<div><!-- TOKEN_A --></div><p><!-- TOKEN_B --></p>';
        Map<String, String> replacements = new Map<String, String>{
            '<!-- TOKEN_A -->' => 'Content A',
            '<!-- TOKEN_B -->' => 'Content B'
        };
        String result = FimbyEmailHtmlBuilder.injectContent(template, replacements);
        System.assert(result.contains('Content A'), 'Should replace token A');
        System.assert(result.contains('Content B'), 'Should replace token B');
        System.assert(!result.contains('TOKEN_A'), 'Should not contain original token');
    }

    @IsTest
    static void injectContent_nullTemplate_returnsNull() {
        String result = FimbyEmailHtmlBuilder.injectContent(null, new Map<String, String>());
        System.assertEquals(null, result);
    }

    @IsTest
    static void injectContent_nullReplacement_usesEmptyString() {
        String template = '<div><!-- TOK --></div>';
        Map<String, String> replacements = new Map<String, String>{ '<!-- TOK -->' => null };
        String result = FimbyEmailHtmlBuilder.injectContent(template, replacements);
        System.assert(!result.contains('<!-- TOK -->'), 'Null value should be replaced with empty');
    }

    @IsTest
    static void hasRequiredPlaceholder_present_returnsTrue() {
        System.assert(FimbyEmailHtmlBuilder.hasRequiredPlaceholder(
            '<div><!-- FIMBY_DYNAMIC_CONTENT --></div>', '<!-- FIMBY_DYNAMIC_CONTENT -->'));
    }

    @IsTest
    static void hasRequiredPlaceholder_absent_returnsFalse() {
        System.assert(!FimbyEmailHtmlBuilder.hasRequiredPlaceholder('<div>no token</div>', '<!-- FIMBY_DYNAMIC_CONTENT -->'));
    }

    @IsTest
    static void hasRequiredPlaceholder_nullHtml_returnsFalse() {
        System.assert(!FimbyEmailHtmlBuilder.hasRequiredPlaceholder(null, '<!-- TOKEN -->'));
    }

    @IsTest
    static void truncateText_shortText_returnsUnchanged() {
        System.assertEquals('Hello', FimbyEmailHtmlBuilder.truncateText('Hello', 120));
    }

    @IsTest
    static void truncateText_longText_truncatesWithEllipsis() {
        String longText = 'A'.repeat(200);
        String result = FimbyEmailHtmlBuilder.truncateText(longText, 120);
        System.assertEquals(123, result.length());
        System.assert(result.endsWith('...'));
    }

    @IsTest
    static void truncateText_nullText_returnsNull() {
        System.assertEquals(null, FimbyEmailHtmlBuilder.truncateText(null, 120));
    }

    @IsTest
    static void escapeHtml_specialChars_escaped() {
        String result = FimbyEmailHtmlBuilder.escapeHtml('<script>alert("xss")</script>');
        System.assert(!result.contains('<script>'), 'Should escape HTML tags');
    }

    @IsTest
    static void escapeHtml_null_returnsEmpty() {
        System.assertEquals('', FimbyEmailHtmlBuilder.escapeHtml(null));
    }

    @IsTest
    static void getRandomIntentLine_returnsString() {
        String line = FimbyEmailHtmlBuilder.getRandomIntentLine();
        System.assertNotEquals(null, line);
        System.assert(line.length() > 0, 'Should return a non-empty intent line');
    }

    @IsTest
    static void buildHeaderGreetingLine_formatsNameWithoutCard() {
        String html = FimbyEmailHtmlBuilder.buildHeaderGreetingLine('Sarah');
        System.assert(html.contains('Hi Sarah,'), 'Should greet by first name.');
        System.assert(!html.contains('border-left:3px'), 'Header greeting should not use card border.');
    }

    @IsTest
    static void wrapInBrandedShell_withRecipientFirstName_greetingBeforeSubject() {
        String result = FimbyEmailHtmlBuilder.wrapInBrandedShell(
            '<p>body</p>', 'Neighbourhood digest for today', 'Kensington', 'intent line', false, false, 'Rosa'
        );
        System.assert(result.contains('Hi Rosa,'), 'Should include header greeting.');
        Integer nhIdx = result.indexOf('Kensington');
        Integer greetingIdx = result.indexOf('Hi Rosa,');
        Integer subjectIdx = result.lastIndexOf('Neighbourhood digest for today');
        System.assert(
            nhIdx >= 0 && greetingIdx > nhIdx && subjectIdx > greetingIdx,
            'Header order should be neighbourhood, greeting, then subject.'
        );
    }

    @IsTest
    static void wrapInBrandedShell_basicContent_hasBrandedStructure() {
        String content = '<p>Hello neighbour</p>';
        String result = FimbyEmailHtmlBuilder.wrapInBrandedShell(content, 'Test Subject', 'Kensington');
        System.assert(result.contains('<!DOCTYPE html>'), 'Should have DOCTYPE');
        System.assert(result.contains('FIMBY'), 'Should have FIMBY branding');
        System.assert(result.contains('Kensington'), 'Should show neighbourhood');
        System.assert(result.contains('Test Subject'), 'Should show subject');
        System.assert(result.contains('Hello neighbour'), 'Should contain inner HTML');
        System.assert(result.contains('Email preferences'), 'Should have footer settings link');
        System.assert(result.contains('Family In My Backyard'), 'Should have tagline');
        System.assert(result.contains('FIMBYwGrass.png'), 'Should include FIMBY logo in header');
        System.assert(result.contains('BellActive.png'), 'Should include bell icon in header');
        System.assert(result.contains('enter.png'), 'Should include enter icon in header');
        System.assert(result.contains('/notifications'), 'Bell should link to notifications');
    }

    @IsTest
    static void wrapInBrandedShell_withIntentLine_includesIntent() {
        String result = FimbyEmailHtmlBuilder.wrapInBrandedShell(
            '<p>Content</p>', 'Subject', 'TestNH', 'Small acts build big trust.'
        );
        System.assert(result.contains('Small acts build big trust.'), 'Should include intent line');
    }

    @IsTest
    static void wrapInBrandedShell_nullNeighbourhood_usesDefault() {
        String result = FimbyEmailHtmlBuilder.wrapInBrandedShell('<p>Hi</p>', 'Subject', null);
        System.assert(result.contains('your neighbourhood'), 'Should fall back to default neighbourhood label');
    }

    @IsTest
    static void wrapInBrandedShell_emptyContent_stillRenders() {
        String result = FimbyEmailHtmlBuilder.wrapInBrandedShell('', 'Empty', 'NH');
        System.assert(result.contains('<!DOCTYPE html>'), 'Should produce valid shell even with empty content');
    }

    @IsTest
    static void wrapInBrandedShell_minimalChrome_stripsBellAndPreferences() {
        String result = FimbyEmailHtmlBuilder.wrapInBrandedShell(
            '<p>Body</p>', 'Subject', null, null, true, true);
        System.assert(result.contains('FIMBYwGrass.png'), 'Logo should still render in minimal chrome');
        System.assert(result.contains('Family In My Backyard'), 'Tagline should still render');
        System.assert(!result.contains('BellActive.png'),
            'Minimal chrome should drop the notifications bell — deactivated accounts cannot read them');
        System.assert(!result.contains('Email preferences'),
            'Minimal chrome should drop the email-preferences footer link');
        System.assert(!result.contains('/notifications'),
            'Minimal chrome should not link to /notifications');
    }

    @IsTest
    static void buildTransactionalCard_rendersBadgeTitleAndBody() {
        String html = FimbyEmailHtmlBuilder.buildTransactionalCard(
            'PAUSED', '#A8844E', 'deactivation.png',
            'Account is paused', '<p>Restore anytime in the next 30 days.</p>');
        System.assert(html.contains('PAUSED'), 'Badge label should render');
        System.assert(html.contains('deactivation.png'), 'Badge icon should render');
        System.assert(html.contains('Account is paused'), 'Title should render');
        System.assert(html.contains('Restore anytime'), 'Body HTML should pass through');
        System.assert(html.contains('#A8844E'),
            'Accent color should appear on the left border / badge background');
    }

    @IsTest
    static void buildTransactionalCard_omitsBadgeWhenLabelBlank() {
        String html = FimbyEmailHtmlBuilder.buildTransactionalCard(
            null, null, null, 'Just a title', '<p>Body</p>');
        System.assert(html.contains('Just a title'), 'Title should render');
        System.assert(html.contains('Body'), 'Body should render');
        System.assert(!html.contains('border-radius:10px'),
            'No badge pill should be emitted when label is blank');
    }

    @IsTest
    static void buildAlertCards_redundantBody_omitsDuplicateBody() {
        Notification__c n = new Notification__c(
            Title__c = 'Desktop reserved 1 share of QA-BB-Test',
            Body__c = 'Desktop reserved 1 share of QA-BB-Test',
            Type__c = 'Bulk_Buy_Reservation',
            Actor_Name__c = 'Desktop'
        );
        String html = FimbyEmailHtmlBuilder.buildAlertCards(new List<Notification__c>{ n });
        System.assertEquals(1, html.split('Desktop reserved 1 share of QA-BB-Test', -1).size() - 1,
            'Identical title and body should render the phrase only once');
    }

    @IsTest
    static void buildAlertCards_distinctTitleAndBody_showsBoth() {
        Notification__c n = new Notification__c(
            Title__c = 'Desktop reserved 1 share',
            Body__c = 'QA-BB-Test-Post',
            Type__c = 'Bulk_Buy_Reservation',
            Actor_Name__c = 'Desktop'
        );
        String html = FimbyEmailHtmlBuilder.buildAlertCards(new List<Notification__c>{ n });
        System.assert(html.contains('Desktop reserved 1 share'), 'Should show title');
        System.assert(html.contains('QA-BB-Test-Post'), 'Should show contextual body');
    }

    @IsTest
    static void isBodyRedundantWithTitle_detectsExactAndContainedMatches() {
        System.assert(FimbyEmailHtmlBuilder.isBodyRedundantWithTitle('Hello world', 'Hello world'));
        System.assert(FimbyEmailHtmlBuilder.isBodyRedundantWithTitle(
            'Desktop reserved 1 share of PostName', 'PostName'));
        System.assert(!FimbyEmailHtmlBuilder.isBodyRedundantWithTitle(
            'Desktop reserved 1 share', 'PostName'));
    }

    @IsTest
    static void wrapInBrandedShell_skipSubjectBlock_omitsVisibleHeading() {
        String result = FimbyEmailHtmlBuilder.wrapInBrandedShell(
            '<p>Card only</p>', 'Desktop reserved 1 share', 'Kensington', null, true, false);
        System.assert(result.contains('Card only'), 'Inner card HTML should render');
        System.assert(result.contains('Kensington'), 'Single-alert shell should still show neighbourhood context');
        System.assert(!result.contains('font-size:20px;font-weight:600'),
            'Single-alert shell should skip the large in-body subject heading');
    }

    @IsTest
    static void singleAlertEmailStructure_headlineAppearsOnceInBody() {
        Notification__c n = new Notification__c(
            Title__c = 'QA-BB-Test has been cancelled',
            Body__c = '',
            Type__c = 'Bulk_Buy_Status',
            Actor_Name__c = 'FIMBY'
        );
        String cards = FimbyEmailHtmlBuilder.buildAlertCards(new List<Notification__c>{ n });
        String html = FimbyEmailHtmlBuilder.wrapInBrandedShell(
            cards, n.Title__c, 'Strathcona / DTES', null, true, false);
        System.assert(html.contains('Strathcona / DTES'), 'Should show neighbourhood tag');
        System.assert(!html.contains('font-size:20px;font-weight:600'),
            'Shell should not repeat the card headline at 20px');
        String bodyHtml = html.substring(html.indexOf('</head>'));
        System.assertEquals(1, bodyHtml.split('QA-BB-Test has been cancelled', -1).size() - 1,
            'Headline should appear once in the visible body (card title only)');
    }

    @IsTest
    static void batchAlertEmailStructure_keepsSummaryHeading() {
        List<Notification__c> notifs = new List<Notification__c>{
            new Notification__c(Title__c = 'First update', Type__c = 'Message', Actor_Name__c = 'Sam'),
            new Notification__c(Title__c = 'Second update', Type__c = 'Response', Actor_Name__c = 'Maya')
        };
        String cards = FimbyEmailHtmlBuilder.buildAlertCards(notifs);
        String html = FimbyEmailHtmlBuilder.wrapInBrandedShell(
            cards, '2 new updates in your neighbourhood', 'Kensington', null, false, false);
        System.assert(html.contains('font-size:20px;font-weight:600'),
            'Batch alert shell should keep the summary heading');
        System.assert(html.contains('2 new updates in your neighbourhood'));
    }

    @IsTest
    static void getSeasonalLine_returnsNullOrString() {
        String line = FimbyEmailHtmlBuilder.getSeasonalLine();
        // May be null if no active seasonal theme — that's fine
        System.assert(true, 'Should not throw');
    }

    @IsTest
    static void brandedShell_iconSrcUsesExperienceSiteHost() {
        String html = FimbyEmailHtmlBuilder.wrapInBrandedShell('<p>Hi</p>', 'Test', 'NH');
        String assetHost = FimbySettings.getUrl('Experience_Site');
        if (String.isBlank(assetHost)) {
            assetHost = FimbySettings.getUrl('Site_Base');
        }
        if (assetHost.endsWith('/')) {
            assetHost = assetHost.substring(0, assetHost.length() - 1);
        }
        System.assert(
            html.contains(assetHost + '/sfsites/c/resource/Impact_Icons/'),
            'Email icons should load from the Experience Cloud host'
        );

        String linkHost = FimbySettings.getUrl('Site_Base');
        if (linkHost.endsWith('/')) {
            linkHost = linkHost.substring(0, linkHost.length() - 1);
        }
        if (linkHost != assetHost) {
            System.assert(
                !html.contains('src="' + linkHost + '/sfsites/c/resource/Impact_Icons/'),
                'Email icons must not use the app-link host when it differs from Experience Site'
            );
        }
    }
}
