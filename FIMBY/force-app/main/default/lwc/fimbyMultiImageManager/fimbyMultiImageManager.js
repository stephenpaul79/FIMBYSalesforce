import { LightningElement, api, track } from 'lwc';
import getAllImageSlots from '@salesforce/apex/FimbyLibraryController.getAllImageSlots';
import uploadImage from '@salesforce/apex/FimbyLibraryController.uploadImage';
import removeAndConsolidateImage from '@salesforce/apex/FimbyLibraryController.removeAndConsolidateImage';
import getImageUploadSettings from '@salesforce/apex/FimbyLibraryController.getImageUploadSettings';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const MAX_SLOTS = 4;
const WIDE_BREAKPOINT = 480;

export default class FimbyMultiImageManager extends LightningElement {
    @api recordId;
    @api objectApiName = 'Needs_Offers__c';
    @api maxSlots = MAX_SLOTS;
    @api mode = 'full';

    @track images = [];
    @track isLoading = true;
    @track uploadingSlot = null;
    @track uploadProgress = 0;
    @track errorMessage = '';
    @track isWide = false;

    maxDimension = 1200;
    jpegQuality = 0.8;
    maxFileSizeBytes = 10 * 1024 * 1024;
    compressedWidth = 0;
    compressedHeight = 0;

    _resizeObserver;

    connectedCallback() {
        this._loadData();
    }

    renderedCallback() {
        if (!this._resizeObserver) {
            const container = this.template.querySelector('.multi-image-manager');
            if (container) {
                this._resizeObserver = new ResizeObserver(entries => {
                    for (const entry of entries) {
                        this.isWide = entry.contentRect.width >= WIDE_BREAKPOINT;
                    }
                });
                this._resizeObserver.observe(container);
            }
        }
    }

    disconnectedCallback() {
        if (this._resizeObserver) {
            this._resizeObserver.disconnect();
            this._resizeObserver = null;
        }
    }

    async _loadData() {
        this.isLoading = true;
        try {
            const [settings, slots] = await Promise.all([
                getImageUploadSettings(),
                this.recordId ? getAllImageSlots({ recordId: this.recordId }) : Promise.resolve([])
            ]);

            if (settings) {
                this.maxDimension = settings.maxDimension || 1200;
                this.jpegQuality = settings.jpegQuality || 0.8;
                this.maxFileSizeBytes = settings.maxFileSizeBytes || (10 * 1024 * 1024);
            }

            this.images = (slots || []).map(s => ({
                slot: s.slot,
                imageUrl: s.imageUrl,
                imageRatio: s.imageRatio
            }));
        } catch (error) {
            console.error('Error loading images:', error);
            this.errorMessage = 'Unable to load photos.';
        } finally {
            this.isLoading = false;
        }
    }

    // ============================================
    // COMPUTED
    // ============================================

    get trashIconUrl() { return `${IMPACT_ICONS}/trash.png`; }

    get containerClass() {
        const classes = ['multi-image-manager'];
        if (this.mode === 'compact') classes.push('compact');
        if (this.isWide) classes.push('wide');
        return classes.join(' ');
    }

    get imageCount() {
        return this.images.length;
    }

    get hasImages() {
        return this.images.length > 0;
    }

    get canAddMore() {
        return this.images.length < this.maxSlots && !this.uploadingSlot;
    }

    get showEmptyState() {
        return !this.isLoading && !this.hasImages;
    }

    get showGrid() {
        return !this.isLoading && this.hasImages;
    }

    get gridCells() {
        const cells = this.images.map((img, idx) => ({
            key: 'img-' + img.slot,
            slot: img.slot,
            imageUrl: img.imageUrl,
            isUploading: this.uploadingSlot === img.slot,
            index: idx
        }));
        return cells;
    }

    get addLabel() {
        return this.images.length === 0
            ? `Add up to ${this.maxSlots} photos`
            : `Add photo (${this.images.length}/${this.maxSlots})`;
    }

    get progressStyle() {
        return `width: ${this.uploadProgress}%`;
    }

    get isUploading() {
        return this.uploadingSlot != null;
    }

    // ============================================
    // ADD PHOTO
    // ============================================

    handleAddClick() {
        if (!this.canAddMore) return;
        this.template.querySelector('.hidden-file-input').click();
    }

    handleFileSelect(event) {
        const files = event.target.files;
        if (files && files.length > 0) {
            this._processFile(files[0]);
        }
        event.target.value = '';
    }

    handleDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
    }

    handleDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        const files = event.dataTransfer.files;
        if (files && files.length > 0 && this.canAddMore) {
            this._processFile(files[0]);
        }
    }

    // ============================================
    // REMOVE PHOTO
    // ============================================

    async handleRemove(event) {
        event.stopPropagation();
        const slot = parseInt(event.currentTarget.dataset.slot, 10);
        if (!slot || !this.recordId) return;

        this.errorMessage = '';
        this.uploadingSlot = slot;

        try {
            const result = await removeAndConsolidateImage({
                recordId: this.recordId,
                removedSlot: slot
            });

            if (result.success) {
                this.images = (result.slots || []).map(s => ({
                    slot: s.slot,
                    imageUrl: s.imageUrl,
                    imageRatio: s.imageRatio
                }));
                this._dispatchChange();
            }
        } catch (error) {
            console.error('Error removing image:', error);
            this.errorMessage = error.body?.message || 'Failed to remove photo.';
        } finally {
            this.uploadingSlot = null;
        }
    }

    // ============================================
    // UPLOAD PROCESSING
    // ============================================

    async _processFile(file) {
        this.errorMessage = '';

        if (!file.type.startsWith('image/')) {
            this.errorMessage = 'Please select an image file (JPG, PNG, etc.)';
            return;
        }

        if (file.size > this.maxFileSizeBytes) {
            const maxMB = Math.round(this.maxFileSizeBytes / (1024 * 1024));
            this.errorMessage = `File too large. Maximum size is ${maxMB}MB.`;
            return;
        }

        const nextSlot = this.images.length + 1;
        if (nextSlot > this.maxSlots) return;

        this.uploadingSlot = nextSlot;
        this.uploadProgress = 10;

        try {
            this.uploadProgress = 20;
            const compressed = await this._compressImage(file);
            this.uploadProgress = 50;

            const result = await uploadImage({
                fileData: compressed.base64,
                fileName: this._generateFileName(file.name),
                recordId: this.recordId,
                objectApiName: this.objectApiName,
                imageSlot: nextSlot,
                imageWidth: this.compressedWidth,
                imageHeight: this.compressedHeight
            });

            this.uploadProgress = 100;

            if (result.success) {
                this.images = [
                    ...this.images,
                    {
                        slot: nextSlot,
                        imageUrl: result.viewUrl,
                        imageRatio: result.imageRatio
                    }
                ];
                this._dispatchChange();
                this.dispatchEvent(new CustomEvent('imageuploaded', {
                    detail: { slot: nextSlot, imageUrl: result.viewUrl },
                    bubbles: true,
                    composed: true
                }));
            }
        } catch (error) {
            console.error('Error uploading image:', error);
            this.errorMessage = error.body?.message || 'Failed to upload photo. Please try again.';
        } finally {
            this.uploadingSlot = null;
            this.uploadProgress = 0;
        }
    }

    _compressImage(file) {
        return new Promise((resolve, reject) => {
            const img = new Image();
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');

            img.onload = () => {
                try {
                    let { width, height } = img;
                    if (width > this.maxDimension || height > this.maxDimension) {
                        if (width > height) {
                            height = Math.round((height * this.maxDimension) / width);
                            width = this.maxDimension;
                        } else {
                            width = Math.round((width * this.maxDimension) / height);
                            height = this.maxDimension;
                        }
                    }
                    this.compressedWidth = width;
                    this.compressedHeight = height;
                    canvas.width = width;
                    canvas.height = height;
                    ctx.fillStyle = '#FFFFFF';
                    ctx.fillRect(0, 0, width, height);
                    ctx.drawImage(img, 0, 0, width, height);
                    canvas.toBlob(
                        (blob) => {
                            if (!blob) { reject(new Error('Failed to compress image')); return; }
                            const reader = new FileReader();
                            reader.onloadend = () => resolve({ base64: reader.result, size: blob.size });
                            reader.onerror = () => reject(new Error('Failed to read compressed image'));
                            reader.readAsDataURL(blob);
                        },
                        'image/jpeg',
                        this.jpegQuality
                    );
                } catch (err) { reject(err); }
            };
            img.onerror = () => reject(new Error('Failed to load image'));
            const reader = new FileReader();
            reader.onload = (e) => { img.src = e.target.result; };
            reader.onerror = () => reject(new Error('Failed to read file'));
            reader.readAsDataURL(file);
        });
    }

    _generateFileName(originalName) {
        const timestamp = new Date().getTime();
        const baseName = originalName.replace(/\.[^/.]+$/, '').substring(0, 50);
        return `${baseName}_${timestamp}.jpg`;
    }

    _dispatchChange() {
        this.dispatchEvent(new CustomEvent('imageschanged', {
            detail: { images: [...this.images], count: this.images.length },
            bubbles: true,
            composed: true
        }));
    }

    @api
    async refresh() {
        await this._loadData();
    }
}