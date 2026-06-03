import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class FimbyResponsesList extends NavigationMixin(LightningElement) {
    @track responses = [];
    @track filteredResponses = [];
    @track selectedFilter = 'all';
    @track isLoading = false;
    @track selectedResponseId = '';
    @track selectedResponderId = '';
    @track selectedResponderName = '';

    get totalResponses() {
        return this.responses.length;
    }

    get unreadResponses() {
        return this.responses.filter(r => r.isUnread).length;
    }

    get allTabClass() {
        return this.selectedFilter === 'all' ? 'filter-tab active' : 'filter-tab';
    }

    get unreadTabClass() {
        return this.selectedFilter === 'unread' ? 'filter-tab active' : 'filter-tab';
    }

    get acceptedTabClass() {
        return this.selectedFilter === 'accepted' ? 'filter-tab active' : 'filter-tab';
    }

    get pendingTabClass() {
        return this.selectedFilter === 'pending' ? 'filter-tab active' : 'filter-tab';
    }

    connectedCallback() {
        this.loadResponses();
    }

    loadResponses() {
        // Mock responses data
        this.responses = [
            {
                id: 'resp-1',
                responderName: 'Sarah Johnson',
                responderId: 'user-1',
                responderAvatar: '/resource/avatar1.jpg',
                responderRating: 4.8,
                isVerified: true,
                itemId: 'item-1',
                itemTitle: 'Garden Help Needed',
                itemType: 'need',
                itemImage: '/resource/garden.jpg',
                responseType: 'offer_help',
                message: 'I can help with your garden! I have experience with vegetable gardens and would love to help.',
                availability: 'Weekends, flexible hours',
                contactShared: true,
                status: 'pending',
                timestamp: new Date(Date.now() - 300000), // 5 min ago
                isUnread: true
            },
            {
                id: 'resp-2',
                responderName: 'Mike Chen',
                responderId: 'user-2',
                responderAvatar: '/resource/avatar2.jpg',
                responderRating: 4.5,
                isVerified: false,
                itemId: 'item-2',
                itemTitle: 'Moving Boxes Available',
                itemType: 'offer',
                itemImage: '/resource/boxes.jpg',
                responseType: 'interested',
                message: 'These would be perfect for my upcoming move! When can I pick them up?',
                availability: null,
                contactShared: false,
                status: 'accepted',
                timestamp: new Date(Date.now() - 3600000), // 1 hour ago
                isUnread: false
            }
        ];

        this.processResponses();
        this.filterResponses();
    }

    processResponses() {
        this.responses = this.responses.map(response => {
            const processed = {
                ...response,
                formattedTime: this.formatTime(response.timestamp),
                statusClass: this.getStatusClass(response.status),
                statusLabel: this.getStatusLabel(response.status),
                itemIcon: this.getItemIcon(response.itemType),
                itemTypeLabel: this.getItemTypeLabel(response.itemType),
                responseIcon: this.getResponseIcon(response.responseType),
                responseTypeLabel: this.getResponseTypeLabel(response.responseType),
                ratingStars: this.getRatingStars(response.responderRating),
                containerClass: this.getContainerClass(response),
                canRespond: response.status === 'pending',
                isPending: response.status === 'pending'
            };
            return processed;
        });
    }

    getContainerClass(response) {
        let classes = ['response-item'];
        if (response.isUnread) classes.push('unread');
        if (response.status === 'accepted') classes.push('accepted');
        if (response.status === 'declined') classes.push('declined');
        return classes.join(' ');
    }

    getStatusClass(status) {
        switch (status) {
            case 'pending': return 'status-pending';
            case 'accepted': return 'status-accepted';
            case 'declined': return 'status-declined';
            default: return 'status-unknown';
        }
    }

    getStatusLabel(status) {
        switch (status) {
            case 'pending': return 'Pending';
            case 'accepted': return 'Accepted';
            case 'declined': return 'Declined';
            default: return 'Unknown';
        }
    }

    getItemIcon(itemType) {
        switch (itemType) {
            case 'need': return 'utility:help';
            case 'offer': return 'utility:gift';
            case 'story': return 'utility:article';
            case 'library': return 'utility:knowledge_base';
            default: return 'utility:apps';
        }
    }

    getItemTypeLabel(itemType) {
        switch (itemType) {
            case 'need': return 'Ask:';
            case 'offer': return 'Offer:';
            case 'story': return 'Story:';
            case 'library': return 'Library:';
            default: return 'Item:';
        }
    }

    getResponseIcon(responseType) {
        switch (responseType) {
            case 'offer_help': return 'utility:help';
            case 'interested': return 'utility:favorite';
            case 'question': return 'utility:question_mark';
            case 'recommend': return 'utility:share';
            default: return 'utility:chat';
        }
    }

    getResponseTypeLabel(responseType) {
        switch (responseType) {
            case 'offer_help': return 'Offered to help';
            case 'interested': return 'Showed interest';
            case 'question': return 'Asked a question';
            case 'recommend': return 'Made a recommendation';
            default: return 'Responded';
        }
    }

    getRatingStars(rating) {
        const stars = [];
        for (let i = 1; i <= 5; i++) {
            stars.push({
                id: i,
                icon: i <= rating ? 'utility:favorite' : 'utility:favorite_alt',
                class: i <= rating ? 'star filled' : 'star empty'
            });
        }
        return stars;
    }

    formatTime(timestamp) {
        const now = new Date();
        const time = new Date(timestamp);
        const diff = now - time;
        const minutes = Math.floor(diff / 60000);
        const hours = Math.floor(diff / 3600000);
        const days = Math.floor(diff / 86400000);

        if (minutes < 1) return 'now';
        if (minutes < 60) return `${minutes}m`;
        if (hours < 24) return `${hours}h`;
        if (days < 7) return `${days}d`;
        return time.toLocaleDateString();
    }

    filterResponses() {
        switch (this.selectedFilter) {
            case 'unread':
                this.filteredResponses = this.responses.filter(r => r.isUnread);
                break;
            case 'accepted':
                this.filteredResponses = this.responses.filter(r => r.status === 'accepted');
                break;
            case 'pending':
                this.filteredResponses = this.responses.filter(r => r.status === 'pending');
                break;
            default:
                this.filteredResponses = [...this.responses];
        }
    }

    // Event handlers
    handleBack() {
        location.href = '/';
    }

    handleShowFilters() {
        // Show filter modal
        console.log('Show filters');
    }

    handleAllResponses() {
        this.selectedFilter = 'all';
        this.filterResponses();
    }

    handleUnreadResponses() {
        this.selectedFilter = 'unread';
        this.filterResponses();
    }

    handleAcceptedResponses() {
        this.selectedFilter = 'accepted';
        this.filterResponses();
    }

    handlePendingResponses() {
        this.selectedFilter = 'pending';
        this.filterResponses();
    }

    handleResponseClick(event) {
        const responseId = event.currentTarget.dataset.responseId;
        const response = this.responses.find(r => r.id === responseId);

        if (response) {
            response.isUnread = false;
            this.processResponses();
            this.filterResponses();
            this.navigateToResponseDetail(responseId);
        }
    }

    handleResponseKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleResponseClick(event);
        }
    }

    handleAcceptResponse(event) {
        event.stopPropagation();
        const responseId = event.currentTarget.dataset.responseId;
        const response = this.responses.find(r => r.id === responseId);

        if (response) {
            response.status = 'accepted';
            response.isUnread = false;
            this.processResponses();
            this.filterResponses();

            // Show success message
            this.dispatchEvent(new CustomEvent('responseaccepted', {
                detail: { responseId, responderName: response.responderName }
            }));
        }
    }

    handleDeclineResponse(event) {
        event.stopPropagation();
        const responseId = event.currentTarget.dataset.responseId;
        const response = this.responses.find(r => r.id === responseId);

        if (response) {
            response.status = 'declined';
            response.isUnread = false;
            this.processResponses();
            this.filterResponses();

            // Show success message
            this.dispatchEvent(new CustomEvent('responsedeclined', {
                detail: { responseId, responderName: response.responderName }
            }));
        }
    }

    handleMessageResponder(event) {
        event.stopPropagation();
        const responseId = event.currentTarget.dataset.responseId;
        const response = this.responses.find(r => r.id === responseId);

        if (response) {
            this.navigateToConversation(response.responderId, response.responderName);
        }
    }

    handleResponseMenu(event) {
        event.stopPropagation();
        const responseId = event.currentTarget.dataset.responseId;
        // Show status update modal
        this.selectedResponseId = responseId;
        const statusModal = this.template.querySelector('c-fimby-response-status-update');
        if (statusModal) {
            statusModal.show();
        }
    }

    handleStatusUpdated(event) {
        const { responseId, newStatus } = event.detail;
        // Update local response data
        const response = this.responses.find(r => r.id === responseId);
        if (response) {
            response.status = newStatus;
            this.processResponses();
            this.filterResponses();
        }
    }

    handleStatusError(event) {
        console.error('Status update error:', event.detail.error);
    }

    // Thanks functionality
    showThanksModal(responseId) {
        const response = this.responses.find(r => r.id === responseId);
        if (response) {
            this.selectedResponseId = responseId;
            this.selectedResponderId = response.responderId;
            this.selectedResponderName = response.responderName;

            const thanksModal = this.template.querySelector('c-fimby-thanks-giving');
            if (thanksModal) {
                thanksModal.show(response.responderId, response.responderName, responseId);
            }
        }
    }

    handleThanksSent(event) {
        console.log('Thanks sent:', event.detail);
        // Could update UI to show thanks was sent
    }

    handleNewPost() {
        location.href = '/create-story';
    }

    handleTabChange(event) {
        const selectedTab = event.detail.tab;
        // Map valid pages for Digital Experience
        const validPages = {
            'home': '/',
            'stories': '/?filter=story',
            'askOffer': '/ask-offer-list',
            'library': '/library-list',
            'messages': '/messages',
            'profile': '/profile'
        };

        if (validPages[selectedTab]) {
            location.href = validPages[selectedTab];
        }
    }

    handleLoadMore() {
        console.log('Load more responses');
    }

    handleRefresh() {
        this.loadResponses();
    }

    navigateToResponseDetail(responseId) {
        location.href = '/response-reply?recordId=' + responseId;
    }

    navigateToConversation(participantId, participantName) {
        location.href = '/conversation?participantId=' + participantId + '&participantName=' + participantName;
    }
}