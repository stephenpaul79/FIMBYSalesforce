/** In-memory deep link intent — one tap, one redirect, then discard. */

export type DeepLinkSource = "universal-link" | "bootstrap";

export type DeepLinkIntent = {
  path: string;
  capturedAt: number;
  source: DeepLinkSource;
};

/** Open-redirect attack window (matches common returnTo cookie max-age). */
export const DEEP_LINK_SECURITY_CAP_MS = 5 * 60 * 1000;

export function isValidDeepLinkPath(path: string): boolean {
  return path.startsWith("/") && !path.startsWith("//");
}

export function createDeepLinkIntent(
  path: string,
  source: DeepLinkSource
): DeepLinkIntent | null {
  if (!isValidDeepLinkPath(path)) return null;
  return { path, capturedAt: Date.now(), source };
}

export function isIntentActive(intent: DeepLinkIntent | null): intent is DeepLinkIntent {
  if (!intent) return false;
  if (!isValidDeepLinkPath(intent.path)) return false;
  return Date.now() - intent.capturedAt <= DEEP_LINK_SECURITY_CAP_MS;
}

/** Read path without discarding (e.g. openFimby before panda may interrupt). */
export function peekIntentPath(intent: DeepLinkIntent | null): string | null {
  return isIntentActive(intent) ? intent.path : null;
}

/** Read path and discard — use-and-discard consumption. */
export function consumeIntentPath(intent: DeepLinkIntent | null): string | null {
  if (!isIntentActive(intent)) return null;
  return intent.path;
}
