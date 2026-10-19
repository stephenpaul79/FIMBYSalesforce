/**
 * Three-zone dim (LWR): header bar + content modal backdrop + footer bar,
 * synced via ref-counted open/close events. No full-viewport layer in the
 * header or on document.body — those stack above content modals.
 */
export const SHELL_SCRIM_OPEN = 'fimbyshellscrimopen';
export const SHELL_SCRIM_CLOSE = 'fimbyshellscrimclose';
export const SHELL_SCRIM_DISMISS = 'fimbyshellscrimdismiss';

const MODAL_HOST_Z_INDEX = '10051';

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

/** Lift modal host above shell scrims and sticky in-page chrome (feed filters z-index 200). */
export function setModalHostElevated(hostElement, elevated) {
    if (!hostElement) {
        return;
    }
    if (elevated) {
        hostElement.style.setProperty('position', 'relative');
        hostElement.style.setProperty('z-index', MODAL_HOST_Z_INDEX);
    } else {
        hostElement.style.removeProperty('position');
        hostElement.style.removeProperty('z-index');
    }
}

/** Call when opening a modal; returns cleanup to run in hide/close. */
export function bindShellScrimDismiss(onDismiss, hostElement = null) {
    acquireShellScrim();
    setModalHostElevated(hostElement, true);
    const unsub = subscribeShellScrimDismiss(onDismiss);
    return () => {
        unsub();
        setModalHostElevated(hostElement, false);
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
        bind(onDismiss, hostElement = null) {
            clear();
            release = bindShellScrimDismiss(onDismiss, hostElement);
        },
        clear,
        /** For template-driven overlays — call from renderedCallback when a flag toggles. */
        sync(isOpen, onDismiss, hostElement = null) {
            if (isOpen) {
                if (!release) {
                    release = bindShellScrimDismiss(onDismiss, hostElement);
                }
            } else {
                clear();
            }
        }
    };
}
