/**
 * @description Exposes the mobile-web app install prompt config (kill switch,
 * cooldown, platform store URLs) to the Experience Cloud LWC. Read-only,
 * cacheable wire — gate decisions stay client-side, this only ships the
 * configuration the modal needs.
 */
public with sharing class FimbyAppPromptController {

    public class AppPromptConfig {
        @AuraEnabled public Boolean enabled;
        @AuraEnabled public Integer cooldownDays;
        @AuraEnabled public String iosStoreUrl;
        @AuraEnabled public String androidStoreUrl;

        public AppPromptConfig(Boolean enabled, Integer cooldownDays, String iosStoreUrl, String androidStoreUrl) {
            this.enabled = enabled;
            this.cooldownDays = cooldownDays;
            this.iosStoreUrl = iosStoreUrl;
            this.androidStoreUrl = androidStoreUrl;
        }
    }

    @AuraEnabled(cacheable=true)
    public static AppPromptConfig getAppPromptConfig() {
        return new AppPromptConfig(
            FimbySettings.appPromptEnabled(),
            FimbySettings.appPromptCooldownDays(),
            FimbySettings.appStoreUrlIos(),
            FimbySettings.appStoreUrlAndroid()
        );
    }
}
