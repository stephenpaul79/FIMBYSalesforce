/**
 * expo-router native intent handler.
 *
 * Universal Links to app.fimby.com (e.g. https://app.fimby.com/conversation?id=...)
 * are NOT file-based routes — the app has a single `index` route that owns the
 * splash/auth flow and drives the WebView. The actual deep-link path is read in
 * `index.tsx` via Linking.getInitialURL()/'url' events and handed to the WebView
 * through the frontdoor `ret` param.
 *
 * Without this redirect, expo-router tries to match `/conversation` against the
 * route tree, finds nothing, and lands on an unmatched/blank screen — so an
 * email-link cold start hangs on the native splash (centered logo) instead of
 * booting `index`. Sending every app.fimby.com path back to `/` keeps the boot
 * flow intact while index.tsx handles the deep link.
 *
 * The custom OAuth scheme (fimbymobileapp://oauth/callback) needs the same
 * treatment on Android: unlike iOS (where ASWebAuthenticationSession captures
 * the redirect internally and it never becomes an OS deep link), Android fires
 * the callback as an intent that re-enters the app and flows through the router.
 * The router has no `/oauth/callback` route, so it renders Unmatched Route.
 * expo-web-browser's auth-session listener (WebBrowser.maybeCompleteAuthSession
 * in index.tsx) consumes the `code` from the redirect URL directly, so the
 * router must not try to match the path — send it to `/` like app.fimby.com.
 */
export function redirectSystemPath({
  path,
}: {
  path: string;
  initial: boolean;
}): string {
  try {
    if (path.includes("oauth/callback") || path.includes("app.fimby.com")) {
      return "/";
    }
  } catch {
    return "/";
  }
  return path;
}
