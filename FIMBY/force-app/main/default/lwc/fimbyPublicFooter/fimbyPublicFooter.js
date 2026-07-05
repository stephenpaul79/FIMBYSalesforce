import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { navigate } from 'c/fimbyNavigation';
import ICONS from '@salesforce/resourceUrl/Icons';
import getAppPromptConfig from '@salesforce/apex/FimbyAppPromptController.getAppPromptConfig';

const IOS_STORE_FALLBACK = 'https://apps.apple.com/app/fimby/id6776707632';
const ANDROID_STORE_FALLBACK = 'https://play.google.com/store/apps/details?id=com.fimby.app';

export default class FimbyPublicFooter extends NavigationMixin(LightningElement) {
    _appConfig = null;

    @wire(getAppPromptConfig)
    wiredAppConfig({ data }) {
        if (data) {
            this._appConfig = data;
        }
    }

    get appStoreBadgeUrl() {
        return `${ICONS}/app-store-badge.png`;
    }

    get googlePlayBadgeUrl() {
        return `${ICONS}/google-play-badge.png`;
    }

    get iosStoreUrl() {
        return this._appConfig?.iosStoreUrl || IOS_STORE_FALLBACK;
    }

    get androidStoreUrl() {
        return this._appConfig?.androidStoreUrl || ANDROID_STORE_FALLBACK;
    }

    handleAccountPausedNav(event) {
        event.preventDefault();
        navigate(this, '/account-paused');
    }
}
