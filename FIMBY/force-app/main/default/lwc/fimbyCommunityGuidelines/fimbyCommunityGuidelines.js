import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { navigateBack, navigateToRoute } from 'c/fimbyNavigation';

export default class FimbyCommunityGuidelines extends NavigationMixin(LightningElement) {
    @track isSupportModalOpen = false;
    @track supportKind = 'help';
    get careIconUrl()      { return `${IMPACT_ICONS}/care.png`; }
    get warningIconUrl()   { return `${IMPACT_ICONS}/warning.png`; }
    get moderatorIconUrl() { return `${IMPACT_ICONS}/moderatoractive.png`; }
    get emailIconUrl()     { return `${IMPACT_ICONS}/email.png`; }

    handleBack() {
        navigateBack(this, '/help-and-support');
    }

    handleEmailSafety() {
        this.supportKind = 'safety';
        this.isSupportModalOpen = true;
    }

    handleContactSupport() {
        this.supportKind = 'help';
        this.isSupportModalOpen = true;
    }

    handleSupportModalClose() {
        this.isSupportModalOpen = false;
    }

    handleTabChange(event) {
        const tab = event.detail?.tab;
        if (tab) navigateToRoute(this, tab);
    }
}
