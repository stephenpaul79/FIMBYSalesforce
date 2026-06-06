/**
 * CommunitiesLanding routing — mobile app handoff gate and legacy forward.
 */
@IsTest
private class CommunitiesLandingControllerTest {

    @TestSetup
    static void setup() {
        Account nh = FimbyTestDataFactory.createNeighbourhood(true);
        Contact c = FimbyTestDataFactory.createNeighbourhoodContact(nh.Id, true);
        FimbyTestDataFactory.createCommunityUser(c.Id, null, true);
    }

    private static User getCommunityUser() {
        Account nh = [
            SELECT Id
            FROM Account
            WHERE Name LIKE 'Test Neighbourhood%'
            LIMIT 1
        ];
        Contact c = [
            SELECT Id
            FROM Contact
            WHERE AccountId = :nh.Id
            LIMIT 1
        ];
        List<User> users = [
            SELECT Id
            FROM User
            WHERE ContactId = :c.Id
              AND IsActive = true
            LIMIT 1
        ];
        System.assert(!users.isEmpty(), 'TestSetup must create a community User for the test Contact.');
        return users[0];
    }

    private static void setLandingPage(String userAgent, String continueParam) {
        CommunitiesLandingController.testSimulateGuest = null;
        CommunitiesLandingController.testHandoffEnabled = null;
        CommunitiesLandingController.testUserAgent = userAgent;
        PageReference pr = Page.CommunitiesLanding;
        if (String.isNotBlank(continueParam)) {
            pr.getParameters().put('continue', continueParam);
        }
        Test.setCurrentPage(pr);
    }

    private static Boolean isHandoffRef(PageReference ref) {
        return ref != null
            && ref.getUrl() != null
            && ref.getUrl().toLowerCase().contains('fimbyapphandoff');
    }

    @IsTest
    static void forwardToStartPage_desktop_skipsHandoff() {
        User u = getCommunityUser();
        System.runAs(u) {
            setLandingPage('Mozilla/5.0 (Windows NT 10.0; Win64; x64)', null);
            CommunitiesLandingController ctrl = new CommunitiesLandingController();
            Test.startTest();
            PageReference ref = ctrl.forwardToStartPage();
            Test.stopTest();
            System.assert(!isHandoffRef(ref), 'Desktop should not redirect to handoff');
        }
    }

    @IsTest
    static void forwardToStartPage_iphone_offersHandoff() {
        System.assert(
            FimbySettings.appHandoffEnabled(),
            'Default CMDT should enable app handoff for this test'
        );
        User u = getCommunityUser();
        System.runAs(u) {
            setLandingPage(
                'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
                null
            );
            CommunitiesLandingController ctrl = new CommunitiesLandingController();
            Test.startTest();
            PageReference ref = ctrl.forwardToStartPage();
            Test.stopTest();
            System.assert(isHandoffRef(ref), 'iPhone should redirect to handoff');
            System.assertEquals(true, ref.getRedirect());
        }
    }

    @IsTest
    static void forwardToStartPage_continueWeb_skipsHandoffOnMobile() {
        User u = getCommunityUser();
        System.runAs(u) {
            setLandingPage(
                'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)',
                'web'
            );
            CommunitiesLandingController ctrl = new CommunitiesLandingController();
            Test.startTest();
            PageReference ref = ctrl.forwardToStartPage();
            Test.stopTest();
            System.assert(!isHandoffRef(ref), 'continue=web should bypass handoff');
        }
    }

    @IsTest
    static void forwardToStartPage_webView_skipsHandoff() {
        User u = getCommunityUser();
        System.runAs(u) {
            setLandingPage('FIMBY-WebView/1.0 Mozilla/5.0 (iPhone)', null);
            CommunitiesLandingController ctrl = new CommunitiesLandingController();
            Test.startTest();
            PageReference ref = ctrl.forwardToStartPage();
            Test.stopTest();
            System.assert(!isHandoffRef(ref), 'Native WebView should skip handoff');
        }
    }

    @IsTest
    static void forwardToStartPage_android_offersHandoff() {
        System.assert(FimbySettings.appHandoffEnabled());
        User u = getCommunityUser();
        System.runAs(u) {
            setLandingPage('Mozilla/5.0 (Linux; Android 14)', null);
            CommunitiesLandingController ctrl = new CommunitiesLandingController();
            PageReference ref = ctrl.forwardToStartPage();
            System.assert(isHandoffRef(ref), 'Android should redirect to handoff');
        }
    }

    @IsTest
    static void forwardToStartPage_guest_skipsHandoff() {
        User u = getCommunityUser();
        System.runAs(u) {
            setLandingPage('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)', null);
            CommunitiesLandingController.testSimulateGuest = true;
            CommunitiesLandingController ctrl = new CommunitiesLandingController();
            PageReference ref = ctrl.forwardToStartPage();
            System.assert(!isHandoffRef(ref), 'Guest should skip handoff');
        }
    }

    @IsTest
    static void forwardToStartPage_handoffDisabled_skipsHandoff() {
        User u = getCommunityUser();
        System.runAs(u) {
            setLandingPage('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)', null);
            CommunitiesLandingController.testHandoffEnabled = false;
            CommunitiesLandingController ctrl = new CommunitiesLandingController();
            PageReference ref = ctrl.forwardToStartPage();
            System.assert(!isHandoffRef(ref), 'Disabled handoff should skip');
        }
    }

    @IsTest
    static void forwardToStartPage_blankUserAgent_skipsHandoff() {
        User u = getCommunityUser();
        System.runAs(u) {
            setLandingPage('', null);
            CommunitiesLandingController ctrl = new CommunitiesLandingController();
            PageReference ref = ctrl.forwardToStartPage();
            System.assert(!isHandoffRef(ref), 'Blank UA should skip handoff');
        }
    }

    @IsTest
    static void isMobileUserAgent_detectsMobileBrowsers() {
        System.assert(
            CommunitiesLandingController.isMobileUserAgent(
                'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)'
            )
        );
        System.assert(
            CommunitiesLandingController.isMobileUserAgent(
                'Mozilla/5.0 (Linux; Android 14)'
            )
        );
        System.assert(
            !CommunitiesLandingController.isMobileUserAgent(
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
            )
        );
    }
}
