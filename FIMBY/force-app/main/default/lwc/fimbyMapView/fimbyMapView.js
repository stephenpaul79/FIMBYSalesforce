import { LightningElement, track } from 'lwc';
export default class FimbyMapView extends LightningElement {
    @track activeFilters = [];

    get mapFilters() {
        return [
            { id: 'needs', label: 'Asks', icon: 'utility:help' },
            { id: 'offers', label: 'Offers', icon: 'utility:gift' },
            { id: 'library', label: 'Library', icon: 'utility:knowledge_base' },
            { id: 'stories', label: 'Stories', icon: 'utility:article' }
        ];
    }

    handleBack() { window.history.back(); }
    handleFilterToggle(event) {
        const filterId = event.currentTarget.dataset.filter;
        console.log('Toggle filter:', filterId);
    }
    handleTabChange(event) { console.log('Tab change:', event.detail.tab); }
}