import { LightningElement, api, track } from 'lwc';
import { getInitials, getAvatarTone } from 'c/fimbyAvatarTone';

const MIN_SIZE = 16;
const MAX_SIZE = 128;
const DEFAULT_SIZE = 40;

export default class FimbyAvatar extends LightningElement {
    @api src;
    @api name;
    @api contactId;
    @api organizationAccountId;
    @api isOrganization = false;
    @api size = DEFAULT_SIZE;
    @api label;

    @track _failedSrc;

    get showImage() {
        return !!this.src && this.src !== this._failedSrc;
    }

    get initials() {
        return getInitials(this.name);
    }

    get pixelSize() {
        const n = Number(this.size);
        if (!Number.isFinite(n)) return DEFAULT_SIZE;
        return Math.min(MAX_SIZE, Math.max(MIN_SIZE, Math.round(n)));
    }

    get wrapperClass() {
        return this.isOrganization ? 'avatar avatar-org' : 'avatar';
    }

    get wrapperStyle() {
        const tone = getAvatarTone({
            contactId: this.contactId,
            organizationAccountId: this.organizationAccountId,
            name: this.name,
            isOrganization: this.isOrganization
        });
        return `--fimby-avatar-size: ${this.pixelSize}px; background-color: ${tone};`;
    }

    get wrapperRole() {
        return this.label ? 'img' : null;
    }

    get wrapperAriaHidden() {
        return this.label ? null : 'true';
    }

    handleImageError(event) {
        const failed = event.target.getAttribute('src');
        if (failed === this.src) {
            this._failedSrc = this.src;
        }
    }
}
