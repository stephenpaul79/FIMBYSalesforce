// api/frontdoor.js
import crypto from "crypto";
import jwt from "jsonwebtoken";
import { apiHygiene } from "../lib/api-hygiene.js";
import { rateLimit } from "../lib/rate-limit.js";
import { FIMBY_APP_JWT_AUDIENCE } from "../lib/sessions.js";

const DEBUG = process.env.DEBUG_AUTH === "true";
const log = (...args) => DEBUG && console.log(...args);

const getRequestId = (req) =>
  req.headers["x-request-id"] || crypto.randomUUID();

// JWT signing key must be provided via env var only. Any filesystem fallback
// would risk bundling the private key with deploy artifacts, so it is not
// supported. Configure SF_PRIVATE_KEY_BASE64 in Vercel and in your local
// .env.development.local.
const { SF_PRIVATE_KEY_BASE64 } = process.env;
if (!SF_PRIVATE_KEY_BASE64 || !SF_PRIVATE_KEY_BASE64.trim()) {
  throw new Error(
    "Missing env var: SF_PRIVATE_KEY_BASE64 (required; no filesystem fallback)"
  );
}
const PRIVATE_KEY = Buffer.from(SF_PRIVATE_KEY_BASE64, "base64").toString("utf8");

function requireEnv(name) {
  const v = process.env[name];
  if (!v || !v.trim()) throw new Error(`Missing env var: ${name}`);
  return v.trim();
}

const oauthError = (res, httpStatus, error, error_description) =>
  res
    .status(httpStatus)
    .json({ error, ...(error_description ? { error_description } : {}) });

function getBearerToken(req) {
  const h = req.headers?.authorization || req.headers?.Authorization;
  if (!h || typeof h !== "string") return null;
  const m = h.match(/^Bearer\s+(.+)$/i);
  return m ? m[1] : null;
}

// Verify app session JWT and return payload (NO client-facing details)
function requireAppSession(req) {
  const secret = requireEnv("APP_JWT_SIGNING_SECRET");
  const expectedIssuer = requireEnv("FIMBY_APP_JWT_ISSUER");
  const token = getBearerToken(req);

  if (!token) {
    const err = new Error("unauthorized");
    err.statusCode = 401;
    err.code = "invalid_token";
    throw err;
  }

  let payload;
  try {
    payload = jwt.verify(token, secret, {
      algorithms: ["HS256"],
      issuer: expectedIssuer,
      audience: FIMBY_APP_JWT_AUDIENCE,
    });
  } catch (e) {
    const err = new Error("unauthorized");
    err.statusCode = 401;
    err.code = "invalid_token";
    err._debug = { reason: "jwt_verify_failed", message: e?.message };
    throw err;
  }

  // Fail helper for internal reasoning without leaking to client
  const fail = (reason, extra = {}) => {
    const err = new Error("unauthorized");
    err.statusCode = 401;
    err.code = "invalid_token";
    err._debug = { reason, ...extra };
    throw err;
  };

  // Require expected token type
  if (payload?.typ !== "access") {
    fail("invalid_token_type", { expectedTyp: "access", gotTyp: payload?.typ });
  }

  // Require sub (string)
  if (typeof payload?.sub !== "string" || !payload.sub.trim()) {
    fail("invalid_sub");
  }

  // Require username (string)
  if (typeof payload?.username !== "string" || !payload.username.trim()) {
    fail("invalid_username");
  }

  // Username sanity checks (MVP)
  const username = payload.username.trim();

  if (username.length > 80) fail("username_too_long");
  if (/\s/.test(username)) fail("username_contains_whitespace");
  if (!/^[a-z0-9]/i.test(username)) fail("username_bad_prefix");
  if (!username.includes("@")) fail("username_missing_at");

  return payload;
}

// JWT bearer -> access token (provider-specific upstream, but generic outward)
async function mintUpstreamAccessTokenForUsername(username) {
  const CONSUMER_KEY = requireEnv("SF_CONSUMER_KEY");

  const LOGIN_HOST = requireEnv("SF_LOGIN_HOST");

  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: CONSUMER_KEY,
    sub: username,
    aud: LOGIN_HOST,
    exp: now + 180,
  };

  const assertion = jwt.sign(payload, PRIVATE_KEY, { algorithm: "RS256" });

  const url = `${LOGIN_HOST}/services/oauth2/token`;
  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion,
  });

  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  const txt = await resp.text();

  if (!resp.ok) {
    const err = new Error("upstream_token_exchange_failed");
    err.statusCode = 502;
    err.code = "server_error";
    err._debug = {
      step: "token_exchange",
      status: resp.status,
      statusText: resp.statusText,
      body: txt,
    };
    throw err;
  }

  let data;
  try {
    data = JSON.parse(txt);
  } catch (e) {
    const err = new Error("upstream_token_parse_failed");
    err.statusCode = 502;
    err.code = "server_error";
    err._debug = { step: "token_parse", body: txt };
    throw err;
  }

  if (!data.access_token) {
    const err = new Error("upstream_token_missing_access_token");
    err.statusCode = 502;
    err.code = "server_error";
    err._debug = { step: "token_shape", keys: Object.keys(data || {}) };
    throw err;
  }

  return { accessToken: data.access_token, instanceUrl: data.instance_url };
}

// access token -> frontdoor URL
async function mintFrontdoorUri(accessToken, redirectPath) {
  const LOGIN_HOST = requireEnv("SF_LOGIN_HOST");
  const url = `${LOGIN_HOST}/services/oauth2/singleaccess`;

  const body = new URLSearchParams({ access_token: accessToken });
  if (redirectPath) body.set("redirect_uri", redirectPath);

  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  const txt = await resp.text();

  if (!resp.ok) {
    const err = new Error("upstream_singleaccess_failed");
    err.statusCode = 502;
    err.code = "server_error";
    err._debug = {
      step: "singleaccess",
      status: resp.status,
      statusText: resp.statusText,
      body: txt,
    };
    throw err;
  }

  let data;
  try {
    data = JSON.parse(txt);
  } catch (e) {
    const err = new Error("upstream_singleaccess_parse_failed");
    err.statusCode = 502;
    err.code = "server_error";
    err._debug = { step: "singleaccess_parse", body: txt };
    throw err;
  }

  const frontdoorUri =
    data.frontdoor_uri || data.frontdoorUrl || data.frontdoorURL;

  if (!frontdoorUri) {
    const err = new Error("upstream_singleaccess_missing_frontdoor");
    err.statusCode = 502;
    err.code = "server_error";
    err._debug = { step: "singleaccess_shape", keys: Object.keys(data || {}) };
    throw err;
  }

  return frontdoorUri;
}

// Best-effort fetch of the user's notification preferences from Salesforce.
// Returns { quietHoursPreference, pushNotificationsEnabled }. The mobile shell
// uses pushNotificationsEnabled to reconcile its device token on every open:
// register when true, delete the stale token when false. We default
// pushNotificationsEnabled to true (matching the User field default) so a fetch
// failure never silently suppresses push for an opted-in user.
async function fetchNotificationPreferences(accessToken, instanceUrl, userId) {
  try {
    const url = `${instanceUrl}/services/data/v62.0/sobjects/User/${userId}?fields=Quiet_Hours_Preference__c,Push_Notifications_Enabled__c`;
    const resp = await fetch(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    if (!resp.ok) return { quietHoursPreference: null, pushNotificationsEnabled: true };
    const data = await resp.json();
    return {
      quietHoursPreference: data.Quiet_Hours_Preference__c || null,
      pushNotificationsEnabled: data.Push_Notifications_Enabled__c !== false,
    };
  } catch {
    return { quietHoursPreference: null, pushNotificationsEnabled: true };
  }
}

export default async function handler(req, res) {
  const reqId = getRequestId(req);

  if (req.method !== "GET" && req.method !== "POST") {
    res.setHeader("Allow", "GET, POST");
    return oauthError(res, 405, "invalid_request");
  }

  // Hygiene: CORS, Content-Type (POST only), small body
  const hygiene = apiHygiene(req, res, { maxBodyBytes: 2048 });
  if (hygiene.preflight) return;
  if (!hygiene.ok) {
    console.log(JSON.stringify({ event: "frontdoor_hygiene_error", reqId, code: hygiene.errorCode }));
    return oauthError(res, 400, "invalid_request");
  }

  // IP rate limit: blunt DoS protection before we decode the JWT
  const ipRl = await rateLimit(req, res, { keyPrefix: "rl:frontdoor:ip", limit: 30, windowSeconds: 60 });
  if (!ipRl.ok) return oauthError(res, 429, "slow_down", "Too many requests");

  try {
    const appSession = requireAppSession(req);

    // Per-user rate limit: prevents a single compromised/misbehaving token
    // from hammering the upstream Salesforce JWT exchange.
    const userRl = await rateLimit(req, res, {
      keyPrefix: "rl:frontdoor:user",
      limit: 20,
      windowSeconds: 60,
      bucketKey: appSession.sub,
    });
    if (!userRl.ok) return oauthError(res, 429, "slow_down", "Too many requests");

    const username = appSession.username;

    // Strict relative-path allowlist for ret. Rejects absolute/protocol-relative
    // URLs, backslashes, and anything that could turn into an open-redirect
    // on the Salesforce singleaccess endpoint.
    // Allowed chars: alphanumerics, -, _, ., ~, /, ?, =, &, %, +, : (none at start),
    // plus fragments (#). Must start with exactly one '/'.
    const rawRet = (req.query.ret || "/").toString();
    const RET_ALLOWED = /^\/[A-Za-z0-9\-._~/?&=%+:#@]*$/;
    const RET_BLOCKED = /^\/\/|^\/\\|\.\.|\\\\|[\x00-\x1f]/;
    let ret;
    if (rawRet === "/" || (RET_ALLOWED.test(rawRet) && !RET_BLOCKED.test(rawRet) && rawRet.length <= 512)) {
      ret = rawRet.replace(/^\/+/, "");
    } else {
      log("[FRONTDOOR] rejecting invalid ret, falling back to '/'", { retLen: rawRet.length });
      ret = "";
    }

    // Debug only
    log("[FRONTDOOR] ret (debug)", ret);
    log("[FRONTDOOR] username_fp (debug)", String(username).slice(0, 3));

    const { accessToken: upstreamAccessToken, instanceUrl } =
      await mintUpstreamAccessTokenForUsername(username);

    const [frontdoorUri, prefs] = await Promise.all([
      mintFrontdoorUri(upstreamAccessToken, ret),
      fetchNotificationPreferences(upstreamAccessToken, instanceUrl, appSession.sub),
    ]);

    console.log(JSON.stringify({ event: "frontdoor_success", reqId, sub: appSession.sub }));

    return res.status(200).json({
      url: frontdoorUri,
      quietHoursPreference: prefs.quietHoursPreference,
      pushNotificationsEnabled: prefs.pushNotificationsEnabled,
    });
  } catch (e) {
    const status = e?.statusCode || 500;
    const code = e?.code || "server_error";

    if (DEBUG) {
      log("[FRONTDOOR] error (debug)", {
        status,
        code,
        message: e?.message,
        debug: e?._debug,
      });
    }
    console.log(JSON.stringify({ event: "frontdoor_error", reqId, status, code }));

    // Client gets only generic, provider-agnostic errors
    if (status === 401) return oauthError(res, 401, "invalid_token");
    if (status === 403) return oauthError(res, 403, "access_denied");
    if (status === 400) return oauthError(res, 400, "invalid_request");

    return oauthError(res, 500, "server_error");
  }
}
