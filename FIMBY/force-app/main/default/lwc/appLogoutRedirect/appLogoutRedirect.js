import { LightningElement } from 'lwc';

export default class AppLogoutRedirect extends LightningElement {
  connectedCallback() {
    // Prevent Experience Builder / Live Preview from crashing
    if (this.isInBuilder()) {
      return;
    }

    // Try deep link back to the mobile app
    try {
      window.location.assign('fimby://logout');
    } catch (e) {
      // ignore
    }

    // Fallback for browsers
    window.setTimeout(() => {
      try {
        window.location.assign('/login');
      } catch (e) {
        window.location.href = '/login';
      }
    }, 800);
  }

  isInBuilder() {
    try {
      const host = window.location.hostname || '';
      const path = window.location.pathname || '';

      // Typical Builder/live preview signals
      if (host.includes('live-preview')) return true;
      if (path.includes('/webruntime/design/')) return true;

      return false;
    } catch (e) {
      return false;
    }
  }
}