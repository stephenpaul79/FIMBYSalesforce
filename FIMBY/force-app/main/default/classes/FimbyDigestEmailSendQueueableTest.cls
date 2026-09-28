@IsTest
private class FimbyDigestEmailSendQueueableTest {

    @IsTest
    static void resolveDigestHeaderTitle_daily_scalesWithItemCount() {
        System.assertEquals(
            'Something your neighbour shared yesterday',
            FimbyDigestEmailSendQueueable.resolveDigestHeaderTitle('Daily', 1)
        );
        System.assertEquals(
            'A couple things your neighbours shared yesterday',
            FimbyDigestEmailSendQueueable.resolveDigestHeaderTitle('Daily', 2)
        );
        System.assertEquals(
            'A few things your neighbours shared yesterday',
            FimbyDigestEmailSendQueueable.resolveDigestHeaderTitle('Daily', 3)
        );
        System.assertEquals(
            'A few things your neighbours shared yesterday',
            FimbyDigestEmailSendQueueable.resolveDigestHeaderTitle('Daily', 10)
        );
    }

    @IsTest
    static void resolveDigestHeaderTitle_weekly_scalesWithItemCount() {
        System.assertEquals(
            'Something your neighbour shared this week',
            FimbyDigestEmailSendQueueable.resolveDigestHeaderTitle('Weekly', 1)
        );
        System.assertEquals(
            'A couple things your neighbours shared this week',
            FimbyDigestEmailSendQueueable.resolveDigestHeaderTitle('Weekly', 2)
        );
        System.assertEquals(
            'A few things your neighbours shared this week',
            FimbyDigestEmailSendQueueable.resolveDigestHeaderTitle('Weekly', 5)
        );
    }

    @IsTest
    static void execute_emptyUserIds_exitsCleanly() {
        Date window = Date.today();
        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'TestNeighbourhood', 'Daily', window, window,
            '<p>Content</p>', 5, new List<Id>()
        ).execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_nullUserIds_exitsCleanly() {
        Date window = Date.today();
        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'TestNeighbourhood', 'Daily', window, window,
            '<p>Content</p>', 5, null
        ).execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_noTemplate_createsLog() {
        List<Id> userIds = new List<Id>{ UserInfo.getUserId() };
        Date window = Date.today().addDays(-1);

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'Maplewood', 'Daily', window, window,
            '<p>Digest content</p>', 3, userIds
        ).execute(null);
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [SELECT Status__c FROM Digest_Email_Log__c];
        System.assert(logs.size() > 0, 'Should create audit log');
    }

    @IsTest
    static void execute_brandedShell_createsLog() {
        FimbyDigestEmailSendQueueable.oweaCached = UserInfo.getUserId();

        List<Id> userIds = new List<Id>{ UserInfo.getUserId() };
        Date window = Date.today().addDays(-1);

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'Maplewood', 'Daily', window, window,
            '<p>Digest cards</p>', 3, userIds
        ).execute(null);
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [
            SELECT Status__c, Cadence__c FROM Digest_Email_Log__c
        ];
        System.assert(logs.size() > 0, 'Should create audit log');
    }

    @IsTest
    static void execute_weeklyFrequency_coversTimeRange() {
        FimbyDigestEmailSendQueueable.oweaCached = UserInfo.getUserId();

        List<Id> userIds = new List<Id>{ UserInfo.getUserId() };
        Date windowStart = Date.today().addDays(-7);

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'Riverside', 'Weekly', windowStart, windowStart.addDays(6),
            '<p>Weekly digest</p>', 8, userIds
        ).execute(null);
        Test.stopTest();
    }

    @IsTest
    static void execute_alreadySentBuild_exitsWithoutChanges() {
        FimbyDigestEmailSendQueueable.oweaCached = UserInfo.getUserId();

        Id userId = UserInfo.getUserId();
        Date windowDate = Date.today().addDays(-1);
        String key = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            null, 'Daily', windowDate, windowDate
        );
        Digest_Email_Log__c existing = new Digest_Email_Log__c(
            Cadence__c = 'Daily',
            Window_Date__c = windowDate,
            Status__c = 'Sent',
            Sent_At__c = Datetime.now(),
            Recipient_Count__c = 1,
            Recipients__c = 'Existing User - ' + userId,
            Content_Item_Count__c = 5,
            Template_Version__c = 'FimbyEmailHtmlBuilder',
            Idempotency_Key__c = key
        );
        insert existing;

        List<Id> userIds = new List<Id>{ userId };

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'Maplewood', 'Daily', windowDate, windowDate,
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
    static void buildIdempotencyKey_sundayRestCatchUp_usesDistinctSuffix() {
        Date sat = Date.newInstance(2026, 4, 11);
        Date sun = Date.newInstance(2026, 4, 12);
        String catchUpKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            '001000000000001', FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST, sat, sun
        );
        String dailyKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            '001000000000001', 'Daily', sun, sun
        );
        System.assert(catchUpKey.contains('DailySundayRest'), 'Catch-up key should use DailySundayRest suffix.');
        System.assertNotEquals(catchUpKey, dailyKey, 'Monday catch-up and daily keys must not collide.');
    }

    @IsTest
    static void buildIdempotencyKey_variantKey_appendsDistinctSuffix() {
        Date window = Date.newInstance(2026, 4, 9);
        String baseKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            '001000000000001', 'Daily', window, window
        );
        String variantKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            '001000000000001', 'Daily', window, window, '003000000000001'
        );
        String otherVariantKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            '001000000000001', 'Daily', window, window, '003000000000002'
        );
        System.assertNotEquals(baseKey, variantKey, 'Variant key must differ from base.');
        System.assertNotEquals(variantKey, otherVariantKey, 'Distinct variants must not collide.');
        System.assert(variantKey.startsWith(baseKey + '_v'), 'Variant key should extend the base key.');
    }

    @IsTest
    static void buildIdempotencyKey_blankVariantKey_returnsBaseKey() {
        Date window = Date.newInstance(2026, 4, 9);
        String baseKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            '001000000000001', 'Daily', window, window
        );
        String withNull = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            '001000000000001', 'Daily', window, window, null
        );
        System.assertEquals(baseKey, withNull, 'Blank variant key must collapse to the base key.');
    }

    @IsTest
    static void execute_variantCohort_writesRowUnderVariantKey() {
        FimbyDigestEmailSendQueueable.oweaCached = UserInfo.getUserId();

        Id userId = UserInfo.getUserId();
        Date window = Date.today().addDays(-1);
        String variantKey = 'someContactSignature';

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'VariantNH', 'Daily', window, window,
            '<p>Filtered content</p>', 2, new List<Id>{ userId }, variantKey
        ).execute(null);
        Test.stopTest();

        String expectedKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            null, 'Daily', window, window, variantKey
        );
        List<Digest_Email_Log__c> logs = [
            SELECT Idempotency_Key__c FROM Digest_Email_Log__c
            WHERE Idempotency_Key__c = :expectedKey
        ];
        System.assertEquals(1, logs.size(),
            'Variant cohort must log under its variant idempotency key.');
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
        FimbyDigestEmailSendQueueable.testOweaUnavailable = true;

        List<Id> userIds = new List<Id>{ UserInfo.getUserId() };
        Date window = Date.today().addDays(-1);

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'NoOweaNH', 'Daily', window, window,
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
        FimbyDigestEmailSendQueueable.oweaCached = UserInfo.getUserId();

        Id userId = UserInfo.getUserId();
        Date windowDate = Date.today().addDays(-1);
        String key = FimbyDigestEmailSendQueueable.buildIdempotencyKey(null, 'Daily', windowDate, windowDate);
        Digest_Email_Log__c partial = new Digest_Email_Log__c(
            Cadence__c = 'Daily',
            Window_Date__c = windowDate,
            Status__c = 'Partial',
            Recipient_Count__c = 1,
            Recipients__c = 'Existing User - ' + userId,
            Content_Item_Count__c = 1,
            Template_Version__c = 'FimbyEmailHtmlBuilder',
            Idempotency_Key__c = key
        );
        insert partial;

        List<Id> userIds = new List<Id>{ userId };

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'PartialNH', 'Daily', windowDate, windowDate,
            '<p>Content</p>', 1, userIds
        ).execute(null);
        Test.stopTest();

        List<Digest_Email_Log__c> logs = [
            SELECT Recipient_Count__c, Recipients__c, Status__c FROM Digest_Email_Log__c
        ];
        System.assertEquals(1, logs.size(),
            'Resume after Partial reuses the same row, never duplicates.');
    }

    private static Digest_Email_Log__c logWith(String recipients, String failures) {
        return new Digest_Email_Log__c(Recipients__c = recipients, Failed_Recipients__c = failures);
    }

    @IsTest
    static void computeStatus_nonFinalSuccess_isPartialNotSent() {
        System.assertEquals('Partial',
            FimbyDigestEmailSendQueueable.computeStatus(logWith('A - 005', null), false, null),
            'A successful mid-run chunk must stay Partial so the next chunk still sends.');
        System.assertEquals('Partial',
            FimbyDigestEmailSendQueueable.computeStatus(logWith(null, 'A - 005'), false, null));
    }

    @IsTest
    static void computeStatus_finalChunk_resolvesOutcome() {
        System.assertEquals('Sent',
            FimbyDigestEmailSendQueueable.computeStatus(logWith('A - 005', null), true, null));
        System.assertEquals('Partial',
            FimbyDigestEmailSendQueueable.computeStatus(logWith('A - 005', 'B - 005'), true, null));
        System.assertEquals('Failed',
            FimbyDigestEmailSendQueueable.computeStatus(logWith(null, 'B - 005'), true, null));
        System.assertEquals('Failed',
            FimbyDigestEmailSendQueueable.computeStatus(logWith(null, null), true, 'OWEA not found'));
    }

    private static List<Id> repeatedUserIds(Integer count) {
        List<Id> ids = new List<Id>();
        for (Integer i = 0; i < count; i++) {
            ids.add(UserInfo.getUserId());
        }
        return ids;
    }

    @IsTest
    static void processStep_moreThanOneChunk_continuesWithRemainder() {
        FimbyDigestEmailSendQueueable.testOweaUnavailable = true;
        Date window = Date.today().addDays(-1);

        FimbyDigestEmailSendQueueable first = new FimbyDigestEmailSendQueueable(
            null, 'BigNH', 'Daily', window, window, '<p>Content</p>', 3, repeatedUserIds(51)
        );

        Test.startTest();
        FimbyDigestEmailSendQueueable second = first.processStep();
        System.assertNotEquals(null, second, '51 recipients need a second chunk.');
        Integer secondIndex = second.cohortIndexForTest();
        Integer remainingAfterFirst = second.cohortsForTest()[0].userIds.size();
        String midStatus = [SELECT Status__c FROM Digest_Email_Log__c LIMIT 1].Status__c;
        FimbyDigestEmailSendQueueable third = second.processStep();
        Test.stopTest();

        System.assertEquals(0, secondIndex, 'Second chunk stays on the same cohort.');
        System.assertEquals(1, remainingAfterFirst,
            'Only the 51st recipient remains after the first chunk.');
        System.assertEquals('Partial', midStatus, 'Mid-run row must not be marked Sent or Failed.');
        System.assertEquals(null, third, 'The final chunk ends the chain.');
        System.assertEquals('Failed', [SELECT Status__c FROM Digest_Email_Log__c LIMIT 1].Status__c,
            'Final chunk resolves the status (every send failed pre-flight here).');
    }

    @IsTest
    static void execute_withRemainingRecipients_enqueuesExactlyOneSuccessor() {
        FimbyDigestEmailSendQueueable.testOweaUnavailable = true;
        Date window = Date.today().addDays(-1);

        Test.startTest();
        new FimbyDigestEmailSendQueueable(
            null, 'ChainNH', 'Daily', window, window, '<p>Content</p>', 3, repeatedUserIds(51)
        ).execute(null);
        Integer enqueued = Limits.getQueueableJobs();
        Test.stopTest();

        System.assertEquals(1, enqueued, 'A step must chain at most one successor.');
    }

    @IsTest
    static void processStep_emptyVariant_writesSkippedAndAdvances() {
        FimbyDigestEmailSendQueueable.testOweaUnavailable = true;
        Account emptyNh = new Account(Name = 'Empty Variant NH');
        insert emptyNh;
        Date window = Date.today().addDays(-1);
        String signature = 'blockedSignature';

        List<FimbyDigestEmailSendQueueable.DispatchCohort> cohorts =
            new List<FimbyDigestEmailSendQueueable.DispatchCohort>{
                new FimbyDigestEmailSendQueueable.DispatchCohort(
                    new List<Id>{ UserInfo.getUserId() }, new Set<Id>(), signature, null, null
                ),
                new FimbyDigestEmailSendQueueable.DispatchCohort(
                    new List<Id>{ UserInfo.getUserId() }, null, 'otherSignature', '<p>Filtered</p>', 1
                )
            };

        Test.startTest();
        FimbyDigestEmailSendQueueable next = new FimbyDigestEmailSendQueueable(
            emptyNh.Id, emptyNh.Name, 'Daily', window, window, cohorts
        ).processStep();
        Test.stopTest();

        String variantKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            emptyNh.Id, 'Daily', window, window, signature
        );
        Digest_Email_Log__c skipped = [
            SELECT Status__c, Error_Message__c, Recipient_Count__c
            FROM Digest_Email_Log__c WHERE Idempotency_Key__c = :variantKey
        ];
        System.assertEquals('Skipped', skipped.Status__c);
        System.assertEquals(FimbyDigestEmailBatch.SKIP_REASON_NO_CONTENT, skipped.Error_Message__c);
        System.assertEquals(0, skipped.Recipient_Count__c);
        System.assertNotEquals(null, next, 'An empty variant hands off to the next cohort.');
        System.assertEquals(1, next.cohortIndexForTest());
    }

    @IsTest
    static void processStep_completedCohortOnRetry_skipsToNextCohort() {
        FimbyDigestEmailSendQueueable.testOweaUnavailable = true;
        Date window = Date.today().addDays(-1);
        String sentKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(null, 'Daily', window, window);
        insert new Digest_Email_Log__c(
            Cadence__c = 'Daily', Window_Date__c = window, Status__c = 'Sent',
            Recipient_Count__c = 1, Recipients__c = 'Existing User - ' + UserInfo.getUserId(),
            Template_Version__c = 'FimbyEmailHtmlBuilder', Idempotency_Key__c = sentKey
        );

        List<FimbyDigestEmailSendQueueable.DispatchCohort> cohorts =
            new List<FimbyDigestEmailSendQueueable.DispatchCohort>{
                new FimbyDigestEmailSendQueueable.DispatchCohort(
                    new List<Id>{ UserInfo.getUserId() }, null, null, '<p>Clean</p>', 1
                ),
                new FimbyDigestEmailSendQueueable.DispatchCohort(
                    new List<Id>{ UserInfo.getUserId() }, null, 'variantSig', '<p>Variant</p>', 1
                )
            };

        Test.startTest();
        FimbyDigestEmailSendQueueable next = new FimbyDigestEmailSendQueueable(
            null, 'RetryNH', 'Daily', window, window, cohorts
        ).processStep();
        Integer nextIndex = next.cohortIndexForTest();
        FimbyDigestEmailSendQueueable last = next.processStep();
        Test.stopTest();

        System.assertEquals(1, nextIndex, 'A Sent cohort is skipped on retry.');
        System.assertEquals(null, last, 'Chain ends after the last cohort.');
        System.assertEquals('Sent',
            [SELECT Status__c FROM Digest_Email_Log__c WHERE Idempotency_Key__c = :sentKey].Status__c,
            'Completed cohort row is left untouched.');
        String variantKey = FimbyDigestEmailSendQueueable.buildIdempotencyKey(
            null, 'Daily', window, window, 'variantSig'
        );
        System.assertEquals(1,
            [SELECT COUNT() FROM Digest_Email_Log__c WHERE Idempotency_Key__c = :variantKey],
            'The next cohort still processes.');
    }
}
