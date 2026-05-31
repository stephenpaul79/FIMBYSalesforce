import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class FimbyActivityFeed extends NavigationMixin(LightningElement) {
    @track activities = [];

    connectedCallback() {
        this.loadActivities();
    }

    loadActivities() {
        this.activities = [
            {
                id: 'act-1',
                actorName: 'Sarah Johnson',
                actorAvatar: '/resource/avatar1.jpg',
                actionText: 'shared a new story',
                timestamp: new Date(Date.now() - 300000),
                formattedTime: '5m ago'
            }
        ];
    }

    handleBack() { window.history.back(); }
    handleTabChange(event) { console.log('Tab change:', event.detail.tab); }
    handleLoadMore() { console.log('Load more activities'); }
    handleRefresh() { this.loadActivities(); }
}