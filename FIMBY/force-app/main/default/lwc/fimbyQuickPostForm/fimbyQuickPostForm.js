import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { navigate } from 'c/fimbyNavigation';
import { registerTourAnchorProvider } from 'c/fimbyGuidedTourAnchorRegistry';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyQuickPostForm extends NavigationMixin(LightningElement) {
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

    _unregisterTourAnchors;
    _forceHideHandler;

    connectedCallback() {
        if (this.isModal) {
            this._unregisterTourAnchors = registerTourAnchorProvider(this);
            this._forceHideHandler = () => {
                if (this.isVisible) {
                    this.isVisible = false;
                }
            };
            window.addEventListener('fimbyquickpostforcehide', this._forceHideHandler);
        }

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

    disconnectedCallback() {
        if (this._forceHideHandler) {
            window.removeEventListener('fimbyquickpostforcehide', this._forceHideHandler);
        }
        if (this._unregisterTourAnchors) {
            this._unregisterTourAnchors();
        }
    }

    @api
    getTourAnchorRect(name) {
        if (!this.isModal || !this.isVisible || name !== 'quick-post-modal') {
            return null;
        }
        const el = this.template.querySelector('[data-tour="quick-post-modal"]');
        if (!el) {
            return null;
        }
        const rect = el.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0 ? rect : null;
    }

    // Public API methods for modal mode
    @api
    show() {
        if (document.activeElement) {
            document.activeElement.blur();
        }
        window.dispatchEvent(new CustomEvent('fimbyquickpostforcehide'));
        this.isVisible = true;
        if (this.isModal) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            requestAnimationFrame(() => {
                window.dispatchEvent(new CustomEvent('fimbyquickpostopened'));
            });
        }
    }

    @api
    hide(options = {}) {
        const wasVisible = this.isVisible;
        this.isVisible = false;
        if (!wasVisible) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('close', { bubbles: true, composed: true })
        );
        if (this.isModal) {
            window.dispatchEvent(new CustomEvent('fimbyquickpostforcehide'));
            window.dispatchEvent(
                new CustomEvent('fimbyquickpostclosed', {
                    detail: { selected: !!options.selected }
                })
            );
        }
    }

    // Event handlers
    handleTypeSelect(event) {
        const contentType = event.currentTarget.dataset.type;

        if (this.isModal) {
            this.navigateTo(contentType);
            this.hide({ selected: true });
            // Let navigation + modal teardown finish before the tour reacts.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            queueMicrotask(() => {
                window.dispatchEvent(
                    new CustomEvent('fimbyquickpostoptionselected', {
                        detail: { type: contentType }
                    })
                );
            });
            return;
        }

        this.navigateTo(contentType);
    }

    handleClose() {
        if (this.isModal) {
            this.hide();
        } else {
            // Navigate back to home in full-page mode
            navigate(this, '/');
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
            navigate(this, url);
        }
    }
}