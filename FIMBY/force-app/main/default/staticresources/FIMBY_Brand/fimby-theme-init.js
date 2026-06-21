/* FIMBY Theme Init — runs before first paint (head markup).
   Supports three modes stored under 'fimby-theme-pref':
     'light'  → data-theme="light", forces light even if OS is dark
     'dark'   → data-theme="dark",  forces dark even if OS is light
     'auto'   → no data-theme attr, CSS @media (prefers-color-scheme) decides
   The LWC sets data-theme directly via document.documentElement.setAttribute
   (works in EC LWR). This script applies the stored pref on first paint so
   there's no flash-of-wrong-theme on page load.
   Uses cookie as cross-boundary fallback (LWS namespaces localStorage). */
(function () {
  var PREF_KEY = 'fimby-theme-pref';

  function readCookie(name) {
    var escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    var match = document.cookie.match(new RegExp('(?:^|; )' + escaped + '=([^;]*)'));
    return match ? decodeURIComponent(match[1]) : null;
  }

  function writeCookie(name, value) {
    document.cookie = name + '=' + encodeURIComponent(value) + ';path=/;max-age=31536000;SameSite=Lax';
  }

  /* Migrate legacy key if present */
  var legacy = localStorage.getItem('fimby-theme');
  if (legacy && !localStorage.getItem(PREF_KEY)) {
    localStorage.setItem(PREF_KEY, legacy);
    localStorage.removeItem('fimby-theme');
  }

  function notifyNativeShell(pref) {
    try {
      if (window.ReactNativeWebView) {
        // Send the raw preference, not a resolved colour, so the native shell
        // can keep 'auto' and follow the device scheme live. Resolving here
        // would pin native to a stale light/dark on every page load.
        var normalized = (pref === 'dark' || pref === 'light' || pref === 'auto') ? pref : 'auto';
        window.ReactNativeWebView.postMessage(JSON.stringify({
          type: 'themeChange',
          theme: normalized
        }));
      }
    } catch (e) { /* native bridge unavailable */ }
  }

  function applyPref(pref) {
    if (pref === 'dark') {
      document.documentElement.setAttribute('data-theme', 'dark');
    } else if (pref === 'light') {
      document.documentElement.setAttribute('data-theme', 'light');
    } else {
      document.documentElement.removeAttribute('data-theme');
    }
    notifyNativeShell(pref);
  }

  function persistPref(pref) {
    try { localStorage.setItem(PREF_KEY, pref); } catch (e) { /* */ }
    writeCookie(PREF_KEY, pref);
  }

  /* Bridge callable from LWC/LWS context.
     Persists preference in real window scope, then reapplies theme. */
  try {
    window.__fimbySetTheme = function (pref) {
      var normalized = (pref === 'dark' || pref === 'light' || pref === 'auto') ? pref : 'auto';
      persistPref(normalized);
      applyPref(normalized);
    };
  } catch (e) { /* bridge unavailable */ }

  /* Initial apply from stored preference (prevents flash of wrong theme).
     LWS prefixes cookie/localStorage keys with 'LSKey-c$', so check both. */
  var stored = localStorage.getItem(PREF_KEY)
            || readCookie(PREF_KEY)
            || localStorage.getItem('LSKey-c$' + PREF_KEY)
            || readCookie('LSKey-c$' + PREF_KEY);
  if (stored) persistPref(stored);
  applyPref(stored);

  /* Watch for data-theme changes made by LWC (crosses LWS boundary via real DOM) */
  var _observerPref = stored;
  try {
    new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        if (mutations[i].attributeName === 'data-theme') {
          var attr = document.documentElement.getAttribute('data-theme');
          var pref = attr === 'dark' ? 'dark' : attr === 'light' ? 'light' : 'auto';
          if (pref !== _observerPref) {
            _observerPref = pref;
            persistPref(pref);
            notifyNativeShell(pref);
          }
          break;
        }
      }
    }).observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
  } catch (e) { /* MutationObserver unavailable */ }
})();
