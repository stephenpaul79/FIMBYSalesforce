import { LightningElement, api, wire } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';
import { createShellScrimHandle } from 'c/fimbyModalShell';
import { fireErrorToast } from 'c/fimbyToastHelper';
import getActingAsContact from '@salesforce/apex/FimbyContactController.getActingAsContact';
import getAvailableIdentities from '@salesforce/apex/FimbySupportRelationshipController.getAvailableIdentities';
import submitSupportRequest from '@salesforce/apex/FimbyFeedbackController.submitSupportRequest';

const SUBJECT_MAX = 80;
const MESSAGE_MAX = 2000;

export default class FimbySupportRequestModal extends LightningElement {
    _shellScrim = createShellScrimHandle();
    _isOpen = false;
    _wasOpen = false;
    _previouslyFocused = null;

    @api kind = 'help';

    subject = '';
    message = '';
    validationMessage = '';
    isSubmitting = false;
    isSent = false;
    routedTo = '';
    hasMultipleIdentities = false;
    actingAsContact = null;

    @api
    get isOpen() {
        return this._isOpen;
    }
    set isOpen(value) {
        const opening = value && !this._isOpen;
        this._isOpen = value;
        if (opening) {
            this._reset();
        }
    }

    @wire(getActingAsContact)
    wiredActingAs({ data }) {
        if (data) {
            this.actingAsContact = data;
        }
    }

    @wire(getAvailableIdentities)
    wiredIdentities({ data }) {
        this.hasMultipleIdentities = Array.isArray(data) && data.length > 0;
    }

    get posterIconUrl() {
        return `${IMPACT_ICONS}/ProfileActive.png`;
    }

    get isSafety() {
        return this.kind === 'safety';
    }

    get modalTitle() {
        return this.isSafety ? 'Message the safety team' : 'Contact support';
    }

    get intro() {
        return this.isSafety
            ? 'This goes to the FIMBY team, not your neighbourhood moderator. We reply using the email on your account.'
            : 'This goes to your neighbourhood moderator. If there isn\u2019t one yet, it goes to the FIMBY team.';
    }

    get submitLabel() {
        return this.isSubmitting ? 'Sending\u2026' : 'Send';
    }

    get postingAsDisplayName() {
        return this.actingAsContact?.postingAsDisplayName || this.actingAsContact?.contactName || '';
    }

    get showIdentityBanner() {
        return this.hasMultipleIdentities && !!this.postingAsDisplayName;
    }

    get subjectCount() {
        return `${this.subject.length}/${SUBJECT_MAX}`;
    }

    get messageCount() {
        return `${this.message.length}/${MESSAGE_MAX}`;
    }

    get subjectCountClass() {
        return this._countClass(this.subject.length, SUBJECT_MAX);
    }

    get messageCountClass() {
        return this._countClass(this.message.length, MESSAGE_MAX);
    }

    get successMessage() {
        if (this.isSafety) {
            return 'Sent. The FIMBY team has this, and they\u2019ll follow up using the email on your account.';
        }
        if (this.routedTo === 'admins') {
            return 'Sent. Your neighbourhood doesn\u2019t have a moderator right now, so this went to the FIMBY team.';
        }
        return 'Sent. Your neighbourhood moderator has this.';
    }

    get showForm() {
        return !this.isSent;
    }

    renderedCallback() {
        this._shellScrim.sync(this._isOpen, () => this.handleClose(), this.template.host);
        if (this._isOpen && !this._wasOpen) {
            this._wasOpen = true;
            this._previouslyFocused = document.activeElement;
            this.template.querySelector('.form-input')?.focus();
        } else if (!this._isOpen && this._wasOpen) {
            this._wasOpen = false;
            this._restoreFocus();
        }
    }

    disconnectedCallback() {
        this._shellScrim.clear();
    }

    handleSubjectChange(event) {
        this.subject = event.target.value;
        this.validationMessage = '';
    }

    handleMessageChange(event) {
        this.message = event.target.value;
        this.validationMessage = '';
    }

    handleSubjectKeydown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.handleSubmit();
        }
    }

    handleBackdrop(event) {
        if (event.target.classList.contains('modal-backdrop')) {
            this.handleClose();
        }
    }

    handleContainerClick(event) {
        event.stopPropagation();
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.handleClose();
            return;
        }
        if (event.key === 'Tab') {
            this._trapFocus(event);
        }
    }

    async handleSubmit() {
        if (this.isSubmitting || this.isSent) {
            return;
        }
        const subject = this.subject.trim();
        const message = this.message.trim();
        if (!subject) {
            this.validationMessage = 'Add a subject so we know what this is about.';
            return;
        }
        if (!message) {
            this.validationMessage = 'Write a short message so we know how to help.';
            return;
        }
        this.validationMessage = '';
        this.isSubmitting = true;
        try {
            const result = await submitSupportRequest({ kind: this.kind, subject, message });
            this.routedTo = result?.routedTo || '';
            this.isSent = true;
        } catch (error) {
            fireErrorToast(error);
        } finally {
            this.isSubmitting = false;
        }
    }

    handleClose() {
        if (this.isSubmitting) {
            return;
        }
        this.dispatchEvent(new CustomEvent('close'));
    }

    _reset() {
        this.subject = '';
        this.message = '';
        this.validationMessage = '';
        this.isSubmitting = false;
        this.isSent = false;
        this.routedTo = '';
    }

    _countClass(length, max) {
        if (length >= max) return 'character-count at-limit';
        if (length >= Math.floor(max * 0.9)) return 'character-count near-limit';
        return 'character-count';
    }

    _trapFocus(event) {
        const focusable = [...this.template.querySelectorAll('button, input, textarea')]
            .filter((el) => !el.disabled);
        if (focusable.length === 0) return;
        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        const active = this.template.activeElement;
        if (event.shiftKey && active === first) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && active === last) {
            event.preventDefault();
            first.focus();
        }
    }

    _restoreFocus() {
        const target = this._previouslyFocused;
        this._previouslyFocused = null;
        if (target && typeof target.focus === 'function' && document.contains(target)) {
            target.focus();
        }
    }
}
