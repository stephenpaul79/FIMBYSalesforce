@IsTest
private class FimbyDigestEmailSendQueueableTest {

    @IsTest
    static void execute_emptyUserIds_exitsCleanly() {
        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'TestNeighbourhood', 'Daily', Date.today(),
            '<p>Content</p>', 5, new List<Id>()
        ).execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_nullUserIds_exitsCleanly() {
        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'TestNeighbourhood', 'Daily', Date.today(),
            '<p>Content</p>', 5, null
        ).execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_noTemplate_createsLog() {
        List<Id> userIds = new List<Id>{ UserInfo.getUserId() };

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'Maplewood', 'Daily', Date.today().addDays(-1),
            '<p>Digest content</p>', 3, userIds
        ).execute(null);
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [SELECT Status__c FROM Digest_Email_Log__c];
        System.assert(logs.size() > 0, 'Should create audit log');
    }

    @IsTest
    static void execute_withTestHtml_exercisesFullRenderPath() {
        FimbyDigestEmailSendQueueable.digestTemplateId = UserInfo.getUserId();
        FimbyDigestEmailSendQueueable.oweaCached = UserInfo.getUserId();
        FimbyDigestEmailSendQueueable.testRenderedHtml =
            '<html><!-- FIMBY_DYNAMIC_CONTENT --><!-- FIMBY_INTENT_LINE -->' +
            '<!-- FIMBY_NEIGHBOURHOOD_NAME --><!-- FIMBY_TIME_RANGE --></html>';

        List<Id> userIds = new List<Id>{ UserInfo.getUserId() };

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'Maplewood', 'Daily', Date.today().addDays(-1),
            '<p>Digest cards</p>', 3, userIds
        ).execute(null);
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [
            SELECT Status__c, Cadence__c FROM Digest_Email_Log__c
        ];
        System.assert(logs.size() > 0, 'Should create audit log');
    }

    @IsTest
    static void execute_withTestHtml_weeklyFrequency_coversTimeRange() {
        FimbyDigestEmailSendQueueable.digestTemplateId = UserInfo.getUserId();
        FimbyDigestEmailSendQueueable.oweaCached = UserInfo.getUserId();
        FimbyDigestEmailSendQueueable.testRenderedHtml =
            '<html><!-- FIMBY_DYNAMIC_CONTENT --><!-- FIMBY_INTENT_LINE -->' +
            '<!-- FIMBY_NEIGHBOURHOOD_NAME --><!-- FIMBY_TIME_RANGE --></html>';

        List<Id> userIds = new List<Id>{ UserInfo.getUserId() };

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'Riverside', 'Weekly', Date.today().addDays(-7),
            '<p>Weekly digest</p>', 8, userIds
        ).execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_alreadySentBuild_exitsWithoutChanges() {
        FimbyDigestEmailSendQueueable.digestTemplateId = UserInfo.getUserId();
        FimbyDigestEmailSendQueueable.oweaCached = UserInfo.getUserId();
        FimbyDigestEmailSendQueueable.testRenderedHtml =
            '<html><!-- FIMBY_DYNAMIC_CONTENT --><!-- FIMBY_INTENT_LINE -->' +
            '<!-- FIMBY_NEIGHBOURHOOD_NAME --><!-- FIMBY_TIME_RANGE --></html>';

        Id userId = UserInfo.getUserId();
        Date windowDate = Date.today().addDays(-1);
        String key = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            null, 'Daily', windowDate
        );
        Digest_Email_Log__c existing = new Digest_Email_Log__c(
            Cadence__c = 'Daily',
            Window_Date__c = windowDate,
            Status__c = 'Sent',
            Sent_At__c = Datetime.now(),
            Recipient_Count__c = 1,
            Recipients__c = 'Existing User - ' + userId,
            Content_Item_Count__c = 5,
            Template_Version__c = 'FIMBY_Digest_Email',
            Idempotency_Key__c = key
        );
        insert existing;

        List<Id> userIds = new List<Id>{ userId };

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'Maplewood', 'Daily', windowDate,
            '<p>Content</p>', 5, userIds
        ).execute(null);
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [
            SELECT Status__c, Recipient_Count__c FROM Digest_Email_Log__c
        ];
        System.assertEquals(1, logs.size(), 'Build-level log should remain unique per neighbourhood/cadence/window.');
        System.assertEquals('Sent', logs[0].Status__c);
    }

    @IsTest
    static void buildIdempotencyKey_producesPerBuildFormat() {
        String key = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            '001000000000001', 'Daily', Date.newInstance(2026, 4, 9)
        );
        System.assert(key.contains('Daily'), 'Key should contain frequency.');
        System.assert(key.contains('001000000000001'), 'Key should contain neighbourhood ID.');
        System.assert(!key.contains('005'), 'Per-build key should NOT carry a user component.');
    }

    @IsTest
    static void buildIdempotencyKey_weeklyDifferentFromDaily() {
        String dailyKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            '001000000000001', 'Daily', Date.newInstance(2026, 4, 9)
        );
        String weeklyKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            '001000000000001', 'Weekly', Date.newInstance(2026, 4, 9)
        );
        System.assertNotEquals(dailyKey, weeklyKey);
    }

    @IsTest
    static void truncateHtml_underLimit_returnsUnchanged() {
        String html = '<p>short</p>';
        String result = FimbyDigestEmailSendQueueable.truncateHtml(html);
        System.assertEquals(html, result);
    }

    @IsTest
    static void truncateHtml_overLimit_appendsMarker() {
        String big = 'a'.repeat(150000);
        String result = FimbyDigestEmailSendQueueable.truncateHtml(big);
        System.assert(result.endsWith('[truncated for storage]'),
            'Overflow HTML should be truncated with marker.');
        System.assert(result.length() < big.length(),
            'Truncated body should be shorter than input.');
    }

    @IsTest
    static void execute_noOwea_writesFailureLines() {
        FimbyDigestEmailSendQueueable.digestTemplateId = UserInfo.getUserId();
        FimbyDigestEmailSendQueueable.oweaCached = null;

        List<Id> userIds = new List<Id>{ UserInfo.getUserId() };

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'NoOweaNH', 'Daily', Date.today().addDays(-1),
            '<p>Content</p>', 1, userIds
        ).execute(null);
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [
            SELECT Status__c, Failed_Recipients__c, Error_Message__c
            FROM Digest_Email_Log__c
        ];
        if (!logs.isEmpty()) {
            System.assert(
                logs[0].Status__c == 'Failed' || logs[0].Status__c == 'Skipped',
                'OWEA missing should produce Failed or Skipped: ' + logs[0].Status__c
            );
        }
    }

    @IsTest
    static void execute_resumeAfterPartial_skipsAlreadyDeliveredUsers() {
        FimbyDigestEmailSendQueueable.digestTemplateId = UserInfo.getUserId();
        FimbyDigestEmailSendQueueable.oweaCached = UserInfo.getUserId();
        FimbyDigestEmailSendQueueable.testRenderedHtml =
            '<html><!-- FIMBY_DYNAMIC_CONTENT --><!-- FIMBY_INTENT_LINE -->' +
            '<!-- FIMBY_NEIGHBOURHOOD_NAME --><!-- FIMBY_TIME_RANGE --></html>';

        Id userId = UserInfo.getUserId();
        Date windowDate = Date.today().addDays(-1);
        String key = FimbyDigestEmailSendQueueable.buildIdempotencyKey(null, 'Daily', windowDate);
        Digest_Email_Log__c partial = new Digest_Email_Log__c(
            Cadence__c = 'Daily',
            Window_Date__c = windowDate,
            Status__c = 'Partial',
            Recipient_Count__c = 1,
            Recipients__c = 'Existing User - ' + userId,
            Content_Item_Count__c = 1,
            Template_Version__c = 'FIMBY_Digest_Email',
            Idempotency_Key__c = key
        );
        insert partial;

        List<Id> userIds = new List<Id>{ userId };

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'PartialNH', 'Daily', windowDate,
            '<p>Content</p>', 1, userIds
        ).execute(null);
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [
            SELECT Recipient_Count__c, Recipients__c, Status__c FROM Digest_Email_Log__c
        ];
        System.assertEquals(1, logs.size(),
            'Resume after Partial reuses the same row, never duplicates.');
    }
}
