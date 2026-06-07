import { LightningElement, api, track } from 'lwc';
import { buildSrcset, SIZES, thumbnailUrl } from 'c/fimbyImageUrl';

const ORIENTATION_THRESHOLDS = {
    HORIZONTAL_MIN: 1.2,
    VERTICAL_MAX: 0.83
};

export default class FimbyImageGrid extends LightningElement {
    @api images = [];
    @api layout = 'auto';
    @api sizes = SIZES.feedColumn;
    @api includeOriginal = false;

    @track errorIndexes = new Set();

    get validImages() {
        if (!this.images || !Array.isArray(this.images)) return [];
        return this.images
            .filter((img, idx) => img && img.url && img.url.trim() !== '' && !this.errorIndexes.has(idx))
            .map((img, idx) => ({
                ...img,
                key: `img-${idx}`,
                index: idx,
                orientation: this._classifyOrientation(img.ratio),
                displayUrl: thumbnailUrl(img.url),
                srcset: buildSrcset(img.url, img.ratio, { includeOriginal: this.includeOriginal })
            }));
    }

    get imageCount() {
        return this.validImages.length;
    }

    get hasImages() {
        return this.imageCount > 0;
    }

    get isSingleImage() {
        return this.imageCount === 1;
    }

    get isTwoImages() {
        return this.imageCount === 2;
    }

    get isThreeImages() {
        return this.imageCount === 3;
    }

    get isFourImages() {
        return this.imageCount >= 4;
    }

    get singleImage() {
        return this.validImages[0] || null;
    }

    get singleImageContainerStyle() {
        const img = this.singleImage;
        if (!img || !img.ratio) return 'aspect-ratio: 16 / 9; max-height: 400px;';
        const parsed = this._parseRatio(img.ratio);
        if (!parsed) return 'aspect-ratio: 16 / 9; max-height: 400px;';
        const clamped = this._clampRatio(parsed.w, parsed.h);
        return `aspect-ratio: ${clamped.w} / ${clamped.h}; max-height: 400px;`;
    }

    get twoImages() {
        return this.validImages.slice(0, 2);
    }

    get twoImageGridClass() {
        const imgs = this.twoImages;
        if (imgs.length < 2) return 'image-grid grid-2';
        const o1 = imgs[0].orientation;
        const o2 = imgs[1].orientation;
        const isMixed = (o1 === 'horizontal' && o2 === 'vertical') ||
                        (o1 === 'vertical' && o2 === 'horizontal');
        if (isMixed) return 'image-grid grid-2 grid-2-mixed';
        const bothVertical = o1 === 'vertical' && o2 === 'vertical';
        if (bothVertical) return 'image-grid grid-2 grid-2-vertical';
        return 'image-grid grid-2';
    }

    get twoImageContainerStyle() {
        const imgs = this.twoImages;
        if (imgs.length < 2) return '';
        const dominant = this._dominantOrientation(imgs);
        if (dominant === 'vertical') return 'aspect-ratio: 3 / 4;';
        if (dominant === 'horizontal') return 'aspect-ratio: 16 / 9;';
        return 'aspect-ratio: 1 / 1;';
    }

    get threeImages() {
        return this.validImages.slice(0, 3);
    }

    get threeImageHero() {
        return this.validImages[0] || null;
    }

    get threeImageSecondary() {
        return this.validImages.slice(1, 3);
    }

    get threeImageContainerStyle() {
        const imgs = this.threeImages;
        if (imgs.length < 3) return '';
        const dominant = this._dominantOrientation(imgs);
        if (dominant === 'vertical') return 'aspect-ratio: 3 / 4;';
        if (dominant === 'horizontal') return 'aspect-ratio: 16 / 9;';
        return 'aspect-ratio: 1 / 1;';
    }

    get fourImages() {
        return this.validImages.slice(0, 4);
    }

    get fourImageRow1() {
        return this.validImages.slice(0, 2);
    }

    get fourImageRow2() {
        return this.validImages.slice(2, 4);
    }

    get fourImageContainerStyle() {
        const imgs = this.fourImages;
        if (imgs.length < 4) return '';
        const dominant = this._dominantOrientation(imgs);
        if (dominant === 'vertical') return 'aspect-ratio: 3 / 4;';
        if (dominant === 'horizontal') return 'aspect-ratio: 16 / 9;';
        return 'aspect-ratio: 1 / 1;';
    }

    handleImageClick(event) {
        event.stopPropagation();
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.dispatchEvent(new CustomEvent('imageclick', {
            detail: { index, images: this.validImages },
            bubbles: true,
            composed: false
        }));
    }

    handleImageError(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const imgEl = event.target;
        const original = event.currentTarget.dataset.original;
        if (original && imgEl.src !== original) {
            imgEl.src = original;
            imgEl.removeAttribute('srcset');
            return;
        }
        if (!isNaN(index)) {
            this.errorIndexes = new Set([...this.errorIndexes, index]);
        }
        imgEl.style.display = 'none';
    }

    _classifyOrientation(ratioString) {
        if (!ratioString) return 'square';
        const parsed = this._parseRatio(ratioString);
        if (!parsed) return 'square';
        const ratio = parsed.w / parsed.h;
        if (ratio > ORIENTATION_THRESHOLDS.HORIZONTAL_MIN) return 'horizontal';
        if (ratio < ORIENTATION_THRESHOLDS.VERTICAL_MAX) return 'vertical';
        return 'square';
    }

    _parseRatio(ratioString) {
        if (!ratioString) return null;
        try {
            const parts = ratioString.toUpperCase().split('X');
            const w = parseInt(parts[0], 10);
            const h = parseInt(parts[1], 10);
            if (isNaN(w) || isNaN(h) || w <= 0 || h <= 0) return null;
            return { w, h };
        } catch (e) {
            return null;
        }
    }

    _clampRatio(w, h) {
        const ratio = w / h;
        if (ratio > 1.91) return { w: Math.round(h * 1.91), h };
        if (ratio < 0.8) return { w, h: Math.round(w / 0.8) };
        return { w, h };
    }

    _dominantOrientation(imgs) {
        const counts = { horizontal: 0, vertical: 0, square: 0 };
        imgs.forEach(img => { counts[img.orientation]++; });
        if (counts.vertical > counts.horizontal && counts.vertical > counts.square) return 'vertical';
        if (counts.horizontal > counts.vertical && counts.horizontal > counts.square) return 'horizontal';
        return 'square';
    }
}
