/**
 * DEPRECATED — fimbyStoriesFeed
 *
 * This component has been replaced by cascading filters in fimbyHomeFeed.
 * Story sub-type filtering (Thank You, God Story, Prayer, Lament, Bio) is
 * now handled as Level 2 pills in the unified home feed.
 *
 * This stub auto-redirects to the home feed with ?filter=story so that
 * any existing links or bookmarks still work.
 */
import { LightningElement, api } from 'lwc';

export default class FimbyStoriesFeed extends LightningElement {
    @api pageSize = 15;
    @api selectedCategory = 'All';

    connectedCallback() {
        location.href = '/?filter=story';
    }
}