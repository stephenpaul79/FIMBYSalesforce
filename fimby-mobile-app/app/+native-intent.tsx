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
 * Note: the custom OAuth scheme (fimbymobileapp://oauth/callback) and any other
 * URL pass through untouched.
 */
export function redirectSystemPath({
  path,
}: {
  path: string;
  initial: boolean;
}): string {
  try {
    if (path.includes("app.fimby.com")) {
      return "/";
    }
  } catch {
    return "/";
  }
  return path;
}
