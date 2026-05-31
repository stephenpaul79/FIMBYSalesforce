import { LightningElement } from 'lwc';

/**
 * fimbyQuickPost - Quick Post Navigation Card
 *
 * A simple navigation trigger that routes users to the appropriate
 * dedicated form components for creating different content types.
 *
 * Routes:
 * - Need → /ask-or-offer-post?type=Need
 * - Offer → /ask-or-offer-post?type=Offer
 * - Story → /story-composer
 * - Lend → /add-library-item
 */
export default class FimbyQuickPost extends LightningElement {

    routeMap = {
        need: '/ask-or-offer-post?type=Need',
        offer: '/ask-or-offer-post?type=Offer',
        bulkbuy: '/ask-or-offer-post?type=BulkBuy',
        story: '/story-composer',
        lending: '/add-library-item'
    };

    // Handle main quick post area click - default to Need form
    handleQuickPostClick() {
        this.navigateTo('need');
    }

    // Handle specific content type quick actions
    handleQuickAction(event) {
        const contentType = event.currentTarget.dataset.type;
        this.navigateTo(contentType);
    }

    // Navigate to the appropriate form
    navigateTo(contentType) {
        const url = this.routeMap[contentType];
        if (url) {
            // eslint-disable-next-line @lwc/lwc/no-document-query
            window.location.href = url;
        }
    }
}