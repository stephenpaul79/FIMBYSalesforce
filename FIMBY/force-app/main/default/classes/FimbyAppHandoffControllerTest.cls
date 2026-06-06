@IsTest
private class FimbyAppHandoffControllerTest {

    @IsTest
    static void continueUrl_includesSitePathPrefix() {
        FimbyAppHandoffController.testSitePathPrefix = '/vforcesite';
        FimbyAppHandoffController.testUserAgent =
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)';
        Test.setCurrentPage(Page.FimbyAppHandoff);

        FimbyAppHandoffController ctrl = new FimbyAppHandoffController();

        System.assert(
            ctrl.continueUrl.contains('/vforcesite/apex/'),
            'Continue URL must include the Experience Cloud site path prefix'
        );
        System.assert(ctrl.continueUrl.contains('continue=web'));
    }

    @IsTest
    static void exposesHandoffUrlsForIos() {
        FimbyAppHandoffController.testSitePathPrefix = null;
        FimbyAppHandoffController.testUserAgent =
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)';
        PageReference pr = Page.FimbyAppHandoff;
        Test.setCurrentPage(pr);

        FimbyAppHandoffController ctrl = new FimbyAppHandoffController();

        System.assertEquals(FimbySettings.getUrl('Site_Base'), ctrl.appOpenUrl);
        System.assert(
            ctrl.continueUrl != null && ctrl.continueUrl.contains('continue'),
            'Continue URL should include escape-hatch param'
        );
        System.assertEquals(true, ctrl.showStoreLink);
        System.assert(String.isNotBlank(ctrl.storeUrl));
    }

    @IsTest
    static void exposesHandoffUrlsForAndroid() {
        FimbyAppHandoffController.testUserAgent =
            'Mozilla/5.0 (Linux; Android 14; Pixel 8)';
        PageReference pr = Page.FimbyAppHandoff;
        Test.setCurrentPage(pr);

        FimbyAppHandoffController ctrl = new FimbyAppHandoffController();

        System.assertEquals(true, ctrl.showStoreLink);
        System.assertEquals(FimbySettings.appStoreUrlAndroid(), ctrl.storeUrl);
    }

    @IsTest
    static void hidesStoreLinkOnDesktopUserAgent() {
        FimbyAppHandoffController.testUserAgent =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64)';
        Test.setCurrentPage(Page.FimbyAppHandoff);

        FimbyAppHandoffController ctrl = new FimbyAppHandoffController();

        System.assertEquals(false, ctrl.showStoreLink);
        System.assertEquals(null, ctrl.storeUrl);
    }

    @IsTest
    static void constructsWithNoPageContext() {
        FimbyAppHandoffController.testUserAgent = null;
        FimbyAppHandoffController ctrl = new FimbyAppHandoffController();
        System.assertEquals(false, ctrl.showStoreLink);
        System.assert(String.isNotBlank(ctrl.appOpenUrl));
    }

    @IsTest
    static void platformDetectionHelpers() {
        System.assert(FimbyAppHandoffController.isIos('Mozilla/5.0 (iPad;)'));
        System.assert(FimbyAppHandoffController.isAndroid('Mozilla/5.0 (Linux; Android 14)'));
        System.assert(!FimbyAppHandoffController.isIos('Mozilla/5.0 (Windows NT 10.0)'));
        System.assert(!FimbyAppHandoffController.isIos(''));
        System.assert(!FimbyAppHandoffController.isAndroid(''));
    }
}
