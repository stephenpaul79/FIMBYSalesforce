import { LightningElement, api, wire } from 'lwc';
import getUiMetadataBundle from '@salesforce/apex/FimbyProfileController.getUiMetadataBundle';

const FALLBACK_MESSAGES = {
    general: ['Hang tight...', 'Almost there...', 'Good things take a moment...'],
    home: ['Asking the neighbours...', 'Checking the bulletin board...', 'Rounding up the stories...'],
    library: ['Checking the toolshed...', 'Dusting off the shelves...', 'Counting the gadgets...'],
    search: ['Scouring the neighbourhood...', 'Peeking behind every fence...', 'Asking around...'],
    posting: ['Getting your post ready...', 'Spreading the word...', 'Alerting the neighbourhood...'],
    stories: ['Gathering the stories...', 'Flipping through the pages...', 'Warming up the campfire...'],
    messages: ['Fetching your messages...', 'Checking the mailbox...', 'The carrier pigeon is en route...'],
    profile: ['Loading your stuff...', 'Checking your collection...', 'Gathering your treasures...'],
    lending: ['Checking availability...', 'Consulting the lending desk...', 'Tracking down the goods...'],
    reserving: ['Reserving your share...', 'Saving you a spot at the table...', 'Locking it in...', 'Almost yours...'],
    responding: ['Sending your response...', 'Letting them know...', 'Connecting neighbours...', 'Passing the message along...'],
    commenting: ['Posting your comment...', 'Adding your voice...', 'Joining the conversation...'],
    neighbour: ['Getting to know your neighbour...', 'Pulling up their info...', 'Checking the neighbourhood directory...'],
    detail: ['Opening the post...', 'Pulling up the details...', 'One moment...'],
    archive: ['Digging through the archives...', 'Flipping through the logbook...', 'Checking the records...']
};

const ROTATE_INTERVAL_MS = 2500;

export default class FimbyLoadingMessage extends LightningElement {
    @api context = 'general';
    @api size = 'medium';

    _messages = null;
    _currentIndex = 0;
    _intervalId = null;
    _currentMessage = '';
    _reducedMotion = false;

    @wire(getUiMetadataBundle)
    wiredUiBundle({ data }) {
        if (data && data.loadingMessages) {
            const contextMessages = data.loadingMessages
                .filter(m => m.context === this.context)
                .map(m => m.message);
            if (contextMessages.length > 0) {
                this._messages = contextMessages;
                this._pickRandom();
            }
        }
    }

    connectedCallback() {
        this._reducedMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
        const fallback = FALLBACK_MESSAGES[this.context] || FALLBACK_MESSAGES.general;
        this._messages = fallback;
        this._pickRandom();

        if (!this._reducedMotion) {
            this._intervalId = setInterval(() => this._rotate(), ROTATE_INTERVAL_MS);
        }
    }

    disconnectedCallback() {
        if (this._intervalId) {
            clearInterval(this._intervalId);
            this._intervalId = null;
        }
    }

    get loadingText() {
        return this._currentMessage;
    }

    get spinnerAltText() {
        return this._currentMessage || 'Loading...';
    }

    _pickRandom() {
        if (!this._messages || this._messages.length === 0) return;
        this._currentIndex = Math.floor(Math.random() * this._messages.length);
        this._currentMessage = this._messages[this._currentIndex];
    }

    _rotate() {
        if (!this._messages || this._messages.length <= 1) return;
        let nextIndex;
        do {
            nextIndex = Math.floor(Math.random() * this._messages.length);
        } while (nextIndex === this._currentIndex && this._messages.length > 1);
        this._currentIndex = nextIndex;
        this._currentMessage = this._messages[this._currentIndex];
    }
}