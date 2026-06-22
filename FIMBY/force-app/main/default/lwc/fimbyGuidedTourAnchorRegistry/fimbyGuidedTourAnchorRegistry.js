/**
 * Registry for tour anchor providers. Each shell/page LWC registers itself
 * and exposes getTourAnchorRect(name) without piercing foreign shadow roots.
 */

const providers = new Set();

export function registerTourAnchorProvider(provider) {
    if (provider) {
        providers.add(provider);
    }
    return () => {
        if (provider) {
            providers.delete(provider);
        }
    };
}

function isVisibleRect(rect) {
    return rect && rect.width > 0 && rect.height > 0;
}

export function getTourAnchorRect(name) {
    if (!name) {
        return null;
    }
    for (const provider of providers) {
        try {
            const rect = provider.getTourAnchorRect?.(name);
            if (isVisibleRect(rect)) {
                return rect;
            }
        } catch {
            // Provider may be tearing down
        }
    }
    return null;
}

export function getTourChromeInsets() {
    let bottom = 0;
    for (const provider of providers) {
        try {
            const insets = provider.getTourChromeInsets?.();
            if (insets?.bottom > bottom) {
                bottom = insets.bottom;
            }
        } catch {
            // Provider may be tearing down
        }
    }
    return { bottom };
}

export async function waitForTourAnchorRect(name, { timeoutMs = 5000, intervalMs = 50 } = {}) {
    const start = Date.now();
    return new Promise((resolve) => {
        const tick = () => {
            const rect = getTourAnchorRect(name);
            if (isVisibleRect(rect)) {
                resolve(rect);
                return;
            }
            if (Date.now() - start >= timeoutMs) {
                resolve(null);
                return;
            }
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(tick, intervalMs);
        };
        tick();
    });
}
