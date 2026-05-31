/**
 * @description Wraps Cache.Org for org-wide caching of hot metadata that rarely changes.
 * Falls back to null (caller re-queries) if the cache partition is unavailable.
 * Partition: local.FIMBY (deployed via cachePartitions/FIMBY.cachePartition-meta.xml)
 */
public with sharing class FimbyCacheService {

    private static final String PARTITION = 'local.FIMBY';

    /**
     * @description Gets a value from org cache by key.
     * @param key Cache key (without partition prefix)
     * @return Cached value or null if not found or cache unavailable
     */
    public static Object get(String key) {
        try {
            return Cache.Org.get(PARTITION + '.' + key);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Puts a value into org cache with TTL.
     * @param key Cache key (without partition prefix)
     * @param value Value to cache
     * @param ttlSeconds Time-to-live in seconds
     */
    public static void put(String key, Object value, Integer ttlSeconds) {
        try {
            Cache.Org.put(PARTITION + '.' + key, value, ttlSeconds);
        } catch (Exception e) {
            // Cache unavailable — silently skip
        }
    }

    /**
     * @description Removes a value from org cache.
     * @param key Cache key (without partition prefix)
     */
    public static void remove(String key) {
        try {
            Cache.Org.remove(PARTITION + '.' + key);
        } catch (Exception e) {
            // Cache unavailable — silently skip
        }
    }

    // ─── Convenience: typed getters with built-in cache-aside pattern ───

    /**
     * Get seasonal theme data. Queries custom metadata directly — __mdt records
     * are already cached in application server memory by Salesforce, and Platform
     * Cache corrupts multi-byte Unicode (emoji) characters.
     */
    public static Map<String, Object> getSeasonalTheme() {
        return querySeasonalTheme();
    }

    /**
     * Get celebration actions. Queries custom metadata directly — same rationale
     * as getSeasonalTheme(): Platform Cache corrupts emoji strings.
     */
    public static List<Map<String, String>> getCelebrationActions() {
        return queryCelebrationActions();
    }

    /**
     * Get loading messages. Cached 24 hours — admin-managed metadata.
     */
    public static List<Map<String, String>> getLoadingMessages() {
        Object cached = get('LoadingMessages');
        if (cached != null) return (List<Map<String, String>>) cached;

        List<Map<String, String>> result = queryLoadingMessages();
        put('LoadingMessages', result, 86400);
        return result;
    }

    // ─── Query implementations ──────────────────────────────────────

    private static Map<String, Object> querySeasonalTheme() {
        Integer todayMonth = Date.today().month();
        Integer todayDay = Date.today().day();
        Date today = Date.today();

        for (FIMBY_Seasonal_Theme__mdt theme : [
            SELECT DeveloperName, Month__c, Day__c, Duration_Days__c,
                   Emoji_List__c, Title__c, Fire_On_Login__c, Animation_Style__c, Active__c
            FROM FIMBY_Seasonal_Theme__mdt
            WHERE Active__c = true
        ]) {
            Integer startMonth = Integer.valueOf(theme.Month__c);
            Integer startDay = Integer.valueOf(theme.Day__c);
            Integer duration = theme.Duration_Days__c != null ? Integer.valueOf(theme.Duration_Days__c) : 1;

            Date startDate = Date.newInstance(today.year(), startMonth, startDay);
            Date endDate = startDate.addDays(duration - 1);

            if (today >= startDate && today <= endDate) {
                return new Map<String, Object>{
                    'name' => theme.DeveloperName,
                    'emojiList' => theme.Emoji_List__c,
                    'title' => theme.Title__c,
                    'fireOnLogin' => theme.Fire_On_Login__c,
                    'animationStyle' => theme.Animation_Style__c
                };
            }
        }
        return null;
    }

    private static List<Map<String, String>> queryCelebrationActions() {
        List<Map<String, String>> actions = new List<Map<String, String>>();
        for (FIMBY_Celebration_Action__mdt rec : [
            SELECT Action_Key__c, Occasion__c, Emoji_List__c, Messages__c,
                   Animation_Style__c, Milestone_Thresholds__c
            FROM FIMBY_Celebration_Action__mdt
            WHERE Active__c = true
            ORDER BY Action_Key__c, Occasion__c
        ]) {
            actions.add(new Map<String, String>{
                'actionKey' => rec.Action_Key__c,
                'occasion' => rec.Occasion__c,
                'emojiList' => rec.Emoji_List__c,
                'messages' => rec.Messages__c,
                'animationStyle' => rec.Animation_Style__c,
                'milestoneThresholds' => rec.Milestone_Thresholds__c
            });
        }
        return actions;
    }

    private static List<Map<String, String>> queryLoadingMessages() {
        List<Map<String, String>> messages = new List<Map<String, String>>();
        for (FIMBY_Loading_Message__mdt msg : [
            SELECT Context__c, Message__c
            FROM FIMBY_Loading_Message__mdt
            WHERE Active__c = true
            ORDER BY Context__c, DeveloperName
        ]) {
            messages.add(new Map<String, String>{
                'context' => msg.Context__c,
                'message' => msg.Message__c
            });
        }
        return messages;
    }
}
