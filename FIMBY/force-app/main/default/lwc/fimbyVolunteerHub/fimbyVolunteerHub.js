import { LightningElement, track } from 'lwc';
export default class FimbyVolunteerHub extends LightningElement {
    @track volunteerOpportunities = [];

    connectedCallback() {
        this.loadOpportunities();
    }

    loadOpportunities() {
        this.volunteerOpportunities = [
            {
                id: 'vol1',
                title: 'Community Garden Cleanup',
                location: 'Central Park',
                date: 'Sat, Mar 15',
                description: 'Help us maintain the community garden and prepare for spring planting.',
                volunteersNeeded: 8,
                icon: 'utility:world'
            },
            {
                id: 'vol2',
                title: 'Senior Helper Program',
                location: 'Various Homes',
                date: 'Ongoing',
                description: 'Assist elderly neighbors with grocery shopping and light household tasks.',
                volunteersNeeded: 12,
                icon: 'utility:heart'
            },
            {
                id: 'vol3',
                title: 'Neighborhood Watch',
                location: 'Oak Street Area',
                date: 'Weekly',
                description: 'Join our community safety patrol to keep our neighborhood secure.',
                volunteersNeeded: 5,
                icon: 'utility:shield'
            }
        ];
    }

    handleOpportunityClick(event) {
        const opportunityId = event.currentTarget.dataset.opportunityId;
        console.log('Opportunity clicked:', opportunityId);
    }

    handleVolunteer(event) {
        event.stopPropagation();
        const opportunityId = event.currentTarget.dataset.opportunityId;
        console.log('Volunteer for:', opportunityId);
    }

    handleBack() { window.history.back(); }
    handleTabChange(event) { console.log('Tab change:', event.detail.tab); }
}