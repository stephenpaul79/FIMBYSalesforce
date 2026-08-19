import { LightningElement, api } from 'lwc';

/**
 * Branded confirmation dialog, replacing window.confirm. A native dialog shows
 * "our.fimby.com says" and cannot carry FIMBY's voice or theming, which is a jarring
 * hand-off for a neighbour in the middle of a considered decision like withdrawing
 * consent.
 *
 * Blank-line breaks in `message` become separate paragraphs, so the same copy reads
 * well here as it did in the native dialog.
 *
 * Usage:
 *   <c-fimby-confirm-modal
 *       is-open={showConfirm}
 *       title="Stop sharing your contact info?"
 *       message={confirmMessage}
 *       confirm-label="Stop sharing"
 *       variant="danger"
 *       is-processing={isRevoking}
 *       onconfirm={handleConfirmed}
 *       oncancel={handleCancelled}>
 *   </c-fimby-confirm-modal>
 */
export default class FimbyConfirmModal extends LightningElement {
    @api isOpen = false;
    @api title = 'Are you sure?';
    @api message = '';
    @api confirmLabel = 'Confirm';
    @api cancelLabel = 'Cancel';
    /** 'danger' for destructive or irreversible actions, 'primary' for everything else. */
    @api variant = 'danger';
    @api isProcessing = false;
    @api processingLabel = 'Working...';

    _wasOpen = false;
    _previouslyFocused = null;

    get paragraphs() {
        return String(this.message || '')
            .split(/\n\s*\n/)
            .map((text) => text.trim())
            .filter((text) => text.length > 0)
            .map((text, index) => ({ key: `para-${index}`, text }));
    }

    get confirmButtonClass() {
        return this.variant === 'primary' ? 'nav-btn nav-next' : 'nav-btn nav-danger';
    }

    renderedCallback() {
        if (this.isOpen && !this._wasOpen) {
            this._wasOpen = true;
            // Cancel takes focus rather than the confirm button: a stray Enter on a
            // destructive dialog should back out, not go through with it.
            this._previouslyFocused = document.activeElement;
            this.template.querySelector('.nav-back')?.focus();
        } else if (!this.isOpen && this._wasOpen) {
            this._wasOpen = false;
            this._restoreFocus();
        }
    }

    handleConfirm() {
        if (this.isProcessing) return;
        this.dispatchEvent(new CustomEvent('confirm'));
    }

    handleCancel() {
        if (this.isProcessing) return;
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleBackdrop(event) {
        if (event.target.classList.contains('modal-backdrop')) {
            this.handleCancel();
        }
    }

    handleKeydown(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.handleCancel();
            return;
        }
        if (event.key === 'Tab') {
            this._trapFocus(event);
        }
    }

    _trapFocus(event) {
        const focusable = [...this.template.querySelectorAll('button')].filter((el) => !el.disabled);
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
