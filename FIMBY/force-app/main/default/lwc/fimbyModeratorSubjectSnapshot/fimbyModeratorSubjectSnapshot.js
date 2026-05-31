import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyModeratorSubjectSnapshot extends LightningElement {
    @api subjectData = {};
    @track isExpanded = false;

    _mediaQuery;

    get infoIconUrl() { return `${IMPACT_ICONS}/info.png`; }

    get photoUrl() {
        return this.subjectData?.photoUrl || `${IMPACT_ICONS}/NoProfilePhoto.png`;
    }

    get chevronIcon() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get ariaExpanded() {
        return this.isExpanded ? 'true' : 'false';
    }

    get hasRecentHistory() {
        return this.subjectData?.recentHistory?.length > 0;
    }

    get noHistory() {
        return !this.hasRecentHistory &&
               (this.subjectData?.reportCount === 0 || this.subjectData?.reportCount == null) &&
               (this.subjectData?.concernCount === 0 || this.subjectData?.concernCount == null) &&
               (this.subjectData?.blockCount === 0 || this.subjectData?.blockCount == null);
    }

    connectedCallback() {
        this._mediaQuery = window.matchMedia('(min-width: 768px)');
        this.isExpanded = this._mediaQuery.matches;
        this._mediaQuery.addEventListener('change', this._handleMediaChange);
    }

    disconnectedCallback() {
        if (this._mediaQuery) {
            this._mediaQuery.removeEventListener('change', this._handleMediaChange);
        }
    }

    _handleMediaChange = (e) => {
        this.isExpanded = e.matches;
    }

    toggleExpanded() {
        this.isExpanded = !this.isExpanded;
    }
}