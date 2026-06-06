/**
 * Branded post-set-password handoff: open the native app or continue in the browser.
 */
public with sharing class FimbyAppHandoffController {

    @TestVisible
    private static String testUserAgent;
    @TestVisible
    private static String testSitePathPrefix;

    public String appOpenUrl { get; private set; }
    public String continueUrl { get; private set; }
    public String storeUrl { get; private set; }
    public Boolean showStoreLink { get; private set; }

    public FimbyAppHandoffController() {
        appOpenUrl = FimbySettings.getUrl('Site_Base');
        continueUrl = buildContinueInBrowserUrl();

        String userAgent = getUserAgent();
        if (isIos(userAgent)) {
            storeUrl = FimbySettings.appStoreUrlIos();
        } else if (isAndroid(userAgent)) {
            storeUrl = FimbySettings.appStoreUrlAndroid();
        }
        showStoreLink = String.isNotBlank(storeUrl);
    }

    private static String getUserAgent() {
        if (Test.isRunningTest() && testUserAgent != null) {
            return testUserAgent;
        }
        if (ApexPages.currentPage() == null) {
            return '';
        }
        Map<String, String> headers = ApexPages.currentPage().getHeaders();
        if (headers == null) {
            return '';
        }
        String ua = headers.get('User-Agent');
        if (String.isBlank(ua)) {
            ua = headers.get('user-agent');
        }
        return ua != null ? ua : '';
    }

    @TestVisible
    private static Boolean isIos(String userAgent) {
        if (String.isBlank(userAgent)) {
            return false;
        }
        String ua = userAgent.toLowerCase();
        return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
    }

    @TestVisible
    private static Boolean isAndroid(String userAgent) {
        return userAgent != null && userAgent.toLowerCase().contains('android');
    }

    private static String buildContinueInBrowserUrl() {
        PageReference cont = Page.CommunitiesLanding;
        cont.getParameters().put('continue', 'web');
        String url = cont.getUrl();

        String prefix = (Test.isRunningTest() && testSitePathPrefix != null)
            ? testSitePathPrefix
            : Site.getPathPrefix();
        if (String.isNotBlank(prefix)) {
            if (!prefix.startsWith('/')) {
                prefix = '/' + prefix;
            }
            url = prefix + url;
        }
        return url;
    }
}
