@isTest
private class FimbySettingsTest {

    @isTest
    static void testAllAccessorsReturnDefaults() {
        // Without a CMT record in test context, all accessors should return their fallback defaults
        System.assertEquals(90, FimbySettings.storyFeedTtlDays());
        System.assertEquals(90, FimbySettings.conversationCleanupDays());
        System.assertEquals(180, FimbySettings.responseThreadCleanupDays());
        System.assertEquals(180, FimbySettings.libraryConversationCleanupDays());
        System.assertEquals(30, FimbySettings.notificationRetentionDays());
        System.assertEquals(7, FimbySettings.libraryJustListedDays());
        System.assertEquals(7, FimbySettings.needDefaultEndDays());
        System.assertEquals(21, FimbySettings.offerDefaultEndDays());

        System.assertEquals(5, FimbySettings.maxNewConversationsPerDay());
        System.assertEquals(100, FimbySettings.pushNotificationBatchSize());
        System.assertEquals(10000, FimbySettings.notificationCleanupBatchSize());
        System.assertEquals(5000, FimbySettings.conversationCleanupBatchSize());

        System.assertEquals(22, FimbySettings.pushQuietHourStart());
        System.assertEquals(6, FimbySettings.pushQuietHourEnd());

        System.assertEquals(15, FimbySettings.homeFeedPageSize());
        System.assertEquals(20, FimbySettings.messagesPageSize());
        System.assertEquals(50, FimbySettings.conversationMessagesPageSize());
        System.assertEquals(50, FimbySettings.responseMessagesPageSize());
        System.assertEquals(20, FimbySettings.notificationsPageSize());
        System.assertEquals(20, FimbySettings.searchPageSize());
        System.assertEquals(15, FimbySettings.libraryPageSize());
        System.assertEquals(20, FimbySettings.myPostsPageSize());
        System.assertEquals(20, FimbySettings.archivePageSize());

        System.assertEquals(200, FimbySettings.myLibraryItemsLimit());
        System.assertEquals(100, FimbySettings.borrowedItemsLimit());
        System.assertEquals(500, FimbySettings.sharedContactsLimit());
        System.assertEquals(200, FimbySettings.messageableContactsLimit());
        System.assertEquals(200, FimbySettings.dmThreadsLimit());
        System.assertEquals(200, FimbySettings.responseThreadsLimit());
        System.assertEquals(200, FimbySettings.searchResultsLimit());
        System.assertEquals(100, FimbySettings.searchContactsLimit());
        System.assertEquals(50, FimbySettings.storyCommentsLimit());
        System.assertEquals(1000, FimbySettings.markAllReadLimit());
        System.assertEquals(2000, FimbySettings.deleteAllNotificationsLimit());
        System.assertEquals(50, FimbySettings.unifiedFeedMinQueryLimit());
    }

    @isTest
    static void testNeighbourhoodHealthAccessorsReturnDefaults() {
        System.assertEquals(150, FimbySettings.neighbourhoodSoftCap());
        System.assertEquals(60, FimbySettings.neighbourhoodIdealMin());
        System.assertEquals(120, FimbySettings.neighbourhoodIdealMax());
        System.assertEquals(0.30, FimbySettings.recognitionScoreThreshold());
        System.assertEquals(0.50, FimbySettings.lurkerRatioThreshold());
        System.assertEquals(150, FimbySettings.splitReviewHouseholdTrigger());
        System.assertEquals(30, FimbySettings.minHouseholdsPerCell());
        System.assertEquals(15, FimbySettings.minActiveMembersPerCell());
        System.assertEquals(8, FimbySettings.minRespondersPerCell());
        System.assertEquals(5, FimbySettings.minPostsPerWeekPerCell());
        System.assertEquals(0.40, FimbySettings.minInternalTieRatio());
        System.assertEquals(0.35, FimbySettings.maxDependencyRatio());
        System.assertEquals(2, FimbySettings.dependencyMonitorWeeks());
        System.assertEquals(5, FimbySettings.dependencyReviewWeeks());
        System.assertEquals(8, FimbySettings.dependencyInterveneWeeks());
    }

    @isTest
    static void testGetUrlReturnsEmptyForUnknownDeveloperName() {
        String result = FimbySettings.getUrl('NonExistent_Record_Name');
        System.assertEquals('', result, 'Unknown developer name should return empty string');
    }

    @isTest
    static void testGetUrlWithRecordIdAppendsId() {
        String result = FimbySettings.getUrl('NonExistent_Record_Name', '001000000000001');
        System.assertEquals('001000000000001', result, 'Should append recordId to empty base URL');
    }

    @isTest
    static void testRemainingAccessorsRunCleanly() {
        Test.startTest();
        FimbySettings.pushBatchCap();
        FimbySettings.pushFatigueDays();
        FimbySettings.lendingConfirmationExpiryDays();
        FimbySettings.emailAlertBatchCap();
        FimbySettings.digestEmailSendHour();
        FimbySettings.digestWeeklyDay();
        FimbySettings.emailAlertsGlobalEnabled();
        FimbySettings.digestEmailGlobalEnabled();
        FimbySettings.emailPilotNeighbourhoodIds();
        FimbySettings.emailPilotUserIds();
        FimbySettings.dataRetentionMonths();
        FimbySettings.conversationTrimKeepCount();
        FimbySettings.dataRetentionBatchSize();
        FimbySettings.tosCurrentVersion();
        FimbySettings.tosEffectiveDate();
        FimbySettings.cgaCurrentVersion();
        FimbySettings.cgaEffectiveDate();
        FimbySettings.vouchingDisableThreshold();
        FimbySettings.vouchRequestExpiryDays();
        FimbySettings.vouchDeclineCooldownDays();
        FimbySettings.vouchPendingModeratorAlertDays();
        FimbySettings.appHandoffEnabled();
        Test.stopTest();
        System.assert(true, 'All remaining accessors completed without throwing');
    }

    @isTest
    static void testAccountDeletionAccessorsReturnDefaults() {
        System.assertEquals(30, FimbySettings.defaultGraceWindowDays(),
            'Default grace window should fall back to 30 days');
        System.assertEquals(24, FimbySettings.reactivationTokenTtlHours(),
            'Reactivation token TTL should fall back to 24 hours');
    }
}
