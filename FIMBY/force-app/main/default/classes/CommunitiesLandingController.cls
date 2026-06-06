/**
 * Routes CommunitiesLanding visitors to the LWR experience, with an optional
 * mobile-browser app handoff after welcome set-password (retURL lands here).
 */
public with sharing class CommunitiesLandingController {

    private static final String CONTINUE_PARAM = 'continue';
    private static final String FIMBY_WEBVIEW_UA = 'FIMBY-WebView';

    @TestVisible
    private static String testUserAgent;
    @TestVisible
    private static Boolean testSimulateGuest;
    @TestVisible
    private static Boolean testHandoffEnabled;

    public PageReference forwardToStartPage() {
        if (ApexPages.currentPage().getParameters().containsKey(CONTINUE_PARAM)) {
            return forwardToCommunityHome();
        }
        if (shouldOfferAppHandoff()) {
            PageReference ref = Page.FimbyAppHandoff;
            ref.setRedirect(true);
            return ref;
        }
        return forwardToCommunityHome();
    }

    private PageReference forwardToCommunityHome() {
        return Network.communitiesLanding();
    }

    private Boolean shouldOfferAppHandoff() {
        Boolean handoffEnabled = (Test.isRunningTest() && testHandoffEnabled != null)
            ? testHandoffEnabled
            : FimbySettings.appHandoffEnabled();
        if (!handoffEnabled) {
            return false;
        }
        Boolean isGuest = (Test.isRunningTest() && testSimulateGuest != null)
            ? testSimulateGuest
            : (UserInfo.getUserType() == 'Guest');
        if (isGuest) {
            return false;
        }
        String userAgent = getUserAgent();
        if (String.isBlank(userAgent)) {
            return false;
        }
        if (userAgent.contains(FIMBY_WEBVIEW_UA)) {
            return false;
        }
        return isMobileUserAgent(userAgent);
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
    private static Boolean isMobileUserAgent(String userAgent) {
        String ua = userAgent.toLowerCase();
        return ua.contains('iphone')
            || ua.contains('ipad')
            || ua.contains('ipod')
            || ua.contains('android');
    }

    public CommunitiesLandingController() {}
}
