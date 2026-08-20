import { LightningElement, api } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyParentManagedBadge extends LightningElement {
    @api parentManaged = false;

    get show() {
        return this.parentManaged === true;
    }

    get iconUrl() {
        return `${IMPACT_ICONS}/youth.png`;
    }
}
