/**
 * DEPRECATED — fimbyAskOfferFeed
 *
 * This component has been replaced by cascading filters in fimbyHomeFeed.
 * Ask & Offer sub-type filtering (Needs, Offers, Services, Events) is
 * now handled as Level 2 pills in the unified home feed.
 *
 * This stub auto-redirects to the home feed with ?filter=askOffer so that
 * any existing links or bookmarks still work.
 */
import { LightningElement, api } from 'lwc';

export default class FimbyAskOfferFeed extends LightningElement {
    @api feedType = 'all';
    @api showFilters = false;
    @api pageSize = 10;

    connectedCallback() {
        location.href = '/?filter=askOffer';
    }
}