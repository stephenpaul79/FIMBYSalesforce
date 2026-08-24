import { LightningElement, api } from 'lwc';
import IMPACT_ICONS from '@salesforce/resourceUrl/Impact_Icons';

const PARENT_MANAGED = 'parent_managed';
const SUPPORTED = 'supported';

const VARIANTS = {
    [PARENT_MANAGED]: { label: 'Parent-managed', icon: 'youth.png', cssClass: 'proxy-badge parent-managed' },
    [SUPPORTED]: { label: 'Supported', icon: 'care.png', cssClass: 'proxy-badge supported' }
};

/**
 * Names who is behind a profile when someone else may speak for it. One component
 * for both proxy kinds so a reader never has to tell a parent-managed child from a
 * supported adult by colour alone — the label always says which.
 */
export default class FimbyProxyBadge extends LightningElement {
    /** PROXY_TYPE_* token from FimbyProxiedPresenceGuard, or falsy to render nothing. */
    @api proxyType;

    /**
     * Back-compat with the parent-managed-only call sites this component replaced.
     * When true and no proxyType is supplied, renders the parent-managed variant.
     */
    @api parentManaged = false;

    get _resolvedType() {
        if (this.proxyType) {
            return this.proxyType;
        }
        return (this.parentManaged === true || this.parentManaged === 'true')
            ? PARENT_MANAGED
            : null;
    }

    get variant() {
        return VARIANTS[this._resolvedType] || null;
    }

    get show() {
        return !!this.variant;
    }

    get badgeClass() {
        return this.variant.cssClass;
    }

    get label() {
        return this.variant.label;
    }

    get iconUrl() {
        return `${IMPACT_ICONS}/${this.variant.icon}`;
    }
}
