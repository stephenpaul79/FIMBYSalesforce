/**
 * @description Lookup helper for FIMBY_Public_Website_URL__mdt records — public-website URLs
 * (fimby.com explainers, terms, privacy, etc.) that are intentionally NOT affected by the
 * Experience Cloud host swap. For Experience Cloud routes use FimbySettings.getUrl().
 *
 * Admins edit URL values in Setup -> Custom Metadata Types -> FIMBY Public Website URL with
 * zero Apex deploy.
 */
public with sharing class FimbyPublicWebsiteLinks {
    private static Map<String, String> cache;

    /**
     * @description Returns the full public-website URL for the given FIMBY_Public_Website_URL__mdt
     * developer name.
     * @param developerName Developer name of the FIMBY_Public_Website_URL__mdt record
     * @return Full_URL__c value, or empty string if no matching record
     */
    public static String getUrl(String developerName) {
        if (cache == null) {
            cache = new Map<String, String>();
            for (FIMBY_Public_Website_URL__mdt rec : FIMBY_Public_Website_URL__mdt.getAll().values()) {
                cache.put(rec.DeveloperName, rec.Full_URL__c);
            }
        }
        if (String.isBlank(developerName)) { return ''; }
        String url = cache.get(developerName);
        return url != null ? url : '';
    }

    @TestVisible
    private static void clearCacheForTest() {
        cache = null;
    }
}
