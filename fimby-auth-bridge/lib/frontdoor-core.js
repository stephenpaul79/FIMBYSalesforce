import jwt from "jsonwebtoken";

const DEBUG = process.env.DEBUG_AUTH === "true";
const log = (...args) => DEBUG && console.log(...args);

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

const RET_ALLOWED = /^\/[A-Za-z0-9\-._~/?&=%+:#@]*$/;
const RET_BLOCKED = /^\/\/|^\/\\|\.\.|\\\\|[\x00-\x1f]/;

/** Strict relative-path allowlist for frontdoor ret. */
export function normalizeFrontdoorRet(rawRet) {
  const raw = (rawRet ?? "/").toString();
  if (
    raw === "/" ||
    (RET_ALLOWED.test(raw) && !RET_BLOCKED.test(raw) && raw.length <= 512)
  ) {
    return raw.replace(/^\/+/, "");
  }
  log("[FRONTDOOR] rejecting invalid ret, falling back to '/'", { retLen: raw.length });
  return "";
}

export async function mintUpstreamAccessTokenForUsername(username) {
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
  } catch {
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

export async function mintFrontdoorUri(accessToken, redirectPath) {
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
  } catch {
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

export async function fetchNotificationPreferences(accessToken, instanceUrl, userId) {
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

/**
 * Mint frontdoor URL for a username. When deferPrefs is true (default), User SOQL
 * runs fire-and-forget so the mobile client gets the URL on the critical path.
 */
export async function buildFrontdoorPayload(username, userId, rawRet, options = {}) {
  const { deferPrefs = true } = options;
  const ret = normalizeFrontdoorRet(rawRet);

  const { accessToken: upstreamAccessToken, instanceUrl } =
    await mintUpstreamAccessTokenForUsername(username);

  const frontdoorUri = await mintFrontdoorUri(upstreamAccessToken, ret);

  if (deferPrefs) {
    fetchNotificationPreferences(upstreamAccessToken, instanceUrl, userId).catch(
      (e) => {
        if (DEBUG) log("[FRONTDOOR] deferred prefs fetch failed (debug)", e?.message);
      }
    );
    return {
      url: frontdoorUri,
      quietHoursPreference: null,
      pushNotificationsEnabled: undefined,
    };
  }

  const prefs = await fetchNotificationPreferences(
    upstreamAccessToken,
    instanceUrl,
    userId
  );

  return {
    url: frontdoorUri,
    quietHoursPreference: prefs.quietHoursPreference,
    pushNotificationsEnabled: prefs.pushNotificationsEnabled,
  };
}
