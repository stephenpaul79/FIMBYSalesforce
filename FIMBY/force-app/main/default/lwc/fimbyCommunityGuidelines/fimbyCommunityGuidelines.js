import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { navigateBack, navigateToRoute } from 'c/fimbyNavigation';

export default class FimbyCommunityGuidelines extends NavigationMixin(LightningElement) {
    get careIconUrl()      { return `${IMPACT_ICONS}/care.png`; }
    get warningIconUrl()   { return `${IMPACT_ICONS}/warning.png`; }
    get moderatorIconUrl() { return `${IMPACT_ICONS}/moderatoractive.png`; }
    get emailIconUrl()     { return `${IMPACT_ICONS}/email.png`; }

    handleBack() {
        navigateBack(this, '/help-and-support');
    }

    handleTabChange(event) {
        const tab = event.detail?.tab;
        if (tab) navigateToRoute(this, tab);
    }
}
