import ORGANIZATION_ID from '@salesforce/label/c.Organization_ID';

export const ORG_ID = ORGANIZATION_ID;

export const RENDITION_THUMB_240 = 'THUMB240BY180';
export const RENDITION_THUMB_720 = 'THUMB720BY480';

export const SIZES = {
    feedColumn: '(min-width: 768px) 760px, 100vw',
    libraryCard: '(min-width: 768px) 320px, 45vw',
    libraryRowThumb: '(min-width: 768px) 320px, 100vw',
    avatar: '48px'
};

const ORIGINAL_RENDITION_PATTERN = /rendition=ORIGINAL_[^&]*/i;

function parseRatio(ratioString) {
    if (!ratioString) {
        return { w: 16, h: 9 };
    }
    try {
        const parts = String(ratioString).toUpperCase().split('X');
        const w = parseInt(parts[0], 10);
        const h = parseInt(parts[1], 10);
        if (isNaN(w) || isNaN(h) || w <= 0 || h <= 0) {
            return { w: 16, h: 9 };
        }
        return { w, h };
    } catch (e) {
        return { w: 16, h: 9 };
    }
}

function fitWidth(maxW, maxH, ratioW, ratioH) {
    const aspect = ratioW / ratioH;
    if (aspect >= maxW / maxH) {
        return maxW;
    }
    return Math.round(maxH * aspect);
}

export function completeImageUrl(url) {
    if (!url) {
        return '';
    }
    const trimmed = String(url).trim();
    if (!trimmed) {
        return '';
    }
    if (ORG_ID && trimmed.includes(ORG_ID)) {
        return trimmed;
    }
    if (ORG_ID) {
        return trimmed + ORG_ID;
    }
    return trimmed;
}

export function originalUrl(url) {
    return completeImageUrl(url);
}

export function renditionUrl(url, rendition) {
    const complete = completeImageUrl(url);
    if (!complete || !rendition) {
        return complete;
    }
    if (ORIGINAL_RENDITION_PATTERN.test(complete)) {
        return complete.replace(ORIGINAL_RENDITION_PATTERN, `rendition=${rendition}`);
    }
    const separator = complete.includes('?') ? '&' : '?';
    return `${complete}${separator}rendition=${rendition}`;
}

export function thumbnailUrl(url) {
    return renditionUrl(url, RENDITION_THUMB_720);
}

export function avatarImageUrl(url) {
    return renditionUrl(url, RENDITION_THUMB_240);
}

/**
 * @param {string} url - ORIGINAL image URL (may omit org id suffix)
 * @param {string} ratio - e.g. "720X480"
 * @param {{ includeOriginal?: boolean }} options
 * @returns {string} srcset value for responsive <img>
 */
export function buildSrcset(url, ratio, options = {}) {
    const complete = completeImageUrl(url);
    if (!complete) {
        return '';
    }

    const { w: ratioW, h: ratioH } = parseRatio(ratio);
    const entries = [
        {
            url: renditionUrl(complete, RENDITION_THUMB_240),
            width: fitWidth(240, 180, ratioW, ratioH)
        },
        {
            url: renditionUrl(complete, RENDITION_THUMB_720),
            width: fitWidth(720, 480, ratioW, ratioH)
        }
    ];

    if (options.includeOriginal) {
        entries.push({
            url: complete,
            width: ratioW
        });
    }

    return entries
        .filter((entry) => entry.url && entry.width > 0)
        .map((entry) => `${entry.url} ${entry.width}w`)
        .join(', ');
}
