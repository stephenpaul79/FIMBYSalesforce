import { LightningElement, track, wire } from 'lwc';
import { getContents } from 'experience/cmsDeliveryApi';
import currentSiteId from '@salesforce/site/Id';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getNeighbourhoodModerator from '@salesforce/apex/FimbyModeratorDashboardController.getNeighbourhoodModerator';
import getOrCreateModeratorConversation from '@salesforce/apex/FimbyModeratorDashboardController.getOrCreateModeratorConversation';

const FALLBACK_FAQ = [
    { id: 'fb-1', question: 'What is FIMBY?', answer: 'FIMBY (Family In My Backyard) is a neighbourhood platform that helps you connect with your neighbours through shared stories, asks &amp; offers, a lending library, and direct messaging.', sortOrder: '010' },
    { id: 'fb-2', question: 'How do I update my profile?', answer: 'Tap the menu icon in the top-right corner and select "Profile". From there you can edit your name, photo, pronouns, bio, and care preferences.', sortOrder: '020' },
    { id: 'fb-3', question: 'What are Asks &amp; Offers?', answer: 'Asks &amp; Offers is a bulletin board where neighbours can post things they need (asks) or things they want to share (offers). This includes goods, services, and events.', sortOrder: '030' },
    { id: 'fb-4', question: 'How does the Library work?', answer: 'The Library lets you share items you\'re willing to lend to neighbours — tools, books, games, and more. Browse what\'s available or add your own items.', sortOrder: '040' },
    { id: 'fb-5', question: 'Who can see my profile and posts?', answer: 'Your profile and posts are visible to other members in your neighbourhood. FIMBY is a private community — only registered neighbours can access the platform.', sortOrder: '050' },
    { id: 'fb-6', question: 'How do I change my notification settings?', answer: 'Go to Settings (via the menu) and scroll to the Notifications section. You can toggle push notifications, email summaries, and choose which types of updates you want to receive.', sortOrder: '060' }
];

export default class FimbyHelpSupportPage extends LightningElement {
    @track faqItems = [];
    @track isLoadingFaq = true;
    _cmsLoaded = false;
    @track _moderatorData = null;

    @wire(getContents, {
        channelOrSiteId: currentSiteId,
        contentTypeFQN: 'fimby_faq_item',
        page: 0,
        pageSize: 100,
        includeContentBody: true
    })
    handleFaqContent({ data, error }) {
        if (data && data.items && data.items.length > 0) {
            this.faqItems = this._mapCmsToFaq(data.items);
            this._cmsLoaded = true;
        } else if (error || (data && (!data.items || data.items.length === 0))) {
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
            .map(item => {
                const nodes = item.contentNodes || {};
                return {
                    id: item.managedContentId || item.contentKey,
                    question: nodes.question?.value || '',
                    answer: nodes.answer?.value || '',
                    sortOrder: nodes.sortOrder?.value || '999',
                    category: nodes.category?.value || '',
                    isRichText: true,
                    expanded: false,
                    chevronIcon: 'utility:chevrondown'
                };
            })
            .filter(item => item.question)
            .sort((a, b) => a.sortOrder.localeCompare(b.sortOrder));
    }

    get hasFaqItems() {
        return this.faqItems.length > 0;
    }

    get lightbulbIconUrl()   { return `${IMPACT_ICONS}/lightbulb.png`; }
    get walkthroughIconUrl() { return `${IMPACT_ICONS}/NeighborhoodActive.png`; }
    get fimbyLinkIconUrl()   { return `${IMPACT_ICONS}/HelpingHandsIcon.png`; }
    get svLinkIconUrl()      { return `${IMPACT_ICONS}/SV-Icon-Forest%20(2).png`; }
    get emailIconUrl()       { return `${IMPACT_ICONS}/email.png`; }
    get careIconUrl()        { return `${IMPACT_ICONS}/care.png`; }

    /* --- Navigation handlers --------------------------------------- */

    handleBack() { location.href = '/my-stuff'; }

    handleGoFimby() {
        window.open('https://www.fimby.com', '_blank', 'noopener,noreferrer');
    }

    handleGoStrathcona() {
        window.open('https://www.strathconavineyard.com', '_blank', 'noopener,noreferrer');
    }

    handleTabChange(event) {
        const routes = {
            home: '/',
            library: '/library-list',
            messages: '/messages',
            mine: '/my-stuff'
        };
        const tab = event.detail?.tab;
        if (routes[tab]) location.href = routes[tab];
    }

    /* --- Tour re-launch -------------------------------------------- */

    handleTakeTour() {
        // Onboarding lives on a dedicated page; flag-driven routing inside
        // fimbyOnboardingPage handles Phase 1 vs Phase 2 (replay viewers skip
        // straight to the walkthrough, returning members don't see the
        // intro-post modal again).
        window.location.href = '/onboarding';
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

    /* --- Neighbourhood Moderator --------------------------------- */

    get moderatorSectionIconUrl() { return `${IMPACT_ICONS}/moderatoractive.png`; }
    get chatIconUrl() { return `${IMPACT_ICONS}/chat.png`; }
    get hasModerator() { return this._moderatorData != null; }
    get moderatorName() { return this._moderatorData?.name || ''; }
    get moderatorPronouns() { return this._moderatorData?.pronouns || ''; }
    get moderatorPhotoUrl() {
        return this._moderatorData?.photoUrl || `${IMPACT_ICONS}/NoProfilePhoto.png`;
    }

    connectedCallback() {
        this._loadModerator();
    }

    async _loadModerator() {
        try {
            this._moderatorData = await getNeighbourhoodModerator();
        } catch (e) {
            // No moderator — section won't show
        }
    }

    async handleMessageModerator() {
        if (!this._moderatorData?.contactId) return;
        try {
            const conversationId = await getOrCreateModeratorConversation({
                targetContactId: this._moderatorData.contactId
            });
            window.location.href = `/conversation?id=${conversationId}`;
        } catch (e) {
            // Silently fail
        }
    }
}