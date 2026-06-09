import { LightningElement, api, wire } from 'lwc';
import MEMES1 from '@salesforce/resourceUrl/Memes1';
import MEMES2 from '@salesforce/resourceUrl/Memes2';
import getCelebrationContext from '@salesforce/apex/FimbyProfileController.getCelebrationContext';
import getUiMetadataBundle from '@salesforce/apex/FimbyProfileController.getUiMetadataBundle';
import markFirstCelebration from '@salesforce/apex/FimbyProfileController.markFirstCelebration';
import { fireEmojiConfetti } from 'c/fimbyConfettiHelper';

const COUNT_FIELD_MAP = {
    ask: 'needPostings',
    offer: 'offerPostings',
    event: 'offerPostings',
    story: 'storiesPosted',
    library: 'libraryItemsPosted',
    response: 'responsesPosted',
    bulkbuy: 'completedBulkBuys'
};

const COUNT_FIRST_TIME_MAP = {
    ask: 'needPostings',
    offer: 'offerPostings',
    event: 'offerPostings'
};

const FIRST_CELEBRATION_MAP = {
    story: { contextKey: 'firstStoryCelebrated', fieldName: 'First_Story_Celebrated__c' },
    library: { contextKey: 'firstLibraryItemCelebrated', fieldName: 'First_Library_Item_Celebrated__c' },
    response: { contextKey: 'firstResponseCelebrated', fieldName: 'First_Response_Celebrated__c' },
    bulkbuy: { contextKey: 'firstBulkBuyCelebrated', fieldName: 'First_Bulk_Buy_Celebrated__c' },
    bulkbuy_reserve: {
        contextKey: 'firstBulkBuyReserveCelebrated',
        fieldName: 'First_Bulk_Buy_Reserve_Celebrated__c'
    }
};

const MEME_GIFS = [
    { resource: 'MEMES1', file: 'ohyeahdance.gif' },
    { resource: 'MEMES1', file: 'Oprah.gif' },
    { resource: 'MEMES1', file: 'TomHanks.gif' },
    { resource: 'MEMES1', file: 'YouDidIt.gif' },
    { resource: 'MEMES2', file: 'FingerHeart.gif' },
    { resource: 'MEMES2', file: 'NailedIt.gif' },
    { resource: 'MEMES2', file: 'Proud.gif' },
    { resource: 'MEMES2', file: 'SpongeBob.gif' },
    { resource: 'MEMES2', file: 'Superstar.gif' }
];

const FALLBACK_EMOJIS = ['🎉', '🥳', '✨', '💛'];

export default class FimbyCelebration extends LightningElement {
    @api actionType = '';
    @api confettiEnabled = null;
    @api memesEnabled = null;
    @api customMessage = '';
    @api preloadedGifUrl = null;

    _renderArmed = false;
    _celebrationFired = false;
    _celebrationContext = null;
    _seasonalTheme = null;
    _actionConfigs = null;
    _selectedGifUrl = null;
    _celebrationMessage = '';
    _isMilestone = false;
    _milestoneCount = 0;
    _isFirstTime = false;

    @wire(getCelebrationContext)
    wiredCelebrationContext({ data, error }) {
        if (data) {
            this._celebrationContext = data;
            this._tryFire();
        }
        if (error) {
            console.error('getCelebrationContext error', error);
        }
    }

    @wire(getUiMetadataBundle)
    wiredUiBundle({ data, error }) {
        if (data) {
            this._seasonalTheme = data.seasonalTheme || null;
            this._actionConfigs = this._buildConfigMap(data.celebrationActions || []);
            this._tryFire();
        }
        if (error) {
            console.error('getUiMetadataBundle error', error);
        }
    }

    get showMeme() {
        return this.effectiveMemesEnabled && !!this._selectedGifUrl;
    }

    get showMessage() {
        return !!this._celebrationMessage;
    }

    get effectiveConfettiEnabled() {
        if (this.confettiEnabled !== null) {
            return this.confettiEnabled;
        }
        return this._celebrationContext?.confettiEnabled ?? true;
    }

    get effectiveMemesEnabled() {
        if (this.memesEnabled !== null) {
            return this.memesEnabled;
        }
        return this._celebrationContext?.memesEnabled ?? true;
    }

    get gifUrl() {
        return this._selectedGifUrl;
    }

    get messageText() {
        return this._celebrationMessage;
    }

    get milestoneLabel() {
        if (!this._isMilestone) {
            return '';
        }
        const label = this.actionType || 'action';
        return `Your ${this._milestoneCount}${this._getOrdinalSuffix(this._milestoneCount)} ${label}!`;
    }

    renderedCallback() {
        if (this._renderArmed) {
            return;
        }
        this._renderArmed = true;
        this._tryFire();
    }

    _tryFire() {
        const hasExplicitProps = this.confettiEnabled !== null || this.memesEnabled !== null;
        if (this._celebrationFired || !this._actionConfigs || (!this._celebrationContext && !hasExplicitProps)) {
            return;
        }
        this._celebrationFired = true;

        this._checkMilestone();
        this._checkFirstTime();

        const config = this._resolveConfig();

        this._selectGif();
        this._selectMessage(config);

        if (this.effectiveConfettiEnabled) {
            this._fireConfetti(config);
        }

        if (this._isFirstTime) {
            const mapping = FIRST_CELEBRATION_MAP[this.actionType];
            if (mapping?.fieldName) {
                markFirstCelebration({ fieldName: mapping.fieldName }).catch((err) => {
                    console.error('markFirstCelebration error', err);
                });
            }
        }
    }

    _buildConfigMap(records) {
        const map = {};
        for (const rec of records) {
            const key = `${rec.actionKey}|${rec.occasion}`;
            map[key] = {
                emojis: rec.emojiList ? rec.emojiList.split(',').map(e => e.trim()).filter(Boolean) : [],
                messages: rec.messages ? rec.messages.split('\n').filter(m => m.trim()) : [],
                animationStyle: rec.animationStyle || 'Cannon',
                milestoneThresholds: rec.milestoneThresholds
                    ? rec.milestoneThresholds.split(',').map(n => parseInt(n.trim(), 10)).filter(n => !isNaN(n))
                    : []
            };
        }
        return map;
    }

    _resolveConfig() {
        const action = this.actionType || 'welcome';

        if (this._isFirstTime) {
            const firstConfig = this._actionConfigs[`${action}|First_Time`];
            if (firstConfig) return firstConfig;
        }

        if (this._isMilestone) {
            const milestoneConfig = this._actionConfigs[`${action}|Milestone`];
            if (milestoneConfig) return milestoneConfig;
        }

        return this._actionConfigs[`${action}|Normal`]
            || this._actionConfigs['welcome|Normal']
            || { emojis: FALLBACK_EMOJIS, messages: [], animationStyle: 'Cannon', milestoneThresholds: [] };
    }

    _selectGif() {
        if (!this.effectiveMemesEnabled) {
            return;
        }
        if (this.preloadedGifUrl) {
            this._selectedGifUrl = this.preloadedGifUrl;
            return;
        }
        const entry = MEME_GIFS[Math.floor(Math.random() * MEME_GIFS.length)];
        const baseUrl = entry.resource === 'MEMES1' ? MEMES1 : MEMES2;
        this._selectedGifUrl = `${baseUrl}/${entry.file}`;
    }

    _selectMessage(config) {
        if (this.customMessage) {
            this._celebrationMessage = this.customMessage;
            return;
        }

        const pool = config.messages || [];
        if (pool.length > 0) {
            let msg = pool[Math.floor(Math.random() * pool.length)];
            if (this._isMilestone && this._milestoneCount) {
                msg = msg.replace(/\{count\}/g, String(this._milestoneCount));
            }
            this._celebrationMessage = msg;
        }
    }

    _checkMilestone() {
        const field = COUNT_FIELD_MAP[this.actionType];
        if (!field || !this._celebrationContext) {
            return;
        }
        const count = this._celebrationContext[field];
        if (count == null) return;

        const milestoneConfig = this._actionConfigs[`${this.actionType}|Milestone`];
        if (milestoneConfig && milestoneConfig.milestoneThresholds.includes(count)) {
            this._isMilestone = true;
            this._milestoneCount = count;
        }
    }

    _checkFirstTime() {
        if (!this._celebrationContext) {
            return;
        }

        const countField = COUNT_FIRST_TIME_MAP[this.actionType];
        if (countField) {
            const count = this._celebrationContext[countField];
            if (count === 1) {
                this._isFirstTime = true;
            }
            return;
        }

        const mapping = FIRST_CELEBRATION_MAP[this.actionType];
        if (mapping && this._celebrationContext[mapping.contextKey] === false) {
            this._isFirstTime = true;
        }
    }

    _fireConfetti(config) {
        if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
            return;
        }

        let emojis = config.emojis;
        let animStyle = config.animationStyle;

        if (this._seasonalTheme?.emojiList) {
            const parsed = this._seasonalTheme.emojiList.split(',').map(e => e.trim()).filter(Boolean);
            if (parsed.length > 0) emojis = parsed;
        }
        if (this._seasonalTheme?.animationStyle) {
            animStyle = this._seasonalTheme.animationStyle;
        }

        if (emojis.length === 0) emojis = FALLBACK_EMOJIS;

        try {
            fireEmojiConfetti({
                emojis,
                style: animStyle || 'Cannon',
                intensity: (this._isMilestone || this._isFirstTime) ? 'bigMoment' : 'normal'
            });
        } catch (e) {
            console.error('Confetti error', e);
        }
    }

    _getOrdinalSuffix(n) {
        const mod10 = n % 10;
        const mod100 = n % 100;
        if (mod10 === 1 && mod100 !== 11) return 'st';
        if (mod10 === 2 && mod100 !== 12) return 'nd';
        if (mod10 === 3 && mod100 !== 13) return 'rd';
        return 'th';
    }
}