/**
 * Sets --sticky-top on a component host from the Experience Cloud page header.
 * The shell header lives outside LWC shadow roots; document query is required once per page.
 */
export function applyStickyHeaderOffset(hostElement) {
    if (!hostElement) {
        return;
    }
    let height = 0;
    try {
        // eslint-disable-next-line @lwc/lwc/no-document-query -- page shell header is outside shadow DOM
        const header = document.querySelector('header.sticky-header');
        if (header) {
            height = header.getBoundingClientRect().height;
        }
    } catch {
        /* Experience Cloud locker */
    }
    hostElement.style.setProperty('--sticky-top', `${height}px`);
}
