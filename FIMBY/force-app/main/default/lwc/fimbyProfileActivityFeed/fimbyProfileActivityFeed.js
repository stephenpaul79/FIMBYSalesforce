import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { navigate } from 'c/fimbyNavigation';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getProfileActivity from '@salesforce/apex/FimbyProfileActivityController.getProfileActivity';
import { completeImageUrl } from 'c/fimbyImageUrl';
import { getCategoryIconUrl, getCategoryStyle } from 'c/fimbyLibraryCategoryConfig';

const SCROLL_BATCH_SIZE = 15;

const BADGE_BG_COLORS = {
    'God Story': 'rgba(163, 128, 69, 0.9)',
    'Thank You': 'rgba(176, 114, 72, 0.9)',
    'Lament': 'rgba(94, 123, 146, 0.9)',
    'Prayer': 'rgba(126, 116, 149, 0.9)',
    'Bio': 'rgba(107, 125, 84, 0.9)',
    'Neighbourhood Moment': 'rgba(175, 130, 125, 0.9)',
    'Need': 'rgba(91, 135, 96, 0.9)',
    'Offer': 'rgba(91, 135, 96, 0.9)',
    'Event': 'rgba(68, 142, 158, 0.9)',
    'Community_Event': 'rgba(113, 90, 158, 0.9)',
    'Bulk Buy': 'rgba(168, 132, 78, 0.90)',
    'library': 'rgba(141, 123, 106, 0.9)'
};

const STORY_BADGE_ICONS = {
    'Thank You': 'ThankYouActive.png',
    'God Story': 'GodStoryActive.png',
    'Prayer': 'PrayActive.png',
    'Lament': 'LamentActive.png',
    'Bio': 'BioActive.png',
    'Neighbourhood Moment': 'tulips.png'
};

export default class FimbyProfileActivityFeed extends NavigationMixin(LightningElement) {
    _profileContactId;

    @api
    get profileContactId() {
        return this._profileContactId;
    }
    set profileContactId(value) {
        if (value !== this._profileContactId) {
            this._profileContactId = value;
            if (value) {
                this.loadInitialData();
            }
        }
    }

    @track activityItems = [];
    @track isLoading = false;
    @track hasMoreContent = true;
    offset = 0;
    loadedRecordIds = new Set();

    get showSection() {
        if (!this.profileContactId || this.isLoading) {
            return false;
        }
        return this.activityItems.length > 0;
    }

    get showEmptyState() {
        return false;
    }

    async loadInitialData() {
        this.isLoading = true;
        this.offset = 0;
        this.activityItems = [];
        this.hasMoreContent = true;
        this.loadedRecordIds = new Set();

        const scrollContainer = this.template.querySelector('c-fimby-infinite-scroll');
        if (scrollContainer?.reset) {
            scrollContainer.reset();
        }

        try {
            await this.loadNextBatch();
        } catch (error) {
            console.error('Error loading profile activity:', error);
        } finally {
            this.isLoading = false;
            this.updateScrollContainer();
        }
    }

    async loadNextBatch() {
        const result = await getProfileActivity({
            profileContactId: this.profileContactId,
            offset: this.offset,
            pageSize: SCROLL_BATCH_SIZE
        });

        if (result?.items?.length) {
            const newItems = result.items.filter((item) => {
                if (this.loadedRecordIds.has(item.recordId)) {
                    return false;
                }
                return true;
            });
            newItems.forEach((item) => this.loadedRecordIds.add(item.recordId));
            this.activityItems = [...this.activityItems, ...this.processItems(newItems)];
            this.offset += result.items.length;
            this.hasMoreContent = result.hasMore;
        } else {
            this.hasMoreContent = false;
        }
    }

    processItems(items) {
        return items.map((item) => {
            const isStory = item.feedType === 'story';
            const isAskOffer = item.feedType === 'askOffer';
            const isEvent = isAskOffer && item.typeValue === 'Event';
            const isBulkBuy = isAskOffer && item.recordTypeName === 'Bulk Buy';
            const isLibrary = item.feedType === 'library';

            let badgeLabel = '';
            let badgeIconUrl = '';
            let badgeStyle = '';
            let cardAccentColor = '';

            if (isStory) {
                badgeLabel = item.itemType === 'Neighbourhood Moment' ? 'Neighbourhood' : (item.itemType || 'Shared Life');
                const iconFile = STORY_BADGE_ICONS[item.itemType] || 'StoriesActive.png';
                badgeIconUrl = `${IMPACT_ICONS}/${iconFile}`;
                const bg = BADGE_BG_COLORS[item.itemType] || BADGE_BG_COLORS.Bio;
                badgeStyle = `background-color: ${bg}; color: #ffffff;`;
                cardAccentColor = bg;
            } else if (isBulkBuy) {
                badgeLabel = 'BULK BUY';
                badgeIconUrl = `${IMPACT_ICONS}/bulkbuy.png`;
                badgeStyle = `background-color: ${BADGE_BG_COLORS['Bulk Buy']}; color: #ffffff;`;
                cardAccentColor = BADGE_BG_COLORS['Bulk Buy'];
            } else if (isEvent) {
                if (item.eventType === 'Community_Event') {
                    badgeLabel = 'COMMUNITY EVENT';
                    badgeIconUrl = `${IMPACT_ICONS}/cityscape.png`;
                    badgeStyle = `background-color: ${BADGE_BG_COLORS.Community_Event}; color: #ffffff;`;
                    cardAccentColor = BADGE_BG_COLORS.Community_Event;
                } else {
                    badgeLabel = item.eventType === 'Gathering' ? 'GATHERING' : 'EVENT';
                    badgeIconUrl = `${IMPACT_ICONS}/${item.eventType === 'Gathering' ? 'dining-table' : 'people'}.png`;
                    badgeStyle = `background-color: ${BADGE_BG_COLORS.Event}; color: #ffffff;`;
                    cardAccentColor = BADGE_BG_COLORS.Event;
                }
            } else if (isAskOffer) {
                badgeLabel = item.itemType === 'Need' ? 'Ask' : (item.itemType || 'Ask & Offer');
                badgeIconUrl = `${IMPACT_ICONS}/${item.itemType === 'Need' ? 'needsm' : 'giftsm'}.png`;
                const bg = BADGE_BG_COLORS[item.itemType] || BADGE_BG_COLORS.Need;
                badgeStyle = `background-color: ${bg}; color: #ffffff;`;
                cardAccentColor = bg;
            } else if (isLibrary) {
                badgeLabel = item.category || 'Library';
                badgeIconUrl = getCategoryIconUrl(item.category);
                badgeStyle = getCategoryStyle(item.category);
                cardAccentColor = BADGE_BG_COLORS.library;
            }

            return {
                ...item,
                badgeLabel,
                badgeIconUrl,
                badgeStyle,
                cardAccentColor,
                displayTimestamp: this.formatTimestamp(item.createdDate),
                imageUrl: completeImageUrl(item.imageUrl)
            };
        });
    }

    formatTimestamp(timestamp) {
        if (!timestamp) {
            return '';
        }
        const time = new Date(timestamp);
        return time.toLocaleDateString('en-AU', { month: 'short', day: 'numeric', year: 'numeric' });
    }

    handleLoadMore() {
        if (!this.hasMoreContent || this.isLoading) {
            return;
        }
        this.loadMoreContent();
    }

    async loadMoreContent() {
        this.isLoading = true;
        try {
            await this.loadNextBatch();
        } catch (error) {
            console.error('Error loading more profile activity:', error);
        } finally {
            this.isLoading = false;
            this.updateScrollContainer();
        }
    }

    updateScrollContainer() {
        const scrollContainer = this.template.querySelector('c-fimby-infinite-scroll');
        if (scrollContainer) {
            scrollContainer.finishLoading(this.hasMoreContent);
        }
    }

    handleCardClick(event) {
        const recordId = event.currentTarget.dataset.recordId;
        const item = this.activityItems.find((row) => row.recordId === recordId);
        if (item) {
            this.navigateToDetailPage(item);
        }
    }

    navigateToDetailPage(item) {
        const detailPages = {
            story: '/sharedlife',
            askOffer: '/asks-offers',
            library: '/library-item'
        };
        const page = detailPages[item.feedType];
        if (page) {
            navigate(this, `${page}/${item.recordId}`);
        }
    }
}
