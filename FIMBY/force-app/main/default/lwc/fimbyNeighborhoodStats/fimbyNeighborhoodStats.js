import { LightningElement, track } from 'lwc';
export default class FimbyNeighborhoodStats extends LightningElement {
    @track neighborhoodStats = [];
    @track recentActivities = [];

    connectedCallback() {
        this.loadStats();
    }

    loadStats() {
        this.neighborhoodStats = [
            { id: 'members', icon: 'utility:people', value: '247', label: 'Active Members', changeText: '+12 this week' },
            { id: 'helped', icon: 'utility:help', value: '89', label: 'People Helped', changeText: '+5 this week' },
            { id: 'shared', icon: 'utility:gift', value: '156', label: 'Items Shared', changeText: '+8 this week' },
            { id: 'stories', icon: 'utility:article', value: '34', label: 'Stories Shared', changeText: '+3 this week' }
        ];

        this.recentActivities = [
            { id: 'act1', icon: 'utility:help', text: 'Sarah helped Mike with garden work', time: '2h ago' },
            { id: 'act2', icon: 'utility:gift', text: 'Emma shared homemade cookies', time: '4h ago' },
            { id: 'act3', icon: 'utility:article', text: 'David posted a community story', time: '6h ago' }
        ];
    }

    handleBack() { window.history.back(); }
    handleTabChange(event) { console.log('Tab change:', event.detail.tab); }
}