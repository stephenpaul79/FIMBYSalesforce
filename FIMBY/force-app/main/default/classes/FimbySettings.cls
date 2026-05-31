/**
 * @description Provides typed access to FIMBY_App_Settings__mdt and FIMBY_URL__mdt custom metadata.
 * All time windows, rate limits, page sizes, and URL lookups are read from metadata with safe fallbacks.
 */
public with sharing class FimbySettings {
    private static FIMBY_App_Settings__mdt cached;

    private static FIMBY_App_Settings__mdt get() {
        if (cached == null) {
            cached = FIMBY_App_Settings__mdt.getInstance('Default');
        }
        return cached;
    }

    private static Integer safe(Decimal val, Integer fallback) {
        return (val != null) ? val.intValue() : fallback;
    }

    // ---- Time Windows ----
    /** @description Days a story remains in the feed. */
    public static Integer storyFeedTtlDays()        { return safe(get()?.Story_Feed_TTL_Days__c, 90); }
    /** @description Days before inactive conversations are cleaned up. */
    public static Integer conversationCleanupDays()  { return safe(get()?.Conversation_Cleanup_Days__c, 90); }
    /** @description Days before response threads are cleaned up. */
    public static Integer responseThreadCleanupDays() { return safe(get()?.Response_Thread_Cleanup_Days__c, 180); }
    /** @description Days before library conversations are cleaned up. */
    public static Integer libraryConversationCleanupDays() { return safe(get()?.Library_Conversation_Cleanup_Days__c, 180); }
    /** @description Days notifications are retained before cleanup. */
    public static Integer notificationRetentionDays(){ return safe(get()?.Notification_Retention_Days__c, 30); }
    /** @description Days an item shows as "Just Listed" in library. */
    public static Integer libraryJustListedDays()    { return safe(get()?.Library_Just_Listed_Days__c, 7); }
    /** @description Days a borrower has to confirm before the request expires. */
    public static Integer lendingConfirmationExpiryDays() { return safe(get()?.Lending_Confirmation_Expiry_Days__c, 3); }
    /** @description Default end days for Need posts. */
    public static Integer needDefaultEndDays()       { return safe(get()?.Need_Default_End_Days__c, 7); }
    /** @description Default end days for Offer posts. */
    public static Integer offerDefaultEndDays()      { return safe(get()?.Offer_Default_End_Days__c, 21); }

    // ---- Rate Limits ----
    /** @description Max new conversations a user can create per day. */
    public static Integer maxNewConversationsPerDay()    { return safe(get()?.Max_New_Conversations_Per_Day__c, 5); }
    /** @description Batch size for push notification processing. */
    public static Integer pushNotificationBatchSize()    { return safe(get()?.Push_Notification_Batch_Size__c, 100); }
    /** @description Batch size for notification cleanup job. */
    public static Integer notificationCleanupBatchSize() { return safe(get()?.Notification_Cleanup_Batch_Size__c, 10000); }
    /** @description Batch size for conversation cleanup job. */
    public static Integer conversationCleanupBatchSize() { return safe(get()?.Conversation_Cleanup_Batch_Size__c, 5000); }

    // ---- Notification Settings ----
    /** @description Hour (0-23) when push quiet hours start. */
    public static Integer pushQuietHourStart() { return safe(get()?.Push_Quiet_Hour_Start__c, 22); }
    /** @description Hour (0-23) when push quiet hours end. */
    public static Integer pushQuietHourEnd()   { return safe(get()?.Push_Quiet_Hour_End__c, 6); }
    /** @description Max Pending notification rows processed per batch cycle. */
    public static Integer pushBatchCap()       { return safe(get()?.Push_Batch_Cap__c, 5000); }
    /** @description Days since last app open before daily gate reset is suppressed. */
    public static Integer pushFatigueDays()    { return safe(get()?.Push_Fatigue_Days__c, 7); }

    // ---- Page Sizes ----
    /** @description Page size for home feed. */
    public static Integer homeFeedPageSize()              { return safe(get()?.Home_Feed_Page_Size__c, 15); }
    /** @description Page size for messages list. */
    public static Integer messagesPageSize()              { return safe(get()?.Messages_Page_Size__c, 20); }
    /** @description Page size for conversation messages. */
    public static Integer conversationMessagesPageSize()  { return safe(get()?.Conversation_Messages_Page_Size__c, 50); }
    /** @description Page size for response thread messages. */
    public static Integer responseMessagesPageSize()      { return safe(get()?.Response_Messages_Page_Size__c, 50); }
    /** @description Page size for notifications list. */
    public static Integer notificationsPageSize()         { return safe(get()?.Notifications_Page_Size__c, 20); }
    /** @description Page size for search results. */
    public static Integer searchPageSize()                { return safe(get()?.Search_Page_Size__c, 20); }
    /** @description Page size for library listing. */
    public static Integer libraryPageSize()               { return safe(get()?.Library_Page_Size__c, 15); }
    /** @description Page size for My Posts listing. */
    public static Integer myPostsPageSize()               { return safe(get()?.My_Posts_Page_Size__c, 20); }
    /** @description Page size for archive listing. */
    public static Integer archivePageSize()               { return safe(get()?.Archive_Page_Size__c, 20); }

    // ---- Query Limits ----
    /** @description Max library items to return for current user. */
    public static Integer myLibraryItemsLimit()          { return safe(get()?.My_Library_Items_Limit__c, 200); }
    /** @description Max borrowed items to return. */
    public static Integer borrowedItemsLimit()           { return safe(get()?.Borrowed_Items_Limit__c, 100); }
    /** @description Max shared contacts to return. */
    public static Integer sharedContactsLimit()          { return safe(get()?.Shared_Contacts_Limit__c, 500); }
    /** @description Max messageable contacts to return. */
    public static Integer messageableContactsLimit()     { return safe(get()?.Messageable_Contacts_Limit__c, 200); }
    /** @description Max DM threads to return. */
    public static Integer dmThreadsLimit()               { return safe(get()?.DM_Threads_Limit__c, 200); }
    /** @description Max response threads to return. */
    public static Integer responseThreadsLimit()         { return safe(get()?.Response_Threads_Limit__c, 200); }
    /** @description Max search results to return. */
    public static Integer searchResultsLimit()           { return safe(get()?.Search_Results_Limit__c, 200); }
    /** @description Max contacts to return from search. */
    public static Integer searchContactsLimit()          { return safe(get()?.Search_Contacts_Limit__c, 100); }
    /** @description Max story comments to return. */
    public static Integer storyCommentsLimit()           { return safe(get()?.Story_Comments_Limit__c, 50); }
    /** @description Max notifications to mark as read in one operation. */
    public static Integer markAllReadLimit()             { return safe(get()?.Mark_All_Read_Limit__c, 1000); }
    /** @description Max notifications to delete in one operation. */
    public static Integer deleteAllNotificationsLimit()  { return safe(get()?.Delete_All_Notifications_Limit__c, 2000); }
    /** @description Minimum query limit for unified feed. */
    public static Integer unifiedFeedMinQueryLimit()     { return safe(get()?.Unified_Feed_Min_Query_Limit__c, 50); }

    // ---- Neighbourhood Health & Split Thresholds ----
    private static Decimal safeDec(Decimal val, Decimal fallback) {
        return val != null ? val : fallback;
    }

    public static Integer neighbourhoodSoftCap()          { return safe(get()?.Neighbourhood_Soft_Cap__c, 150); }
    public static Integer neighbourhoodIdealMin()          { return safe(get()?.Neighbourhood_Ideal_Min__c, 60); }
    public static Integer neighbourhoodIdealMax()          { return safe(get()?.Neighbourhood_Ideal_Max__c, 120); }
    public static Decimal recognitionScoreThreshold()      { return safeDec(get()?.Recognition_Score_Threshold__c, 0.30); }
    public static Decimal lurkerRatioThreshold()           { return safeDec(get()?.Lurker_Ratio_Threshold__c, 0.50); }
    public static Integer splitReviewHouseholdTrigger()    { return safe(get()?.Split_Review_Household_Trigger__c, 150); }
    public static Integer minHouseholdsPerCell()           { return safe(get()?.Min_Households_Per_Cell__c, 30); }
    public static Integer minActiveMembersPerCell()        { return safe(get()?.Min_Active_Members_Per_Cell__c, 15); }
    public static Integer minRespondersPerCell()           { return safe(get()?.Min_Responders_Per_Cell__c, 8); }
    public static Integer minPostsPerWeekPerCell()         { return safe(get()?.Min_Posts_Per_Week_Per_Cell__c, 5); }
    public static Decimal minInternalTieRatio()            { return safeDec(get()?.Min_Internal_Tie_Ratio__c, 0.40); }
    public static Decimal maxDependencyRatio()             { return safeDec(get()?.Max_Dependency_Ratio__c, 0.35); }
    public static Integer dependencyMonitorWeeks()         { return safe(get()?.Dependency_Monitor_Weeks__c, 2); }
    public static Integer dependencyReviewWeeks()          { return safe(get()?.Dependency_Review_Weeks__c, 5); }
    public static Integer dependencyInterveneWeeks()       { return safe(get()?.Dependency_Intervene_Weeks__c, 8); }

    // ---- Email Alert Settings ----
    public static Integer emailAlertBatchCap()           { return safe(get()?.Email_Alert_Batch_Cap__c, 5000); }
    public static Integer digestEmailSendHour()          { return safe(get()?.Digest_Email_Send_Hour__c, 6); }
    public static Integer digestWeeklyDay()              { return safe(get()?.Digest_Weekly_Day__c, 7); }
    public static Boolean emailAlertsGlobalEnabled()     { return get()?.Email_Alerts_Global_Enabled__c == true; }
    public static Boolean digestEmailGlobalEnabled()     { return get()?.Digest_Email_Global_Enabled__c == true; }

    public static Set<String> emailPilotNeighbourhoodIds() {
        return parseCsvIds(get()?.Email_Pilot_Neighbourhood_Ids__c);
    }
    public static Set<String> emailPilotUserIds() {
        return parseCsvIds(get()?.Email_Pilot_User_Ids__c);
    }

    private static Set<String> parseCsvIds(String csv) {
        Set<String> ids = new Set<String>();
        if (String.isNotBlank(csv)) {
            for (String s : csv.split(',')) {
                String trimmed = s.trim();
                if (String.isNotBlank(trimmed)) {
                    ids.add(trimmed);
                }
            }
        }
        return ids;
    }

    // ---- Data Retention ----
    public static Integer dataRetentionMonths()          { return safe(get()?.Data_Retention_Months__c, 6); }
    public static Integer conversationTrimKeepCount()    { return safe(get()?.Conversation_Trim_Keep_Count__c, 50); }
    public static Integer dataRetentionBatchSize()       { return safe(get()?.Data_Retention_Batch_Size__c, 200); }

    // ---- Vouching ----
    /** @description Counting revocations within the rolling 12-month window that auto-pause a voucher's ability to vouch. */
    public static Integer vouchingDisableThreshold()     { return safe(get()?.Vouching_Disable_Threshold__c, 2); }
    /** @description Days a vouch request can sit Pending before being marked Expired by FimbyVouchExpiryJob. */
    public static Integer vouchRequestExpiryDays()       { return safe(get()?.Vouch_Request_Expiry_Days__c, 30); }
    /** @description Days after a decline before the same requester can re-ask the same reference. */
    public static Integer vouchDeclineCooldownDays()     { return safe(get()?.Vouch_Decline_Cooldown_Days__c, 14); }
    /** @description Days before a still-Pending vouch triggers a moderator pending-7-days alert. */
    public static Integer vouchPendingModeratorAlertDays() { return safe(get()?.Vouch_Pending_Moderator_Alert_Days__c, 7); }

    // ---- Account Deletion / Grace Window ----
    /** @description Default grace window (days) for in-app delete requests before scrub runs. */
    public static Integer defaultGraceWindowDays()       { return safe(get()?.Default_Grace_Window_Days__c, 30); }
    /** @description TTL (hours) for reactivation magic-link tokens requested via /account-paused. */
    public static Integer reactivationTokenTtlHours()    { return safe(get()?.Reactivation_Token_TTL_Hours__c, 24); }

    // ---- App Install Prompt (mobile web) ----
    /** @description Master kill switch for the mobile-web app install prompt. */
    public static Boolean appPromptEnabled()             { return get()?.App_Prompt_Enabled__c == true; }
    /** @description Days between repeat showings of the install prompt for the same browser. */
    public static Integer appPromptCooldownDays()        { return safe(get()?.App_Prompt_Cooldown_Days__c, 14); }
    /** @description Destination for the iOS "Get the app" CTA in the install prompt. */
    public static String appStoreUrlIos()                { return get()?.App_Store_URL_iOS__c; }
    /** @description Destination for the Android "Get the app" CTA in the install prompt. */
    public static String appStoreUrlAndroid()            { return get()?.App_Store_URL_Android__c; }

    // ---- Terms / Agreement Versioning ----
    /** @description Current published version of the FIMBY Terms of Service. */
    public static String tosCurrentVersion()             { return get()?.Tos_Current_Version__c; }
    /** @description Date the current Terms of Service version took effect. */
    public static Date   tosEffectiveDate()              { return get()?.Tos_Effective_Date__c; }
    /** @description Current published version of the Community Group Agreement. */
    public static String cgaCurrentVersion()             { return get()?.Cga_Current_Version__c; }
    /** @description Date the current CGA version took effect. */
    public static Date   cgaEffectiveDate()              { return get()?.Cga_Effective_Date__c; }

    @TestVisible
    private static void setMock(FIMBY_App_Settings__mdt mock) {
        cached = mock;
    }

    // URL management via FIMBY_URL__mdt
    private static Map<String, FIMBY_URL__mdt> urlCache;

    /**
     * @description Returns the base URL + path for the given FIMBY_URL__mdt developer name.
     * @param developerName Developer name of the FIMBY_URL__mdt record
     * @return Combined Base_URL__c + Path__c, or empty string if not found
     */
    public static String getUrl(String developerName) {
        if (urlCache == null) {
            urlCache = FIMBY_URL__mdt.getAll();
        }
        FIMBY_URL__mdt rec = urlCache.get(developerName);
        if (rec == null) { return ''; }
        String base = rec.Base_URL__c != null ? rec.Base_URL__c : '';
        String path = rec.Path__c != null ? rec.Path__c : '';
        return base + path;
    }

    /**
     * @description Returns the base URL + path for the given FIMBY_URL__mdt, appended with recordId.
     * @param developerName Developer name of the FIMBY_URL__mdt record
     * @param recordId Record ID to append to the URL
     * @return Combined Base_URL__c + Path__c + recordId
     */
    public static String getUrl(String developerName, String recordId) {
        return getUrl(developerName) + (recordId != null ? recordId : '');
    }

    /**
     * @description Returns the base URL + path + recordId + query suffix for the given FIMBY_URL__mdt.
     * Use for record-detail URLs that need an action query string, e.g.
     * `FimbySettings.getUrl('Library_Item', itemId, '?action=reviewRequest&requestId=' + reqId)`.
     * @param developerName Developer name of the FIMBY_URL__mdt record
     * @param recordId Record ID to append to the URL (may be null for page routes)
     * @param querySuffix Query string suffix including leading '?' (or '&' if path already contains '?')
     * @return Combined Base_URL__c + Path__c + recordId + querySuffix
     */
    public static String getUrl(String developerName, String recordId, String querySuffix) {
        return getUrl(developerName, recordId) + (querySuffix != null ? querySuffix : '');
    }
}
