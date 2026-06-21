import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { navigateBack, navigateToRoute } from 'c/fimbyNavigation';

export default class FimbySystemProfile extends NavigationMixin(LightningElement) {
    get pandaImageUrl() {
        return `${IMPACT_ICONS}/systempanda.png`;
    }

    get contactIconUrl() { return `${IMPACT_ICONS}/sign.png`; }
    get aboutIconUrl() { return `${IMPACT_ICONS}/chat.png`; }
    get accessibilityIconUrl() { return `${IMPACT_ICONS}/accessibility.png`; }

    handleBack() {
        navigateBack(this, '/');
    }

    handleTabChange(event) {
        navigateToRoute(this, event.detail.tab);
    }
}
