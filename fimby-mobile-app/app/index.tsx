import * as AuthSession from "expo-auth-session";
import * as LocalAuthentication from "expo-local-authentication";
import * as Notifications from "expo-notifications";
import * as SecureStore from "expo-secure-store";
import * as WebBrowser from "expo-web-browser";
import AsyncStorage from "@react-native-async-storage/async-storage";
import NetInfo from "@react-native-community/netinfo";
import { useVideoPlayer, VideoView } from "expo-video";
import { useEventListener } from "expo";
import { StatusBar } from "expo-status-bar";
import { Stack } from "expo-router";
import * as Linking from "expo-linking";
import React, { useRef, useCallback } from "react";
import {
  AccessibilityInfo,
  ActivityIndicator,
  Animated,
  AppState,
  BackHandler,
  Easing,
  Image,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  useColorScheme,
  View,
} from "react-native";
import type { AppStateStatus } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { WebView, WebViewNavigation } from "react-native-webview";
import type { ShouldStartLoadRequest } from "react-native-webview/lib/WebViewTypes";
import type { WebViewErrorEvent, WebViewHttpErrorEvent, WebViewMessageEvent, WebViewRenderProcessGoneEvent } from "react-native-webview/lib/WebViewTypes";
import {
  usePushNotifications,
  getLastNotificationResponse,
  clearLastNotificationResponse,
  NotificationData,
  MARK_READ_ACTION,
} from "../hooks/use-push-notifications";
import { log, warn, safeUrlForLog } from "../lib/log";
import {
  authTimingMark,
  authTimingDelta,
  deeplinkTimingMark,
} from "../lib/auth-timing";
import {
  createDeepLinkIntent,
  peekIntentPath,
  isIntentActive,
  type DeepLinkIntent,
  type DeepLinkSource,
} from "../lib/deep-link-intent";

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

// Pre-auth inline cards — warm, themed replacements for the old OS Alert.alert
// modals. Rendered on the pre-auth screen (logo stays above) with the action
// button right there, instead of a jarring system dialog.
type PreAuthCardId = 'session' | 'door' | 'signin-failed' | 'offline';

const PRE_AUTH_CARDS: Record<
  PreAuthCardId,
  { heading: string; body: string; button: string | null }
> = {
  session: {
    heading: "Welcome back!",
    body: "It's been a little while, so we signed you out to keep your account safe. Come on in.",
    button: "Sign in",
  },
  door: {
    heading: "Hmm, the door's jammed.",
    body: "We couldn't open your neighbourhood. Give it another try in a moment.",
    button: "Try again",
  },
  'signin-failed': {
    heading: "Hmmm that didn't work",
    body: "Something got tangled up. Let's try that sign-in once more.",
    button: "Try again",
  },
  offline: {
    heading: "You're offline right now",
    body: "No rush. We'll be open for business when you're back online.",
    button: null,
  },
};

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

// Push-permission primer: shown at most once per install. We record when it was
// shown (either choice) and, separately, when the user chose "Not now" so we can
// respect that decision and never auto-re-ask.
const PUSH_PRIMER_SHOWN_KEY = "fimby_push_primer_shown";
const PUSH_PRIMER_DECLINED_KEY = "fimby_push_primer_declined_at";

// Biometric app lock: opt-in, stored per install. Locks on cold launch and on
// resume after a long absence (see threshold). Cleared on sign-out.
const APP_LOCK_ENABLED_KEY = "fimby_app_lock_enabled";
const APP_LOCK_RESUME_THRESHOLD_MS = 5 * 60 * 1000;

type BiometricType = 'faceId' | 'touchId' | 'fingerprint' | 'none';

// Map the OS's supported authentication types to the device-specific term Apple
// HIG requires (never say "Face ID" on a Touch ID device). Android collapses to
// the generic "fingerprint".
function resolveBiometricType(
  types: LocalAuthentication.AuthenticationType[]
): BiometricType {
  const hasFace = types.includes(LocalAuthentication.AuthenticationType.FACIAL_RECOGNITION);
  const hasFinger = types.includes(LocalAuthentication.AuthenticationType.FINGERPRINT);
  if (Platform.OS === 'ios') {
    if (hasFace) return 'faceId';
    if (hasFinger) return 'touchId';
    return 'none';
  }
  if (hasFinger || hasFace) return 'fingerprint';
  return 'none';
}

function biometricMethodLabel(type: BiometricType): string {
  switch (type) {
    case 'faceId':
      return 'Face ID';
    case 'touchId':
      return 'Touch ID';
    case 'fingerprint':
      return 'fingerprint';
    default:
      return 'biometric unlock';
  }
}

// Endpoints
const BACKEND_LOGIN_AND_FRONTDOOR_URL = `${BACKEND_BASE_URL}/api/login-and-frontdoor`;
const BACKEND_REFRESH_URL = `${BACKEND_BASE_URL}/api/session/refresh`;
const BACKEND_FRONTDOOR_URL = `${BACKEND_BASE_URL}/api/frontdoor`;
const BACKEND_LOGOUT_URL = `${BACKEND_BASE_URL}/api/logout`;
const BACKEND_PUSH_ACTION_URL = `${BACKEND_BASE_URL}/api/notifications/action`;

/** Pre-kettle loading line. The bootstrap spinner runs UNDER the splash video
 *  from app start; if the video lifts before the frontdoor URL is ready (the
 *  kettle moment), this is the message shown in that gap. */
const BOOTSTRAP_LOADING_MESSAGE = "Herding the dust bunnies…";

/** Loading-phrase pool for the kettle handoff overlay. One is chosen at random
 *  per launch (see LAUNCH_PHRASES) so each cold start feels a little different;
 *  the phrase stays put while visible and only rotates on a long wait (>5s), so
 *  slow readers and screen-reader users aren't fighting a moving target. */
const LOADING_PHRASES = [
  "Putting the kettle on…",
  "Raking up the leaves…",
  "Sweeping the front porch…",
  "Letting folks know you're here…",
  "Setting out some cookies…",
  "Checking the mailbox…",
  "Turning on the porch light…",
];

function shuffledPhrases(): string[] {
  const a = [...LOADING_PHRASES];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// Shuffled once per JS launch: different order each cold start, stable while a
// given phrase is on screen. LAUNCH_PHRASES[0] is the initial kettle caption.
const LAUNCH_PHRASES = shuffledPhrases();

// Rotation timing: hold the first phrase for a while, then advance gently only
// when the wait is genuinely long, so variety appears exactly when there's time
// to enjoy it (never mid-read on a fast handoff).
const LOADING_ROTATE_START_MS = 5000;
const LOADING_ROTATE_INTERVAL_MS = 3000;

/** How long the kettle overlay holds the bunny arrival caption ("Herding
 *  the dust bunnies…") after snapping opaque before handing off to the
 *  caller's real target caption + rotation. The overlay snaps to full
 *  opacity in the same commit as the Layer 1 primary swap so the swap is
 *  never visible; the bunny caption then sits for this window so the two
 *  loading phases still feel like distinct beats rather than one flash.
 *  Reduced-motion users skip this hold and go straight to the target. */
const LOADING_BUNNY_HOLD_MS = 350;

/** WebView handoff overlay — the FINAL loading state before the app, triggered
 *  the moment the frontdoor URL is ready. Trigger is unchanged; shown to
 *  everyone right before they land in the app. */
const WEBVIEW_HANDOFF_MESSAGE = LAUNCH_PHRASES[0];
const WEBVIEW_HANDOFF_MIN_MS = 1000;
const WEBVIEW_HANDOFF_FADE_MS = 550;
/** If the EC shell never posts quietHours (Apex/bridge failure), lift the kettle
 *  anyway so the user is never stuck. Measured from first EC document loadEnd.
 *  Header now signals from renderedCallback (pre-Apex) so this should almost
 *  never fire — 4s covers a really slow LWR boot without being a visible wait. */
const WEBVIEW_HANDOFF_FALLBACK_MS = 4000;

/** Playback time (s) at which the themed dissolve overlay starts fading in over
 *  the splash video. Tuned to the 3s clip's built-in fade-out tail. */
const SPLASH_FADE_AT = 2.25;

const INJECT_FALLBACK_MS = 2000;
const SF_EC_HOST_PATTERN = /^fimby\.my\.site\.com$/i;

// ─────────────────────────────────────────────────────────────────────────────
// Foreground resume reconciliation thresholds
// The app does NOT run in the background; these only govern how much work we do
// when it returns to the foreground (active) after an absence.
// ─────────────────────────────────────────────────────────────────────────────
const LIGHT_RESUME_AFTER_MS = 30 * 1000;        // notify the WebView after this
const AUTH_RESUME_AFTER_MS = 5 * 60 * 1000;     // refresh the native session after this
const MIN_RESUME_REFRESH_SPACING_MS = 20 * 1000; // throttle resume work churn

// Experience Cloud frontdoor session lifetime. Mirrors the org session timeout
// (~24h), anchored on WHEN the frontdoor was established (not on last EC
// activity). A small margin keeps us under the live edge so we re-mint just
// before the cookie dies. Past this age on resume we silently re-mint the
// frontdoor at the last page — no taps. The reactive /login backstop covers the
// case where the cookie dies earlier than this clock predicts.
const EC_SESSION_MAX_AGE_MS = 23 * 60 * 60 * 1000;

// Silent re-auth loop guard: if a re-auth attempt keeps landing back on /login
// within this window, stop re-minting and fall to the Sign In screen.
const REAUTH_LOOP_WINDOW_MS = 60 * 1000;
const REAUTH_MAX_ATTEMPTS = 3;

function isExperienceCloudUrl(rawUrl: string): boolean {
  try {
    return SF_EC_HOST_PATTERN.test(new URL(rawUrl).hostname);
  } catch {
    return false;
  }
}

type FrontdoorPayload = {
  url: string;
  quietHoursPreference?: string | null;
  pushNotificationsEnabled?: boolean | null;
};

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

// Standard Experience Cloud error route. Salesforce lands users here on a bad
// URL, an unknown/inaccessible record, or an unauthorized/expired-session
// request. The page renders only a static "Page not available" message with no
// navigation of its own, so inside the WebView (no browser back button) the
// user is trapped until they force-quit. We detect it and surface our own
// escape hatch instead.
function isFimbyErrorPage(url: string): boolean {
  try {
    const u = new URL(url);
    if (!SF_EC_HOST_PATTERN.test(u.hostname)) return false;
    return /^\/error\/?$/i.test(u.pathname);
  } catch {
    return false;
  }
}

// Salesforce server-side logout endpoint. An explicit navigation here (the
// header web-fallback, the VF SiteHeader link, account deletion, etc.) is an
// unambiguous, user-initiated logout — distinct from a session-timeout bounce
// to /login. We treat it as the deterministic "this is a real logout" signal so
// the ensuing /login redirect is never mistaken for a timeout.
function isFimbyLogoutEndpoint(url: string): boolean {
  try {
    const u = new URL(url);
    if (!SF_EC_HOST_PATTERN.test(u.hostname)) return false;
    return /\/secur\/logout\.jsp/i.test(u.pathname);
  } catch {
    return false;
  }
}

// Turn a full Experience Cloud URL (e.g. lastEcUrlRef) into a frontdoor `ret`
// path (`pathname + search + hash`) so silent re-auth lands the user back on the
// exact page they were on. Returns null for non-EC or malformed URLs (frontdoor
// then falls back to the default landing page).
function ecUrlToRetPath(rawUrl: string | null): string | null {
  if (!rawUrl) return null;
  try {
    const u = new URL(rawUrl);
    if (!SF_EC_HOST_PATTERN.test(u.hostname)) return null;
    const path = u.pathname + u.search + u.hash;
    if (!path.startsWith("/") || path.startsWith("//")) return null;
    return path;
  } catch {
    return null;
  }
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

/**
 * True when the app was opened from the FimbyAppHandoff Visualforce page (the
 * post-set-password "Open the FIMBY app" button carries ?src=handoff). When
 * this fires we run the next OAuth prompt non-ephemerally once, so the sign-in
 * sheet can reuse the live fimby.my.site.com cookie the browser just set —
 * turning a password retype into a tap-through. See item 9 in the pre-auth plan.
 */
function isHandoffDeepLink(rawUrl: string): boolean {
  try {
    const u = new URL(rawUrl);
    if (u.hostname.toLowerCase() !== APP_LINK_HOST) return false;
    return u.searchParams.get("src") === "handoff";
  } catch {
    return false;
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

type LoginAndFrontdoorResponse = TokenResponse & FrontdoorPayload;

function isJwtLike(token: string) {
  return token.split(".").length === 3;
}

// Server sets data.channelId ('messages' | 'activity' | 'default') in
// FimbyPushBatchJob, plus notification_type on single sends. Single-notification
// pushes also carry data.action_url — a deep link to the exact record. We prefer
// that (validated to the FIMBY app host + a safe path via parseFimbyDeepLink, so
// no free-form input reaches the WebView), then fall back to the channel bucket.
// Aggregate/quiet pushes carry no action_url and land on the bucket list.
function resolvePushRoute(data: NotificationData | null | undefined): string {
  const actionUrl = typeof data?.action_url === "string" ? data.action_url : "";
  if (actionUrl) {
    const path = parseFimbyDeepLink(actionUrl);
    if (path) return path;
  }
  const channel = typeof data?.channelId === "string" ? data.channelId : "";
  // startsWith so quiet DM refreshes (channelId 'messages_quiet') also route to /messages.
  if (channel.startsWith("messages")) return "/messages";
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

/**
 * Revoke the refresh token server-side. Retries once on a transient failure
 * (network error or non-2xx) so a momentary blip doesn't strand a still-valid
 * token in Redis. Resolves true only when the server confirms revocation.
 */
async function revokeRefreshTokenOnBackend(refresh: string): Promise<boolean> {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetch(BACKEND_LOGOUT_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ refresh_token: refresh }),
      });
      if (res.ok) return true;
    } catch {
      // fall through to retry / give up
    }
  }
  return false;
}

export default function IndexScreen() {
  // Theme preference — synced from WebView via postMessage, persisted in
  // AsyncStorage. We store the user's *preference* ('auto' | 'light' | 'dark'),
  // not a resolved colour, so 'auto' can track the OS live.
  const deviceScheme = useColorScheme();
  const [themePref, setThemePref] = React.useState<'light' | 'dark' | 'auto'>('auto');

  React.useEffect(() => {
    AsyncStorage.getItem(THEME_STORAGE_KEY).then(stored => {
      if (stored === 'dark' || stored === 'light' || stored === 'auto') {
        setThemePref(stored);
      }
    }).catch(() => {});
  }, []);

  // Resolve the active theme. On 'auto' we follow the device scheme, which
  // useColorScheme() updates live — so an OS flip mid-session re-renders the
  // native shell with no stale-memory lag. Default 'auto' also seeds the very
  // first paint from the OS, avoiding a cold-start flash of the wrong theme.
  const appTheme: 'light' | 'dark' =
    themePref === 'auto' ? (deviceScheme === 'dark' ? 'dark' : 'light') : themePref;

  React.useEffect(() => {
    AccessibilityInfo.isReduceMotionEnabled()
      .then((enabled) => {
        reduceMotionRef.current = enabled;
      })
      .catch(() => {});
    const sub = AccessibilityInfo.addEventListener("reduceMotionChanged", (enabled) => {
      reduceMotionRef.current = enabled;
    });
    return () => sub.remove();
  }, []);

  // Biometric capability detection + cold-launch lock gate. Runs once on mount.
  React.useEffect(() => {
    (async () => {
      let available = false;
      let type: BiometricType = 'none';
      try {
        const hasHardware = await LocalAuthentication.hasHardwareAsync();
        const enrolled = await LocalAuthentication.isEnrolledAsync();
        const types = await LocalAuthentication.supportedAuthenticationTypesAsync();
        type = resolveBiometricType(types);
        available = hasHardware && enrolled && type !== 'none';
      } catch {
        available = false;
      }
      let enabledStored = false;
      try {
        enabledStored = (await SecureStore.getItemAsync(APP_LOCK_ENABLED_KEY)) === 'true';
      } catch {
        enabledStored = false;
      }
      const enabled = enabledStored && available;
      setAppLockCapability({ available, type });
      setAppLockEnabled(enabled);
      appLockEnabledRef.current = enabled;
      // Cold-launch gate: if the lock is on, cover the screen until the user
      // proves it's them. EC can still load behind the lock for a fast unlock.
      if (enabled) {
        setLocked(true);
      }
    })();
  }, []);

  // Warm/cold splash decision. null = still deciding (SecureStore read in
  // flight); 'video' = cold/signed-out launch, play the full mp4 ceremony;
  // 'static' = warm start (stored token) or reduced-motion — skip the mp4 and
  // go straight to the themed branded screen + loading states.
  const [splashDecision, setSplashDecision] = React.useState<'video' | 'static' | null>(null);

  // Splash video state - track separately so bootstrap can run in parallel
  const [splashVideoComplete, setSplashVideoComplete] = React.useState(false);
  // Ref mirror so showWebViewHandoff can tell, without re-binding, whether the
  // video is still covering the screen. The kettle must NOT start (or burn its
  // minimum-view clock) while the video plays — it's deferred until the lift.
  const splashVideoCompleteRef = useRef(false);

  const [booting, setBooting] = React.useState(true);
  const [busy, setBusy] = React.useState(false);
  const [accessToken, setAccessToken] = React.useState<string | null>(null);
  const [status, setStatus] = React.useState<string>("Waking up…");

  // Track bootstrap errors for retry functionality
  const [bootstrapError, setBootstrapError] = React.useState<'network' | 'other' | null>(null);

  // Inline pre-auth card (replaces the old OS Alert.alert modals). Shown on the
  // pre-auth screen; `detail` carries optional small-print (e.g. a raw OAuth
  // error for support). See PRE_AUTH_CARDS for copy.
  const [preAuthCard, setPreAuthCard] = React.useState<{ id: PreAuthCardId; detail?: string } | null>(null);

  // WebView state
  const [webViewUrl, setWebViewUrl] = React.useState<string | null>(null);
  // Bumped to force a full remount of the native WebView when its content
  // process is terminated (iOS) or killed (Android) — recovers a blank page.
  const [webViewKey, setWebViewKey] = React.useState(0);
  const [webViewError, setWebViewError] = React.useState<string | null>(null);
  // In-session WebView offline state (load failed with no connectivity). Shows a
  // themed offline overlay instead of the generic error screen; auto-reloads on
  // reconnect.
  const [webViewOffline, setWebViewOffline] = React.useState(false);
  const webViewOfflineRef = useRef(false);
  // Latest known connectivity, updated by the NetInfo subscription. null/unknown
  // internet-reachability is treated as connected (don't false-alarm offline).
  const netConnectedRef = useRef(true);
  // True while the pre-auth offline card is up, so a reconnect can auto-resume.
  const offlineCardActiveRef = useRef(false);
  // True while the WebView is sitting on the Experience Cloud /error route, so
  // we can overlay our own recovery card (the EC error page has no navigation).
  const [stuckOnErrorPage, setStuckOnErrorPage] = React.useState(false);
  const [webViewHandoffVisible, setWebViewHandoffVisible] = React.useState(false);
  // Caption for the single deferred loading overlay; swaps in place from the
  // "bunny" (pre-frontdoor) line to the "kettle" (WebView loading) line.
  const [loadingCaption, setLoadingCaption] = React.useState(WEBVIEW_HANDOFF_MESSAGE);
  // True only in the kettle phase (not the pre-frontdoor "bunny" phase): enables
  // the slow phrase rotation on long waits.
  const [loadingRotates, setLoadingRotates] = React.useState(false);
  // Post-fade-in target: caption + rotation the caller *actually* wants once
  // the arrival fade completes. Read live inside the fade animation's
  // completion callback so any mid-fade update (e.g. bunny→kettle handoff
  // fires while the intro fade is still running) is honoured with the
  // latest intent, not a stale closure over the first caller's args.
  const loadingTargetRef = useRef<{ caption: string; rotate: boolean }>({
    caption: WEBVIEW_HANDOFF_MESSAGE,
    rotate: true,
  });
  // Kettle overlay opacity. Initial value is 0 because the overlay is now
  // *pre-mounted* — its Animated.View + SafeAreaView + logo + spinner +
  // caption + HELP/FAQ subtree renders from the very first frame of the
  // app, sitting there invisible. When the loading state is needed we
  // *snap* opacity to 1 in the same commit as the Layer 1 primary swap
  // (pre-auth tree → WebView tree), so Layer 3 is fully opaque on the
  // very first frame the swap is visible on. Layer 3's native views are
  // already laid out and painted — the opacity flip is the only work
  // left, and there is no fade window during which the swap could leak
  // through. See presentLoadingOverlay for the snap + bunny hold →
  // kettle handoff.
  const webViewHandoffFade = useRef(new Animated.Value(0)).current;
  // WebView reveal (Plan C). Starts at 0 so the WKWebView's first-mount frame
  // dance (0,0,0,0 → 0,0,W,0 → 0,0,W,H) happens completely invisibly behind
  // our opaque kettle overlay. Ramped to 1 in parallel with the overlay's
  // dismiss fade — a crossfade rather than a hard cut. Reset back to 0
  // whenever a new loading cycle starts (fresh sign-in, crash recovery,
  // sign-out then sign-in again) so the next WebView mount is invisible too.
  const webViewRevealFade = useRef(new Animated.Value(0)).current;
  const webViewHandoffShownAtRef = useRef<number | null>(null);
  const webViewHandoffEcReadyAtRef = useRef<number | null>(null);
  const webViewHandoffDismissedRef = useRef(false);
  const webViewHandoffDismissTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const webViewHandoffFallbackTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Handle for the "hold bunny caption for LOADING_BUNNY_HOLD_MS then swap to
  // the caller's target" timer scheduled inside presentLoadingOverlay. Cleared
  // on dismiss (so the swap doesn't fire onto an invisible overlay) and on
  // every fresh present (defensive — the already-up branch short-circuits
  // before this in normal use).
  const loadingBunnyHoldTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  /** Set when quietHours arrives before the kettle overlay has a shownAt clock. */
  const webViewShellReadyPendingRef = useRef(false);
  // A frontdoor handoff requested while the splash video was still playing. The
  // kettle decision (skip vs show) is deferred to the video-lift effect below.
  const handoffPendingRef = useRef(false);
  // Ensures the video-lift loading decision runs exactly once.
  const videoLiftHandledRef = useRef(false);
  const reduceMotionRef = useRef(false);

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
  // "Come on in" pressed — swaps the two buttons for a spinner + caption while
  // openFimby runs, and keeps the panda screen visible until openFimby resolves
  // (either to WebView, session card, or offline). Avoids the panda-to-preauth
  // cream flash in light mode by never exposing pre-auth between tap and
  // handoff.
  const [pandaAcknowledged, setPandaAcknowledged] = React.useState(false);
  // Post-panda transition — while true, the kettle overlay uses the panda dark
  // palette regardless of user theme, so the handoff from panda → EC content
  // is a single dark canvas. Cleared when the EC shell signals ready.
  const [postPandaTransition, setPostPandaTransition] = React.useState(false);
  const postPandaTransitionRef = useRef(false);
  React.useEffect(() => {
    postPandaTransitionRef.current = postPandaTransition;
  }, [postPandaTransition]);

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

  // Create video player for splash screen. Playback is NOT started here — the
  // warm/cold decision below (splashDecision) starts it only for cold/signed-out
  // launches. Warm starts and reduced-motion skip the ceremony entirely.
  const splashPlayer = useVideoPlayer(SPLASH_VIDEO, (player) => {
    player.loop = false;
    player.timeUpdateEventInterval = 0.25;
  });

  // Handle splash video completion using expo-video event system
  useEventListener(splashPlayer, "playToEnd", () => {
    setSplashVideoComplete(true);
  });

  // Sync a themed color overlay to the splash video's tail (~2.25s -> ~3.0s on the
  // 3s clip) so the animation dissolves into the destination screen — which is now
  // loading UNDERNEATH the video — instead of hard-cutting. Adjust SPLASH_FADE_AT
  // if the video asset's built-in fade-out starts at a different time.
  useEventListener(splashPlayer, "timeUpdate", ({ currentTime }) => {
    if (splashFadeStartedRef.current || currentTime < SPLASH_FADE_AT) return;
    splashFadeStartedRef.current = true;
    Animated.timing(splashFadeAnim, {
      toValue: 1,
      duration: 750,
      useNativeDriver: true,
    }).start();
  });

  // Warm/cold splash decision (runs once on mount). A stored refresh token means
  // this is a returning neighbour — skip the mp4 ceremony and land them faster
  // on the themed loading screen that dissolves into the app. Reduced-motion
  // users always get the static path (see item 4). A cold/signed-out launch
  // plays the full branded animation, keeping the ceremony with the sign-in
  // moment.
  React.useEffect(() => {
    let cancelled = false;
    (async () => {
      let staticSplash = false;
      try {
        staticSplash = await AccessibilityInfo.isReduceMotionEnabled();
      } catch {
        staticSplash = false;
      }
      if (!staticSplash) {
        try {
          const refresh = await SecureStore.getItemAsync(REFRESH_KEY);
          staticSplash = !!refresh;
        } catch {
          staticSplash = false;
        }
      }
      if (cancelled) return;
      if (staticSplash) {
        setSplashDecision('static');
        // No video ceremony: treat the splash as already complete so the loading
        // orchestration (kettle handoff, bootstrap spinner) takes over at once.
        setSplashVideoComplete(true);
      } else {
        setSplashDecision('video');
        try {
          splashPlayer.play();
        } catch {
          // If playback can't start, fall through to the static path so the
          // user is never stuck behind a paused frame.
          setSplashDecision('static');
          setSplashVideoComplete(true);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [splashPlayer]);

  // Splash video timeout fallback - ensures user is never stuck on splash
  React.useEffect(() => {
    if (splashDecision !== 'video') return;
    const timeout = setTimeout(() => {
      if (!splashVideoComplete) {
        warn("Splash video timeout - forcing completion");
        setSplashVideoComplete(true);
      }
    }, 10000); // 10 seconds max

    return () => clearTimeout(timeout);
  }, [splashVideoComplete, splashDecision]);

  // Announce a newly shown pre-auth card to screen readers (heading + body).
  React.useEffect(() => {
    if (!preAuthCard) return;
    const card = PRE_AUTH_CARDS[preAuthCard.id];
    AccessibilityInfo.announceForAccessibility(`${card.heading}. ${card.body}`);
  }, [preAuthCard]);

  // Coordinated fade-in animation when splash completes. Reduced-motion users
  // get an instant reveal instead of the fade.
  React.useEffect(() => {
    if (splashVideoComplete) {
      if (reduceMotionRef.current) {
        fadeAnim.setValue(1);
        return;
      }
      Animated.timing(fadeAnim, {
        toValue: 1,
        duration: 400,
        useNativeDriver: true,
      }).start();
    }
  }, [splashVideoComplete, fadeAnim]);

  // Announce meaningful status transitions to screen readers on iOS (Android
  // gets these via the accessibilityLiveRegion on the status line). Skips the
  // initial mount value so we only speak actual progress changes.
  const lastAnnouncedStatusRef = useRef<string | null>(null);
  React.useEffect(() => {
    if (Platform.OS !== 'ios') return;
    if (!status) return;
    if (lastAnnouncedStatusRef.current === status) return;
    if (lastAnnouncedStatusRef.current !== null) {
      AccessibilityInfo.announceForAccessibility(status);
    }
    lastAnnouncedStatusRef.current = status;
  }, [status]);

  // Panda Screen: check quiet hours on cold launch. Signed-in only — panda is
  // a personal "not now" gesture, so we never show it to a user who has no
  // relationship with FIMBY yet. Fresh installs during quiet hours go straight
  // to the pre-auth screen; the panda greets them the second night after
  // they've signed in and their pref has been cached.
  React.useEffect(() => {
    if (pandaCheckedRef.current) return;
    pandaCheckedRef.current = true;

    (async () => {
      const refresh = await SecureStore.getItemAsync(REFRESH_KEY);
      if (!refresh) return;

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

  // Pending Universal Link intent (one tap → one redirect → discard).
  const deepLinkIntentRef = useRef<DeepLinkIntent | null>(null);
  // True when bootstrap captured a Universal Link (cold start) — beats push replay.
  const bootstrapCapturedUniversalLinkRef = useRef(false);
  // Warm inject: confirm navigation or fall back to openFimby(ret).
  const injectFallbackRef = useRef<{ path: string; confirmed: boolean } | null>(null);
  const injectFallbackTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Replay a link received while backgrounded once AppState returns to active.
  const resumeDeepLinkPathRef = useRef<string | null>(null);
  // One-shot: set when opened via the FimbyAppHandoff deep link so the very next
  // OAuth prompt runs non-ephemerally (shares the browser's fresh site cookie),
  // then cleared. See isHandoffDeepLink / item 9.
  const handoffSignInRef = useRef(false);

  // Cold-start Universal Links are captured by runBootstrap() (which controls
  // the auto-login openFimby call). This guard stops the separate deep-link
  // effect from re-handling the same launch URL and double-firing the frontdoor.
  const coldStartDeepLinkHandledRef = useRef(false);

  // WebView ref for deep linking from notifications
  const webViewRef = useRef<WebView>(null);
  // Mirrors WebView history depth so the Android hardware/gesture back can walk
  // the EC page stack instead of backgrounding the app on the first press.
  const webViewCanGoBackRef = useRef(false);
  // After a push launch is handled (or none pending), skip cold-start re-checks on later loadEnd events.
  const coldStartPushHandledRef = useRef(false);

  // Foreground resume coordinator state. The app reconciles on the active
  // transition; it does not run while backgrounded.
  const appStateRef = useRef<AppStateStatus>(AppState.currentState);
  const backgroundedAtRef = useRef<number | null>(null);
  const lastResumeRefreshAtRef = useRef(0);
  const resumeRefreshInFlightRef = useRef(false);

  // WebView crash recovery. The last live Experience Cloud page we can safely
  // reload after the OS kills the WebView process (NOT the one-time frontdoor
  // URL, which is long expired by then). Plus a loop guard.
  const lastEcUrlRef = useRef<string | null>(null);
  const lastCrashRecoverAtRef = useRef(0);
  const crashRecoverCountRef = useRef(0);

  // Frontdoor (EC) session age anchor + silent re-auth guards. lastFrontdoorAtRef
  // is stamped each time a frontdoor URL is applied; the resume coordinator uses
  // it to decide when the EC session is likely past the org timeout. The reauth
  // refs throttle and loop-guard the silent re-establish path.
  const lastFrontdoorAtRef = useRef<number | null>(null);
  const reauthInFlightRef = useRef(false);
  const reauthAttemptCountRef = useRef(0);
  const lastReauthAtRef = useRef(0);

  // Keep the latest access token in a ref so WebView message handlers (whose
  // useCallback deps stay []) never read a stale/null token from closure.
  const accessTokenRef = useRef<string | null>(null);
  React.useEffect(() => {
    accessTokenRef.current = accessToken;
  }, [accessToken]);

  // refreshSession is declared further below; expose it via a ref so earlier
  // callbacks (e.g. the push "Mark read" handler) can call it without a
  // forward-reference TDZ error or a churning dependency.
  const refreshSessionRef = useRef<(() => Promise<{ token?: string | null; sessionExpired?: boolean; message?: string }>) | null>(null);

  const captureDeepLinkIntent = useCallback((path: string, source: DeepLinkSource) => {
    const intent = createDeepLinkIntent(path, source);
    if (!intent) return;
    deepLinkIntentRef.current = intent;
    deeplinkTimingMark("captured", { path, source });
    log("[DEEPLINK] captured:", path, source);
  }, []);

  const discardDeepLinkIntent = useCallback((reason?: string) => {
    if (deepLinkIntentRef.current) {
      log("[DEEPLINK] discarded", reason ?? "");
      deepLinkIntentRef.current = null;
    }
  }, []);

  const clearInjectFallback = useCallback(() => {
    if (injectFallbackTimeoutRef.current) {
      clearTimeout(injectFallbackTimeoutRef.current);
      injectFallbackTimeoutRef.current = null;
    }
    injectFallbackRef.current = null;
  }, []);

  const clearWebViewHandoffFallback = useCallback(() => {
    if (webViewHandoffFallbackTimeoutRef.current) {
      clearTimeout(webViewHandoffFallbackTimeoutRef.current);
      webViewHandoffFallbackTimeoutRef.current = null;
    }
  }, []);

  const dismissWebViewHandoff = useCallback(
    (opts?: { immediate?: boolean }) => {
      if (webViewHandoffDismissTimeoutRef.current) {
        clearTimeout(webViewHandoffDismissTimeoutRef.current);
        webViewHandoffDismissTimeoutRef.current = null;
      }
      if (loadingBunnyHoldTimeoutRef.current) {
        clearTimeout(loadingBunnyHoldTimeoutRef.current);
        loadingBunnyHoldTimeoutRef.current = null;
      }
      clearWebViewHandoffFallback();

      const finish = () => {
        webViewHandoffDismissedRef.current = true;
        setWebViewHandoffVisible(false);
      };

      if (opts?.immediate || reduceMotionRef.current) {
        // Snap both layers into their end state simultaneously so no
        // dark/blank frame ever exists.
        webViewHandoffFade.setValue(0);
        webViewRevealFade.setValue(1);
        finish();
        return;
      }

      // Snap Layer 2 (WebView) to opacity 1 IMMEDIATELY at dismiss start.
      // By the time markWebViewShellReady fires, the WKWebView has fully
      // finished its mount lifecycle inside our opaque kettle, EC's LWC
      // has painted (renderedCallback), and the underlying tree is stable
      // — there is nothing left to reflow. Making it opaque now means the
      // kettle then fades to reveal a *fully rendered* EC, giving a clean
      // 50/50 crossfade at every intermediate frame (kettle * α + EC * (1-α))
      // rather than the double-transparency blend that Animated.parallel
      // would have produced.
      webViewRevealFade.setValue(1);
      Animated.timing(webViewHandoffFade, {
        toValue: 0,
        duration: WEBVIEW_HANDOFF_FADE_MS,
        easing: Easing.out(Easing.cubic),
        useNativeDriver: true,
      }).start(({ finished }) => {
        if (finished) finish();
      });
    },
    [webViewHandoffFade, webViewRevealFade, clearWebViewHandoffFallback]
  );

  // Reveal the pre-auth offline card and stop any doomed loading. A reconnect
  // (NetInfo subscription) auto-resumes via resumeAfterOffline — no button.
  const showOfflineCard = useCallback(() => {
    dismissWebViewHandoff({ immediate: true });
    setBooting(false);
    offlineCardActiveRef.current = true;
    setPreAuthCard({ id: 'offline' });
  }, [dismissWebViewHandoff]);

  const scheduleWebViewHandoffDismiss = useCallback(() => {
    if (webViewHandoffDismissedRef.current) return;
    const shownAt = webViewHandoffShownAtRef.current;
    const ecReadyAt = webViewHandoffEcReadyAtRef.current;
    if (shownAt == null || ecReadyAt == null) return;

    if (webViewHandoffDismissTimeoutRef.current) {
      clearTimeout(webViewHandoffDismissTimeoutRef.current);
    }

    const dismissAt = Math.max(shownAt + WEBVIEW_HANDOFF_MIN_MS, ecReadyAt);
    const delay = Math.max(0, dismissAt - Date.now());

    webViewHandoffDismissTimeoutRef.current = setTimeout(() => {
      webViewHandoffDismissTimeoutRef.current = null;
      if (webViewHandoffDismissedRef.current) return;
      dismissWebViewHandoff();
    }, delay);
  }, [dismissWebViewHandoff]);

  const markWebViewShellReady = useCallback(
    (source: string) => {
      if (webViewHandoffDismissedRef.current) return;
      if (webViewHandoffEcReadyAtRef.current != null) return;

      log("[WebView] Shell ready for handoff:", source);
      authTimingMark("webview_shell_ready", { source });
      clearWebViewHandoffFallback();
      // EC content is painted → the post-panda dark override can drop; the
      // kettle's fade will hand off to the user's real theme in the WebView.
      if (postPandaTransitionRef.current) {
        postPandaTransitionRef.current = false;
        setPostPandaTransition(false);
      }

      if (webViewHandoffShownAtRef.current == null) {
        webViewShellReadyPendingRef.current = true;
        return;
      }

      webViewHandoffEcReadyAtRef.current = Date.now();
      scheduleWebViewHandoffDismiss();
    },
    [clearWebViewHandoffFallback, scheduleWebViewHandoffDismiss]
  );

  const armWebViewHandoffFallback = useCallback(() => {
    if (webViewHandoffDismissedRef.current) return;
    if (webViewHandoffShownAtRef.current == null) return;
    if (webViewHandoffEcReadyAtRef.current != null) return;
    if (webViewHandoffFallbackTimeoutRef.current != null) return;

    webViewHandoffFallbackTimeoutRef.current = setTimeout(() => {
      webViewHandoffFallbackTimeoutRef.current = null;
      markWebViewShellReady("load-end-fallback");
    }, WEBVIEW_HANDOFF_FALLBACK_MS);
  }, [markWebViewShellReady]);

  // Single deferred loading overlay used for BOTH phases. On first present
  // the overlay *snaps* to full opacity in the same React commit as the
  // Layer 1 primary swap (pre-auth SafeAreaView → WebView SafeAreaView) so
  // the swap is never visible — no fade window through which the underlying
  // tree can flicker. It then holds the bunny caption ("Herding the dust
  // bunnies…") for LOADING_BUNNY_HOLD_MS as an arrival beat, and finally
  // hands off to the caller's intended caption + rotation (kettle rotation
  // for the WebView loading phase, or just staying on bunny if the caller
  // wanted bunny because auth is still in flight).
  //
  // The overlay itself is *pre-mounted* in the tree from app launch (see
  // loadingOverlay + webViewHandoffFade initial value 0). The snap is a
  // single opacity flip on already-laid-out native views — no mount race
  // between Layer 1 (primary swap) and Layer 3.
  //
  // The minimum-view clock is anchored once, when the overlay first
  // appears, so the two caption phases never stack and never flash.
  const presentLoadingOverlay = useCallback(
    (caption: string, opts?: { rotate?: boolean }) => {
      const rotate = !!opts?.rotate;
      // Update the "what we ultimately want on screen" target immediately.
      // If a fade-in is already in flight when a later call updates this
      // (e.g. showWebViewHandoff fires during the bunny fade), the fade's
      // completion callback reads the latest value from this ref rather
      // than a stale closure.
      loadingTargetRef.current = { caption, rotate };

      // Already up: skip the fade-in and just swap caption/rotation live.
      // The overlay is opaque, nothing to mount, no clock to re-anchor.
      if (
        webViewHandoffShownAtRef.current != null &&
        !webViewHandoffDismissedRef.current
      ) {
        setLoadingCaption(caption);
        setLoadingRotates(rotate);
        return;
      }

      if (webViewHandoffDismissTimeoutRef.current) {
        clearTimeout(webViewHandoffDismissTimeoutRef.current);
        webViewHandoffDismissTimeoutRef.current = null;
      }
      if (loadingBunnyHoldTimeoutRef.current) {
        clearTimeout(loadingBunnyHoldTimeoutRef.current);
        loadingBunnyHoldTimeoutRef.current = null;
      }
      clearWebViewHandoffFallback();
      webViewHandoffDismissedRef.current = false;
      webViewHandoffEcReadyAtRef.current = null;
      webViewHandoffShownAtRef.current = Date.now();
      setWebViewHandoffVisible(true);
      // Start of a new loading cycle — make sure the WebView (Layer 2)
      // begins the next mount fully invisible. Also covers the case where
      // a previous session set webViewRevealFade to 1 during dismiss and
      // we're now signing in again (sign-out then sign-in, crash recovery).
      webViewRevealFade.setValue(0);

      if (reduceMotionRef.current) {
        // No bunny intro — go straight to the caller's caption and full
        // opacity so reduced-motion users get the loading state instantly
        // with the intended text.
        setLoadingCaption(caption);
        setLoadingRotates(rotate);
        webViewHandoffFade.setValue(1);
      } else {
        // Snap Layer 3 to full opacity in the same commit as any Layer 1
        // primary swap the caller triggered (e.g. openFimby setting
        // webViewUrl). Because Layer 3 is pre-mounted and its subtree is
        // already laid out, this is a single native opacity flip — no
        // fade window during which the swap could leak through. Then
        // hold the bunny caption briefly as an arrival beat before
        // handing off to the caller's target caption + rotation.
        webViewHandoffFade.setValue(1);
        setLoadingCaption(BOOTSTRAP_LOADING_MESSAGE);
        setLoadingRotates(false);
        loadingBunnyHoldTimeoutRef.current = setTimeout(() => {
          loadingBunnyHoldTimeoutRef.current = null;
          // Guard: if the overlay was dismissed during the hold (very
          // fast EC + short minimum view + immediate dismiss path), do
          // nothing — we don't want to reflash a caption onto an
          // invisible overlay.
          if (webViewHandoffDismissedRef.current) return;
          // Read the latest intent — any mid-hold call that updated
          // loadingTargetRef takes effect here.
          const target = loadingTargetRef.current;
          setLoadingCaption(target.caption);
          setLoadingRotates(target.rotate);
        }, LOADING_BUNNY_HOLD_MS);
      }

      if (webViewShellReadyPendingRef.current) {
        webViewShellReadyPendingRef.current = false;
        markWebViewShellReady("shell-ready-deferred");
      }
    },
    [webViewHandoffFade, webViewRevealFade, clearWebViewHandoffFallback, markWebViewShellReady]
  );

  const showWebViewHandoff = useCallback(() => {
    // While the splash video still covers the screen, don't start the overlay or
    // its minimum-view clock — just record that a handoff is wanted. The
    // video-lift effect below then either skips the kettle (EC already loaded
    // behind the video) or shows it anchored to the lift moment. This is why the
    // minimum view time is never partly consumed behind the video.
    if (!splashVideoCompleteRef.current) {
      handoffPendingRef.current = true;
      return;
    }
    presentLoadingOverlay(WEBVIEW_HANDOFF_MESSAGE, { rotate: true });
  }, [presentLoadingOverlay]);

  // When the splash video lifts, decide the loading overlay (runs once):
  //  - EC already loaded behind the video  → skip, straight to app
  //  - frontdoor ready, page still loading → kettle
  //  - auth still in flight                → bunny (swaps to kettle when ready)
  React.useEffect(() => {
    if (!splashVideoComplete) return;
    splashVideoCompleteRef.current = true;
    if (videoLiftHandledRef.current) return;
    videoLiftHandledRef.current = true;

    if (handoffPendingRef.current) {
      handoffPendingRef.current = false;
      if (webViewHandoffEcReadyAtRef.current != null || webViewShellReadyPendingRef.current) {
        webViewShellReadyPendingRef.current = false;
        return;
      }
      presentLoadingOverlay(WEBVIEW_HANDOFF_MESSAGE, { rotate: true });
      return;
    }
    // Cold start only: the video just lifted and auth is still resolving, so
    // show the bunny bootstrap overlay in the gap. On a warm/static start we let
    // the branded pre-auth screen (logo on themed background) show during
    // bootstrap instead, then the kettle appears when the frontdoor is ready.
    if (splashDecision === 'video' && !webViewUrl && !showPanda && booting) {
      presentLoadingOverlay(BOOTSTRAP_LOADING_MESSAGE);
    }
  }, [splashVideoComplete, splashDecision, webViewUrl, showPanda, booting, presentLoadingOverlay]);

  // Safety net: if the overlay is in the pre-frontdoor (bunny) phase but auth
  // resolves to something other than the WebView (error, quiet-hours panda, or
  // no session), drop it so the right screen shows. The kettle phase dismisses
  // when the EC shell signals ready (quietHours) or the load-end fallback fires.
  React.useEffect(() => {
    if (!webViewHandoffVisible || webViewUrl) return;
    const stillWaitingOnAuth = booting && !bootstrapError && !showPanda;
    if (!stillWaitingOnAuth) {
      dismissWebViewHandoff({ immediate: true });
    }
  }, [
    webViewHandoffVisible,
    webViewUrl,
    booting,
    bootstrapError,
    showPanda,
    dismissWebViewHandoff,
  ]);

  // Loading-phrase rotation. Only in the kettle phase, and only once the wait
  // passes LOADING_ROTATE_START_MS — then advance gently through the launch's
  // shuffled pool. Short/normal handoffs never rotate (no text swap mid-read).
  React.useEffect(() => {
    if (!webViewHandoffVisible || !loadingRotates) return;
    let idx = 0; // LAUNCH_PHRASES[0] is the initial kettle caption
    let interval: ReturnType<typeof setInterval> | null = null;
    const start = setTimeout(() => {
      interval = setInterval(() => {
        idx = (idx + 1) % LAUNCH_PHRASES.length;
        setLoadingCaption(LAUNCH_PHRASES[idx]);
      }, LOADING_ROTATE_INTERVAL_MS);
    }, LOADING_ROTATE_START_MS);
    return () => {
      clearTimeout(start);
      if (interval) clearInterval(interval);
    };
  }, [webViewHandoffVisible, loadingRotates]);

  const handleWebViewLoadEnd = useCallback(
    (url?: string, loading?: boolean) => {
      authTimingMark("webview_load_end", { url: safeUrlForLog(url), loading });
      authTimingDelta("frontdoor_url_set", "webview_load_end");

      if (!url || !isExperienceCloudUrl(url)) return;
      if (loading === true) return;
      if (webViewOfflineRef.current) {
        webViewOfflineRef.current = false;
        setWebViewOffline(false);
      }
      armWebViewHandoffFallback();
    },
    [armWebViewHandoffFallback]
  );

  // Holds an access token when push is wanted but OS permission is still
  // undetermined at login. The first-time permission prompt is deferred out of
  // the login/frontdoor handoff and fired once the WebView is stable (onLoadEnd)
  // to avoid backgrounding the app mid-navigation. Cleared after it fires.
  const pendingPushPromptRef = useRef<string | null>(null);

  // Push-permission primer sheet: a warm, themed explainer shown once in front
  // of the OS permission prompt (which spends its single one-shot ask only after
  // the user has already said yes → near-100% grant rate).
  const [showPushPrimer, setShowPushPrimer] = React.useState(false);

  // Biometric app lock. Capability is detected once on mount; `enabled` is the
  // user's stored opt-in (gated on capability). `locked` drives the native lock
  // overlay. The ref mirror lets []-dep handlers read the latest enabled state.
  const [appLockCapability, setAppLockCapability] = React.useState<{
    available: boolean;
    type: BiometricType;
  }>({ available: false, type: 'none' });
  const [appLockEnabled, setAppLockEnabled] = React.useState(false);
  const appLockEnabledRef = useRef(false);
  React.useEffect(() => {
    appLockEnabledRef.current = appLockEnabled;
  }, [appLockEnabled]);
  const [locked, setLocked] = React.useState(false);
  const [lockPromptFailed, setLockPromptFailed] = React.useState(false);
  const lockInProgressRef = useRef(false);
  const [appLockDisabledNotice, setAppLockDisabledNotice] = React.useState(false);

  // Guards the device-token-rotation re-registration below. Re-acquiring the
  // Expo token internally fetches a device token, which can re-fire the
  // rotation listener; this prevents that from looping.
  const pushReRegisterInFlightRef = useRef(false);

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

  // Background "Mark read" quick action: the device cannot reach Salesforce
  // directly, so we POST the notification id to the auth bridge, which mints an
  // SF session for this user and calls the FimbyPushActionResource Apex REST
  // endpoint (which re-checks ownership and marks the notification + DM read).
  // Fire-and-forget: failures are non-fatal (the user can still open the app).
  const markNotificationRead = useCallback(
    async (data: NotificationData) => {
      const notificationId =
        typeof data?.notification_id === "string" ? data.notification_id : null;
      if (!notificationId) return;

      let token = accessTokenRef.current;
      if (!token && refreshSessionRef.current) {
        const result = await refreshSessionRef.current();
        token = result.token ?? null;
      }
      if (!token) {
        log("[PUSH] Mark read skipped: no session token");
        return;
      }

      try {
        const res = await fetch(BACKEND_PUSH_ACTION_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ action: MARK_READ_ACTION, notificationId }),
        });
        if (!res.ok) {
          log("[PUSH] Mark read failed:", res.status);
        }
      } catch (e: any) {
        log("[PUSH] Mark read error:", e?.message);
      }
    },
    []
  );

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
    onNotificationAction: (actionId: string, data: NotificationData) => {
      // "Mark read" quick action: clear it server-side without opening the app.
      if (actionId === MARK_READ_ACTION) {
        void markNotificationRead(data);
      }
    },
  });

  // Clear the app icon badge once the WebView session is showing. Moved out of
  // render (it was called inline during the webViewUrl branch) so it does not
  // fire on every re-render while the WebView is mounted.
  React.useEffect(() => {
    if (webViewUrl) {
      clearBadge();
    }
  }, [webViewUrl, clearBadge]);

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
    // Primer shows at most once per install. If it's already been shown (either
    // choice), never surface it again — the EC Settings toggle is the recovery
    // path, and flipping that fires the OS prompt directly via syncPushRegistration.
    try {
      const shown = await AsyncStorage.getItem(PUSH_PRIMER_SHOWN_KEY);
      if (shown) {
        pendingPushPromptRef.current = null;
        return;
      }
    } catch {
      // If storage is unreadable, err on the side of showing the primer once.
    }
    setShowPushPrimer(true);
  }, []);

  // "Yes please": mark the primer shown, then fire the real OS permission prompt.
  const acceptPushPrimer = useCallback(async () => {
    setShowPushPrimer(false);
    const token = pendingPushPromptRef.current;
    pendingPushPromptRef.current = null;
    try {
      await AsyncStorage.setItem(PUSH_PRIMER_SHOWN_KEY, new Date().toISOString());
    } catch {
      // Non-fatal — worst case the primer could show again next launch.
    }
    if (token) {
      await registerPushNotificationsAsync(token, { prompt: true });
    }
  }, [registerPushNotificationsAsync]);

  // "Not now": record the decline, do NOT fire the OS prompt (its one-shot ask
  // stays unspent). We never auto-re-ask; the EC Settings toggle is the way back.
  const declinePushPrimer = useCallback(async () => {
    setShowPushPrimer(false);
    pendingPushPromptRef.current = null;
    const now = new Date().toISOString();
    try {
      await AsyncStorage.multiSet([
        [PUSH_PRIMER_SHOWN_KEY, now],
        [PUSH_PRIMER_DECLINED_KEY, now],
      ]);
    } catch {
      // Non-fatal.
    }
  }, []);

  // Run the native biometric (or device-passcode fallback) unlock. On success
  // the lock lifts; on cancel/failure the lock screen offers a retry. If the
  // device has NO secure lock at all, there's nothing to protect — fail open
  // once, auto-disable the lock, and explain why.
  const runBiometricUnlock = useCallback(async () => {
    if (lockInProgressRef.current) return;
    lockInProgressRef.current = true;
    setLockPromptFailed(false);
    try {
      let level = LocalAuthentication.SecurityLevel.NONE;
      try {
        level = await LocalAuthentication.getEnrolledLevelAsync();
      } catch {
        level = LocalAuthentication.SecurityLevel.NONE;
      }
      if (level === LocalAuthentication.SecurityLevel.NONE) {
        appLockEnabledRef.current = false;
        setAppLockEnabled(false);
        await SecureStore.deleteItemAsync(APP_LOCK_ENABLED_KEY).catch(() => {});
        setLocked(false);
        setAppLockDisabledNotice(true);
        return;
      }
      const result = await LocalAuthentication.authenticateAsync({
        promptMessage: 'Unlock FIMBY',
        cancelLabel: 'Cancel',
        disableDeviceFallback: false,
      });
      if (result.success) {
        setLocked(false);
      } else {
        setLockPromptFailed(true);
      }
    } catch {
      setLockPromptFailed(true);
    } finally {
      lockInProgressRef.current = false;
    }
  }, []);

  // Auto-fire the unlock prompt whenever the lock overlay appears.
  React.useEffect(() => {
    if (locked) {
      void runBiometricUnlock();
    }
  }, [locked, runBiometricUnlock]);

  // Enable/disable the app lock from EC Settings. Both directions require a
  // biometric confirm ("prove it's you") before committing, then ack the result
  // back so the toggle reflects reality (reverts on cancel/failure).
  const handleAppLockToggle = useCallback(async (enable: boolean) => {
    try {
      const result = await LocalAuthentication.authenticateAsync({
        promptMessage: enable ? "Confirm it's you" : 'Confirm to turn off the lock',
        disableDeviceFallback: false,
      });
      if (!result.success) {
        webViewRef.current?.injectJavaScript(
          "window.__fimbyAppLockResult && window.__fimbyAppLockResult({granted:false}); true;"
        );
        return;
      }
      if (enable) {
        await SecureStore.setItemAsync(APP_LOCK_ENABLED_KEY, 'true');
        setAppLockEnabled(true);
        appLockEnabledRef.current = true;
      } else {
        await SecureStore.deleteItemAsync(APP_LOCK_ENABLED_KEY);
        setAppLockEnabled(false);
        appLockEnabledRef.current = false;
      }
      webViewRef.current?.injectJavaScript(
        `window.__fimbyAppLockResult && window.__fimbyAppLockResult({granted:true, enabled:${enable}}); true;`
      );
    } catch {
      webViewRef.current?.injectJavaScript(
        "window.__fimbyAppLockResult && window.__fimbyAppLockResult({granted:false}); true;"
      );
    }
  }, []);

  // Hardening: the OS device push token can rotate mid-session. When it does,
  // re-acquire the *Expo* push token and re-register it so a long-lived session
  // keeps receiving pushes without waiting for the next cold start. Only acts
  // when signed in.
  //
  // addPushTokenListener emits a DevicePushToken (raw APNs/FCM string), NOT an
  // Expo token. Registering that raw value directly would fail the backend's
  // Expo-format validator, so we ignore tokenData.data and go through
  // registerPushNotificationsAsync, which calls getExpoPushTokenAsync to mint
  // the correctly formatted ExponentPushToken[...]. An in-flight guard stops
  // that internal device-token fetch from re-firing this listener into a loop.
  React.useEffect(() => {
    const sub = Notifications.addPushTokenListener(() => {
      const token = accessTokenRef.current;
      if (!token || pushReRegisterInFlightRef.current) {
        return;
      }
      log("[PUSH] Device push token rotated; re-acquiring Expo token");
      pushReRegisterInFlightRef.current = true;
      registerPushNotificationsAsync(token, { prompt: false })
        .catch(() => {})
        .finally(() => {
          pushReRegisterInFlightRef.current = false;
        });
    });
    return () => {
      try {
        sub.remove();
      } catch {
        // Safe to ignore (e.g. Expo Go)
      }
    };
  }, [registerPushNotificationsAsync]);

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
    // Never mint a fresh token while a logout is tearing down the session.
    // Refresh rotates the slot (mints a new family member server-side); if that
    // races a logout, the new token outlives the revoke and silently re-auths
    // the user on next open. Logout owns the session during teardown.
    if (logoutInProgressRef.current) {
      log("[AUTH] refresh skipped — logout in progress");
      return { token: null };
    }

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

    // A logout may have started while this refresh was in flight. The server
    // has already minted a new token (data.refresh_token) — if we persist it,
    // it outlives logout's revoke and re-auths the user. Drop it: revoke the
    // just-minted token and leave the slot for logout to clear.
    if (logoutInProgressRef.current) {
      log("[AUTH] refresh completed during logout — discarding minted token");
      void revokeRefreshTokenOnBackend(data.refresh_token);
      return { token: null };
    }

    await SecureStore.setItemAsync(REFRESH_KEY, data.refresh_token);
    setAccessToken(data.access_token);

    log("[AUTH] refresh successful");

    return { token: data.access_token };
  }, []);

  // Expose refreshSession to earlier-declared callbacks (push "Mark read") via
  // a ref, avoiding a forward-reference TDZ in their dependency arrays.
  React.useEffect(() => {
    refreshSessionRef.current = refreshSession;
  }, [refreshSession]);

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

  const applyFrontdoorPayload = useCallback(
    async (token: string, payload: FrontdoorPayload, retUsed: string | null) => {
      const url = payload?.url;
      if (!url) {
        log("Frontdoor response missing url:", payload);
        setPreAuthCard({ id: 'door' });
        return;
      }

      if (await shouldShowQuietHoursPanda(payload.quietHoursPreference ?? null)) {
        setShowPanda(true);
        return;
      }

      if (retUsed) {
        discardDeepLinkIntent("frontdoor-consumed");
        deeplinkTimingMark("consumed", { path: retUsed });
      }

      authTimingMark("frontdoor_url_set");
      setPreAuthCard(null);
      showWebViewHandoff();
      // Anchor the EC session age clock and clear the re-auth loop guard: a
      // freshly minted frontdoor is a clean, full-lifetime session.
      lastFrontdoorAtRef.current = Date.now();
      reauthAttemptCountRef.current = 0;
      setWebViewUrl(url);
      setStatus("You're in!");
      reconcilePushRegistration(token, payload.pushNotificationsEnabled);
    },
    [
      shouldShowQuietHoursPanda,
      discardDeepLinkIntent,
      showWebViewHandoff,
      reconcilePushRegistration,
    ]
  );

  const openFimby = React.useCallback(
    async (maybeAccess?: string | null, retArg?: string | null) => {
      let token = maybeAccess || accessToken;

      const ret = retArg ?? peekIntentPath(deepLinkIntentRef.current);

      if (!token) {
        const result = await refreshSession();
        if (result.sessionExpired) {
          setPreAuthCard({ id: 'session' });
          return;
        }
        token = result.token;
      }

      if (!token) {
        // No session at all — this IS the sign-in screen's default state, so no
        // card is needed; the Sign In button says it all.
        setPreAuthCard(null);
        return;
      }

      setStatus("Unlocking the door…");
      authTimingMark("frontdoor_fetch_start", { hasRet: !!ret });

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

        const result = await refreshSession();
        if (result.sessionExpired) {
          setPreAuthCard({ id: 'session' });
          return;
        }
        if (!result.token) {
          setPreAuthCard({ id: 'session' });
          return;
        }

        const retry = await fetch(frontdoorUrl, {
          method: "GET",
          headers: { Authorization: `Bearer ${result.token}` },
        });

        if (!retry.ok) {
          const retryBody = await jsonOrText(retry);
          log("Frontdoor retry failed:", retryBody);
          setPreAuthCard({ id: 'door' });
          return;
        }

        const retryJson = (await retry.json()) as FrontdoorPayload;
        await applyFrontdoorPayload(result.token, retryJson, ret);
        return;
      }

      const json = (await res.json()) as FrontdoorPayload;
      await applyFrontdoorPayload(token, json, ret);
    },
    [accessToken, refreshSession, applyFrontdoorPayload]
  );

  const loginWithBackendAndFrontdoor = React.useCallback(
    async (code: string, codeVerifier: string) => {
      if (!codeVerifier) {
        throw new Error("Missing PKCE codeVerifier.");
      }

      setStatus("Doing the secret handshake…");
      authTimingMark("login_start");
      log("Calling /api/login-and-frontdoor at:", BACKEND_LOGIN_AND_FRONTDOOR_URL);

      const ret = peekIntentPath(deepLinkIntentRef.current);
      const res = await fetch(BACKEND_LOGIN_AND_FRONTDOOR_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          code,
          code_verifier: codeVerifier,
          redirect_uri: redirectUri,
          ...(ret ? { ret } : {}),
        }),
      });

      if (!res.ok) {
        const body = await jsonOrText(res);
        log("Backend /api/login-and-frontdoor failed:", body);
        throw new Error("Login failed. See logs.");
      }

      const data = (await res.json()) as LoginAndFrontdoorResponse;

      if (!data?.access_token || !data?.refresh_token || !data?.url) {
        log("Backend /api/login-and-frontdoor unexpected payload:", data);
        throw new Error("Login payload missing tokens or URL.");
      }

      await SecureStore.setItemAsync(REFRESH_KEY, data.refresh_token);
      setAccessToken(data.access_token);
      authTimingMark("login_frontdoor_done");
      authTimingDelta("login_start", "login_frontdoor_done");
      log("[AUTH] login-and-frontdoor successful");

      setStatus("Welcome back!");
      await applyFrontdoorPayload(
        data.access_token,
        {
          url: data.url,
          quietHoursPreference: data.quietHoursPreference,
          pushNotificationsEnabled: data.pushNotificationsEnabled,
        },
        ret
      );

      return data.access_token;
    },
    [applyFrontdoorPayload]
  );

  const openFimbyRef = useRef(openFimby);
  openFimbyRef.current = openFimby;

  // Revoke the refresh family server-side and clear all local session state.
  // Shared by every explicit-logout path (header postMessage, /secur/logout.jsp
  // interception, account deletion). Best-effort revoke with one retry; we clear
  // locally regardless so the device never holds a stranded token.
  const revokeAndClearTokens = React.useCallback(async () => {
    try {
      if (accessTokenRef.current) {
        unregisterTokenFromBackend(accessTokenRef.current).catch(() => {});
      }
      const refresh = await SecureStore.getItemAsync(REFRESH_KEY);
      if (refresh) {
        const revoked = await revokeRefreshTokenOnBackend(refresh);
        if (!revoked) {
          warn("[LOGOUT] backend revoke not confirmed; clearing locally anyway");
        }
      }
      await SecureStore.deleteItemAsync(REFRESH_KEY);
      // A signed-out app has nothing to protect; next user starts fresh.
      await SecureStore.deleteItemAsync(APP_LOCK_ENABLED_KEY).catch(() => {});
      setAppLockEnabled(false);
      appLockEnabledRef.current = false;
      setAccessToken(null);
      bootstrapRanRef.current = false;
    } catch (e: any) {
      log("[LOGOUT] revoke/clear error:", e?.message || e);
    }
  }, [unregisterTokenFromBackend]);

  // Finish an explicit logout: tear down the WebView immediately (so the user
  // sees the pre-auth screen at once) and revoke tokens in the background. Safe
  // to call more than once — the logout endpoint and the trailing /login
  // redirect can both fire — without double-revoking. logoutInProgressRef stays
  // true through teardown so the /login interceptors treat it as logout, not a
  // timeout.
  const completeLogout = React.useCallback(
    (reason: string) => {
      const alreadyTearingDown = logoutInProgressRef.current;
      logoutInProgressRef.current = true;
      log("[LOGOUT] complete:", reason);
      setWebViewUrl(null);
      dismissWebViewHandoff({ immediate: true });
      discardDeepLinkIntent(reason);
      clearInjectFallback();
      setStatus("Until next time!");
      if (alreadyTearingDown) return;
      void revokeAndClearTokens().finally(() => {
        logoutInProgressRef.current = false;
      });
    },
    [dismissWebViewHandoff, discardDeepLinkIntent, clearInjectFallback, revokeAndClearTokens]
  );

  // Silently re-establish a timed-out Experience Cloud session and land the user
  // back on the page they were on — no taps. Refreshes the (still-valid) native
  // token, then re-mints the frontdoor with a `ret` to lastEcPath. Never revokes
  // the refresh token: a timeout is recoverable. Falls to Sign In only when the
  // native session is genuinely expired (30/90-day TTL) or re-mint keeps failing.
  const reestablishEcSession = React.useCallback(
    async (retPath: string | null, reason: string) => {
      if (logoutInProgressRef.current) return;
      if (reauthInFlightRef.current) return;

      const now = Date.now();
      if (now - lastReauthAtRef.current < REAUTH_LOOP_WINDOW_MS) {
        reauthAttemptCountRef.current += 1;
      } else {
        reauthAttemptCountRef.current = 1;
      }
      lastReauthAtRef.current = now;

      const fallToSignIn = (_message?: string) => {
        dismissWebViewHandoff({ immediate: true });
        setWebViewUrl(null);
        setAccessToken(null);
        setPreAuthCard({ id: 'session' });
      };

      if (reauthAttemptCountRef.current > REAUTH_MAX_ATTEMPTS) {
        log("[AUTH] silent re-auth loop guard tripped:", reason);
        fallToSignIn();
        return;
      }

      reauthInFlightRef.current = true;
      log(
        "[AUTH] silent re-auth:",
        reason,
        safeUrlForLog(retPath ? `${SF_AUTH_HOST}${retPath}` : undefined)
      );
      showWebViewHandoff();
      try {
        const result = await refreshSession();
        if (result.sessionExpired || !result.token) {
          fallToSignIn(result.message);
          return;
        }
        await openFimby(result.token, retPath);
      } catch (e: any) {
        log("[AUTH] silent re-auth failed:", e?.message || e);
        fallToSignIn();
      } finally {
        reauthInFlightRef.current = false;
      }
    },
    [refreshSession, openFimby, showWebViewHandoff, dismissWebViewHandoff]
  );

  const logout = React.useCallback(async () => {
    setBusy(true);
    // Claim the session for teardown so an in-flight/triggered refresh can't
    // mint a new token behind us (see refreshSession's logout guards).
    logoutInProgressRef.current = true;
    try {
      // Unregister push token (best-effort, don't block logout)
      if (accessToken) {
        unregisterTokenFromBackend(accessToken).catch(() => {});
      }

      // Revoke server-side first (with one retry). Read the slot last-moment so
      // we revoke whatever token is actually current. Log if it didn't confirm
      // so a stranded, still-valid token in Redis is visible rather than silent.
      const refresh = await SecureStore.getItemAsync(REFRESH_KEY);
      if (refresh) {
        const revoked = await revokeRefreshTokenOnBackend(refresh);
        if (!revoked) {
          warn("[LOGOUT] backend revoke not confirmed; clearing locally anyway");
        }
      }

      await SecureStore.deleteItemAsync(REFRESH_KEY);
      await SecureStore.deleteItemAsync(APP_LOCK_ENABLED_KEY).catch(() => {});
      setAppLockEnabled(false);
      appLockEnabledRef.current = false;
      setAccessToken(null);
      setWebViewUrl(null);
      dismissWebViewHandoff({ immediate: true });
      discardDeepLinkIntent("logout");
      clearInjectFallback();
      bootstrapRanRef.current = false;
      setStatus("Until next time!");
    } finally {
      logoutInProgressRef.current = false;
      setBusy(false);
    }
  }, [accessToken, unregisterTokenFromBackend, discardDeepLinkIntent, clearInjectFallback, dismissWebViewHandoff]);

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
      log("[WebView] onShouldStartLoadWithRequest:", safeUrlForLog(url));

      // Explicit logout: a navigation to /secur/logout.jsp is always a real,
      // user-initiated logout (header web-fallback, VF SiteHeader link, account
      // deletion). Tear down deterministically — this is the signal that lets us
      // treat the trailing /login redirect as logout rather than a timeout.
      if (isFimbyLogoutEndpoint(url)) {
        log("[WebView] Intercepted logout endpoint, tearing down");
        completeLogout("webview-logout-endpoint");
        return false;
      }

      if (isFimbyLoginRedirect(url)) {
        // Our own logout teardown in progress → finish it (don't re-auth).
        if (logoutInProgressRef.current) {
          log("[WebView] /login during logout teardown, finishing logout");
          completeLogout("login-after-logout");
          return false;
        }
        // Unexpected /login = Experience Cloud session timeout. Silently
        // re-establish the frontdoor at the last page; never revoke the
        // still-valid native refresh token here.
        log("[WebView] /login with no logout in progress — treating as timeout");
        void reestablishEcSession(ecUrlToRetPath(lastEcUrlRef.current), "login-redirect-timeout");
        return false; // block the EC login page from rendering
      }

      // Origin allowlist: anything outside the FIMBY/Salesforce surface is
      // opened in the system browser so the Experience Cloud session cookie
      // stays inside the WebView.
      if (!isAllowedWebViewUrl(url)) {
        log("[WebView] Blocked off-origin nav, handing to system browser:", safeUrlForLog(url));
        Linking.openURL(url).catch((err) => {
          log("[WebView] Linking.openURL failed:", err);
        });
        return false;
      }

      return true;
    },
    [completeLogout, reestablishEcSession]
  );

  /**
   * Fallback interception: onNavigationStateChange
   * Fires after navigation state changes. Used as backup for JS redirects.
   * Also clears notification tray + badge when user navigates to /notifications.
   */
  const onNavigationStateChange = useCallback(
    (navState: WebViewNavigation) => {
      const url = navState.url;
      log("[WebView] onNavigationStateChange:", safeUrlForLog(url));

      // Track history depth for the Android back handler below.
      webViewCanGoBackRef.current = navState.canGoBack;

      // Remember the last committed, authenticated page so we can reload it if
      // the WebView process is later killed while backgrounded. Skip the login
      // redirect, about:blank, and anything off the FIMBY/SF surface.
      if (
        !navState.loading &&
        url &&
        url !== "about:blank" &&
        isAllowedWebViewUrl(url) &&
        !isFimbyLoginRedirect(url) &&
        !isFimbyErrorPage(url)
      ) {
        lastEcUrlRef.current = url;
      }

      // The EC /error page is a dead end (static message, no navigation). Show
      // our recovery card so the user can get back instead of force-quitting.
      // Clear it again as soon as they navigate anywhere else.
      if (isFimbyErrorPage(url)) {
        setStuckOnErrorPage(true);
        // The error page never mounts fimbyUniversalHeader, so no quietHours
        // shell-ready signal will arrive. Lift the kettle now (still honours the
        // 1s minimum) so the recovery card is usable without waiting the full
        // fallback window. /login is deliberately excluded: it may be a silent
        // re-auth bounce the kettle should keep hidden.
        markWebViewShellReady("error-page");
      } else if (!navState.loading) {
        setStuckOnErrorPage(false);
      }

      if (injectFallbackRef.current && isExperienceCloudUrl(url)) {
        injectFallbackRef.current.confirmed = true;
        clearInjectFallback();
      }

      if (url.includes("/notifications")) {
        Notifications.dismissAllNotificationsAsync().catch(() => {});
        Notifications.setBadgeCountAsync(0).catch(() => {});
      }

      // Fallback if onShouldStartLoadWithRequest didn't catch it (e.g. JS-driven
      // redirects). Same logout-vs-timeout split as the primary interceptor.
      if (isFimbyLogoutEndpoint(url)) {
        log("[WebView] Fallback: logout endpoint, tearing down");
        completeLogout("nav-logout-endpoint");
        return;
      }

      if (isFimbyLoginRedirect(url)) {
        if (logoutInProgressRef.current) {
          log("[WebView] Fallback: /login during logout teardown, finishing logout");
          completeLogout("nav-login-after-logout");
          return;
        }
        log("[WebView] Fallback: /login with no logout in progress — treating as timeout");
        void reestablishEcSession(ecUrlToRetPath(lastEcUrlRef.current), "nav-login-timeout");
      }
    },
    [clearInjectFallback, completeLogout, reestablishEcSession, markWebViewShellReady]
  );

  /**
   * WebView render error handler -- shows a retry overlay
   */
  const onWebViewError = useCallback(
    (event: WebViewErrorEvent) => {
      const { nativeEvent } = event;
      log("[WebView] Render error:", nativeEvent.description);
      dismissWebViewHandoff({ immediate: true });
      // If the load failed because we're offline, show the warm offline overlay
      // (auto-reloads on reconnect) instead of the generic error screen.
      if (!netConnectedRef.current) {
        webViewOfflineRef.current = true;
        setWebViewOffline(true);
        return;
      }
      setWebViewError(nativeEvent.description || "Something went wrong loading the page.");
    },
    [dismissWebViewHandoff]
  );

  /**
   * WebView HTTP error handler -- catches 401/403 on main frame
   */
  const onHttpError = useCallback(
    (event: WebViewHttpErrorEvent) => {
      const { nativeEvent } = event;
      const statusCode = nativeEvent.statusCode;
      log("[WebView] HTTP error:", statusCode, safeUrlForLog(nativeEvent.url));

      if (statusCode === 401 || statusCode === 403) {
        dismissWebViewHandoff({ immediate: true });
        setWebViewError("Your session has expired. Let's get you signed back in.");
      }
    },
    [dismissWebViewHandoff]
  );

  /**
   * WebView process-death recovery -- the real fix for the blank/white frozen
   * page after a long background. iOS terminates the WKWebView content process
   * (and Android can kill the renderer) to reclaim memory; the view then shows
   * a dead white page and never recovers on its own, because no navigation or
   * HTTP error fires. We remount a fresh native WebView pointed at the last
   * live page (session cookie reload), not the expired one-time frontdoor URL.
   */
  const recoverWebViewFromCrash = useCallback(
    (reason: string) => {
      const now = Date.now();
      if (now - lastCrashRecoverAtRef.current < 4000) {
        crashRecoverCountRef.current += 1;
      } else {
        crashRecoverCountRef.current = 1;
      }
      lastCrashRecoverAtRef.current = now;

      log(
        "[WebView] process gone, recovering:",
        reason,
        safeUrlForLog(lastEcUrlRef.current)
      );

      dismissWebViewHandoff({ immediate: true });

      // Loop guard: if the page keeps crashing on load, stop remounting and let
      // the user retry or sign out via the existing error overlay.
      if (crashRecoverCountRef.current > 3) {
        log("[WebView] repeated crashes; surfacing recovery overlay");
        setWebViewError("FIMBY needs to reload. Tap Try Again to continue.");
        return;
      }

      // Point the remount at the last authenticated page (cookie session) so we
      // land back where the user was; fall back to the current url otherwise.
      if (lastEcUrlRef.current) {
        setWebViewUrl(lastEcUrlRef.current);
      }
      setWebViewKey((k) => k + 1);
    },
    [dismissWebViewHandoff]
  );

  /**
   * Handle messages from LWC (postMessage bridge)
   * quietHours: preference sync + shell-ready signal for the kettle handoff
   */
  const onWebViewMessage = useCallback(
    (event: WebViewMessageEvent) => {
      try {
        const data = JSON.parse(event.nativeEvent.data);
        if (data.type === "quietHours" && data.window) {
          AsyncStorage.setItem("fimby_quiet_hours", data.window).catch(() => {});
          log("[WebView] Quiet hours synced:", data.window);
          markWebViewShellReady("quiet-hours");
        } else if (data.type === "themeChange" && (data.theme === "light" || data.theme === "dark" || data.theme === "auto")) {
          setThemePref(data.theme);
          AsyncStorage.setItem(THEME_STORAGE_KEY, data.theme).catch(() => {});
          log("[WebView] Theme pref synced:", data.theme);
        } else if (data.type === "pushNotifications" && typeof data.enabled === "boolean") {
          log("[WebView] Push toggle synced:", data.enabled);
          void syncPushRegistration(data.enabled);
        } else if (data.type === "appLock" && typeof data.enabled === "boolean") {
          log("[WebView] App lock toggle requested:", data.enabled);
          void handleAppLockToggle(data.enabled);
        } else if (data.type === "appLockCapabilityRequest") {
          // Settings LWC asks on mount so it never renders based on stale
          // first-paint data. Detection long since resolved by this point.
          const payload = JSON.stringify({
            available: appLockCapability.available,
            type: appLockCapability.type,
            enabled: appLockEnabledRef.current,
          });
          webViewRef.current?.injectJavaScript(
            `window.__fimbyAppLockCapabilityResult && window.__fimbyAppLockCapabilityResult(${payload}); true;`
          );
        } else if (data.type === "logout") {
          // Explicit, user-initiated logout from inside the WebView (header,
          // account deletion). Native owns teardown so a real logout is never
          // confused with a session timeout.
          log("[WebView] Native logout requested via postMessage");
          completeLogout("postmessage");
        }
      } catch {
        // Not JSON or not a message we handle
      }
    },
    [syncPushRegistration, completeLogout, markWebViewShellReady, handleAppLockToggle, appLockCapability]
  );

  /**
   * Apply a Universal Link deep-link path to the WebView.
   */
  const applyDeepLink = useCallback((path: string) => {
    log("[DEEPLINK] applying:", path);
    deeplinkTimingMark("apply", { path });

    if (AppState.currentState !== "active") {
      resumeDeepLinkPathRef.current = path;
      captureDeepLinkIntent(path, "universal-link");
      log("[DEEPLINK] deferred until AppState active:", path);
      return;
    }

    captureDeepLinkIntent(path, "universal-link");

    if (webViewRef.current && webViewUrl) {
      const target = `${SF_AUTH_HOST}${path}`;
      webViewRef.current.injectJavaScript(
        `window.location.assign(${JSON.stringify(target)}); true;`
      );
      discardDeepLinkIntent("inject-consumed");
      deeplinkTimingMark("inject", { path });

      clearInjectFallback();
      injectFallbackRef.current = { path, confirmed: false };
      injectFallbackTimeoutRef.current = setTimeout(() => {
        const pending = injectFallbackRef.current;
        if (!pending || pending.confirmed) return;
        const token = accessTokenRef.current;
        if (!token) return;
        log("[DEEPLINK] inject fallback → openFimby", path);
        deeplinkTimingMark("inject-fallback", { path });
        captureDeepLinkIntent(path, "universal-link");
        void openFimbyRef.current(token, path);
        injectFallbackRef.current = null;
      }, INJECT_FALLBACK_MS);
      return;
    }

    if (accessTokenRef.current || accessToken) {
      void openFimbyRef.current(accessTokenRef.current ?? accessToken, path);
      return;
    }

    log("[DEEPLINK] stashed for after sign-in:", path);
  }, [accessToken, webViewUrl, captureDeepLinkIntent, discardDeepLinkIntent, clearInjectFallback]);

  /**
   * Cold-start deep linking when the app was opened from a killed state via push.
   * Runs at most once: later WebView loadEnd events must not re-read the stored tap.
   */
  const handleColdStartNotification = useCallback(async () => {
    if (coldStartPushHandledRef.current) {
      return;
    }

    if (
      bootstrapCapturedUniversalLinkRef.current &&
      isIntentActive(deepLinkIntentRef.current)
    ) {
      log("[DEEPLINK] skipping cold-start push — Universal Link intent active");
      coldStartPushHandledRef.current = true;
      await clearLastNotificationResponse();
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

    // Capture a cold-start Universal Link BEFORE auto-login opens FIMBY, so the
    // frontdoor 'ret' lands the user on the deep-linked page. Without this,
    // openFimby() can fire before getInitialURL() resolves and the deep link is
    // lost — the app appears to hang on the native splash on email-link launches.
    try {
      const initialUrl = await Linking.getInitialURL();
      if (initialUrl) {
        if (isHandoffDeepLink(initialUrl)) handoffSignInRef.current = true;
        const path = parseFimbyDeepLink(initialUrl);
        if (path) {
          captureDeepLinkIntent(path, "bootstrap");
          bootstrapCapturedUniversalLinkRef.current = true;
          deeplinkTimingMark("bootstrap-captured", { path });
          log("[DEEPLINK] cold-start captured in bootstrap:", path);
          await clearLastNotificationResponse();
        }
      }
    } catch (e: any) {
      warn("[DEEPLINK] bootstrap getInitialURL error:", e?.message || e);
    }

    try {
      setStatus("Checking if you're still you…");
      const refresh = await SecureStore.getItemAsync(REFRESH_KEY);
      if (refresh) {
        // Offline pre-flight: a doomed refresh just spins. Show the offline card
        // and auto-resume bootstrap the moment connectivity returns.
        try {
          const net = await NetInfo.fetch();
          if (net.isConnected === false || net.isInternetReachable === false) {
            netConnectedRef.current = false;
            log("[BOOTSTRAP] offline — showing offline card");
            setBooting(false);
            showOfflineCard();
            return;
          }
        } catch {
          // If the probe itself fails, fall through and let the fetch surface it.
        }
        log("[BOOTSTRAP] stored refresh token present");
        const result = await refreshSession();

        if (result.sessionExpired) {
          // Session TTL exceeded. The card renders on the pre-auth screen, which
          // is naturally covered by the splash until it lifts — no manual defer.
          log("Session expired due to TTL policy.");
          setStatus("Let's catch up!");
          setPreAuthCard({ id: 'session' });
        } else if (result.token) {
          log("Valid session found, auto-opening FIMBY...");
          authTimingMark("bootstrap_auto_login");
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
  }, [refreshSession, openFimby, isNetworkError, captureDeepLinkIntent, showOfflineCard]);

  // Keep a ref to the latest runBootstrap so the reconnect resume can re-run it
  // without capturing a stale closure.
  const runBootstrapRef = useRef(runBootstrap);
  runBootstrapRef.current = runBootstrap;

  // On reconnect after an offline card, clear it and pick up where we left off:
  // re-run bootstrap if a session token exists, otherwise fall to the sign-in
  // screen's default state.
  const resumeAfterOffline = useCallback(async () => {
    offlineCardActiveRef.current = false;
    setPreAuthCard((prev) => (prev?.id === 'offline' ? null : prev));
    let refresh: string | null = null;
    try {
      refresh = await SecureStore.getItemAsync(REFRESH_KEY);
    } catch {
      refresh = null;
    }
    if (refresh) {
      void runBootstrapRef.current();
    } else {
      setStatus("Neighbours are waiting.");
    }
  }, []);

  // NetInfo subscription: track connectivity and auto-resume on reconnect (both
  // the pre-auth offline card and an in-session WebView offline overlay).
  React.useEffect(() => {
    const unsubscribe = NetInfo.addEventListener((state) => {
      const connected =
        state.isConnected !== false && state.isInternetReachable !== false;
      const wasConnected = netConnectedRef.current;
      netConnectedRef.current = connected;
      if (wasConnected || !connected) return;

      // Just came back online.
      if (offlineCardActiveRef.current) {
        void resumeAfterOffline();
      }
      if (webViewOfflineRef.current) {
        webViewOfflineRef.current = false;
        setWebViewOffline(false);
        webViewRef.current?.reload();
      }
    });
    return () => unsubscribe();
  }, [resumeAfterOffline]);

  // Initial bootstrap effect
  React.useEffect(() => {
    // Guard: only run bootstrap once on mount
    if (bootstrapRanRef.current) return;
    bootstrapRanRef.current = true;
    // Claim the cold-start deep link synchronously so the deep-link effect below
    // doesn't also consume getInitialURL() and double-open the frontdoor.
    coldStartDeepLinkHandledRef.current = true;
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

    // Cold start is owned by runBootstrap() (it stashes the path before
    // auto-login). Only fall back to handling getInitialURL here if bootstrap
    // somehow didn't claim it, to avoid a double frontdoor call.
    Linking.getInitialURL()
      .then((url) => {
        if (cancelled || !url) return;
        if (coldStartDeepLinkHandledRef.current) return;
        if (isHandoffDeepLink(url)) handoffSignInRef.current = true;
        const path = parseFimbyDeepLink(url);
        if (path) applyDeepLink(path);
      })
      .catch((err) => warn("[DEEPLINK] getInitialURL error:", err));

    const sub = Linking.addEventListener("url", (event) => {
      if (isHandoffDeepLink(event.url)) handoffSignInRef.current = true;
      const path = parseFimbyDeepLink(event.url);
      if (path) applyDeepLink(path);
    });

    return () => {
      cancelled = true;
      sub.remove();
    };
  }, [applyDeepLink]);

  // ─────────────────────────────────────────────────────────────────────────────
  // FOREGROUND RESUME RECONCILIATION
  // One coordinator owns the active transition: replay deferred deep links,
  // notify the WebView, and refresh the native session after a long absence.
  // We never run work while backgrounded — only reconcile when foregrounded.
  // ─────────────────────────────────────────────────────────────────────────────

  // Tell the embedded Experience Cloud app the native shell just resumed, so
  // LWCs can refresh stale data (badge counts, feeds) without a full reload.
  // injectJavaScript must end with `true;` and is a no-op if the WebView is not
  // ready. awayForMs may be null → JSON.stringify(null) emits valid JS.
  const notifyWebViewAppResumed = useCallback(
    (awayForMs: number | null) => {
      if (!webViewRef.current || !webViewUrl) return;
      webViewRef.current.injectJavaScript(`
        window.dispatchEvent(new CustomEvent('fimby-app-resumed', {
          detail: {
            awayForMs: ${JSON.stringify(awayForMs)},
            resumedAt: ${JSON.stringify(Date.now())}
          }
        }));
        true;
      `);
    },
    [webViewUrl]
  );

  const handleAppResumed = useCallback(async () => {
    const now = Date.now();
    const awayForMs = backgroundedAtRef.current
      ? now - backgroundedAtRef.current
      : null;
    // Null immediately so a later inactive→active blip can't reuse a stale time.
    backgroundedAtRef.current = null;

    // Biometric lock gate: re-lock after a long absence (> threshold). Quick app
    // switches stay unlocked. EC work below still runs behind the lock overlay so
    // the app is warm the moment they unlock.
    if (
      appLockEnabledRef.current &&
      awayForMs != null &&
      awayForMs >= APP_LOCK_RESUME_THRESHOLD_MS
    ) {
      setLocked(true);
    }

    // 1. Deferred deep link wins, before any throttle. Auth for this branch is
    //    delegated to applyDeepLink/openFimby and the existing /login intercept.
    const pendingPath = resumeDeepLinkPathRef.current;
    if (pendingPath) {
      resumeDeepLinkPathRef.current = null;
      log("[DEEPLINK] replay on AppState active:", pendingPath);
      applyDeepLink(pendingPath);
      return;
    }

    // 2. Never reconcile during logout teardown or before a session exists.
    if (logoutInProgressRef.current) return;
    if (!webViewUrl) return;

    // 3. Short blips (app switcher, Control Center, Face ID) are no-ops.
    if (awayForMs != null && awayForMs < LIGHT_RESUME_AFTER_MS) return;

    // 4. Throttle the notify + refresh path so rapid switching can't churn.
    if (
      resumeRefreshInFlightRef.current ||
      now - lastResumeRefreshAtRef.current < MIN_RESUME_REFRESH_SPACING_MS
    ) {
      return;
    }

    lastResumeRefreshAtRef.current = now;
    resumeRefreshInFlightRef.current = true;

    try {
      notifyWebViewAppResumed(awayForMs);

      // If the frontdoor (EC) session is likely past the org timeout, silently
      // re-mint it at the last page — no taps. Anchored on when the frontdoor was
      // established (24h since frontdoor login, not last EC activity), per spec.
      // If it turns out the cookie is still alive this is just an extra reload;
      // if it died earlier than this clock, the /login backstop catches it.
      const ecAgeMs =
        lastFrontdoorAtRef.current != null ? now - lastFrontdoorAtRef.current : null;

      if (ecAgeMs != null && ecAgeMs >= EC_SESSION_MAX_AGE_MS) {
        await reestablishEcSession(ecUrlToRetPath(lastEcUrlRef.current), "resume-ec-age");
      } else if (awayForMs == null || awayForMs >= AUTH_RESUME_AFTER_MS) {
        const result = await refreshSession();

        if (result.sessionExpired) {
          // refreshSession already cleared the stored refresh token on failure.
          dismissWebViewHandoff({ immediate: true });
          setWebViewUrl(null);
          setAccessToken(null);
          setPreAuthCard({ id: 'session' });
        }
      }
    } catch (e: any) {
      log("[APPSTATE] resume refresh failed:", e?.message || e);
    } finally {
      resumeRefreshInFlightRef.current = false;
    }
  }, [
    applyDeepLink,
    notifyWebViewAppResumed,
    refreshSession,
    reestablishEcSession,
    dismissWebViewHandoff,
    webViewUrl,
  ]);

  // Single AppState coordinator. Records the earliest away-time on the way out
  // and reconciles on the way back in.
  React.useEffect(() => {
    const sub = AppState.addEventListener("change", (nextState: AppStateStatus) => {
      const prevState = appStateRef.current;
      appStateRef.current = nextState;

      if (nextState === "background" || nextState === "inactive") {
        // Set-if-null preserves the earliest away-time across an
        // active → inactive → background double-fire.
        if (backgroundedAtRef.current == null) {
          backgroundedAtRef.current = Date.now();
        }
        return;
      }

      if (
        nextState === "active" &&
        (prevState === "background" || prevState === "inactive")
      ) {
        void handleAppResumed();
      }
    });

    return () => sub.remove();
  }, [handleAppResumed]);

  // Android hardware/gesture back: walk the WebView's page history instead of
  // backgrounding the app on the first press. Only intercepts when the WebView
  // is showing and has somewhere to go back to; otherwise returns false so the
  // OS default (background the app) runs. iOS has no system back button, so this
  // is Android-only and never touches the iOS swipe gesture.
  React.useEffect(() => {
    if (Platform.OS !== "android") return;
    const sub = BackHandler.addEventListener("hardwareBackPress", () => {
      if (webViewUrl && webViewCanGoBackRef.current && webViewRef.current) {
        webViewRef.current.goBack();
        return true;
      }
      return false;
    });
    return () => sub.remove();
  }, [webViewUrl]);

  /**
   * Start Sign In flow (pre-flight network check + OAuth)
   * Used by both Sign In button and Try Again button
   */
  const startSignIn = useCallback(async () => {
    if (!request) return;

    setBusy(true);
    setPreAuthCard(null);
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
        let offline = !netConnectedRef.current;
        try {
          const net = await NetInfo.fetch();
          offline = net.isConnected === false || net.isInternetReachable === false;
        } catch {
          // keep the netConnectedRef-based guess
        }
        if (offline) {
          netConnectedRef.current = false;
          showOfflineCard();
          return;
        }
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
        "Captured PKCE verifier:",
        pkceVerifierRef.current ? "present" : "missing"
      );

      setStatus("Opening the door…");
      // One-shot non-ephemeral sign-in right after browser password setup: the
      // handoff deep link means Safari holds a live site cookie, so a non-
      // ephemeral sheet turns a retype into a tap-through (iOS). Consumed once,
      // then we fall back to the ephemeral default. Android ignores this flag
      // (Custom Tabs already share cookies).
      const useHandoffSession = handoffSignInRef.current;
      handoffSignInRef.current = false;
      const result = await promptAsync({
        preferEphemeralSession: !useHandoffSession,
      });

      // Handle non-success responses (user cancelled, dismissed, or error)
      if (result.type === 'dismiss' || result.type === 'cancel') {
        discardDeepLinkIntent("oauth-cancel");
        setStatus("Neighbours are waiting.");
      } else if (result.type === 'error') {
        discardDeepLinkIntent("oauth-error");
        log("OAuth error:", result.error);
        setStatus("Something went sideways. Try again?");
      }
      // 'success' is handled by the useEffect watching response
    } finally {
      setBusy(false);
    }
  }, [request, promptAsync, isNetworkError, discardDeepLinkIntent, showOfflineCard]);

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
        discardDeepLinkIntent("oauth-state-mismatch");
        setPreAuthCard({ id: 'signin-failed' });
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

        const token = await loginWithBackendAndFrontdoor(code, verifier);
        if (!token) return;
      } catch (e: any) {
        handledAuthCodeRef.current = null;
        discardDeepLinkIntent("oauth-failed");
        setPreAuthCard({ id: 'signin-failed', detail: e?.message });
      } finally {
        setBusy(false);
      }
    })();
  }, [response, request?.codeVerifier, request?.state, loginWithBackendAndFrontdoor, discardDeepLinkIntent]);

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

  // Splash video plays as an opaque overlay ON TOP of the real app while the
  // app bootstraps. The destination screens below — including the WebView once
  // its frontdoor URL is ready — mount and load UNDERNEATH during these ~3s, so
  // by the time the video lifts the destination is already warm (no remount: the
  // WebView keeps a stable tree position across splashVideoComplete). On a slow
  // network the "kettle" handoff / booting spinner is simply what's revealed when
  // the video lifts. Dismissal is still video-driven (playToEnd / 10s fallback).
  // Neutral themed cover shown only during the brief warm/cold decision window
  // (SecureStore read in flight), so neither the pre-auth screen nor a paused
  // video frame flashes before we know which path to take.
  const nullCover =
    splashDecision === null ? (
      <View
        style={[StyleSheet.absoluteFill, { backgroundColor: PREAUTH_COLORS[appTheme].bg }]}
      />
    ) : null;

  const splashOverlay = splashDecision === 'video' && !splashVideoComplete ? (
    <View style={[StyleSheet.absoluteFill, styles.splashContainer]}>
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
  ) : null;

  // Single deferred loading overlay (bunny → kettle). Rendered above the body so
  // it covers both the pre-frontdoor pre-auth screen and the loading WebView,
  // and below the splash overlay so the video stays on top while it plays.
  //
  // Layout is a pixel-match of the pre-auth screen (logo + tagline up top,
  // spinner + rotating caption in the middle, HELP · FAQ at the bottom) so the
  // curtain drop from bunny → kettle → live app is invisible to the user —
  // only the caption text swaps. Sign Up is intentionally omitted here; once
  // we're loading, we're already signed in.
  // Post-panda override: keep the loading canvas dark (matches the panda
  // backdrop) until EC content paints, so a light-mode user never sees a bright
  // cream flash between panda dismiss and their neighbourhood loading.
  const loadingPalette = postPandaTransition
    ? PREAUTH_COLORS.dark
    : PREAUTH_COLORS[appTheme];
  // Layer 3, ALWAYS in the tree — see webViewHandoffFade for the "why".
  // Visibility is now purely an opacity animation, not a mount/unmount, so
  // no first-paint delay can ever leak a raw underlying frame at the moment
  // the loading state is requested. `pointerEvents` is bound to the visible
  // flag so the invisible overlay never intercepts taps on the pre-auth
  // Sign In button underneath.
  const loadingOverlay = (
    <Animated.View
      pointerEvents={webViewHandoffVisible ? "auto" : "none"}
      style={[
        StyleSheet.absoluteFill,
        { opacity: webViewHandoffFade },
      ]}
    >
      <SafeAreaView
        style={[styles.container, { backgroundColor: loadingPalette.bg }]}
        edges={["top", "bottom"]}
      >
        <View style={styles.contentShift}>
          <View style={styles.upperSection}>
            <Image
              source={getTimeOfDayLogo()}
              style={styles.heroLogo}
              resizeMode="contain"
              accessibilityRole="image"
              accessibilityLabel="FIMBY"
            />
            <Text style={[styles.tagline, { color: loadingPalette.secondary }]}>
              Turning the place you live{"\n"}into a place you belong.
            </Text>
          </View>

          <View style={styles.middleSection}>
            <View style={styles.centerContent}>
              <ActivityIndicator
                size="large"
                color={loadingPalette.spinner}
                style={styles.spinner}
              />
              <Text
                style={[styles.status, { color: loadingPalette.secondary }]}
                accessibilityRole="text"
                accessibilityLiveRegion="polite"
              >
                {loadingCaption}
              </Text>
            </View>
          </View>

          <View style={styles.lowerSection}>
            <View style={styles.footerRow}>
              <Pressable
                hitSlop={12}
                accessibilityRole="link"
                accessibilityLabel="Help"
                onPress={() => openExternal(HELP_URL)}
              >
                <Text style={[styles.footerLinkText, { color: loadingPalette.secondary }]}>HELP</Text>
              </Pressable>
              <Text style={[styles.footerBullet, { color: loadingPalette.secondary }]}>·</Text>
              <Pressable
                hitSlop={12}
                accessibilityRole="link"
                accessibilityLabel="FAQ"
                onPress={() => openExternal(FAQ_URL)}
              >
                <Text style={[styles.footerLinkText, { color: loadingPalette.secondary }]}>FAQ</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </SafeAreaView>
    </Animated.View>
  );

  // Push-permission primer sheet. Shown over the WebView the first (and only)
  // time we would otherwise fire the OS prompt, so the user knows what they're
  // agreeing to before the one-shot system dialog is spent.
  const pushPrimerOverlay = showPushPrimer ? (
    <View style={styles.primerBackdrop}>
      <View
        style={[styles.primerSheet, { backgroundColor: PREAUTH_COLORS[appTheme].bg }]}
        accessibilityViewIsModal
      >
        <Text style={[styles.primerHeading, { color: PREAUTH_COLORS[appTheme].heading }]}>
          Can we knock when something&apos;s waiting?
        </Text>
        <Text style={[styles.primerBody, { color: PREAUTH_COLORS[appTheme].secondary }]}>
          When a neighbour writes to you or something needs your attention, FIMBY sends one
          notification for messages, one for what&apos;s happening nearby, then waits quietly
          until you&apos;ve stopped by. No piling on, and no buzzing during your quiet hours.
          You choose what&apos;s worth a nudge in Settings.
        </Text>
        <Pressable
          style={[styles.button, styles.primerPrimary, { backgroundColor: PREAUTH_COLORS[appTheme].primaryBg }]}
          accessibilityRole="button"
          onPress={() => void acceptPushPrimer()}
        >
          <Text style={[styles.buttonText, { color: PREAUTH_COLORS[appTheme].primaryText }]}>
            Yes please
          </Text>
        </Pressable>
        <Pressable
          style={styles.primerDismiss}
          accessibilityRole="button"
          onPress={() => void declinePushPrimer()}
        >
          <Text style={[styles.primerDismissText, { color: PREAUTH_COLORS[appTheme].secondary }]}>
            Not now
          </Text>
        </Pressable>
      </View>
    </View>
  ) : null;

  // Biometric lock screen. Opaque, themed, topmost. Auto-fires the unlock prompt
  // (see effect); offers a retry after a failed/cancelled attempt and a sign-out
  // escape hatch so nobody is ever locked out of their own device's app.
  const lockMethodLabel = biometricMethodLabel(appLockCapability.type);
  const lockOverlay = locked ? (
    <View style={[styles.lockOverlay, { backgroundColor: PREAUTH_COLORS[appTheme].bg }]}>
      <Image
        source={getTimeOfDayLogo()}
        style={styles.lockLogo}
        resizeMode="contain"
        accessibilityRole="image"
        accessibilityLabel="FIMBY"
      />
      <Text style={[styles.lockTitle, { color: PREAUTH_COLORS[appTheme].heading }]}>
        Unlock FIMBY
      </Text>
      {lockPromptFailed && (
        <Pressable
          style={[styles.button, styles.lockButton, { backgroundColor: PREAUTH_COLORS[appTheme].primaryBg }]}
          accessibilityRole="button"
          onPress={() => void runBiometricUnlock()}
        >
          <Text style={[styles.buttonText, { color: PREAUTH_COLORS[appTheme].primaryText }]}>
            {`Try ${lockMethodLabel} again`}
          </Text>
        </Pressable>
      )}
      <Pressable
        style={styles.lockSignOut}
        accessibilityRole="button"
        onPress={() => {
          setLocked(false);
          void logout();
        }}
      >
        <Text style={[styles.lockSignOutText, { color: PREAUTH_COLORS[appTheme].secondary }]}>
          Sign out instead
        </Text>
      </Pressable>
    </View>
  ) : null;

  // Fail-open notice: shown when the lock auto-disabled because the device has no
  // secure lock of its own to fall back on.
  const appLockNoticeOverlay = appLockDisabledNotice ? (
    <View style={styles.primerBackdrop}>
      <View
        style={[styles.primerSheet, { backgroundColor: PREAUTH_COLORS[appTheme].bg }]}
        accessibilityViewIsModal
      >
        <Text style={[styles.primerHeading, { color: PREAUTH_COLORS[appTheme].heading }]}>
          App lock turned off
        </Text>
        <Text style={[styles.primerBody, { color: PREAUTH_COLORS[appTheme].secondary }]}>
          Your phone doesn&apos;t have a screen lock set up yet, so FIMBY can&apos;t add one. Add a
          passcode or biometric lock in your phone&apos;s settings, then switch this back on in
          FIMBY Settings.
        </Text>
        <Pressable
          style={[styles.button, styles.primerPrimary, { backgroundColor: PREAUTH_COLORS[appTheme].primaryBg }]}
          accessibilityRole="button"
          onPress={() => setAppLockDisabledNotice(false)}
        >
          <Text style={[styles.buttonText, { color: PREAUTH_COLORS[appTheme].primaryText }]}>Got it</Text>
        </Pressable>
      </View>
    </View>
  ) : null;

  // Primary content tree is chosen inline below and rendered inside a single
  // stable top-level Fragment together with all the absolute overlays
  // (loading, push primer, splash, null cover, lock, app-lock notice). Keeping
  // the outer Fragment stable across `showPanda` / `webViewUrl` transitions is
  // what prevents the loading overlay from being unmounted-and-remounted
  // during a branch swap — the source of the "spinner jumps up then back down"
  // stutter Stephen caught between the two loading wheels.
  let primary: React.ReactNode = null;

  // Panda Screen: quiet hours interstitial (before auth)
  if (showPanda && !webViewUrl) {
    const dismissPanda = async () => {
      await AsyncStorage.setItem("lastPandaDate", new Date().toDateString());
      setPandaFarewell(null);
      // Announce the intent to hand off before we do any async work. This flips
      // the panda screen into "opening the door" mode (spinner + caption) and
      // arms the dark palette for the kettle so the panda → EC transition
      // stays visually continuous. The screen itself remains up until
      // openFimby settles (WebView URL set, session card set, or offline
      // path taken) — this is what kills the light-mode cream flash.
      setPandaAcknowledged(true);
      setPostPandaTransition(true);
      postPandaTransitionRef.current = true;
      try {
        await openFimby();
      } finally {
        setShowPanda(false);
        setPandaAcknowledged(false);
      }
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

    primary = (
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
          {pandaAcknowledged
            ? "Opening the door…"
            : (pandaFarewell || "FIMBY is resting right now, but you're always welcome.")}
        </Text>
        {pandaAcknowledged && (
          <ActivityIndicator
            size="large"
            color={PREAUTH_COLORS.dark.spinner}
            style={styles.spinner}
          />
        )}
        {!pandaFarewell && !pandaAcknowledged && (
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
  } else if (webViewUrl) {
    const themeColors = THEME_COLORS[appTheme];
    const handoffPalette = PREAUTH_COLORS[appTheme];
    primary = (
      <SafeAreaView
        style={[styles.safeArea, { backgroundColor: themeColors.statusBar }]}
        edges={Platform.OS === "android" ? ["top", "bottom"] : ["top"]}
      >
        <StatusBar style={themeColors.barStyle} backgroundColor={themeColors.statusBar} />
        <Stack.Screen options={{ headerShown: false }} />
        {/* WebView backgroundColor themed (surface-page) so the loading canvas
            is never bare white — this is what caused the dark-mode flash when
            the kettle faded before EC painted. SafeArea/StatusBar stay on the
            surface-card tone so the top inset matches the EC header. */}
        {/* Plan C: hide the WebView (Layer 2) until EC is truly ready.
            react-native-webview issue #474 confirms WKWebView's frame goes
            through 0,0,0,0 → 0,0,W,0 → 0,0,W,H on iOS first mount, and even
            though our opaque kettle overlay (Layer 3) sits on top, that
            mount reflow was leaking through — this is the "flash between
            bunny and kettle" Stephen was seeing. Wrapping the WebView in an
            Animated.View at opacity=0 makes the mount literally invisible.
            The reveal happens in dismissWebViewHandoff as a crossfade with
            the kettle's own 1→0 fade, so the user only ever sees kettle or
            EC or a smooth blend of the two — never a raw WebView frame. */}
        <Animated.View
          style={[
            styles.webViewWrapper,
            { backgroundColor: handoffPalette.bg, opacity: webViewRevealFade },
          ]}
        >
        <WebView
          key={webViewKey}
          ref={webViewRef}
          source={{ uri: webViewUrl }}
          style={[styles.webView, { backgroundColor: handoffPalette.bg }]}
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
          // Intentionally NO startInLoadingState / renderLoading. Our own
          // `loadingOverlay` is the canonical kettle. (See wrapping comment
          // above for the Plan C reveal-crossfade story.)
          sharedCookiesEnabled={true}
          thirdPartyCookiesEnabled={true}
          // iOS: don't let WKWebView auto-adjust its own scroll insets for
          // safe areas — our SafeAreaView already positions the WebView in
          // the correct frame, and double-inset math is one of the things
          // that makes the WKWebView mount reflow visible.
          contentInsetAdjustmentBehavior="never"
          automaticallyAdjustContentInsets={false}
          // Android scales web content by the OS font/display-size setting;
          // iOS (WKWebView) ignores it. Pin to 100% so both platforms render
          // the LWR site at the same baseline — the device-font scaling was
          // what made everything (text + rem-based spacing) larger on Android.
          textZoom={100}
          applicationNameForUserAgent="FIMBY-WebView/1.0"
          injectedJavaScriptBeforeContentLoaded={
            // Only the always-true "am I in the native app" flag is injected up
            // front. Biometric capability is a Settings-only concern; the LWC
            // pulls it on-demand via an appLockCapabilityRequest message so we
            // never race first paint against async LocalAuthentication reads.
            `window.__FIMBY_NATIVE_APP__ = true; true;`
          }
          onShouldStartLoadWithRequest={onShouldStartLoadWithRequest}
          onNavigationStateChange={onNavigationStateChange}
          onError={onWebViewError}
          onHttpError={onHttpError}
          onContentProcessDidTerminate={() =>
            recoverWebViewFromCrash("ios-content-process-terminated")
          }
          onRenderProcessGone={(event: WebViewRenderProcessGoneEvent) =>
            recoverWebViewFromCrash(
              `android-render-process-gone (didCrash=${event?.nativeEvent?.didCrash})`
            )
          }
          onMessage={onWebViewMessage}
          onLoadEnd={(event) => {
            const { url, loading } = event.nativeEvent;
            handleWebViewLoadEnd(url, loading);
            handleColdStartNotification();
            void maybeRunDeferredPushPrompt();
          }}
        />
        </Animated.View>
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
        {webViewOffline && !webViewError && (
          <View style={[styles.webViewHandoff, { backgroundColor: handoffPalette.bg }]}>
            <Text style={[styles.cardHeading, { color: handoffPalette.heading }]}>
              You&apos;re offline right now
            </Text>
            <Text style={[styles.cardBody, { color: handoffPalette.secondary }]}>
              No rush. We&apos;ll be open for business when you&apos;re back online.
            </Text>
            <Pressable
              style={[styles.button, { backgroundColor: handoffPalette.primaryBg }]}
              accessibilityRole="button"
              onPress={() => {
                webViewOfflineRef.current = false;
                setWebViewOffline(false);
                webViewRef.current?.reload();
              }}
            >
              <Text style={[styles.buttonText, { color: handoffPalette.primaryText }]}>Try again</Text>
            </Pressable>
          </View>
        )}
        {stuckOnErrorPage && !webViewError && !webViewOffline && (
          <View style={styles.stuckOverlay} pointerEvents="box-none">
            <Pressable
              style={[styles.stuckPrimaryButton, { backgroundColor: handoffPalette.primaryBg }]}
              onPress={() => {
                setStuckOnErrorPage(false);
                const target = lastEcUrlRef.current ?? `${SF_AUTH_HOST}/home`;
                setWebViewUrl(target);
                setWebViewKey((k) => k + 1);
              }}
            >
              <Text style={[styles.stuckPrimaryButtonText, { color: handoffPalette.primaryText }]}>
                Back to FIMBY
              </Text>
            </Pressable>
            <Pressable
              style={[
                styles.stuckSecondaryButton,
                { backgroundColor: handoffPalette.bg, borderColor: handoffPalette.signUpOutline },
              ]}
              onPress={() => {
                setStuckOnErrorPage(false);
                logout();
              }}
            >
              <Text style={[styles.stuckSecondaryButtonText, { color: handoffPalette.signUpOutline }]}>
                Sign in again
              </Text>
            </Pressable>
          </View>
        )}
      </SafeAreaView>
    );
  } else {
    // Theme-aware pre-auth palette (applied inline; StyleSheet is static)
    const c = PREAUTH_COLORS[appTheme];

  // Determine what content to show
  const renderContent = () => {
    // Inline card (replaces the old OS alerts). Takes precedence so a session /
    // door / sign-in-failed / offline message is what the user sees.
    if (preAuthCard) {
      const card = PRE_AUTH_CARDS[preAuthCard.id];
      return (
        <View style={styles.centerContent}>
          <Text style={[styles.cardHeading, { color: c.heading }]}>{card.heading}</Text>
          <Text style={[styles.cardBody, { color: c.secondary }]}>{card.body}</Text>
          {preAuthCard.detail ? (
            <Text style={[styles.cardDetail, { color: c.secondary }]}>{preAuthCard.detail}</Text>
          ) : null}
          {card.button ? (
            <Pressable
              style={[
                styles.button,
                styles.cardButton,
                { backgroundColor: c.primaryBg },
                (!request || busy) && styles.buttonDisabled,
              ]}
              disabled={!request || busy}
              accessibilityRole="button"
              onPress={() => {
                if (preAuthCard.id === 'door') {
                  setPreAuthCard(null);
                  void openFimby();
                } else {
                  void startSignIn();
                }
              }}
            >
              <Text style={[styles.buttonText, { color: c.primaryText }]}>{card.button}</Text>
            </Pressable>
          ) : null}
          {busy && (
            <ActivityIndicator size="large" color={c.spinner} style={styles.spinner} />
          )}
        </View>
      );
    }

    // Pre-kettle loading screen (session restoring). Runs UNDER the splash
    // video; revealed if the video lifts before the frontdoor URL is ready.
    if (booting) {
      return (
        <View style={styles.centerContent}>
          <ActivityIndicator size="large" color={c.spinner} style={styles.spinner} />
          <Text style={[styles.status, { color: c.secondary }]}>
            {BOOTSTRAP_LOADING_MESSAGE}
          </Text>
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
          <Text
            style={[styles.status, { color: c.secondary }]}
            accessibilityRole="text"
            accessibilityLiveRegion="polite"
          >
            {status}
          </Text>
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

        <Text
          style={[styles.status, { color: c.secondary }]}
          accessibilityRole="text"
          accessibilityLiveRegion="polite"
        >
          {status}
        </Text>
      </View>
    );
  };

    // Main pre-auth layout: three distinct sections distributed top / middle / bottom
    primary = (
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
            {!booting && !bootstrapError && !preAuthCard && (
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

  // Single, stable top-level Fragment. Because the outer Fragment structure
  // never changes across a `showPanda` / `webViewUrl` swap, React reconciles
  // every overlay in place — `loadingOverlay` (the kettle) in particular
  // stays continuously mounted while the primary tree switches between
  // pre-auth, panda, and WebView. That kills the pre-auth → WebView remount
  // gap where the WebView's built-in centered ActivityIndicator briefly
  // painted underneath our overlay and read as a spinner jumping up and back
  // down. `loadingOverlay` and `pushPrimerOverlay` are already `null` when
  // inactive, so sharing them across branches doesn't leak any behavior; the
  // panda "Opening the door…" state is a beat shorter now because the kettle
  // lands on top the moment `showWebViewHandoff()` fires (dark-to-dark, so
  // visually continuous).
  return (
    <>
      {primary}
      {loadingOverlay}
      {pushPrimerOverlay}
      {splashOverlay}
      {nullCover}
      {lockOverlay}
      {appLockNoticeOverlay}
    </>
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
  cardHeading: {
    fontSize: 22,
    fontFamily: "Nunito_800ExtraBold",
    textAlign: "center",
    marginBottom: 12,
  },
  cardBody: {
    fontSize: 16,
    lineHeight: 23,
    fontFamily: "Nunito_400Regular",
    textAlign: "center",
    paddingHorizontal: 8,
    marginBottom: 24,
  },
  cardDetail: {
    fontSize: 12,
    lineHeight: 17,
    fontFamily: "Nunito_400Regular",
    textAlign: "center",
    opacity: 0.7,
    marginBottom: 20,
    paddingHorizontal: 8,
  },
  cardButton: {
    marginTop: 0,
  },
  // Push-permission primer sheet
  primerBackdrop: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: "rgba(0,0,0,0.5)",
    justifyContent: "flex-end",
  },
  primerSheet: {
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    paddingHorizontal: 28,
    paddingTop: 28,
    paddingBottom: 40,
    alignItems: "center",
  },
  primerHeading: {
    fontSize: 21,
    fontFamily: "Nunito_800ExtraBold",
    textAlign: "center",
    marginBottom: 14,
  },
  primerBody: {
    fontSize: 16,
    lineHeight: 24,
    fontFamily: "Nunito_400Regular",
    textAlign: "center",
    marginBottom: 26,
  },
  primerPrimary: {
    alignSelf: "stretch",
  },
  primerDismiss: {
    paddingVertical: 14,
    marginTop: 8,
  },
  primerDismissText: {
    fontSize: 16,
    fontFamily: "Nunito_700Bold",
  },
  // Biometric lock screen
  lockOverlay: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: 32,
  },
  lockLogo: {
    height: 96,
    aspectRatio: HERO_LOGO_ASPECT,
    maxWidth: "88%",
    marginBottom: 20,
  },
  lockTitle: {
    fontSize: 20,
    fontFamily: "Nunito_800ExtraBold",
    textAlign: "center",
    marginBottom: 24,
  },
  lockButton: {
    marginBottom: 8,
  },
  lockSignOut: {
    paddingVertical: 14,
    marginTop: 8,
  },
  lockSignOutText: {
    fontSize: 15,
    fontFamily: "Nunito_700Bold",
  },
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
  },
  webView: {
    flex: 1,
  },
  webViewWrapper: {
    // Occupies the same flex slot the raw WebView used to; hosts the
    // reveal Animated.Value so we can crossfade EC in as the kettle
    // fades out. backgroundColor is applied inline so the wrapper matches
    // the current theme's handoff palette (light cream / dark surface),
    // meaning any frame where the WebView is at opacity 0 shows flat
    // themed colour rather than a bare gap.
    flex: 1,
  },
  webViewHandoff: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: 32,
  },
  webViewHandoffText: {
    marginTop: 16,
    fontSize: 16,
    textAlign: "center",
    lineHeight: 22,
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
  // Recovery buttons shown over the EC /error dead-end. Centered vertically so
  // they land in the middle of the screen — clear of the error page's own
  // illustration up top and sitting on the empty (black) lower half. No panel:
  // the buttons float directly on the page to avoid overlapping a backdrop with
  // existing content.
  stuckOverlay: {
    ...StyleSheet.absoluteFillObject,
    justifyContent: "center",
    alignItems: "center",
    paddingHorizontal: 32,
  },
  stuckPrimaryButton: {
    alignSelf: "stretch",
    maxWidth: 340,
    width: "100%",
    paddingVertical: 14,
    borderRadius: 12,
    alignItems: "center",
    marginBottom: 14,
    // Lift the button off whatever is behind it in both themes.
    shadowColor: "#000000",
    shadowOpacity: 0.2,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 4 },
    elevation: 6,
  },
  stuckPrimaryButtonText: {
    fontSize: 16,
    fontWeight: "700",
  },
  stuckSecondaryButton: {
    alignSelf: "stretch",
    maxWidth: 340,
    width: "100%",
    paddingVertical: 13,
    borderRadius: 12,
    borderWidth: 1,
    alignItems: "center",
    shadowColor: "#000000",
    shadowOpacity: 0.2,
    shadowRadius: 10,
    shadowOffset: { width: 0, height: 4 },
    elevation: 6,
  },
  stuckSecondaryButtonText: {
    fontSize: 15,
    fontWeight: "600",
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
