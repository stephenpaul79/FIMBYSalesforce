import { LightningElement } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyCommunityGuidelines extends LightningElement {
    get careIconUrl()      { return `${IMPACT_ICONS}/care.png`; }
    get warningIconUrl()   { return `${IMPACT_ICONS}/warning.png`; }
    get moderatorIconUrl() { return `${IMPACT_ICONS}/moderatoractive.png`; }
    get emailIconUrl()     { return `${IMPACT_ICONS}/email.png`; }

    handleBack() {
        location.href = '/help-and-support';
    }

    handleTabChange(event) {
        const routes = {
            home: '/',
            library: '/library-list',
            messages: '/messages',
            mine: '/my-stuff'
        };
        const tab = event.detail?.tab;
        if (routes[tab]) location.href = routes[tab];
    }
}
