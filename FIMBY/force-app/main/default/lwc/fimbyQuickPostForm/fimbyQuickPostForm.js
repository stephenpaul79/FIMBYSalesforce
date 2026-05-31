import { LightningElement, api, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyQuickPostForm extends LightningElement {
    @api selectedType = ''; // Can be passed from parent component
    @api isModal = false;   // Modal mode flag

    @track isVisible = false;

    get needIconUrl()    { return `${IMPACT_ICONS}/needsm.png`; }
    get offerIconUrl()   { return `${IMPACT_ICONS}/giftsm.png`; }
    get eventIconUrl()   { return `${IMPACT_ICONS}/plannersm.png`; }
    get bulkBuyIconUrl() { return `${IMPACT_ICONS}/bulkbuy.png`; }
    get storyIconUrl()   { return `${IMPACT_ICONS}/StoriesActive.png`; }
    get lendingIconUrl() { return `${IMPACT_ICONS}/ToolboxActive.png`; }

    routeMap = {
        need: '/ask-or-offer-post?type=Need',
        offer: '/ask-or-offer-post?type=Offer',
        event: '/ask-or-offer-post?type=Event',
        bulkbuy: '/ask-or-offer-post?type=BulkBuy',
        story: '/shared-life-post',
        lending: '/library-item-post'
    };

    connectedCallback() {
        // Only check URL params in full-page mode
        if (!this.isModal) {
            // Check if type was passed from URL parameter
            const urlParams = new URLSearchParams(window.location.search);
            const typeParam = urlParams.get('type') || this.selectedType;

            if (typeParam) {
                // Normalize the type to lowercase for route lookup
                const normalizedType = typeParam.toLowerCase();

                // If we have a valid type, redirect immediately
                if (this.routeMap[normalizedType]) {
                    this.navigateTo(normalizedType);
                }
            }
        }
    }

    // Public API methods for modal mode
    @api
    show() {
        if (document.activeElement) {
            document.activeElement.blur();
        }
        this.isVisible = true;
    }

    @api
    hide() {
        this.isVisible = false;
        this.dispatchEvent(new CustomEvent('close'));
    }

    // Event handlers
    handleTypeSelect(event) {
        const contentType = event.currentTarget.dataset.type;

        if (this.isModal) {
            this.hide();
        }

        this.navigateTo(contentType);
    }

    handleClose() {
        if (this.isModal) {
            this.hide();
        } else {
            // Navigate back to home in full-page mode
            window.location.href = '/';
        }
    }

    handleOverlayClick(event) {
        // Close when clicking on overlay background
        if (event.target === event.currentTarget) {
            this.hide();
        }
    }

    handleModalContentClick(event) {
        // Prevent overlay click when clicking modal content
        event.stopPropagation();
    }

    // Navigate to the appropriate form
    navigateTo(contentType) {
        const url = this.routeMap[contentType];
        if (url) {
            window.location.href = url;
        }
    }
}