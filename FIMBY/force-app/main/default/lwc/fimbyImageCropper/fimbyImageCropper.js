import { LightningElement, api, track } from 'lwc';

const VIEWPORT_SIZE = 280;
const ZOOM_MAX_MULTIPLIER = 3;

export default class FimbyImageCropper extends LightningElement {
    @api imageSrc;
    @api outputSize = 300;
    @api quality = 0.8;

    @track zoomPercent = 100;
    @track isExporting = false;

    _img = null;
    _scale = 1;
    _minScale = 1;
    _offsetX = 0;
    _offsetY = 0;
    _isPanning = false;
    _isPinching = false;
    _panStartX = 0;
    _panStartY = 0;
    _panOriginX = 0;
    _panOriginY = 0;
    _canvas = null;
    _ctx = null;
    _pointers = new Map();
    _pinchStartDistance = 0;
    _pinchStartScale = 1;
    _renderScheduled = false;

    get zoomMinPercent() {
        return 100;
    }

    get zoomMaxPercent() {
        return Math.round(ZOOM_MAX_MULTIPLIER * 100);
    }

    get confirmLabel() {
        return this.isExporting ? 'Saving…' : 'Use photo';
    }

    renderedCallback() {
        if (!this._canvas) {
            const canvas = this.template.querySelector('.crop-canvas');
            if (!canvas) return;
            this._canvas = canvas;
            this._ctx = canvas.getContext('2d');
            canvas.width = VIEWPORT_SIZE;
            canvas.height = VIEWPORT_SIZE;
        }

        if (this.imageSrc && !this._img) {
            this._loadImage(this.imageSrc);
        }
    }

    _loadImage(src) {
        const img = new Image();
        img.onload = () => {
            this._img = img;
            this._minScale = Math.max(
                VIEWPORT_SIZE / img.naturalWidth,
                VIEWPORT_SIZE / img.naturalHeight
            );
            this._scale = this._minScale;
            this._centerImage();
            this.zoomPercent = 100;
            this._scheduleRender();
        };
        img.onerror = () => {
            this.dispatchEvent(new CustomEvent('cropcancel'));
        };
        img.src = src;
    }

    _centerImage() {
        if (!this._img) return;
        const w = this._img.naturalWidth * this._scale;
        const h = this._img.naturalHeight * this._scale;
        this._offsetX = (VIEWPORT_SIZE - w) / 2;
        this._offsetY = (VIEWPORT_SIZE - h) / 2;
        this._clampOffsets();
    }

    _clampOffsets() {
        if (!this._img) return;
        const w = this._img.naturalWidth * this._scale;
        const h = this._img.naturalHeight * this._scale;
        const minX = VIEWPORT_SIZE - w;
        const minY = VIEWPORT_SIZE - h;
        this._offsetX = Math.min(0, Math.max(minX, this._offsetX));
        this._offsetY = Math.min(0, Math.max(minY, this._offsetY));
    }

    _scheduleRender() {
        if (this._renderScheduled) return;
        this._renderScheduled = true;
        requestAnimationFrame(() => {
            this._renderScheduled = false;
            this._render();
        });
    }

    _render() {
        if (!this._ctx || !this._img) return;
        const ctx = this._ctx;
        ctx.fillStyle = '#FFFFFF';
        ctx.fillRect(0, 0, VIEWPORT_SIZE, VIEWPORT_SIZE);
        ctx.drawImage(
            this._img,
            this._offsetX,
            this._offsetY,
            this._img.naturalWidth * this._scale,
            this._img.naturalHeight * this._scale
        );
    }

    _scaleFromPercent(percent) {
        const t = (percent - 100) / (this.zoomMaxPercent - 100);
        return this._minScale * (1 + t * (ZOOM_MAX_MULTIPLIER - 1));
    }

    _percentFromScale(scale) {
        if (scale <= this._minScale) return 100;
        const t = (scale / this._minScale - 1) / (ZOOM_MAX_MULTIPLIER - 1);
        return Math.round(100 + t * (this.zoomMaxPercent - 100));
    }

    _setScale(newScale, focalX, focalY) {
        if (!this._img) return;
        const clamped = Math.max(this._minScale, Math.min(this._minScale * ZOOM_MAX_MULTIPLIER, newScale));
        const ratio = clamped / this._scale;
        this._offsetX = focalX - ratio * (focalX - this._offsetX);
        this._offsetY = focalY - ratio * (focalY - this._offsetY);
        this._scale = clamped;
        this._clampOffsets();
        this.zoomPercent = this._percentFromScale(this._scale);
        this._scheduleRender();
    }

    handleZoomInput(event) {
        const percent = parseInt(event.target.value, 10);
        this._setScale(this._scaleFromPercent(percent), VIEWPORT_SIZE / 2, VIEWPORT_SIZE / 2);
    }

    _viewportPoint(clientX, clientY, viewport) {
        const rect = viewport.getBoundingClientRect();
        return { x: clientX - rect.left, y: clientY - rect.top };
    }

    _pointerDistance(a, b) {
        const dx = a.x - b.x;
        const dy = a.y - b.y;
        return Math.sqrt(dx * dx + dy * dy);
    }

    _activePointerList() {
        return Array.from(this._pointers.values());
    }

    _storePointer(event) {
        const viewport = event.currentTarget;
        const local = this._viewportPoint(event.clientX, event.clientY, viewport);
        this._pointers.set(event.pointerId, {
            clientX: event.clientX,
            clientY: event.clientY,
            x: local.x,
            y: local.y
        });
    }

    _beginPan(pointer) {
        this._isPinching = false;
        this._pinchStartDistance = 0;
        this._isPanning = true;
        this._panStartX = pointer.clientX;
        this._panStartY = pointer.clientY;
        this._panOriginX = this._offsetX;
        this._panOriginY = this._offsetY;
    }

    _beginPinch() {
        const pts = this._activePointerList();
        if (pts.length < 2) return;
        this._isPanning = false;
        this._isPinching = true;
        this._pinchStartScale = this._scale;
        this._pinchStartDistance = this._pointerDistance(pts[0], pts[1]) || 1;
    }

    _applyPinch() {
        const pts = this._activePointerList();
        if (pts.length < 2) return;
        const dist = this._pointerDistance(pts[0], pts[1]);
        const midX = (pts[0].x + pts[1].x) / 2;
        const midY = (pts[0].y + pts[1].y) / 2;
        const newScale = this._pinchStartScale * (dist / this._pinchStartDistance);
        this._setScale(newScale, midX, midY);
    }

    handlePointerDown(event) {
        if (!this._img) return;
        const viewport = event.currentTarget;
        this._storePointer(event);
        try {
            viewport.setPointerCapture(event.pointerId);
        } catch {
            /* capture unavailable */
        }

        if (this._pointers.size === 1) {
            this._beginPan(this._pointers.get(event.pointerId));
        } else if (this._pointers.size >= 2) {
            this._beginPinch();
        }
    }

    handlePointerMove(event) {
        if (!this._pointers.has(event.pointerId)) return;
        this._storePointer(event);

        if (this._pointers.size >= 2) {
            if (!this._isPinching) {
                this._beginPinch();
            }
            this._applyPinch();
            return;
        }

        if (this._isPanning) {
            const pointer = this._pointers.get(event.pointerId);
            const dx = pointer.clientX - this._panStartX;
            const dy = pointer.clientY - this._panStartY;
            this._offsetX = this._panOriginX + dx;
            this._offsetY = this._panOriginY + dy;
            this._clampOffsets();
            this._scheduleRender();
        }
    }

    handlePointerUp(event) {
        const viewport = event.currentTarget;
        this._pointers.delete(event.pointerId);
        try {
            viewport.releasePointerCapture(event.pointerId);
        } catch {
            /* already released */
        }

        if (this._pointers.size === 0) {
            this._isPanning = false;
            this._isPinching = false;
            this._pinchStartDistance = 0;
            return;
        }

        if (this._pointers.size === 1) {
            this._beginPan(this._pointers.values().next().value);
            return;
        }

        if (this._pointers.size >= 2) {
            this._beginPinch();
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cropcancel', { bubbles: true, composed: true }));
    }

    async handleConfirm() {
        if (!this._img || this.isExporting) return;
        this.isExporting = true;

        try {
            const viewportCanvas = document.createElement('canvas');
            viewportCanvas.width = VIEWPORT_SIZE;
            viewportCanvas.height = VIEWPORT_SIZE;
            const vctx = viewportCanvas.getContext('2d');
            vctx.fillStyle = '#FFFFFF';
            vctx.fillRect(0, 0, VIEWPORT_SIZE, VIEWPORT_SIZE);
            vctx.drawImage(
                this._img,
                this._offsetX,
                this._offsetY,
                this._img.naturalWidth * this._scale,
                this._img.naturalHeight * this._scale
            );

            const outSize = this.outputSize || 300;
            const outCanvas = document.createElement('canvas');
            outCanvas.width = outSize;
            outCanvas.height = outSize;
            const outCtx = outCanvas.getContext('2d');
            outCtx.fillStyle = '#FFFFFF';
            outCtx.fillRect(0, 0, outSize, outSize);
            outCtx.drawImage(viewportCanvas, 0, 0, VIEWPORT_SIZE, VIEWPORT_SIZE, 0, 0, outSize, outSize);

            const blob = await new Promise((resolve, reject) => {
                outCanvas.toBlob(
                    (b) => (b ? resolve(b) : reject(new Error('Failed to export image'))),
                    'image/jpeg',
                    this.quality
                );
            });

            const base64 = await new Promise((resolve, reject) => {
                const reader = new FileReader();
                reader.onloadend = () => resolve(reader.result);
                reader.onerror = () => reject(new Error('Failed to read export'));
                reader.readAsDataURL(blob);
            });

            this.dispatchEvent(new CustomEvent('cropconfirm', {
                detail: {
                    base64,
                    width: outSize,
                    height: outSize,
                    size: blob.size
                },
                bubbles: true,
                composed: true
            }));
        } catch (err) {
            console.error('Crop export failed:', err);
            this.dispatchEvent(new CustomEvent('cropcancel', { bubbles: true, composed: true }));
        } finally {
            this.isExporting = false;
        }
    }
}
