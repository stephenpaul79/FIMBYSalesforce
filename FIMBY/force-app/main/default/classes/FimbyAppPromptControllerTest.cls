@isTest
private class FimbyAppPromptControllerTest {

    @isTest
    static void testGetAppPromptConfigReturnsMetadataValues() {
        Test.startTest();
        FimbyAppPromptController.AppPromptConfig cfg = FimbyAppPromptController.getAppPromptConfig();
        Test.stopTest();

        System.assertNotEquals(null, cfg, 'Config wrapper should never be null');
        System.assertEquals(FimbySettings.appPromptEnabled(), cfg.enabled,
            'enabled should round-trip from FimbySettings');
        System.assertEquals(FimbySettings.appPromptCooldownDays(), cfg.cooldownDays,
            'cooldownDays should round-trip from FimbySettings');
        System.assertEquals(FimbySettings.appStoreUrlIos(), cfg.iosStoreUrl,
            'iosStoreUrl should round-trip from FimbySettings');
        System.assertEquals(FimbySettings.appStoreUrlAndroid(), cfg.androidStoreUrl,
            'androidStoreUrl should round-trip from FimbySettings');
    }
}
