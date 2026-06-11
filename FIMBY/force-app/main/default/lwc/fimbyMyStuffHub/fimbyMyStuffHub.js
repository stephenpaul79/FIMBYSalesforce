import { LightningElement, track } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import getMineSummary from '@salesforce/apex/FimbyMyStuffController.getMineSummary';
import { getModeratorContext } from 'c/fimbyModeratorContext';

export default class FimbyMyStuffHub extends LightningElement {
    contactsIconUrl = `${IMPACT_ICONS}/people.png`;
    postsIconUrl = `${IMPACT_ICONS}/BulletinBoardActive.png`;
    sharedLifeIconUrl = `${IMPACT_ICONS}/GodStoryActive.png`;
    libraryIconUrl = `${IMPACT_ICONS}/ToolboxActive.png`;
    skillsIconUrl = `${IMPACT_ICONS}/lightbulb.png`;
    borrowingIconUrl = `${IMPACT_ICONS}/BorrowActive.png`;
    moderatorIconUrl = `${IMPACT_ICONS}/moderatoractive.png`;
    @track _isModerator = false;
    @track _moderatorTaskCount = 0;
    @track isLoading = true;
    @track postsCount = 0;
    @track postsActiveCount = 0;
    @track postsInactiveCount = 0;
    @track storiesCount = 0;
    @track libraryCount = 0;
    @track libraryActiveCount = 0;
    @track libraryAvailableCount = 0;
    @track borrowedCount = 0;
    @track skillsCount = 0;
    @track contactsCount = 0;

    connectedCallback() {
        this._loadSummary();
        this._loadModeratorContext();
    }

    _loadModeratorContext() {
        getModeratorContext()
            .then(ctx => {
                this._isModerator = ctx.isModerator;
                this._moderatorTaskCount = ctx.taskCount;
            })
            .catch(() => { /* non-moderators see nothing */ });
    }

    async _loadSummary() {
        this.isLoading = true;
        try {
            const summary = await getMineSummary();
            this.postsCount = summary.postsCount || 0;
            this.postsActiveCount = summary.postsActiveCount || 0;
            this.postsInactiveCount = summary.postsInactiveCount || 0;
            this.storiesCount = summary.storiesCount || 0;
            this.libraryCount = summary.libraryCount || 0;
            this.libraryActiveCount = summary.libraryActiveCount || 0;
            this.libraryAvailableCount = summary.libraryAvailableCount || 0;
            this.borrowedCount = summary.borrowedCount || 0;
            this.skillsCount = summary.skillsCount || 0;
            this.contactsCount = summary.contactsCount || 0;
        } catch (error) {
            console.error('Error loading My Stuff summary:', error);
        } finally {
            this.isLoading = false;
        }
    }

    handleRowClick(event) {
        const path = event.currentTarget.dataset.path;
        if (path) {
            location.href = path;
        }
    }
}