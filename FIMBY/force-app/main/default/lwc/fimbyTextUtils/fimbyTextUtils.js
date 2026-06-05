/**
 * Decode HTML entities in plain text from Salesforce (e.g. &amp; → &).
 * Uses DOMParser instead of textarea.innerHTML (disallowed in LWC).
 */
export function decodeHtmlEntities(text) {
    if (text == null || text === '') {
        return '';
    }
    const doc = new DOMParser().parseFromString(String(text), 'text/html');
    return doc.documentElement.textContent ?? '';
}
