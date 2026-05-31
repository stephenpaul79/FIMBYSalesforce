import { LightningElement, api, track } from 'lwc';

const SWIPE_THRESHOLD = 50;

export default class FimbyLightbox extends LightningElement {
    @api images = [];
    @api startIndex = 0;

    @track currentIndex = 0;
    @track isVisible = false;

    _touchStartX = 0;
    _touchStartY = 0;
    _keyHandler = null;

    /* ----------------------------------------------------------
     * Public API
     * ---------------------------------------------------------- */
    @api
    open(index) {
        this.currentIndex = (typeof index === 'number') ? index : (this.startIndex || 0);
        this.isVisible = true;
        this._bindKeyboard();
        this._trapFocus();
    }

    @api
    close() {
        this.isVisible = false;
        this._unbindKeyboard();
        this.dispatchEvent(new CustomEvent('close'));
    }

    /* ----------------------------------------------------------
     * Getters
     * ---------------------------------------------------------- */
    get validImages() {
        if (!this.images || !Array.isArray(this.images)) return [];
        return this.images.filter(img => img && img.url);
    }

    get currentImage() {
        return this.validImages[this.currentIndex] || null;
    }

    get counterText() {
        return `${this.currentIndex + 1} / ${this.validImages.length}`;
    }

    get showCounter() {
        return this.validImages.length > 1;
    }

    get showPrev() {
        return this.currentIndex > 0;
    }

    get showNext() {
        return this.currentIndex < this.validImages.length - 1;
    }

    get backdropClass() {
        return this.isVisible ? 'lightbox-backdrop visible' : 'lightbox-backdrop';
    }

    /* ----------------------------------------------------------
     * Navigation
     * ---------------------------------------------------------- */
    handlePrev(event) {
        if (event) event.stopPropagation();
        if (this.currentIndex > 0) {
            this.currentIndex--;
        }
    }

    handleNext(event) {
        if (event) event.stopPropagation();
        if (this.currentIndex < this.validImages.length - 1) {
            this.currentIndex++;
        }
    }

    handleClose(event) {
        if (event) event.stopPropagation();
        this.close();
    }

    handleBackdropClick(event) {
        if (event.target.classList.contains('lightbox-backdrop') ||
            event.target.classList.contains('lightbox-content-area')) {
            this.close();
        }
    }

    handleImageClick(event) {
        event.stopPropagation();
    }

    /* ----------------------------------------------------------
     * Touch / swipe support
     * ---------------------------------------------------------- */
    handleTouchStart(event) {
        if (event.touches.length !== 1) return;
        this._touchStartX = event.touches[0].clientX;
        this._touchStartY = event.touches[0].clientY;
    }

    handleTouchEnd(event) {
        if (event.changedTouches.length !== 1) return;
        const deltaX = event.changedTouches[0].clientX - this._touchStartX;
        const deltaY = event.changedTouches[0].clientY - this._touchStartY;

        if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > SWIPE_THRESHOLD) {
            if (deltaX < 0) {
                this.handleNext();
            } else {
                this.handlePrev();
            }
        }
    }

    /* ----------------------------------------------------------
     * Keyboard
     * ---------------------------------------------------------- */
    _bindKeyboard() {
        this._keyHandler = (e) => {
            switch (e.key) {
                case 'Escape':
                    this.close();
                    break;
                case 'ArrowLeft':
                    this.handlePrev();
                    break;
                case 'ArrowRight':
                    this.handleNext();
                    break;
                default:
                    break;
            }
        };
        document.addEventListener('keydown', this._keyHandler);
    }

    _unbindKeyboard() {
        if (this._keyHandler) {
            document.removeEventListener('keydown', this._keyHandler);
            this._keyHandler = null;
        }
    }

    _trapFocus() {
        requestAnimationFrame(() => {
            const closeBtn = this.template.querySelector('.lightbox-close');
            if (closeBtn) closeBtn.focus();
        });
    }

    disconnectedCallback() {
        this._unbindKeyboard();
    }
}