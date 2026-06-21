import { LightningElement, api, track } from 'lwc';
import getImageUploadSettings from '@salesforce/apex/FimbyLibraryController.getImageUploadSettings';
import uploadImage from '@salesforce/apex/FimbyLibraryController.uploadImage';
import removeImage from '@salesforce/apex/FimbyLibraryController.removeImage';
import getCurrentImage from '@salesforce/apex/FimbyLibraryController.getCurrentImage';
import uploadFeedbackScreenshot from '@salesforce/apex/FimbyFeedbackController.uploadScreenshot';
import removeFeedbackScreenshot from '@salesforce/apex/FimbyFeedbackController.removeScreenshot';
import getFeedbackScreenshot from '@salesforce/apex/FimbyFeedbackController.getScreenshot';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

export default class FimbyImageUploader extends LightningElement {
    // Required: The record to attach the image to
    @api recordId;

    // Required: The object API name (Contact, Story__c, Library_Item__c, Needs_Offers__c, Feedback__c)
    @api objectApiName;

    // For Needs_Offers__c only: Which image slot (1, 2, 3, or 4)
    @api imageSlot;

    // Optional: Custom label
    @api label = 'Upload Photo';

    // When true, accepts PDFs in addition to images (verification letters, auth docs).
    @api allowDocuments = false;

    // When true, opens interactive crop step before upload (avatars/logos).
    @api enableCrop = false;
    @api cropSize = 300;
    @api cropShape = 'circle';

    // When true, shows a calm reminder to get consent before sharing photos of other people.
    // Enable on people-facing composers (Story, Ask/Offer, Library) — never the user's own profile photo.
    @api requirePeopleConsent = false;

    /** Bare `allow-documents` in markup sets "" not true — normalize before use. */
    get documentsEnabled() {
        return this.allowDocuments === true || this.allowDocuments === '';
    }

    /** Bare `require-people-consent` in markup sets "" not true — normalize before use. */
    get showPeopleConsentNote() {
        return this.requirePeopleConsent === true || this.requirePeopleConsent === '';
    }

    get peopleConsentMessage() {
        return "Is someone else in this photo? Please make sure they're okay with it being shared.";
    }

    get cropEnabled() {
        return this.enableCrop === true || this.enableCrop === '';
    }

    // State
    @track imageUrl = '';
    @track uploadedFileName = '';
    @track isPdfUpload = false;
    @track isLoading = true;
    @track isUploading = false;
    @track uploadProgress = 0;
    @track errorMessage = '';
    @track successMessage = '';

    // Settings from custom setting
    @track maxDimension = 1200;
    @track jpegQuality = 0.8;
    @track maxFileSizeBytes = 10 * 1024 * 1024;

    // Image dimensions after compression
    compressedWidth = 0;
    compressedHeight = 0;

    // Crop step state
    @track showCropper = false;
    cropSourceDataUrl = '';
    pendingFileName = '';

    get isFeedbackObject() {
        return this.objectApiName === 'Feedback__c';
    }

    async _loadCurrentImage() {
        if (!this.recordId) {
            return { success: true, imageUrl: null };
        }
        if (this.isFeedbackObject) {
            return getFeedbackScreenshot({ recordId: this.recordId });
        }
        return getCurrentImage({
            recordId: this.recordId,
            objectApiName: this.objectApiName,
            imageSlot: this.imageSlot || null
        });
    }

    connectedCallback() {
        this.loadInitialData();
    }

    async loadInitialData() {
        this.isLoading = true;
        this.errorMessage = '';

        try {
            // Load settings and current image in parallel
            const [settings, currentImage] = await Promise.all([
                getImageUploadSettings(),
                this._loadCurrentImage()
            ]);

            // Apply settings
            if (settings) {
                this.maxDimension = settings.maxDimension || 1200;
                this.jpegQuality = settings.jpegQuality || 0.8;
                this.maxFileSizeBytes = settings.maxFileSizeBytes || (10 * 1024 * 1024);
            }

            // Set current image if exists
            if (currentImage?.success && currentImage.imageUrl) {
                this.imageUrl = currentImage.imageUrl;
            }
        } catch (error) {
            console.error('Error loading data:', error);
            // Use defaults on error
        } finally {
            this.isLoading = false;
        }
    }

    // Getters
    get editIconUrl() { return `${IMPACT_ICONS}/edit.png`; }
    get trashIconUrl() { return `${IMPACT_ICONS}/trash.png`; }
    get photoIconUrl() { return `${IMPACT_ICONS}/photo.png`; }

    get hasImage() {
        return !!this.imageUrl || this.isPdfUpload;
    }

    get uploadAreaClass() {
        let classes = 'upload-area';
        if (this.hasImage) classes += ' has-image';
        if (this.isUploading) classes += ' uploading';
        return classes;
    }

    get progressStyle() {
        return `width: ${this.uploadProgress}%`;
    }

    get maxFileSizeMB() {
        return Math.round(this.maxFileSizeBytes / (1024 * 1024));
    }

    get acceptTypes() {
        return this.documentsEnabled ? 'image/*,.pdf,application/pdf' : 'image/*';
    }

    get primaryUploadText() {
        return this.documentsEnabled ? 'Tap to add photo or PDF' : 'Tap to add photo';
    }

    get displayLabel() {
        if (!this.label) {
            return '';
        }
        if (this.documentsEnabled && this.label === 'Upload Photo') {
            return 'Upload document';
        }
        return this.label;
    }

    get showDocumentPreview() {
        return this.isPdfUpload && !this.isLoading;
    }

    get showUploadArea() {
        return !this.isLoading && !this.hasImage;
    }

    get showImagePreview() {
        return !this.isLoading && !!this.imageUrl && !this.isPdfUpload;
    }

    get displayImageUrl() {
        if (!this.imageUrl) return '';
        return this.imageUrl;
    }

    // Event Handlers
    handleUploadClick() {
        this.template.querySelector('.file-input').click();
    }

    handleDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
        this.template.querySelector('.upload-area').classList.add('dragover');
    }

    handleDragLeave(event) {
        event.preventDefault();
        event.stopPropagation();
        this.template.querySelector('.upload-area').classList.remove('dragover');
    }

    handleDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        this.template.querySelector('.upload-area').classList.remove('dragover');

        const files = event.dataTransfer.files;
        if (files && files.length > 0) {
            this.processFile(files[0]);
        }
    }

    handleFileSelect(event) {
        const files = event.target.files;
        if (files && files.length > 0) {
            this.processFile(files[0]);
        }
        // Reset input so same file can be selected again
        event.target.value = '';
    }

    async handleRemoveImage(event) {
        event.stopPropagation();

        if (!this.recordId) {
            // Just clear locally if no record
            this._clearLocalUpload();
            this.dispatchImageEvent('imageremoved', {});
            return;
        }

        this.isUploading = true;
        this.errorMessage = '';

        try {
            const result = this.isFeedbackObject
                ? await removeFeedbackScreenshot({ recordId: this.recordId })
                : await removeImage({
                    recordId: this.recordId,
                    objectApiName: this.objectApiName,
                    imageSlot: this.imageSlot || null
                });

            if (result.success) {
                this._clearLocalUpload();
                this.successMessage = 'Image removed';
                // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce / delayed UI
                setTimeout(() => { this.successMessage = ''; }, 2000);
                this.dispatchImageEvent('imageremoved', {});
            }
        } catch (error) {
            console.error('Error removing image:', error);
            this.errorMessage = error.body?.message || 'Failed to remove image';
        } finally {
            this.isUploading = false;
        }
    }

    // Core Processing
    async processFile(file) {
        this.errorMessage = '';
        this.successMessage = '';

        if (!this.isAllowedFile(file)) {
            this.errorMessage = this.documentsEnabled
                ? 'Please select an image (JPG, PNG) or PDF file.'
                : 'Please select an image file (JPG, PNG, etc.)';
            return;
        }

        // Validate file size before compression
        if (file.size > this.maxFileSizeBytes) {
            this.errorMessage = `File too large. Maximum size is ${this.maxFileSizeMB}MB before compression.`;
            return;
        }

        const isPdf = this.isPdfFile(file);

        if (!isPdf && this.cropEnabled) {
            try {
                this.pendingFileName = this.generateFileName(file.name, false);
                this.cropSourceDataUrl = await this.readFileAsDataUrl(file);
                this.showCropper = true;
            } catch (error) {
                console.error('Error preparing crop:', error);
                this.errorMessage = error.message || 'Failed to load image. Please try again.';
            }
            return;
        }

        this.isUploading = true;
        this.uploadProgress = 10;

        try {
            let fileData;
            let fileName;
            let fileSize;

            if (isPdf) {
                this.uploadProgress = 20;
                const rawData = await this.readFileAsDataUrl(file);
                fileData = rawData;
                fileName = this.generateFileName(file.name, true);
                fileSize = file.size;
                this.uploadProgress = 50;
            } else {
                this.uploadProgress = 20;
                const compressedData = await this.compressImage(file);
                fileData = compressedData.base64;
                fileName = this.generateFileName(file.name, false);
                fileSize = compressedData.size;
                this.uploadProgress = 50;
            }

            await this._finishImageUpload({
                base64: fileData,
                fileName,
                width: this.compressedWidth,
                height: this.compressedHeight,
                size: fileSize,
                isPdf
            });
        } catch (error) {
            console.error('Error processing image:', error);
            this.errorMessage = error.body?.message || error.message || 'Failed to upload file. Please try again.';
        } finally {
            this.isUploading = false;
            this.uploadProgress = 0;
        }
    }

    async _finishImageUpload({ base64, fileName, width, height, size, isPdf }) {
        this.compressedWidth = width;
        this.compressedHeight = height;

        if (this.recordId) {
            const result = this.isFeedbackObject
                ? await uploadFeedbackScreenshot({
                    fileData: base64,
                    fileName,
                    recordId: this.recordId,
                    imageWidth: width,
                    imageHeight: height
                })
                : await uploadImage({
                    fileData: base64,
                    fileName,
                    recordId: this.recordId,
                    objectApiName: this.objectApiName,
                    imageSlot: this.imageSlot || null,
                    imageWidth: width,
                    imageHeight: height
                });

            this.uploadProgress = 100;

            if (result.success) {
                if (isPdf) {
                    this.isPdfUpload = true;
                    this.uploadedFileName = fileName;
                    this.imageUrl = '';
                } else {
                    this.imageUrl = result.viewUrl;
                    this.isPdfUpload = false;
                    this.uploadedFileName = '';
                }
                this.successMessage = isPdf ? 'Document uploaded successfully!' : 'Image uploaded successfully!';
                // eslint-disable-next-line @lwc/lwc/no-async-operation -- debounce / delayed UI
                setTimeout(() => { this.successMessage = ''; }, 3000);

                this.dispatchImageEvent('imageuploaded', {
                    imageUrl: result.viewUrl,
                    imageRatio: result.imageRatio,
                    contentVersionId: result.contentVersionId,
                    fileName,
                    isPdf
                });
            }
        } else {
            this.uploadProgress = 100;
            if (isPdf) {
                this.isPdfUpload = true;
                this.uploadedFileName = fileName;
                this.imageUrl = '';
            } else {
                this.imageUrl = base64;
                this.isPdfUpload = false;
                this.uploadedFileName = '';
            }

            this.dispatchImageEvent('imageselected', {
                base64,
                fileName,
                width,
                height,
                size,
                isPdf
            });
        }
    }

    async handleCropConfirm(event) {
        const { base64, width, height, size } = event.detail || {};
        const fileName = this.pendingFileName || this.generateFileName('photo.jpg', false);
        this._closeCropper();
        if (!base64) return;

        this.isUploading = true;
        this.uploadProgress = 50;
        this.errorMessage = '';

        try {
            await this._finishImageUpload({
                base64,
                fileName,
                width,
                height,
                size,
                isPdf: false
            });
        } catch (error) {
            console.error('Error uploading cropped image:', error);
            this.errorMessage = error.body?.message || error.message || 'Failed to upload file. Please try again.';
        } finally {
            this.isUploading = false;
            this.uploadProgress = 0;
        }
    }

    handleCropCancel() {
        this._closeCropper();
    }

    _closeCropper() {
        this.showCropper = false;
        this.cropSourceDataUrl = '';
        this.pendingFileName = '';
    }

    /**
     * Compress and resize image using Canvas API
     * Handles iOS/Android orientation via EXIF
     */
    async compressImage(file) {
        return new Promise((resolve, reject) => {
            const img = new Image();
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');

            img.onload = () => {
                try {
                    let { width, height } = img;

                    // Calculate new dimensions (maintain aspect ratio)
                    if (width > this.maxDimension || height > this.maxDimension) {
                        if (width > height) {
                            height = Math.round((height * this.maxDimension) / width);
                            width = this.maxDimension;
                        } else {
                            width = Math.round((width * this.maxDimension) / height);
                            height = this.maxDimension;
                        }
                    }

                    // Store final dimensions for ratio calculation
                    this.compressedWidth = width;
                    this.compressedHeight = height;

                    // Set canvas size
                    canvas.width = width;
                    canvas.height = height;

                    // Fill with white background (for transparent PNGs converted to JPEG)
                    ctx.fillStyle = '#FFFFFF';
                    ctx.fillRect(0, 0, width, height);

                    // Draw the image
                    ctx.drawImage(img, 0, 0, width, height);

                    // Convert to JPEG blob
                    canvas.toBlob(
                        (blob) => {
                            if (!blob) {
                                reject(new Error('Failed to compress image'));
                                return;
                            }

                            // Convert blob to base64
                            const reader = new FileReader();
                            reader.onloadend = () => {
                                resolve({
                                    base64: reader.result,
                                    size: blob.size
                                });
                            };
                            reader.onerror = () => reject(new Error('Failed to read compressed image'));
                            reader.readAsDataURL(blob);
                        },
                        'image/jpeg',
                        this.jpegQuality
                    );
                } catch (err) {
                    reject(err);
                }
            };

            img.onerror = () => reject(new Error('Failed to load image'));

            // Read file as data URL
            const reader = new FileReader();
            reader.onload = (e) => {
                img.src = e.target.result;
            };
            reader.onerror = () => reject(new Error('Failed to read file'));
            reader.readAsDataURL(file);
        });
    }

    isAllowedFile(file) {
        if (file.type.startsWith('image/')) {
            return true;
        }
        if (this.documentsEnabled && this.isPdfFile(file)) {
            return true;
        }
        return false;
    }

    isPdfFile(file) {
        const name = (file.name || '').toLowerCase();
        return file.type === 'application/pdf' || name.endsWith('.pdf');
    }

    readFileAsDataUrl(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = (e) => resolve(e.target.result);
            reader.onerror = () => reject(new Error('Failed to read file'));
            reader.readAsDataURL(file);
        });
    }

    _clearLocalUpload() {
        this.imageUrl = '';
        this.uploadedFileName = '';
        this.isPdfUpload = false;
    }

    /**
     * Generate a clean file name
     */
    generateFileName(originalName, isPdf = false) {
        const timestamp = new Date().getTime();
        const extension = isPdf ? '.pdf' : '.jpg';
        const baseName = originalName.replace(/\.[^/.]+$/, '').substring(0, 50);
        return `${baseName}_${timestamp}${extension}`;
    }

    /**
     * Dispatch custom event to parent
     */
    dispatchImageEvent(eventName, detail) {
        this.dispatchEvent(new CustomEvent(eventName, {
            detail: detail,
            bubbles: true,
            composed: true
        }));
    }

    // Public API methods
    @api
    reset() {
        this._clearLocalUpload();
        this.errorMessage = '';
        this.successMessage = '';
        const fileInput = this.template.querySelector('.file-input');
        if (fileInput) fileInput.value = '';
    }

    @api
    setImage(url) {
        this.imageUrl = url;
    }

    @api
    async refresh() {
        await this.loadInitialData();
    }
}