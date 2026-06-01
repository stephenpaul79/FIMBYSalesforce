import * as AuthSession from "expo-auth-session";
import * as Notifications from "expo-notifications";
import * as SecureStore from "expo-secure-store";
import * as WebBrowser from "expo-web-browser";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { useVideoPlayer, VideoView } from "expo-video";
import { useEventListener } from "expo";
import { StatusBar } from "expo-status-bar";
import { Stack } from "expo-router";
import * as Linking from "expo-linking";
import React, { useRef, useCallback } from "react";
import {
  AccessibilityInfo,
  ActivityIndicator,
  Alert,
  Animated,
  AppState,
  Image,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { WebView, WebViewNavigation } from "react-native-webview";
import type { ShouldStartLoadRequest } from "react-native-webview/lib/WebViewTypes";
import type { WebViewErrorEvent, WebViewHttpErrorEvent, WebViewMessageEvent } from "react-native-webview/lib/WebViewTypes";
import {
  usePushNotifications,
  getLastNotificationResponse,
  clearLastNotificationResponse,
  NotificationData,
} from "../hooks/use-push-notifications";
import { log, warn } from "../lib/log";

// Splash video asset
const SPLASH_VIDEO = require("../assets/Fimby_Startup.mp4");

// Hero logo (full FIMBY lockup: house + wordmark + tree) for the pre-auth screen.
// Time-of-day variants (all 1024x358 transparent PNGs): morning has a sunrise +
// birdsong, day has the full sun, evening has a moon, stars, and a sleeping owl.
const LOGO_MORNING = require("../assets/images/FIMBYLogoTransparentLight.png");
const LOGO_DAY = require("../assets/images/FIMBYLogoTransparent.png");
const LOGO_EVENING = require("../assets/images/FIMBYLogoTransparentDark.png");
// All three lockups are 1024x358; pin the ratio so the box can't balloon
// (a runtime asset lookup once returned bad dims and overflowed the section).
const HERO_LOGO_ASPECT = 1024 / 358;

// Downward nudge (px) so the three-section stack reads optically centered
// (top gap was ~250, bottom ~350; +50 evens them to ~300/300).
const PREAUTH_VERTICAL_NUDGE = 50;

// Pick the hero logo by the device's local time (whimsy, independent of theme):
//   morning 5:00-10:59, day 11:00-18:59, evening 19:00-04:59
function getTimeOfDayLogo() {
  const h = new Date().getHours();
  if (h >= 5 && h < 11) return LOGO_MORNING;
  if (h >= 11 && h < 19) return LOGO_DAY;
  return LOGO_EVENING;
}

// No wifi icon for network errors
const NO_WIFI_ICON = require("../assets/images/nowifi.png");

// Panda sleeping: video (primary) and static image (fallback on error)
const PANDA_SLEEPING_VIDEO = require("../assets/panda-sleeping.mp4");
const PANDA_SLEEPING = require("../assets/images/panda-sleeping.png");

const THEME_COLORS = {
  light: { statusBar: '#FAF7F2', barStyle: 'dark' as const },
  dark:  { statusBar: '#1B1512', barStyle: 'light' as const },
} as const;

// Warm pre-auth palette (from FIMBY_Brand/fimby-tokens.css). Applied inline
// since StyleSheet.create is static and these switch by theme.
const PREAUTH_COLORS = {
  light: {
    bg: '#FAF7F2',          // cream surface-card
    heading: '#261A11',     // espresso text-strong
    secondary: '#8B7355',   // bronze text-secondary (tagline / status / footer)
    primaryBg: '#3A7D8C',   // teal CTA fill
    primaryText: '#FFFFFF',
    signUpOutline: '#4B3627', // espresso outline border + text
    spinner: '#3A7D8C',
  },
  dark: {
    bg: '#14100D',          // espresso surface-page
    heading: '#FFFBF7',     // text-strong (dark)
    secondary: '#D6CFC7',   // text-secondary (dark)
    primaryBg: '#3A7D8C',
    primaryText: '#FFFFFF',
    signUpOutline: '#D6CFC7', // warm sand outline for contrast on near-black
    spinner: '#67BBD2',
  },
} as const;

// Splash + pre-video continuity background — matches the animation's canvas so
// there is no color flash at launch.
const SPLASH_BG = '#F0EBE3';

const THEME_STORAGE_KEY = 'fimby_app_theme';

const FAREWELL_MESSAGES = [
  "Sweet dreams, neighbour.",
  "Night night! See you in the morning.",
  "See you when the sun comes up.",
  "Adieu, adieu -- to you and you and you.",
  "Goodnight, moon. Goodnight, neighbour.",
];

const QUIET_WINDOWS: Record<string, [number, number] | null> = {
  "9PM_5AM": [21, 5],
  "10PM_6AM": [22, 6],
  "11PM_7AM": [23, 7],
  "12AM_8AM": [0, 8],
  NONE: null,
};

function isInQuietHours(pref: string): boolean {
  const window = QUIET_WINDOWS[pref];
  if (!window) return false;
  const [start, end] = window;
  const hour = new Date().getHours();
  if (start > end) return hour >= start || hour < end;
  if (start === 0) return hour < end;
  return hour >= start && hour < end;
}

// Use your Vercel backend base URL
const BACKEND_BASE_URL = "https://fimby-auth-bridge.vercel.app";

// Salesforce Experience Cloud auth host (no trailing slash)
const SF_AUTH_HOST = "https://fimby.my.site.com";

// Key names in SecureStore
const REFRESH_KEY = "fimby_refresh_token";

// Endpoints
const BACKEND_LOGIN_URL = `${BACKEND_BASE_URL}/api/login`;
const BACKEND_REFRESH_URL = `${BACKEND_BASE_URL}/api/session/refresh`;
const BACKEND_FRONTDOOR_URL = `${BACKEND_BASE_URL}/api/frontdoor`;
const BACKEND_LOGOUT_URL = `${BACKEND_BASE_URL}/api/logout`;

// Public marketing/onboarding URLs opened in the in-app browser sheet
const SIGN_UP_URL = "https://our.fimby.com/sign-up";
const HELP_URL = "https://fimby.com/help/";
const FAQ_URL = "https://fimby.com/faq/";

// URL to intercept as logout trigger from Experience Cloud
// When SF session expires or user logs out, it redirects to the community login page
const FIMBY_LOGIN_INTERCEPT_URL = "https://fimby.my.site.com/login";

// Boundary-aware match: intercept `/login`, `/login?…`, `/login#…`, `/login/…`
// but NOT `/login-handler`, `/login2`, etc. Plain `startsWith` used to match
// those and kick the user back to the native splash screen.
function isFimbyLoginRedirect(url: string): boolean {
  const base = FIMBY_LOGIN_INTERCEPT_URL;
  if (url === base) return true;
  if (url.startsWith(base + "?")) return true;
  if (url.startsWith(base + "#")) return true;
  if (url.startsWith(base + "/")) return true;
  return false;
}

// WebView origin allowlist. Anything outside this set is handed off to the
// system browser so the FIMBY Experience Cloud session cookie is never
// exposed to third-party sites a neighbour clicks through to.
//
// Pinned to FIMBY's own Salesforce org (MyDomain "fimby") rather than every
// tenant on the platform: under Enhanced Domains every Salesforce host keeps
// the org prefix (fimby.* or fimby--<pkg>.*), so an attacker controlling some
// other org's *.my.site.com / *.lightning.force.com can no longer load a
// look-alike page inside the trusted app chrome.
const WEBVIEW_ALLOWED_HOST_PATTERNS: RegExp[] = [
  // Experience Cloud community + org + Lightning (Enhanced Domains).
  /^fimby\.my\.site\.com$/i,
  /^fimby\.my\.salesforce\.com$/i,
  /^fimby\.lightning\.force\.com$/i,
  // Visualforce / file / content delivery (may carry a "--<pkg>" suffix).
  /^fimby(?:--[a-z0-9]+)?\.vf\.force\.com$/i,
  /^fimby(?:--[a-z0-9]+)?\.file\.force\.com$/i,
  /^fimby(?:--[a-z0-9]+)?\.content\.force\.com$/i,
  /^fimby(?:--[a-z0-9]+)?\.documentforce\.com$/i,
  // Embedded chat / Live Agent hosts are instance-scoped, not tenant-prefixed.
  /^[a-z0-9-]+\.salesforceliveagent\.com$/i,
  // Salesforce global SSO host. The frontdoor /singleaccess flow bounces the
  // session through https://login.salesforce.com/login/sessionserver*.html to
  // bridge the cookie. This is the single platform-wide login host (not a
  // tenant-prefixed Experience Cloud / Lightning origin), so it cannot be a
  // cross-org look-alike. Without it that hop gets ejected to the system
  // browser mid-login.
  /^login\.salesforce\.com$/i,
  // FIMBY-owned domains (custom community domain our.fimby.com, app.fimby.com,
  // marketing fimby.com, etc.).
  /^(?:[^.]+\.)*fimby\.com$/i,
];

function isAllowedWebViewUrl(rawUrl: string): boolean {
  // about:blank is the only non-https scheme we permit — the WebView itself
  // uses it during loads. data:, blob:, javascript:, file:, http:, and custom
  // schemes are all rejected so they can never execute script in the trusted
  // app chrome or be handed the Experience Cloud session cookie.
  if (rawUrl === "about:blank") return true;
  try {
    const u = new URL(rawUrl);
    if (u.protocol !== "https:") return false;
    return WEBVIEW_ALLOWED_HOST_PATTERNS.some((rx) => rx.test(u.hostname));
  } catch {
    return false;
  }
}

// Universal Link host. Tapping any https://app.fimby.com/<path> link from
// outside the app should land the user on the matching Experience Cloud page
// inside the WebView. AASA + Android intent filter on this exact host.
const APP_LINK_HOST = "app.fimby.com";

// Extract the in-app navigation path from an inbound Universal Link / App Link.
// Returns the `path + search + hash` portion (always starts with `/`) or null
// if the URL is not a FIMBY deep link we should act on.
//
// `/oauth/callback` is intentionally excluded — those URLs are handled by
// expo-auth-session via the `fimbymobileapp://` custom scheme; if a Universal
// Link to /oauth/callback ever fires (rare; user manually visited it), we
// don't want the deep-link handler to push it into the WebView.
function parseFimbyDeepLink(rawUrl: string): string | null {
  try {
    const u = new URL(rawUrl);
    if (u.protocol !== "https:") return null;
    if (u.hostname.toLowerCase() !== APP_LINK_HOST) return null;
    if (u.pathname === "/oauth/callback") return null;
    const path = u.pathname + u.search + u.hash;
    // Auth-bridge ret validator requires a leading '/' and rejects protocol-
    // relative shapes ('//...'). pathname always starts with '/' so this is
    // defense in depth.
    if (!path.startsWith("/") || path.startsWith("//")) return null;
    return path;
  } catch {
    return null;
  }
}

// Your Salesforce PKCE Connected App Client Id (Public client)
const SF_PKCE_CLIENT_ID =
  "3MVG9p1Q1BCe9GmAritiW5LdGnQ5D.mAz06DvuBuDIjAQFVoo7meaVL8frF_wqAhScnkYePDt4XndVqdUooO8";

/**
 * Redirect URI for OAuth callback.
 *
 * Uses the custom scheme `fimbymobileapp://oauth/callback`. PKCE + the
 * ephemeral `ASWebAuthenticationSession` browser protect against scheme-
 * hijacking attacks (intercepted codes cannot be redeemed without the
 * `code_verifier`, which never leaves this app's memory).
 *
 * The Universal Link / App Link infrastructure (AASA at app.fimby.com,
 * `ios.associatedDomains`, Android `intentFilters`, Salesforce Connected App
 * callback entry) is kept in place as scaffolding. When we upgrade to
 * Expo SDK 56+ (which ships the `preferUniversalLinks` opt-in on
 * `ASWebAuthenticationSession.https(host:path:)` — see expo/expo #44452),
 * switch this back to:
 *
 *   AuthSession.makeRedirectUri({ native: "https://app.fimby.com/oauth/callback" })
 *
 * and pass `preferUniversalLinks: true` to `promptAsync`.
 */
const redirectUri = AuthSession.makeRedirectUri({
  scheme: "fimbymobileapp",
  path: "oauth/callback",
});

WebBrowser.maybeCompleteAuthSession();

type TokenResponse = {
  access_token: string;
  refresh_token: string;
  token_type?: string;
  expires_in?: number;
};

function isJwtLike(token: string) {
  return token.split(".").length === 3;
}

// Server sets data.channelId ('messages' | 'activity' | 'default') in
// FimbyPushBatchJob, plus notification_type on single sends. We map that to
// a small hardcoded route allowlist — no free-form input ever reaches the
// WebView. Anything unknown falls back to the generic notifications list.
function resolvePushRoute(data: NotificationData | null | undefined): string {
  const channel = typeof data?.channelId === "string" ? data.channelId : "";
  if (channel === "messages") return "/messages";
  const notifType = typeof data?.notification_type === "string" ? data.notification_type : "";
  if (notifType.toUpperCase() === "MESSAGE") return "/messages";
  return "/notifications";
}

async function jsonOrText(res: Response) {
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

export default function IndexScreen() {
  // Theme state — synced from WebView via postMessage, persisted in AsyncStorage
  const [appTheme, setAppTheme] = React.useState<'light' | 'dark'>('light');

  React.useEffect(() => {
    AsyncStorage.getItem(THEME_STORAGE_KEY).then(stored => {
      if (stored === 'dark' || stored === 'light') setAppTheme(stored);
    }).catch(() => {});
  }, []);

  // Splash video state - track separately so bootstrap can run in parallel
  const [splashVideoComplete, setSplashVideoComplete] = React.useState(false);

  const [booting, setBooting] = React.useState(true);
  const [busy, setBusy] = React.useState(false);
  const [accessToken, setAccessToken] = React.useState<string | null>(null);
  const [status, setStatus] = React.useState<string>("Waking up…");

  // Track bootstrap errors for retry functionality
  const [bootstrapError, setBootstrapError] = React.useState<'network' | 'other' | null>(null);

  // WebView state
  const [webViewUrl, setWebViewUrl] = React.useState<string | null>(null);
  const [webViewError, setWebViewError] = React.useState<string | null>(null);

  // Panda Screen state
  const [showPanda, setShowPanda] = React.useState(false);
  const [pandaFarewell, setPandaFarewell] = React.useState<string | null>(null);
  const [pandaEscapeVisible, setPandaEscapeVisible] = React.useState(false);
  const [pandaVideoFailed, setPandaVideoFailed] = React.useState(false);
  const [pandaVideoReady, setPandaVideoReady] = React.useState(false);
  const pandaEscapeFade = useRef(new Animated.Value(0)).current;
  const pandaCheckedRef = useRef(false);
  const pandaVideoReadyRef = useRef(false);
  const pandaVideoFallbackTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Panda video player (looping) - used when showPanda is true
  const pandaPlayer = useVideoPlayer(PANDA_SLEEPING_VIDEO, (player) => {
    player.loop = true;
  });

  useEventListener(pandaPlayer, "statusChange", ({ status }) => {
    if (status === "readyToPlay") {
      setPandaVideoReady(true);
      return;
    }
    if (status === "error") {
      setPandaVideoFailed(true);
    }
  });

  React.useEffect(() => {
    pandaVideoReadyRef.current = pandaVideoReady;
  }, [pandaVideoReady]);

  React.useEffect(() => {
    if (pandaVideoFallbackTimeoutRef.current) {
      clearTimeout(pandaVideoFallbackTimeoutRef.current);
      pandaVideoFallbackTimeoutRef.current = null;
    }

    if (showPanda) {
      setPandaVideoReady(false);
      if (!pandaVideoFailed) {
        pandaPlayer.play();
        // Fallback if player never reaches ready state or error state.
        pandaVideoFallbackTimeoutRef.current = setTimeout(() => {
          if (!pandaVideoReadyRef.current) {
            setPandaVideoFailed(true);
          }
        }, 3000);
      }
    } else {
      setPandaVideoFailed(false); // Reset so next time we try video again
      setPandaVideoReady(false);
    }

    return () => {
      if (pandaVideoFallbackTimeoutRef.current) {
        clearTimeout(pandaVideoFallbackTimeoutRef.current);
        pandaVideoFallbackTimeoutRef.current = null;
      }
    };
  }, [showPanda, pandaVideoFailed, pandaPlayer]);

  React.useEffect(() => {
    if (pandaVideoReady && pandaVideoFallbackTimeoutRef.current) {
      clearTimeout(pandaVideoFallbackTimeoutRef.current);
      pandaVideoFallbackTimeoutRef.current = null;
    }
  }, [pandaVideoReady]);

  // Fade-in animation for coordinated content appearance
  const fadeAnim = useRef(new Animated.Value(0)).current;

  // Themed overlay opacity, faded in during the splash video's built-in fade-out
  const splashFadeAnim = useRef(new Animated.Value(0)).current;
  const splashFadeStartedRef = useRef(false);

  // Deferred alert to show after splash video completes
  const pendingAlertRef = useRef<{ title: string; message: string } | null>(null);

  // Create video player for splash screen
  const splashPlayer = useVideoPlayer(SPLASH_VIDEO, (player) => {
    player.loop = false;
    player.timeUpdateEventInterval = 0.25;
    player.play();
  });

  // Handle splash video completion using expo-video event system
  useEventListener(splashPlayer, "playToEnd", () => {
    setSplashVideoComplete(true);
  });

  // Sync a themed color overlay to the video's built-in fade-out (~4.15s -> ~5.0s)
  // so the animation dissolves into the destination screen instead of hard-cutting.
  useEventListener(splashPlayer, "timeUpdate", ({ currentTime }) => {
    if (splashFadeStartedRef.current || currentTime < 4.15) return;
    splashFadeStartedRef.current = true;
    Animated.timing(splashFadeAnim, {
      toValue: 1,
      duration: 750,
      useNativeDriver: true,
    }).start();
  });

  // Splash video timeout fallback - ensures user is never stuck on splash
  React.useEffect(() => {
    const timeout = setTimeout(() => {
      if (!splashVideoComplete) {
        warn("Splash video timeout - forcing completion");
        setSplashVideoComplete(true);
      }
    }, 10000); // 10 seconds max

    return () => clearTimeout(timeout);
  }, [splashVideoComplete]);

  // Show deferred alerts after splash completes
  React.useEffect(() => {
    if (splashVideoComplete && pendingAlertRef.current) {
      const { title, message } = pendingAlertRef.current;
      pendingAlertRef.current = null;
      Alert.alert(title, message);
    }
  }, [splashVideoComplete]);

  // Coordinated fade-in animation when splash completes
  React.useEffect(() => {
    if (splashVideoComplete) {
      Animated.timing(fadeAnim, {
        toValue: 1,
        duration: 400,
        useNativeDriver: true,
      }).start();
    }
  }, [splashVideoComplete, fadeAnim]);

  // Panda Screen: check quiet hours on cold launch (before auth)
  React.useEffect(() => {
    if (pandaCheckedRef.current) return;
    pandaCheckedRef.current = true;

    (async () => {
      const pref = (await AsyncStorage.getItem("fimby_quiet_hours")) || "10PM_6AM";
      if (pref === "NONE") return;

      const today = new Date().toDateString();
      const lastPandaDate = await AsyncStorage.getItem("lastPandaDate");
      if (lastPandaDate === today) return;

      if (isInQuietHours(pref)) {
        setShowPanda(true);
      }
    })();
  }, []);

  // AppState listener: if user returns from background after quiet hours end, dismiss panda
  React.useEffect(() => {
    if (!showPanda) return;
    const sub = AppState.addEventListener("change", async (state) => {
      if (state === "active") {
        const pref = (await AsyncStorage.getItem("fimby_quiet_hours")) || "10PM_6AM";
        if (!isInQuietHours(pref)) {
          setShowPanda(false);
          setPandaFarewell(null);
        }
      }
    });
    return () => sub.remove();
  }, [showPanda]);

  // ✅ Guard and PKCE verifier capture (fixes invalid_grant from mismatched verifier)
  // Store the processed auth code (not just boolean) to detect stale responses after logout
  const handledAuthCodeRef = React.useRef<string | null>(null);
  const pkceVerifierRef = React.useRef<string | null>(null);

  // ✅ Guard to prevent logout interception loops
  const logoutInProgressRef = useRef(false);

  // ✅ Guard to prevent bootstrap from running multiple times
  const bootstrapRanRef = useRef(false);

  // Pending Universal Link path captured before the WebView is ready or before
  // the user has signed in. Consumed by openFimby() the next time it mints a
  // frontdoor URL, so the user lands directly on the deep-linked page.
  const pendingDeepLinkRef = useRef<string | null>(null);

  // WebView ref for deep linking from notifications
  const webViewRef = useRef<WebView>(null);
  // After a push launch is handled (or none pending), skip cold-start re-checks on later loadEnd events.
  const coldStartPushHandledRef = useRef(false);

  // Keep the latest access token in a ref so WebView message handlers (whose
  // useCallback deps stay []) never read a stale/null token from closure.
  const accessTokenRef = useRef<string | null>(null);
  React.useEffect(() => {
    accessTokenRef.current = accessToken;
  }, [accessToken]);

  // Holds an access token when push is wanted but OS permission is still
  // undetermined at login. The first-time permission prompt is deferred out of
  // the login/frontdoor handoff and fired once the WebView is stable (onLoadEnd)
  // to avoid backgrounding the app mid-navigation. Cleared after it fires.
  const pendingPushPromptRef = useRef<string | null>(null);

  const navigateFromPush = useCallback(
    (data: NotificationData): boolean => {
      if (!webViewUrl || !webViewRef.current) {
        return false;
      }
      const path = resolvePushRoute(data);
      webViewRef.current.injectJavaScript(
        `window.location.assign(${JSON.stringify(`${SF_AUTH_HOST}${path}`)}); true;`
      );
      return true;
    },
    [webViewUrl]
  );

  const finishPushLaunch = useCallback(async () => {
    coldStartPushHandledRef.current = true;
    await clearLastNotificationResponse();
  }, []);

  // ─────────────────────────────────────────────────────────────────────────────
  // PUSH NOTIFICATIONS
  // ─────────────────────────────────────────────────────────────────────────────
  const {
    registerForPushNotifications,
    registerTokenWithBackend,
    unregisterTokenFromBackend,
    shouldPromptForPermission,
    clearBadge,
  } = usePushNotifications({
    onNotificationReceived: (notification) => {
      log("[PUSH] Notification received in foreground:", notification.request.content.title);
    },
    onNotificationTapped: (data: NotificationData) => {
      // Per humane-push plan, payloads never carry a free-form URL. The
      // client maps the server-set channelId (or notification_type) to a
      // small, hardcoded route allowlist. Anything unknown falls back to
      // the generic /notifications list.
      if (navigateFromPush(data)) {
        void finishPushLaunch();
      }
    },
  });

  // Register push notifications after successful login.
  // prompt=false (the default on the login/app-open path) registers only when
  // permission is already granted, so the OS permission dialog never fires
  // mid-login. A first-time prompt is deferred to a stable moment (see
  // pendingPushPromptRef / maybeRunDeferredPushPrompt).
  const registerPushNotificationsAsync = useCallback(
    async (token: string, opts: { prompt?: boolean } = {}) => {
      const { prompt = false } = opts;
      try {
        const pushToken = await registerForPushNotifications({ prompt });
        if (pushToken) {
          await registerTokenWithBackend(token, pushToken);
        }
        return pushToken;
      } catch (e: any) {
        log("[PUSH] Error during push registration:", e?.message);
        // Don't fail login if push registration fails
        return null;
      }
    },
    [registerForPushNotifications, registerTokenWithBackend]
  );

  // Sync device push registration with the master toggle the user just flipped
  // in the in-WebView Settings screen. Enable: acquire OS permission + token and
  // register it. Disable: delete the token so no more pushes arrive. If the OS
  // permission is denied/blocked on enable, tell the LWC so it reverts the toggle
  // (SF stays in sync with device reality). Reads the token from a ref to avoid a
  // stale closure.
  const syncPushRegistration = useCallback(
    async (enabled: boolean) => {
      const token = accessTokenRef.current;
      if (!token) {
        log("[PUSH] syncPushRegistration skipped: no access token");
        return;
      }
      try {
        if (enabled) {
          const pushToken = await registerForPushNotifications();
          if (pushToken) {
            await registerTokenWithBackend(token, pushToken);
          } else {
            // Permission denied/blocked — ask the WebView to revert the toggle.
            webViewRef.current?.injectJavaScript(
              "window.__fimbyPushResult && window.__fimbyPushResult({granted:false}); true;"
            );
          }
        } else {
          await unregisterTokenFromBackend(token);
          Notifications.dismissAllNotificationsAsync().catch(() => {});
          Notifications.setBadgeCountAsync(0).catch(() => {});
        }
      } catch (e: any) {
        log("[PUSH] syncPushRegistration error:", e?.message);
      }
    },
    [registerForPushNotifications, registerTokenWithBackend, unregisterTokenFromBackend]
  );

  // Reconcile the device token with the user's Salesforce push preference on
  // every app open / re-auth. The frontdoor response carries
  // pushNotificationsEnabled. When the user opted out (possibly on desktop web
  // while the app was closed), delete any stale token; otherwise register.
  // Undefined/null is treated as enabled to match the User field default and to
  // stay safe against older bridge responses.
  const reconcilePushRegistration = useCallback(
    async (token: string, pushEnabled: boolean | null | undefined) => {
      if (pushEnabled === false) {
        await unregisterTokenFromBackend(token).catch(() => {});
        return;
      }
      // Register without prompting so the OS dialog can't fire during the
      // login/frontdoor handoff. If permission is already granted this registers
      // the token immediately. If it's still undetermined, queue the first-time
      // prompt for after the WebView settles. If it's denied, do nothing (the
      // user already declined — respect that).
      const pushToken = await registerPushNotificationsAsync(token, { prompt: false });
      if (!pushToken && (await shouldPromptForPermission())) {
        pendingPushPromptRef.current = token;
      }
    },
    [registerPushNotificationsAsync, unregisterTokenFromBackend, shouldPromptForPermission]
  );

  // Fire the deferred first-time permission prompt once the WebView is stable.
  // Guarded by the ref so it runs a single time even though onLoadEnd fires on
  // every navigation. If permission is granted the token is registered; if the
  // user denies, syncPushRegistration's denial path isn't involved here — we
  // simply leave the SF toggle as-is since this is the passive login path.
  const maybeRunDeferredPushPrompt = useCallback(async () => {
    const token = pendingPushPromptRef.current;
    if (!token) return;
    pendingPushPromptRef.current = null;
    await registerPushNotificationsAsync(token, { prompt: true });
  }, [registerPushNotificationsAsync]);

  // Hardening: Expo can rotate the push token mid-session. Re-register the new
  // token with the backend so a long-lived session keeps receiving pushes
  // without waiting for the next cold start. Only acts when signed in.
  React.useEffect(() => {
    const sub = Notifications.addPushTokenListener((tokenData) => {
      const token = accessTokenRef.current;
      if (token && tokenData?.data) {
        log("[PUSH] Expo token rotated; re-registering");
        registerTokenWithBackend(token, tokenData.data).catch(() => {});
      }
    });
    return () => {
      try {
        sub.remove();
      } catch {
        // Safe to ignore (e.g. Expo Go)
      }
    };
  }, [registerTokenWithBackend]);

  // Salesforce OAuth discovery endpoints for Experience Cloud host
  const discovery = React.useMemo(
    () => ({
      authorizationEndpoint: `${SF_AUTH_HOST}/services/oauth2/authorize`,
      tokenEndpoint: `${SF_AUTH_HOST}/services/oauth2/token`,
      revocationEndpoint: `${SF_AUTH_HOST}/services/oauth2/revoke`,
    }),
    []
  );

  // PKCE request
  const [request, response, promptAsync] = AuthSession.useAuthRequest(
    {
      clientId: SF_PKCE_CLIENT_ID,
      responseType: AuthSession.ResponseType.Code,
      scopes: ["openid", "profile", "email"],
      redirectUri,
      usePKCE: true,
    },
    discovery
  );

  /**
   * ========= BACKEND CALLS =========
   */

  /**
   * Refresh session with proper handling for session_expired
   * Returns: { token, sessionExpired, message }
   * - token: new access token if successful, null otherwise
   * - sessionExpired: true if session TTL exceeded (user needs to re-login)
   * - message: user-friendly message from backend (for session_expired)
   */
  const refreshSession = React.useCallback(async (): Promise<{
    token: string | null;
    sessionExpired?: boolean;
    message?: string;
  }> => {
    const refresh = await SecureStore.getItemAsync(REFRESH_KEY);
    if (!refresh) return { token: null };

    setStatus("Freshening up…");
    log("Calling /api/session/refresh at:", BACKEND_REFRESH_URL);
    const res = await fetch(BACKEND_REFRESH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: refresh }),
    });

    if (!res.ok) {
      const body = await jsonOrText(res);
      log("Refresh failed:", body);
      await SecureStore.deleteItemAsync(REFRESH_KEY);

      // Check for session_expired - return the user-friendly message
      if (body?.error === "session_expired") {
        return {
          token: null,
          sessionExpired: true,
          message: body?.error_description || "Your session has expired. Please sign in again.",
        };
      }

      return { token: null };
    }

    const data = (await res.json()) as TokenResponse;

    if (!data?.access_token || !data?.refresh_token) {
      log("Refresh returned unexpected payload:", data);
      await SecureStore.deleteItemAsync(REFRESH_KEY);
      return { token: null };
    }

    await SecureStore.setItemAsync(REFRESH_KEY, data.refresh_token);
    setAccessToken(data.access_token);

    log("[AUTH] refresh successful");

    return { token: data.access_token };
  }, []);

  const loginWithBackend = React.useCallback(async (code: string, codeVerifier: string) => {
    if (!codeVerifier) {
      throw new Error("Missing PKCE codeVerifier.");
    }

    setStatus("Doing the secret handshake…");
    log("Calling /api/login at:", BACKEND_LOGIN_URL);

    const res = await fetch(BACKEND_LOGIN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        code,
        code_verifier: codeVerifier,
        redirect_uri: redirectUri,
      }),
    });

    if (!res.ok) {
      const body = await jsonOrText(res);
      log("Backend /api/login failed:", body);
      throw new Error("Login failed. See logs.");
    }

    const data = (await res.json()) as TokenResponse;

    if (!data?.access_token || !data?.refresh_token) {
      log("Backend /api/login unexpected payload:", data);
      throw new Error("Login payload missing tokens.");
    }

    await SecureStore.setItemAsync(REFRESH_KEY, data.refresh_token);
    setAccessToken(data.access_token);

    log("[AUTH] login successful");

    // Push registration is handled by openFimby (called right after login),
    // which reconciles against the user's Salesforce push preference from the
    // frontdoor response. Registering here too would double-prompt/register.

    return data.access_token;
  }, []);

  const shouldShowQuietHoursPanda = useCallback(async (serverPref: string | null): Promise<boolean> => {
    const pref = serverPref
      || (await AsyncStorage.getItem("fimby_quiet_hours"))
      || "10PM_6AM";
    if (serverPref) {
      await AsyncStorage.setItem("fimby_quiet_hours", serverPref);
    }
    if (pref === "NONE") return false;
    const today = new Date().toDateString();
    const lastPandaDate = await AsyncStorage.getItem("lastPandaDate");
    const quietNow = isInQuietHours(pref);
    log("[PANDA] quiet-hours check", { pref, lastPandaDate, today, quietNow });
    return lastPandaDate !== today && quietNow;
  }, []);

  const openFimby = React.useCallback(
    async (maybeAccess?: string | null, retArg?: string | null) => {
      let token = maybeAccess || accessToken;

      // Resolve the deep-link target: explicit arg wins, otherwise consume any
      // pending Universal Link captured before sign-in or before WebView mount.
      // We don't clear pendingDeepLinkRef here — quiet-hours panda may
      // interrupt and the next openFimby call needs to see the same value.
      // The ref is cleared at the moment we actually setWebViewUrl().
      const ret = retArg ?? pendingDeepLinkRef.current;

      if (!token) {
        const result = await refreshSession();
        if (result.sessionExpired) {
          Alert.alert(
            "Please Sign In",
            result.message || "Your session has expired. Please sign in again."
          );
          return;
        }
        token = result.token;
      }

      if (!token) {
        Alert.alert("Not signed in", "Tap Sign in to start a session.");
        return;
      }

      setStatus("Unlocking the door…");

      const frontdoorUrl = ret
        ? `${BACKEND_FRONTDOOR_URL}?ret=${encodeURIComponent(ret)}`
        : BACKEND_FRONTDOOR_URL;

      const res = await fetch(frontdoorUrl, {
        method: "GET",
        headers: {
          Authorization: `Bearer ${token}`,
        },
      });

      if (!res.ok) {
        const body = await jsonOrText(res);
        log("Frontdoor failed:", body);

        // One retry after refresh (nice UX)
        const result = await refreshSession();
        if (result.sessionExpired) {
          Alert.alert(
            "Please Sign In",
            result.message || "Your session has expired. Please sign in again."
          );
          return;
        }
        if (!result.token) {
          Alert.alert("Session expired", "Please sign in again.");
          return;
        }

        const retry = await fetch(frontdoorUrl, {
          method: "GET",
          headers: { Authorization: `Bearer ${result.token}` },
        });

        if (!retry.ok) {
          const retryBody = await jsonOrText(retry);
          log("Frontdoor retry failed:", retryBody);
          Alert.alert("Could not open FIMBY", "Try again.");
          return;
        }

        const retryJson = await retry.json();
        const retryUrl = retryJson?.url;
        if (!retryUrl) {
          Alert.alert("Could not open FIMBY", "No URL returned.");
          return;
        }

        if (await shouldShowQuietHoursPanda(retryJson.quietHoursPreference ?? null)) {
          setShowPanda(true);
          return;
        }

        if (pendingDeepLinkRef.current === ret) pendingDeepLinkRef.current = null;
        setWebViewUrl(retryUrl);
        setStatus("You're in!");

        reconcilePushRegistration(result.token, retryJson.pushNotificationsEnabled);
        return;
      }

      const json = await res.json();
      const url = json?.url;

      if (!url) {
        log("Frontdoor response missing url:", json);
        Alert.alert("Could not open FIMBY", "No URL returned.");
        return;
      }

      if (await shouldShowQuietHoursPanda(json.quietHoursPreference ?? null)) {
        setShowPanda(true);
        return;
      }

      if (pendingDeepLinkRef.current === ret) pendingDeepLinkRef.current = null;
      setWebViewUrl(url);
      setStatus("You're in!");

      reconcilePushRegistration(token, json.pushNotificationsEnabled);
    },
    [accessToken, refreshSession, reconcilePushRegistration, shouldShowQuietHoursPanda]
  );

  const logout = React.useCallback(async () => {
    setBusy(true);
    try {
      const refresh = await SecureStore.getItemAsync(REFRESH_KEY);

      // Unregister push token (best-effort, don't block logout)
      if (accessToken) {
        unregisterTokenFromBackend(accessToken).catch(() => {});
      }

      // Best-effort call backend logout (swallow errors)
      if (refresh) {
        await fetch(BACKEND_LOGOUT_URL, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ refresh_token: refresh }),
        }).catch(() => {});
      }

      await SecureStore.deleteItemAsync(REFRESH_KEY);
      setAccessToken(null);
      setWebViewUrl(null); // Exit WebView and return to main screen
      // Reset bootstrap guard so next app open can auto-login
      bootstrapRanRef.current = false;
      setStatus("Until next time!");
    } finally {
      setBusy(false);
    }
  }, [accessToken, unregisterTokenFromBackend]);

  /**
   * ========= WEBVIEW LOGIN INTERCEPTION (LOGOUT TRIGGER) =========
   * When Experience Cloud redirects to /login, treat it as logout completion.
   */

  /**
   * Primary interception: onShouldStartLoadWithRequest
   * Fires before navigation starts. Return false to block.
   * On iOS this fires for all requests; on Android needs originWhitelist={["*"]}
   */
  const onShouldStartLoadWithRequest = useCallback(
    (request: ShouldStartLoadRequest): boolean => {
      const url = request.url;
      log("[WebView] onShouldStartLoadWithRequest:", url);

      // Check if this is the login URL we want to intercept
      if (isFimbyLoginRedirect(url)) {
        // Guard: if already handling logout, just block
        if (logoutInProgressRef.current) {
          log("[WebView] Logout already in progress, blocking");
          return false;
        }
        logoutInProgressRef.current = true;

        log("[WebView] Intercepted login redirect, triggering logout");

        // Immediately clear WebView to exit (don't wait for async logout)
        setWebViewUrl(null);
        setStatus("Waving goodbye…");

        // Fire-and-forget the rest of logout cleanup
        (async () => {
          try {
            const refresh = await SecureStore.getItemAsync(REFRESH_KEY);
            if (refresh) {
              await fetch(BACKEND_LOGOUT_URL, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ refresh_token: refresh }),
              }).catch(() => {});
            }
            await SecureStore.deleteItemAsync(REFRESH_KEY);
            setAccessToken(null);
            // Reset bootstrap guard so next app open can auto-login
            bootstrapRanRef.current = false;
            setStatus("Until next time!");
            log("[WebView] Logout cleanup complete");
          } catch (e) {
            log("[WebView] Logout cleanup error:", e);
          } finally {
            logoutInProgressRef.current = false;
          }
        })();

        return false; // Block the WebView from rendering /login
      }

      // Origin allowlist: anything outside the FIMBY/Salesforce surface is
      // opened in the system browser so the Experience Cloud session cookie
      // stays inside the WebView.
      if (!isAllowedWebViewUrl(url)) {
        log("[WebView] Blocked off-origin nav, handing to system browser:", url);
        Linking.openURL(url).catch((err) => {
          log("[WebView] Linking.openURL failed:", err);
        });
        return false;
      }

      return true;
    },
    []
  );

  /**
   * Fallback interception: onNavigationStateChange
   * Fires after navigation state changes. Used as backup for JS redirects.
   * Also clears notification tray + badge when user navigates to /notifications.
   */
  const onNavigationStateChange = useCallback(
    (navState: WebViewNavigation) => {
      const url = navState.url;
      log("[WebView] onNavigationStateChange:", url);

      // Clear notification tray + badge when user views notifications page
      if (url.includes("/notifications")) {
        Notifications.dismissAllNotificationsAsync().catch(() => {});
        Notifications.setBadgeCountAsync(0).catch(() => {});
      }

      // Fallback check if onShouldStartLoadWithRequest didn't catch it
      if (isFimbyLoginRedirect(url)) {
        // Guard: if already handling logout, skip
        if (logoutInProgressRef.current) {
          log("[WebView] Fallback: logout already in progress");
          return;
        }
        logoutInProgressRef.current = true;

        log("[WebView] Fallback: detected login redirect, triggering logout");

        // Immediately clear WebView to exit
        setWebViewUrl(null);
        setStatus("Waving goodbye…");

        // Fire-and-forget the rest of logout cleanup
        (async () => {
          try {
            const refresh = await SecureStore.getItemAsync(REFRESH_KEY);
            if (refresh) {
              await fetch(BACKEND_LOGOUT_URL, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ refresh_token: refresh }),
              }).catch(() => {});
            }
            await SecureStore.deleteItemAsync(REFRESH_KEY);
            setAccessToken(null);
            bootstrapRanRef.current = false;
            setStatus("Until next time!");
            log("[WebView] Fallback logout cleanup complete");
          } catch (e) {
            log("[WebView] Fallback logout cleanup error:", e);
          } finally {
            logoutInProgressRef.current = false;
          }
        })();
      }
    },
    []
  );

  /**
   * WebView render error handler -- shows a retry overlay
   */
  const onWebViewError = useCallback(
    (event: WebViewErrorEvent) => {
      const { nativeEvent } = event;
      log("[WebView] Render error:", nativeEvent.description);
      setWebViewError(nativeEvent.description || "Something went wrong loading the page.");
    },
    []
  );

  /**
   * WebView HTTP error handler -- catches 401/403 on main frame
   */
  const onHttpError = useCallback(
    (event: WebViewHttpErrorEvent) => {
      const { nativeEvent } = event;
      const statusCode = nativeEvent.statusCode;
      log("[WebView] HTTP error:", statusCode, nativeEvent.url);

      if (statusCode === 401 || statusCode === 403) {
        setWebViewError("Your session has expired. Let's get you signed back in.");
      }
    },
    []
  );

  /**
   * Handle messages from LWC (postMessage bridge)
   * Currently handles quiet hours preference sync
   */
  const onWebViewMessage = useCallback(
    (event: WebViewMessageEvent) => {
      try {
        const data = JSON.parse(event.nativeEvent.data);
        if (data.type === "quietHours" && data.window) {
          AsyncStorage.setItem("fimby_quiet_hours", data.window).catch(() => {});
          log("[WebView] Quiet hours synced:", data.window);
        } else if (data.type === "themeChange" && (data.theme === "light" || data.theme === "dark")) {
          setAppTheme(data.theme);
          AsyncStorage.setItem(THEME_STORAGE_KEY, data.theme).catch(() => {});
          log("[WebView] Theme synced:", data.theme);
        } else if (data.type === "pushNotifications" && typeof data.enabled === "boolean") {
          log("[WebView] Push toggle synced:", data.enabled);
          void syncPushRegistration(data.enabled);
        }
      } catch {
        // Not JSON or not a message we handle
      }
    },
    [syncPushRegistration]
  );

  /**
   * Apply a Universal Link deep-link path to the WebView.
   *
   * Three states:
   * 1. WebView already mounted -> inject JS to navigate the existing session.
   * 2. Signed in but WebView not yet visible -> open with ret so frontdoor
   *    lands the user directly on the deep-linked page.
   * 3. Signed out -> stash the path; openFimby() consumes pendingDeepLinkRef
   *    on the next call (post-OAuth or after panda dismiss).
   */
  const applyDeepLink = useCallback((path: string) => {
    log("[DEEPLINK] applying:", path);
    if (webViewRef.current) {
      const target = `${SF_AUTH_HOST}${path}`;
      webViewRef.current.injectJavaScript(
        `window.location.assign(${JSON.stringify(target)}); true;`
      );
      return;
    }
    if (accessToken) {
      void openFimby(accessToken, path);
      return;
    }
    pendingDeepLinkRef.current = path;
    log("[DEEPLINK] stashed for after sign-in:", path);
  }, [accessToken, openFimby]);

  /**
   * Cold-start deep linking when the app was opened from a killed state via push.
   * Runs at most once: later WebView loadEnd events must not re-read the stored tap.
   */
  const handleColdStartNotification = useCallback(async () => {
    if (coldStartPushHandledRef.current) {
      return;
    }

    const data = await getLastNotificationResponse();
    if (!data) {
      coldStartPushHandledRef.current = true;
      return;
    }

    if (navigateFromPush(data)) {
      await finishPushLaunch();
    }
  }, [navigateFromPush, finishPushLaunch]);

  /**
   * Helper to detect network errors from exceptions
   */
  const isNetworkError = useCallback((error: any): boolean => {
    const message = (error?.message || '').toLowerCase();
    return (
      message.includes('network') ||
      message.includes('fetch') ||
      message.includes('connection') ||
      message.includes('internet') ||
      message.includes('offline') ||
      error?.name === 'TypeError' // fetch throws TypeError on network failure
    );
  }, []);

  /**
   * ========= BOOTSTRAP ON APP START =========
   * Auto-login: if valid refresh token exists, go straight to FIMBY
   * Runs in PARALLEL with splash video - alerts are deferred until video ends
   */
  const runBootstrap = useCallback(async () => {
    setBooting(true);
    setBootstrapError(null);

    try {
      setStatus("Checking if you're still you…");
      const refresh = await SecureStore.getItemAsync(REFRESH_KEY);
      if (refresh) {
        log("[BOOTSTRAP] stored refresh token present");
        const result = await refreshSession();

        if (result.sessionExpired) {
          // Session TTL exceeded - defer alert until after splash video
          log("Session expired due to TTL policy.");
          setStatus("Let's catch up!");
          pendingAlertRef.current = {
            title: "Welcome Back!",
            message: result.message || "Your session has expired. Please sign in again.",
          };
        } else if (result.token) {
          log("Valid session found, auto-opening FIMBY...");
          await openFimby(result.token);
        } else {
          // Refresh failed (token expired/invalid for other reasons)
          log("Refresh token invalid or expired.");
          setStatus("Let's reconnect.");
        }
      } else {
        log("No stored refresh token.");
        setStatus("Neighbours are waiting.");
      }
    } catch (e: any) {
      log("Bootstrap error:", e?.message || e);

      // Detect network vs other errors
      if (isNetworkError(e)) {
        setBootstrapError('network');
        setStatus('The internet said "BRB"');
      } else {
        setBootstrapError('other');
        setStatus("Well that didn't work! 🤷‍♂️");
      }
    } finally {
      setBooting(false);
    }
  }, [refreshSession, openFimby, isNetworkError]);

  // Initial bootstrap effect
  React.useEffect(() => {
    // Guard: only run bootstrap once on mount
    if (bootstrapRanRef.current) return;
    bootstrapRanRef.current = true;
    runBootstrap();
  }, [runBootstrap]);

  /**
   * Universal Link / App Link handling.
   *
   * Cold start: if the app was launched by tapping app.fimby.com/<path>,
   * Linking.getInitialURL() returns that URL. We extract the path and feed it
   * through applyDeepLink (which stashes it for sign-in if needed).
   *
   * Warm start: while the app is running, taps on app.fimby.com links fire
   * the 'url' event. Same handler.
   */
  React.useEffect(() => {
    let cancelled = false;

    Linking.getInitialURL()
      .then((url) => {
        if (cancelled || !url) return;
        const path = parseFimbyDeepLink(url);
        if (path) applyDeepLink(path);
      })
      .catch((err) => warn("[DEEPLINK] getInitialURL error:", err));

    const sub = Linking.addEventListener("url", (event) => {
      const path = parseFimbyDeepLink(event.url);
      if (path) applyDeepLink(path);
    });

    return () => {
      cancelled = true;
      sub.remove();
    };
  }, [applyDeepLink]);

  /**
   * Start Sign In flow (pre-flight network check + OAuth)
   * Used by both Sign In button and Try Again button
   */
  const startSignIn = useCallback(async () => {
    if (!request) return;

    setBusy(true);
    // Don't clear bootstrapError yet - wait until network check passes
    // This keeps "Try Again" visible during the check

    try {
      // Pre-flight network check before opening OAuth
      setStatus("Knocking on the door…");
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 5000);
        await fetch(BACKEND_BASE_URL, {
          method: 'HEAD',
          signal: controller.signal,
        });
        clearTimeout(timeoutId);
      } catch (networkErr: any) {
        log("Pre-flight network check failed:", networkErr?.message);
        if (isNetworkError(networkErr) || networkErr?.name === 'AbortError') {
          setBootstrapError('network');
          setStatus('The internet said "BRB"');
        } else {
          setBootstrapError('other');
          setStatus("Well that didn't work! 🤷‍♂️");
        }
        return;
      }

      // Network check passed - now clear error state
      setBootstrapError(null);

      // ✅ Capture verifier right before launching auth
      pkceVerifierRef.current = request?.codeVerifier || null;
      log(
        "Captured PKCE verifier (len/fp):",
        (pkceVerifierRef.current || "").length,
        (pkceVerifierRef.current || "").slice(0, 6)
      );

      setStatus("Opening the door…");
      const result = await promptAsync({ preferEphemeralSession: true });

      // Handle non-success responses (user cancelled, dismissed, or error)
      if (result.type === 'dismiss' || result.type === 'cancel') {
        setStatus("Neighbours are waiting.");
      } else if (result.type === 'error') {
        log("OAuth error:", result.error);
        setStatus("Something went sideways. Try again?");
      }
      // 'success' is handled by the useEffect watching response
    } finally {
      setBusy(false);
    }
  }, [request, promptAsync, isNetworkError]);

  /**
   * ========= HANDLE PKCE REDIRECT =========
   */
  React.useEffect(() => {
    (async () => {
      if (response?.type !== "success") return;
      const code = response.params?.code;
      if (!code) return;

      // Explicit OAuth state check (defense in depth on top of
      // expo-auth-session's internal verification): reject the response
      // if the returned state does not match the one we sent. This blocks
      // CSRF-style callback injection — an attacker can't hand us a code
      // from a different session.
      const returnedState = response.params?.state;
      const expectedState = request?.state;
      if (!expectedState || !returnedState || returnedState !== expectedState) {
        log("OAuth state mismatch, rejecting auth response");
        handledAuthCodeRef.current = null;
        Alert.alert("Sign in failed", "Authentication response was invalid. Please try again.");
        return;
      }

      // ✅ Guard: skip if this exact code was already processed
      // This prevents re-processing stale responses after logout resets state
      if (handledAuthCodeRef.current === code) {
        log("OAuth code already processed, ignoring duplicate.");
        return;
      }
      handledAuthCodeRef.current = code;

      setBusy(true);
      try {
        const verifier = pkceVerifierRef.current || request?.codeVerifier || "";
        log(
          "Using PKCE verifier (len/fp):",
          verifier.length,
          verifier.slice(0, 6)
        );

        const token = await loginWithBackend(code, verifier);
        setStatus("Welcome back!");
        await openFimby(token);
      } catch (e: any) {
        handledAuthCodeRef.current = null; // allow retry if it truly failed
        Alert.alert("Sign in failed", e?.message || "Unknown error");
      } finally {
        setBusy(false);
      }
    })();
  }, [response, request?.codeVerifier, loginWithBackend, openFimby]);

  // Open a public URL in the in-app browser sheet (sign-up, help, faq).
  // Dismisses back into the native screen; never takes over the auth WebView.
  const openExternal = useCallback(async (url: string) => {
    try {
      await WebBrowser.openBrowserAsync(url);
    } catch (e) {
      warn("[LINK] openBrowserAsync failed", e);
    }
  }, []);

  const canLogin = !!request && !busy;

  // Show splash video on startup (bootstrap runs in parallel)
  // Preload images during splash so they're ready when home screen appears
  if (!splashVideoComplete) {
    return (
      <View style={styles.splashContainer}>
        <Stack.Screen options={{ headerShown: false }} />
        <VideoView
          player={splashPlayer}
          style={styles.splashVideo}
          contentFit="cover"
          nativeControls={false}
        />
        {/* Preload images hidden (1x1, opacity 0) during splash so they're
            decoded and ready when the pre-auth screen appears. Never visible. */}
        <View style={styles.preloadContainer}>
          <Image source={LOGO_MORNING} style={styles.preloadImage} />
          <Image source={LOGO_DAY} style={styles.preloadImage} />
          <Image source={LOGO_EVENING} style={styles.preloadImage} />
          <Image source={NO_WIFI_ICON} style={styles.preloadImage} />
        </View>
        {/* Themed overlay fades in during the video's built-in fade-out so the
            animation lands on the destination screen (cream / espresso). */}
        <Animated.View
          pointerEvents="none"
          style={[
            StyleSheet.absoluteFill,
            { backgroundColor: PREAUTH_COLORS[appTheme].bg, opacity: splashFadeAnim },
          ]}
        />
      </View>
    );
  }

  // Panda Screen: quiet hours interstitial (before auth)
  if (showPanda && !webViewUrl) {
    const dismissPanda = async () => {
      await AsyncStorage.setItem("lastPandaDate", new Date().toDateString());
      setShowPanda(false);
      setPandaFarewell(null);
      void openFimby();
    };

    const showFarewell = () => {
      const msg = FAREWELL_MESSAGES[Math.floor(Math.random() * FAREWELL_MESSAGES.length)];
      setPandaFarewell(msg);
      setTimeout(() => {
        setPandaEscapeVisible(true);
        Animated.timing(pandaEscapeFade, {
          toValue: 1,
          duration: 600,
          useNativeDriver: true,
        }).start();
      }, 5000);
    };

    return (
      <View style={pandaStyles.container}>
        <Stack.Screen options={{ headerShown: false }} />
        <View style={pandaStyles.pandaTopSpacer} />
        <View style={pandaStyles.pandaSection}>
          {pandaVideoFailed ? (
            <Image
              source={PANDA_SLEEPING}
              style={pandaStyles.image}
              resizeMode="contain"
              accessibilityLabel="A panda curled up sleeping"
            />
          ) : (
            <VideoView
              player={pandaPlayer}
              style={pandaStyles.image}
              contentFit="contain"
              nativeControls={false}
            />
          )}
        </View>
        <View style={pandaStyles.contentSection}>
        <Text style={pandaStyles.caption}>
          {pandaFarewell || "FIMBY is resting right now, but you're always welcome."}
        </Text>
        {!pandaFarewell && (
          <>
            <Pressable style={pandaStyles.primaryButton} onPress={dismissPanda}>
              <Text style={pandaStyles.primaryButtonText}>Come on in</Text>
            </Pressable>
            <Pressable style={pandaStyles.secondaryButton} onPress={showFarewell}>
              <Text style={pandaStyles.secondaryButtonText}>Come back in the morning</Text>
            </Pressable>
          </>
        )}
        {pandaFarewell && pandaEscapeVisible && (
          <Animated.View style={{ opacity: pandaEscapeFade }}>
            <Pressable style={pandaStyles.escapeButton} onPress={dismissPanda}>
              <Text style={pandaStyles.escapeButtonText}>Actually, let me in</Text>
            </Pressable>
          </Animated.View>
        )}
        </View>
      </View>
    );
  }

  // If WebView URL is set, show the WebView full-screen with no UI chrome
  if (webViewUrl) {
    // Clear badge count when entering WebView (user is engaging with app)
    clearBadge();
    const themeColors = THEME_COLORS[appTheme];
    return (
      <SafeAreaView style={[styles.safeArea, { backgroundColor: themeColors.statusBar }]} edges={["top"]}>
        <StatusBar style={themeColors.barStyle} backgroundColor={themeColors.statusBar} />
        <Stack.Screen options={{ headerShown: false }} />
        <WebView
          ref={webViewRef}
          source={{ uri: webViewUrl }}
          style={styles.webView}
          originWhitelist={[
            "https://*.fimby.com",
            "https://*.my.site.com",
            "https://*.salesforce.com",
            "https://*.force.com",
            "https://*.documentforce.com",
            "https://*.salesforceliveagent.com",
            "about:blank",
          ]}
          javaScriptEnabled={true}
          domStorageEnabled={true}
          startInLoadingState={true}
          sharedCookiesEnabled={true}
          thirdPartyCookiesEnabled={true}
          applicationNameForUserAgent="FIMBY-WebView/1.0"
          injectedJavaScriptBeforeContentLoaded={"window.__FIMBY_NATIVE_APP__ = true; true;"}
          onShouldStartLoadWithRequest={onShouldStartLoadWithRequest}
          onNavigationStateChange={onNavigationStateChange}
          onError={onWebViewError}
          onHttpError={onHttpError}
          onMessage={onWebViewMessage}
          onLoadEnd={() => {
            handleColdStartNotification();
            void maybeRunDeferredPushPrompt();
          }}
        />
        {webViewError && (
          <View style={styles.errorOverlay}>
            <Text style={styles.errorOverlayText}>{webViewError}</Text>
            <Pressable
              style={styles.errorOverlayButton}
              onPress={() => {
                setWebViewError(null);
                if (webViewRef.current) {
                  webViewRef.current.reload();
                }
              }}
            >
              <Text style={styles.errorOverlayButtonText}>Try Again</Text>
            </Pressable>
            <Pressable
              style={styles.errorOverlaySignOut}
              onPress={() => {
                setWebViewError(null);
                logout();
              }}
            >
              <Text style={styles.errorOverlaySignOutText}>Sign Out</Text>
            </Pressable>
          </View>
        )}
      </SafeAreaView>
    );
  }

  // Theme-aware pre-auth palette (applied inline; StyleSheet is static)
  const c = PREAUTH_COLORS[appTheme];

  // Determine what content to show
  const renderContent = () => {
    // Loading screen while booting (session restoring)
    if (booting) {
      return (
        <View style={styles.centerContent}>
          <ActivityIndicator size="large" color={c.spinner} style={styles.spinner} />
          <Text style={[styles.status, { color: c.secondary }]}>{status}</Text>
        </View>
      );
    }

    // Error screen with retry button
    if (bootstrapError) {
      return (
        <View style={styles.centerContent}>
          <Image source={NO_WIFI_ICON} style={styles.errorIcon} resizeMode="contain" />
          <Pressable
            style={[styles.button, { backgroundColor: c.primaryBg }, !request && styles.buttonDisabled]}
            disabled={!request || busy}
            onPress={startSignIn}
          >
            <Text style={[styles.buttonText, { color: c.primaryText }]}>Try Again</Text>
          </Pressable>
          {busy && (
            <ActivityIndicator size="large" color={c.spinner} style={styles.spinner} />
          )}
          <Text style={[styles.status, { color: c.secondary }]}>{status}</Text>
        </View>
      );
    }

    // Sign In screen (no session, or session expired)
    return (
      <View style={styles.centerContent}>
        <Pressable
          style={[styles.button, { backgroundColor: c.primaryBg }, !canLogin && styles.buttonDisabled]}
          disabled={!canLogin}
          onPress={startSignIn}
        >
          <Text style={[styles.buttonText, { color: c.primaryText }]}>Sign In</Text>
        </Pressable>

        {busy && (
          <ActivityIndicator size="large" color={c.spinner} style={styles.spinner} />
        )}

        <Text style={[styles.status, { color: c.secondary }]}>{status}</Text>
      </View>
    );
  };

  // Main pre-auth layout: three distinct sections distributed top / middle / bottom
  return (
    <SafeAreaView style={[styles.container, { backgroundColor: c.bg }]} edges={["top", "bottom"]}>
      <Stack.Screen options={{ headerShown: false }} />
      <StatusBar style={THEME_COLORS[appTheme].barStyle} backgroundColor={c.bg} />

      {/* Whole stack nudged down so the content reads optically centered
          (top gap was smaller than the bottom gap). Tweak PREAUTH_VERTICAL_NUDGE. */}
      <View style={styles.contentShift}>
        {/* UPPER: full FIMBY logo + tagline */}
        <Animated.View style={[styles.upperSection, { opacity: fadeAnim }]}>
          <Image
            source={getTimeOfDayLogo()}
            style={styles.heroLogo}
            resizeMode="contain"
            accessibilityRole="image"
            accessibilityLabel="FIMBY"
          />
          <Text style={[styles.tagline, { color: c.secondary }]}>
            Turning the place you live{"\n"}into a place you belong.
          </Text>
        </Animated.View>

        {/* MIDDLE: primary action + status (or loading / error state) */}
        <Animated.View style={[styles.middleSection, { opacity: fadeAnim }]}>
          {renderContent()}
        </Animated.View>

        {/* LOWER: secondary action + footer links */}
        <Animated.View style={[styles.lowerSection, { opacity: fadeAnim }]}>
          {!booting && !bootstrapError && (
            <Pressable
              style={[styles.createAccountButton, { borderColor: c.signUpOutline }]}
              accessibilityRole="button"
              accessibilityLabel="Sign Up"
              onPress={() => openExternal(SIGN_UP_URL)}
            >
              <Text style={[styles.createAccountText, { color: c.signUpOutline }]}>Sign Up</Text>
            </Pressable>
          )}
          <View style={styles.footerRow}>
            <Pressable
              hitSlop={12}
              accessibilityRole="link"
              accessibilityLabel="Help"
              onPress={() => openExternal(HELP_URL)}
            >
              <Text style={[styles.footerLinkText, { color: c.secondary }]}>HELP</Text>
            </Pressable>
            <Text style={[styles.footerBullet, { color: c.secondary }]}>·</Text>
            <Pressable
              hitSlop={12}
              accessibilityRole="link"
              accessibilityLabel="FAQ"
              onPress={() => openExternal(FAQ_URL)}
            >
              <Text style={[styles.footerLinkText, { color: c.secondary }]}>FAQ</Text>
            </Pressable>
          </View>
        </Animated.View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  // Splash video styles
  splashContainer: {
    flex: 1,
    backgroundColor: SPLASH_BG,
  },
  splashVideo: {
    flex: 1,
    width: "100%",
    height: "100%",
  },
  preloadContainer: {
    position: "absolute",
    opacity: 0,
    pointerEvents: "none",
  },
  preloadImage: {
    width: 1,
    height: 1,
  },
  // Main pre-auth screen styles (theme colors applied inline).
  // Three equal flex regions guarantee distinct, evenly distributed sections.
  container: {
    flex: 1,
    paddingVertical: 16,
  },
  contentShift: {
    flex: 1,
    transform: [{ translateY: PREAUTH_VERTICAL_NUDGE }],
  },
  upperSection: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: 24,
  },
  heroLogo: {
    height: 104,
    aspectRatio: HERO_LOGO_ASPECT,
    maxWidth: "92%",
    marginBottom: 16,
  },
  tagline: {
    fontSize: 17,
    lineHeight: 25,
    fontFamily: "Nunito_400Regular",
    textAlign: "center",
    paddingHorizontal: 16,
  },
  middleSection: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    width: "100%",
    paddingHorizontal: 32,
  },
  lowerSection: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
    width: "100%",
    paddingHorizontal: 32,
  },
  centerContent: {
    alignItems: "center",
    width: "100%",
  },
  button: {
    paddingVertical: 16,
    paddingHorizontal: 48,
    borderRadius: 12,
    alignItems: "center",
    minWidth: 200,
  },
  buttonDisabled: { opacity: 0.5 },
  buttonText: { fontSize: 20, fontFamily: "Nunito_800ExtraBold" },
  createAccountButton: {
    borderWidth: 1.5,
    paddingVertical: 10,
    paddingHorizontal: 28,
    borderRadius: 8,
    alignItems: "center",
    alignSelf: "center",
  },
  createAccountText: { fontSize: 16, fontFamily: "Nunito_700Bold" },
  spinner: {
    marginTop: 24,
  },
  errorIcon: {
    width: 80,
    height: 80,
    opacity: 0.9,
    marginBottom: 24,
  },
  status: {
    fontSize: 15,
    marginTop: 20,
    fontFamily: "Nunito_400Regular",
    textAlign: "center",
  },
  footerRow: {
    flexDirection: "row",
    justifyContent: "center",
    alignItems: "center",
    marginTop: 28,
  },
  footerLinkText: {
    fontSize: 16,
    fontFamily: "Nunito_700Bold",
    letterSpacing: 0.5,
    paddingVertical: 10,
    paddingHorizontal: 18,
  },
  footerBullet: {
    fontSize: 16,
    fontFamily: "Nunito_700Bold",
    paddingHorizontal: 2,
  },
  // WebView styles
  safeArea: {
    flex: 1,
    backgroundColor: "#ffffff",
  },
  webView: {
    flex: 1,
  },
  errorOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: "rgba(0,0,0,0.85)",
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: 32,
  },
  errorOverlayText: {
    color: "#ffffff",
    fontSize: 16,
    textAlign: "center",
    marginBottom: 24,
    lineHeight: 22,
  },
  errorOverlayButton: {
    backgroundColor: "#67BBD2",
    paddingVertical: 14,
    paddingHorizontal: 40,
    borderRadius: 12,
    marginBottom: 16,
  },
  errorOverlayButtonText: {
    color: "#ffffff",
    fontSize: 16,
    fontWeight: "700",
  },
  errorOverlaySignOut: {
    paddingVertical: 10,
  },
  errorOverlaySignOutText: {
    color: "#aaaaaa",
    fontSize: 14,
  },
});

const pandaStyles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#14100D",
    paddingHorizontal: 32,
  },
  pandaTopSpacer: {
    flex: 0.7,
  },
  pandaSection: {
    justifyContent: "center",
    alignItems: "center",
  },
  image: {
    width: 200,
    height: 200,
  },
  contentSection: {
    flex: 1,
    justifyContent: "flex-start",
    alignItems: "center",
    paddingTop: 24,
  },
  caption: {
    color: "#D6CFC7",
    fontSize: 16,
    textAlign: "center",
    lineHeight: 24,
    marginBottom: 32,
    paddingHorizontal: 16,
  },
  primaryButton: {
    borderWidth: 2,
    borderColor: "#B3A79E",
    paddingVertical: 8,
    paddingHorizontal: 8,
    borderRadius: 999,
    marginBottom: 16,
    alignItems: "center",
    width: 260,
  },
  primaryButtonText: {
    color: "#B3A79E",
    fontSize: 20,
    fontWeight: "600",
  },
  secondaryButton: {
    borderWidth: 2,
    borderColor: "#B3A79E",
    borderRadius: 999,
    paddingVertical: 14,
    paddingHorizontal: 8,
    alignItems: "center",
    width: 260,
  },
  secondaryButtonText: {
    color: "#B3A79E",
    fontSize: 14,
    fontWeight: "600",
  },
  escapeButton: {
    borderWidth: 2,
    borderColor: "#B3A79E",
    borderRadius: 999,
    paddingVertical: 14,
    paddingHorizontal: 40,
    alignItems: "center",
    minWidth: 160,
    marginTop: 8,
  },
  escapeButtonText: {
    color: "#B3A79E",
    fontSize: 13,
    fontWeight: "600",
  },
});
