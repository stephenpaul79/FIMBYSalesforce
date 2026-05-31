/**
 * Dev-only logger.
 *
 * In release builds (`__DEV__ === false`) every call is a no-op, so nothing
 * hits the device log, logcat, os_log, Sentry, or any collector an attacker
 * or OEM might scrape. We still keep call sites so dev builds can trace
 * behaviour.
 *
 * Rules for callers:
 * - Never pass a bearer token, refresh token, session JWT, OAuth code, PKCE
 *   verifier, or frontdoor URL into these helpers. Even in dev, those values
 *   show up in `adb logcat` and in screen-recording sessions.
 * - If you want to confirm "a token exists / roughly this shape", log a
 *   redacted summary (e.g. `"present"` / `"missing"`), not the value or its
 *   length.
 * - Metadata like request IDs, event names, URL paths (no query string), and
 *   HTTP status codes are fine.
 */

type LogFn = (...args: unknown[]) => void;

const noop: LogFn = () => {};

export const log: LogFn = __DEV__ ? (...args) => console.log(...args) : noop;
export const warn: LogFn = __DEV__ ? (...args) => console.warn(...args) : noop;
export const error: LogFn = __DEV__ ? (...args) => console.error(...args) : noop;
