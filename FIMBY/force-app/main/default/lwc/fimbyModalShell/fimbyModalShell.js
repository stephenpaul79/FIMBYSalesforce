/**
 * Site-wide modal scrim mounted in fimbyUniversalHeader so fixed overlays
 * in the content region can dim the sticky header (LWR theme stacking).
 */
export const SHELL_SCRIM_OPEN = 'fimbyshellscrimopen';
export const SHELL_SCRIM_CLOSE = 'fimbyshellscrimclose';
export const SHELL_SCRIM_DISMISS = 'fimbyshellscrimdismiss';

let _refCount = 0;

export function acquireShellScrim() {
    _refCount += 1;
    if (_refCount === 1) {
        window.dispatchEvent(new CustomEvent(SHELL_SCRIM_OPEN));
    }
}

export function releaseShellScrim() {
    if (_refCount <= 0) {
        return;
    }
    _refCount -= 1;
    if (_refCount === 0) {
        window.dispatchEvent(new CustomEvent(SHELL_SCRIM_CLOSE));
    }
}

export function subscribeShellScrimDismiss(handler) {
    window.addEventListener(SHELL_SCRIM_DISMISS, handler);
    return () => window.removeEventListener(SHELL_SCRIM_DISMISS, handler);
}

export function dispatchShellScrimDismiss() {
    window.dispatchEvent(new CustomEvent(SHELL_SCRIM_DISMISS));
}

/** Call when opening a modal; returns cleanup to run in hide/close. */
export function bindShellScrimDismiss(onDismiss) {
    acquireShellScrim();
    const unsub = subscribeShellScrimDismiss(onDismiss);
    return () => {
        unsub();
        releaseShellScrim();
    };
}

/** Per-modal ref holder — use as a class field: _shellScrim = createShellScrimHandle(); */
export function createShellScrimHandle() {
    let release = null;
    const clear = () => {
        if (release) {
            release();
            release = null;
        }
    };
    return {
        bind(onDismiss) {
            clear();
            release = bindShellScrimDismiss(onDismiss);
        },
        clear,
        /** For template-driven overlays — call from renderedCallback when a flag toggles. */
        sync(isOpen, onDismiss) {
            if (isOpen) {
                if (!release) {
                    release = bindShellScrimDismiss(onDismiss);
                }
            } else {
                clear();
            }
        }
    };
}
