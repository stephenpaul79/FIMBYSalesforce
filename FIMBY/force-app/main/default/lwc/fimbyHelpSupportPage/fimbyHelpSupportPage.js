import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { navigate, navigateBack, navigateToRoute } from 'c/fimbyNavigation';
import { launchGuidedTourReplay } from 'c/fimbyGuidedTourLauncher';
import { avatarImageUrl } from 'c/fimbyImageUrl';
import getFaqItems from '@salesforce/apex/FimbyFaqController.getFaqItems';
import getNeighbourhoodModerator from '@salesforce/apex/FimbyModeratorDashboardController.getNeighbourhoodModerator';
import getOrCreateModeratorConversation from '@salesforce/apex/FimbyModeratorDashboardController.getOrCreateModeratorConversation';

// Curated offline subset (plain text, no markup) shown only when the CMS is
// unreachable. The full FAQ lives in the fimby_faq_item CMS content type.
// Ordered so categories stay contiguous for the grouped accordion.
const FALLBACK_FAQ = [
    { id: 'fb-1', question: 'How do I find my way around?', answer: 'The bar along the bottom has four tabs: Home, Library, Messages, and My Stuff. The + button in the middle creates a new post. The menu in the top-right corner holds your Profile, Settings, and Help, and the bell shows your notifications.', sortOrder: '010', category: 'Getting Started' },
    { id: 'fb-2', question: 'How do I update my profile?', answer: 'Open the top-right menu and choose Profile. Each section has a small pencil to edit it - tap one to change your name, photo, pronouns, contact details, About You answers, or care preferences, then Save.', sortOrder: '030', category: 'Getting Started' },
    { id: 'fb-3', question: 'How do I borrow something from the Library?', answer: 'Open the Library tab, open an item, and tap Borrow then Submit Request. The owner approves and shares pickup details; tap I Have the Item once you collect it, and Return Item when you are done. Borrowing needs a neighbour to vouch for you first.', sortOrder: '210', category: 'Lending Library' },
    { id: 'fb-4', question: 'What is vouching?', answer: 'A vouch is one neighbour saying they know you and you belong here. It opens the lending library for you. Tap Request a vouch (on your profile or the Library) and choose a neighbour or community group. You must be acting as yourself to give or request a vouch.', sortOrder: '400', category: 'Trust & Safety' },
    { id: 'fb-5', question: 'How do I message a neighbour?', answer: 'Open the Messages tab and tap New, or tap Message on a neighbour profile. You can message neighbours you have shared contact info with, plus community groups in your neighbourhood.', sortOrder: '300', category: 'Messaging' },
    { id: 'fb-6', question: 'How do I report content or block someone?', answer: 'Open the three-dot menu on a post or message and choose Report - reports are private and reviewed within 24 hours. To block a neighbour, use Block on their profile menu, or Settings then Blocked Contacts. Blocking is mutual.', sortOrder: '410', category: 'Trust & Safety' },
    { id: 'fb-7', question: 'How do I share my contact info?', answer: 'Your email, phone, and address stay private until you choose to share them. In a response thread tap Share Contact Info and tick exactly what to share. You can also turn on Auto-Share Contact Info when you create an ask or offer.', sortOrder: '600', category: 'Privacy & Account' },
    { id: 'fb-8', question: 'How do I change my notification settings?', answer: 'Open Settings from the top-right menu and go to Notifications and Email. You can turn Push Notifications and Email Alerts on or off, set Quiet Hours, choose which categories reach you, and pick your Neighbourhood Digest. Account and safety messages always come through.', sortOrder: '610', category: 'Privacy & Account' }
];

export default class FimbyHelpSupportPage extends NavigationMixin(LightningElement) {
    @track faqItems = [];
    @track isLoadingFaq = true;
    _cmsLoaded = false;
    @track _moderatorData = null;

    // FAQ content comes from the fimby_faq_item CMS type via Apex
    // (FimbyFaqController), which queries getManagedContentsForSite in site
    // context and rewrites in-app links to site-relative paths. The Apex
    // returns [] on any failure, in which case we render the offline fallback.
    @wire(getFaqItems)
    handleFaqContent({ data, error }) {
        if (data && data.length > 0) {
            this.faqItems = this._mapCmsToFaq(data);
            this._cmsLoaded = true;
        } else if (error || (data && data.length === 0)) {
            if (!this._cmsLoaded) {
                this.faqItems = FALLBACK_FAQ.map(item => ({
                    ...item,
                    isRichText: false,
                    expanded: false,
                    chevronIcon: 'utility:chevrondown'
                }));
            }
        }
        this.isLoadingFaq = false;
    }

    _mapCmsToFaq(items) {
        return items
            .map((item, index) => ({
                id: `faq-${item.sortOrder || '999'}-${index}`,
                question: item.question || '',
                answer: item.answer || '',
                sortOrder: item.sortOrder || '999',
                category: item.category || '',
                isRichText: true,
                expanded: false,
                chevronIcon: 'utility:chevrondown'
            }))
            .filter(item => item.question)
            .sort((a, b) => a.sortOrder.localeCompare(b.sortOrder));
    }

    get hasFaqItems() {
        return this.faqItems.length > 0;
    }

    // Buckets the (already sortOrder-sorted) faqItems by category. Group order
    // is derived from first appearance, so the sortOrder ranges in the CMS
    // decide category order with no hardcoded list. Items with a blank category
    // fall into a trailing ungrouped bucket.
    get faqGroups() {
        const order = [];
        const byKey = new Map();
        this.faqItems.forEach((item) => {
            const category = (item.category || '').trim();
            const key = category || '__ungrouped';
            let group = byKey.get(key);
            if (!group) {
                group = { key, category, hasCategory: category.length > 0, items: [] };
                byKey.set(key, group);
                order.push(group);
            }
            group.items.push(item);
        });
        return order.sort((a, b) => {
            if (a.hasCategory === b.hasCategory) return 0;
            return a.hasCategory ? -1 : 1;
        });
    }

    get lightbulbIconUrl()   { return `${IMPACT_ICONS}/lightbulb.png`; }
    get walkthroughIconUrl() { return `${IMPACT_ICONS}/NeighborhoodActive.png`; }
    get fimbyLinkIconUrl()   { return `${IMPACT_ICONS}/FwithGrass.png`; }
    get svLinkIconUrl()      { return `${IMPACT_ICONS}/SV-Icon-Forest%20(2).png`; }
    get emailIconUrl()       { return `${IMPACT_ICONS}/email.png`; }
    get careIconUrl()        { return `${IMPACT_ICONS}/care.png`; }

    /* --- Navigation handlers --------------------------------------- */

    handleBack() { navigateBack(this, '/my-stuff'); }

    handleNavLink(event) {
        event.preventDefault();
        navigate(this, event.currentTarget.getAttribute('href'));
    }

    handleGoFimby() {
        window.open('https://www.fimby.com', '_blank', 'noopener,noreferrer');
    }

    handleGoStrathcona() {
        window.open('https://www.strathconavineyard.com', '_blank', 'noopener,noreferrer');
    }

    handleTabChange(event) {
        const tab = event.detail?.tab;
        if (tab) navigateToRoute(this, tab);
    }

    /* --- Tour re-launch -------------------------------------------- */

    handleTakeTour() {
        launchGuidedTourReplay(this);
    }

    /* --- FAQ accordion --------------------------------------------- */

    handleToggleFaq(event) {
        const faqId = event.currentTarget.dataset.id;
        this.faqItems = this.faqItems.map(item => ({
            ...item,
            expanded: item.id === faqId ? !item.expanded : item.expanded,
            chevronIcon: (item.id === faqId ? !item.expanded : item.expanded)
                ? 'utility:chevronup'
                : 'utility:chevrondown'
        }));
    }

    // FAQ answers are CMS rich text that can contain in-app deep links
    // (e.g. <a href="/library-list">). The anchors render inside
    // lightning-formatted-rich-text's shadow root, so we delegate from the
    // answer container and read the click's composedPath to find the anchor,
    // then soft-navigate via the shared service. External/scheme links
    // (http, mailto, tel) fall through to default browser handling.
    handleAnswerClick(event) {
        const path = (event.composedPath && event.composedPath()) || [];
        const anchor = path.find(
            (el) => el && el.tagName === 'A' && el.getAttribute
        );
        if (!anchor) return;
        const href = anchor.getAttribute('href');
        if (!href || href === '#') return;
        if (/^(https?:|mailto:|tel:|sms:)/i.test(href)) return;
        event.preventDefault();
        navigate(this, href);
    }

    /* --- Neighbourhood Moderator --------------------------------- */

    get moderatorSectionIconUrl() { return `${IMPACT_ICONS}/moderatoractive.png`; }
    get chatIconUrl() { return `${IMPACT_ICONS}/chat.png`; }
    get hasModerator() { return this._moderatorData != null; }
    get moderatorName() { return this._moderatorData?.name || ''; }
    get moderatorPronouns() { return this._moderatorData?.pronouns || ''; }
    get moderatorPhotoUrl() {
        const url = avatarImageUrl(this._moderatorData?.photoUrl || '');
        return url || `${IMPACT_ICONS}/NoProfilePhoto.png`;
    }

    connectedCallback() {
        this._loadModerator();
    }

    async _loadModerator() {
        try {
            this._moderatorData = await getNeighbourhoodModerator();
        } catch {
            // No moderator — section won't show
        }
    }

    async handleMessageModerator() {
        if (!this._moderatorData?.contactId) return;
        try {
            const conversationId = await getOrCreateModeratorConversation({
                targetContactId: this._moderatorData.contactId
            });
            navigate(this, `/conversation?id=${conversationId}`);
        } catch {
            // Silently fail
        }
    }
}