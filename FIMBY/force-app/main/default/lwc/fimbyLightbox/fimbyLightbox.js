import { LightningElement, api, track } from 'lwc';

const SWIPE_THRESHOLD = 50;
const MIN_SCALE = 1;
const MAX_SCALE = 4;
const DOUBLE_TAP_SCALE = 2.5;
const DOUBLE_TAP_MS = 300;
const DOUBLE_TAP_SLOP = 30; // px of finger travel still treated as a tap

export default class FimbyLightbox extends LightningElement {
    @api images = [];
    @api startIndex = 0;

    @track currentIndex = 0;
    @track isVisible = false;
    @track _zoomed = false; // drives arrow hiding; mirrors _scale > 1

    _touchStartX = 0;
    _touchStartY = 0;
    _keyHandler = null;

    // Zoom / pan transform state (plain fields — applied imperatively for 60fps,
    // and reflected by the imageStyle getter on every re-render so the two stay
    // in sync). Reset to fit whenever the photo changes or the viewer opens/closes.
    _scale = 1;
    _tx = 0;
    _ty = 0;
    _pinchStartDist = 0;
    _startScale = 1;
    _panStartX = 0;
    _panStartY = 0;
    _panOriginX = 0;
    _panOriginY = 0;
    _isPinching = false;
    _isPanning = false;
    _lastTapTime = 0;

    /* ----------------------------------------------------------
     * Public API
     * ---------------------------------------------------------- */
    @api
    open(index) {
        this.currentIndex = (typeof index === 'number') ? index : (this.startIndex || 0);
        this._resetZoom();
        this.isVisible = true;
        this._bindKeyboard();
        this._trapFocus();
    }

    @api
    close() {
        this.isVisible = false;
        this._resetZoom();
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
        return this.currentIndex > 0 && !this._zoomed;
    }

    get showNext() {
        return this.currentIndex < this.validImages.length - 1 && !this._zoomed;
    }

    get backdropClass() {
        return this.isVisible ? 'lightbox-backdrop visible' : 'lightbox-backdrop';
    }

    get imageStyle() {
        return `transform: translate(${this._tx}px, ${this._ty}px) scale(${this._scale});`;
    }

    /* ----------------------------------------------------------
     * Navigation
     * ---------------------------------------------------------- */
    handlePrev(event) {
        if (event) event.stopPropagation();
        if (this.currentIndex > 0) {
            this.currentIndex--;
            this._resetZoom();
        }
    }

    handleNext(event) {
        if (event) event.stopPropagation();
        if (this.currentIndex < this.validImages.length - 1) {
            this.currentIndex++;
            this._resetZoom();
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
     * Touch / swipe / pinch-zoom / pan support
     * ---------------------------------------------------------- */
    handleTouchStart(event) {
        if (event.touches.length === 2) {
            // Begin pinch
            this._isPinching = true;
            this._isPanning = false;
            this._pinchStartDist = this._touchDistance(event.touches);
            this._startScale = this._scale;
            this._setSmooth(false);
            return;
        }

        if (event.touches.length !== 1) return;

        const touch = event.touches[0];
        this._touchStartX = touch.clientX;
        this._touchStartY = touch.clientY;

        if (this._scale > 1) {
            // Begin pan of the zoomed image
            this._isPanning = true;
            this._panStartX = touch.clientX;
            this._panStartY = touch.clientY;
            this._panOriginX = this._tx;
            this._panOriginY = this._ty;
            this._setSmooth(false);
        }
    }

    handleTouchMove(event) {
        if (this._isPinching && event.touches.length === 2) {
            event.preventDefault();
            const dist = this._touchDistance(event.touches);
            if (this._pinchStartDist > 0) {
                const next = this._startScale * (dist / this._pinchStartDist);
                this._scale = this._clamp(next, MIN_SCALE, MAX_SCALE);
                this._clampPan();
                this._applyTransform();
            }
            return;
        }

        if (this._isPanning && event.touches.length === 1) {
            event.preventDefault();
            const touch = event.touches[0];
            this._tx = this._panOriginX + (touch.clientX - this._panStartX);
            this._ty = this._panOriginY + (touch.clientY - this._panStartY);
            this._clampPan();
            this._applyTransform();
        }
    }

    handleTouchEnd(event) {
        if (this._isPinching) {
            // Wait until both fingers are lifted before clearing pinch state.
            if (event.touches.length === 0) {
                this._isPinching = false;
                if (this._scale <= MIN_SCALE) {
                    this._resetZoom();
                } else {
                    this._zoomed = true;
                }
            }
            return;
        }

        if (this._isPanning) {
            if (event.touches.length === 0) {
                this._isPanning = false;
            }
            return;
        }

        if (event.changedTouches.length !== 1) return;

        const deltaX = event.changedTouches[0].clientX - this._touchStartX;
        const deltaY = event.changedTouches[0].clientY - this._touchStartY;

        // Double-tap to toggle zoom (only a near-stationary single tap counts).
        if (Math.abs(deltaX) < DOUBLE_TAP_SLOP && Math.abs(deltaY) < DOUBLE_TAP_SLOP) {
            const now = Date.now();
            if (now - this._lastTapTime < DOUBLE_TAP_MS) {
                this._lastTapTime = 0;
                this._toggleDoubleTapZoom(event.changedTouches[0]);
                return;
            }
            this._lastTapTime = now;
        }

        // Swipe navigation only when not zoomed — a zoom-pan must never flip photos.
        if (this._scale === 1 &&
            Math.abs(deltaX) > Math.abs(deltaY) &&
            Math.abs(deltaX) > SWIPE_THRESHOLD) {
            if (deltaX < 0) {
                this.handleNext();
            } else {
                this.handlePrev();
            }
        }
    }

    /* ----------------------------------------------------------
     * Zoom helpers
     * ---------------------------------------------------------- */
    _touchDistance(touches) {
        return Math.hypot(
            touches[1].clientX - touches[0].clientX,
            touches[1].clientY - touches[0].clientY
        );
    }

    _clamp(value, min, max) {
        return Math.min(Math.max(value, min), max);
    }

    _imageEl() {
        return this.template.querySelector('.lightbox-image');
    }

    _applyTransform() {
        const img = this._imageEl();
        if (img) {
            img.style.transform = `translate(${this._tx}px, ${this._ty}px) scale(${this._scale})`;
        }
    }

    // Disable the CSS transition during continuous gestures so the image tracks
    // the fingers exactly; re-enable it for the snap of a double-tap / reset.
    _setSmooth(on) {
        const img = this._imageEl();
        if (img) {
            img.style.transition = on ? '' : 'none';
        }
    }

    _clampPan() {
        const img = this._imageEl();
        if (!img) return;
        const maxX = (img.offsetWidth * (this._scale - 1)) / 2;
        const maxY = (img.offsetHeight * (this._scale - 1)) / 2;
        this._tx = this._clamp(this._tx, -maxX, maxX);
        this._ty = this._clamp(this._ty, -maxY, maxY);
    }

    _toggleDoubleTapZoom(touch) {
        this._setSmooth(true);
        if (this._scale > 1) {
            this._resetZoom();
            return;
        }
        const img = this._imageEl();
        this._scale = DOUBLE_TAP_SCALE;
        if (img) {
            const rect = img.getBoundingClientRect();
            const cx = rect.left + rect.width / 2;
            const cy = rect.top + rect.height / 2;
            // Keep the tapped point stationary: t = p * (1 - scale).
            this._tx = (touch.clientX - cx) * (1 - this._scale);
            this._ty = (touch.clientY - cy) * (1 - this._scale);
        }
        this._clampPan();
        this._applyTransform();
        this._zoomed = true;
    }

    _resetZoom() {
        this._scale = 1;
        this._tx = 0;
        this._ty = 0;
        this._isPinching = false;
        this._isPanning = false;
        this._zoomed = false;
        this._setSmooth(true);
        this._applyTransform();
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
        // eslint-disable-next-line @lwc/lwc/no-async-operation -- scroll/focus after render
        requestAnimationFrame(() => {
            const closeBtn = this.template.querySelector('.lightbox-close');
            if (closeBtn) closeBtn.focus();
        });
    }

    disconnectedCallback() {
        this._unbindKeyboard();
    }
}