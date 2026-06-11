import { LightningElement, track } from 'lwc';
import isGroupConversation from '@salesforce/apex/FimbyCommunicationController.isGroupConversation';

export default class FimbyConversationRouter extends LightningElement {
    @track conversationId = '';
    @track targetContactId = '';
    @track isGroup = false;
    @track isLoading = true;
    @track hasError = false;

    get showGroupView() {
        return !this.isLoading && !this.hasError && this.isGroup;
    }

    get showDirectView() {
        return !this.isLoading && !this.hasError && !this.isGroup
            && (!!this.conversationId || !!this.targetContactId);
    }

    async connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        this.conversationId = params.get('id') || '';
        this.targetContactId = params.get('contactId') || '';

        if (!this.conversationId && !this.targetContactId) {
            this.hasError = true;
            this.isLoading = false;
            return;
        }

        if (!this.conversationId) {
            this.isGroup = false;
            this.isLoading = false;
            return;
        }

        try {
            this.isGroup = await isGroupConversation({ conversationId: this.conversationId });
        } catch (e) {
            console.error('Error checking conversation type:', e);
            this.hasError = true;
        } finally {
            this.isLoading = false;
        }
    }
}