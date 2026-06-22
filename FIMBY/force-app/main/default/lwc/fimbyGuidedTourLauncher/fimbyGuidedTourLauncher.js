/**
 * Cross-page launcher for the live guided tour. Dispatches a window event
 * consumed by fimbyUniversalHeader's mounted c-fimby-guided-tour.
 */

import { navigate } from 'c/fimbyNavigation';
import { waitForTourAnchorRect } from 'c/fimbyGuidedTourAnchorRegistry';
import basePath from '@salesforce/community/basePath';

export const GUIDED_TOUR_REQUEST_EVENT = 'fimbyguidedtourrequest';
export const TOUR_RESET_FEED_SCROLL_EVENT = 'fimbytourresetfeedscroll';

export function isHomePath() {
    try {
        const normalized = (window.location.pathname || '').replace(basePath, '') || '/';
        return normalized === '/' || normalized === '/home';
    } catch {
        return true;
    }
}

export function resetHomeFeedScroll() {
    window.dispatchEvent(new CustomEvent(TOUR_RESET_FEED_SCROLL_EVENT));
}

export async function ensureHomeFeedReadyForTour() {
    resetHomeFeedScroll();
    await new Promise((resolve) => {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => requestAnimationFrame(resolve));
    });
    await waitForTourAnchorRect('feed-filter-bar', { timeoutMs: 8000 });
}

/**
 * @param {{ replay?: boolean }} options
 */
export function requestGuidedTour(options = {}) {
    window.dispatchEvent(
        new CustomEvent(GUIDED_TOUR_REQUEST_EVENT, {
            detail: {
                replay: !!options.replay
            },
            bubbles: true,
            composed: true
        })
    );
}

/**
 * Navigate to Home when needed, wait for feed chrome, then start replay tour.
 * @param {object} navigationComponent LWC with NavigationMixin
 */
export async function launchGuidedTourReplay(navigationComponent) {
    if (!isHomePath()) {
        navigate(navigationComponent, '/');
        await waitForTourAnchorRect('feed-filter-bar', { timeoutMs: 8000 });
    }
    await ensureHomeFeedReadyForTour();
    requestGuidedTour({ replay: true });
}
