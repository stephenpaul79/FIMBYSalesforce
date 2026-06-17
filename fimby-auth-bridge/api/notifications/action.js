// api/notifications/action.js
// Performs a push-notification quick action (e.g. "mark read") on behalf of the
// authenticated app user WITHOUT opening the app. The device cannot talk to
// Salesforce directly (it never holds an SF token), so this endpoint:
//   1. verifies the app-session JWT (same as frontdoor / push-token),
//   2. mints a short-lived Salesforce access token for that user (JWT Bearer),
//   3. calls the FimbyPushActionResource Apex REST endpoint, which re-checks
//      ownership server-side and marks the notification (and DM conversation) read.
//
// This is the first bridge endpoint that writes to Salesforce on a user's behalf.
// It is gated by app-JWT verification + the revocation denylist + per-user rate
// limiting, and the Apex re-enforces ownership, so a device can only ever act on
// its own notifications.

import crypto from "crypto";
import jwt from "jsonwebtoken";
import { apiHygiene } from "../../lib/api-hygiene.js";
import { rateLimit } from "../../lib/rate-limit.js";
import { FIMBY_APP_JWT_AUDIENCE, isUserDenied } from "../../lib/sessions.js";
import { mintUpstreamAccessTokenForUsername } from "../../lib/frontdoor-core.js";

const DEBUG = process.env.DEBUG_AUTH === "true";
const log = (...args) => DEBUG && console.log(...args);

const getRequestId = (req) =>
  req.headers["x-request-id"] || crypto.randomUUID();

const json = (res, status, body) => {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(body));
};

function requireEnv(name) {
  const v = process.env[name];
  if (!v || !v.trim()) throw new Error(`Missing env var: ${name}`);
  return v.trim();
}

function getBearerToken(req) {
  const h = req.headers?.authorization || req.headers?.Authorization;
  if (!h || typeof h !== "string") return null;
  const m = h.match(/^Bearer\s+(.+)$/i);
  return m ? m[1] : null;
}

// Mirrors frontdoor.js requireAppSession: verify the app access JWT and return
// its payload (sub = SF user id, username = SF username). Throws {statusCode}.
function requireAppSession(req) {
  const secret = requireEnv("APP_JWT_SIGNING_SECRET");
  const expectedIssuer = requireEnv("FIMBY_APP_JWT_ISSUER");
  const token = getBearerToken(req);

  const fail = (reason, extra = {}) => {
    const err = new Error("unauthorized");
    err.statusCode = 401;
    err._debug = { reason, ...extra };
    throw err;
  };

  if (!token) fail("missing_token");

  let payload;
  try {
    payload = jwt.verify(token, secret, {
      algorithms: ["HS256"],
      issuer: expectedIssuer,
      audience: FIMBY_APP_JWT_AUDIENCE,
    });
  } catch (e) {
    fail("jwt_verify_failed", { message: e?.message });
  }

  if (payload?.typ !== "access") fail("invalid_token_type");
  if (typeof payload?.sub !== "string" || !payload.sub.trim()) fail("invalid_sub");
  if (typeof payload?.username !== "string" || !payload.username.trim()) fail("invalid_username");

  const username = payload.username.trim();
  if (username.length > 80) fail("username_too_long");
  if (/\s/.test(username)) fail("username_contains_whitespace");
  if (!/^[a-z0-9]/i.test(username)) fail("username_bad_prefix");
  if (!username.includes("@")) fail("username_missing_at");

  return payload;
}

// Salesforce 15/18-char id, loosely validated before we forward it.
function isSafeSalesforceId(v) {
  return typeof v === "string" && /^[a-zA-Z0-9]{15,18}$/.test(v);
}

const ALLOWED_ACTIONS = new Set(["mark_read"]);

const APEX_ACTION_PATH = "/services/apexrest/fimby/push-action";

export default async function handler(req, res) {
  const reqId = getRequestId(req);

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return json(res, 405, { error: "method_not_allowed" });
  }

  const hygiene = apiHygiene(req, res, { maxBodyBytes: 2048 });
  if (hygiene.preflight) return;
  if (!hygiene.ok) {
    return json(res, hygiene.errorCode === "payload_too_large" ? 413 : 400, {
      error: hygiene.errorCode || "invalid_request",
    });
  }

  const ipRl = await rateLimit(req, res, {
    keyPrefix: "rl:push-action:ip",
    limit: 60,
    windowSeconds: 60,
  });
  if (!ipRl.ok) return json(res, 429, { error: "slow_down" });

  try {
    const session = requireAppSession(req);

    if (await isUserDenied(session.sub)) {
      console.log(JSON.stringify({ event: "push_action_denied", reqId, sub: session.sub }));
      return json(res, 401, { error: "unauthorized" });
    }

    const userRl = await rateLimit(req, res, {
      keyPrefix: "rl:push-action:user",
      limit: 30,
      windowSeconds: 60,
      bucketKey: session.sub,
    });
    if (!userRl.ok) return json(res, 429, { error: "slow_down" });

    const body = req.body || {};
    const action = typeof body.action === "string" ? body.action : "mark_read";
    const notificationId = body.notificationId;

    if (!ALLOWED_ACTIONS.has(action)) {
      return json(res, 400, { error: "unsupported_action" });
    }
    if (!isSafeSalesforceId(notificationId)) {
      return json(res, 400, { error: "invalid_notification_id" });
    }

    // Mint a short-lived SF access token for this user and call Apex REST.
    const { accessToken, instanceUrl } = await mintUpstreamAccessTokenForUsername(
      session.username
    );

    const apexResp = await fetch(`${instanceUrl}${APEX_ACTION_PATH}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ action, notificationId }),
    });

    const text = await apexResp.text();
    let parsed;
    try {
      parsed = text ? JSON.parse(text) : {};
    } catch {
      parsed = {};
    }

    if (!apexResp.ok) {
      log("[PUSH_ACTION] Apex error", apexResp.status, text);
      console.log(JSON.stringify({ event: "push_action_apex_error", reqId, status: apexResp.status }));
      return json(res, 502, { error: "server_error" });
    }

    console.log(JSON.stringify({
      event: "push_action_done",
      reqId,
      action,
      status: parsed?.status || "unknown",
    }));

    return json(res, 200, { ok: true, status: parsed?.status || "ok" });
  } catch (e) {
    const status = e?.statusCode || 500;
    if (DEBUG) log("[PUSH_ACTION] error", { status, message: e?.message, debug: e?._debug });
    console.log(JSON.stringify({ event: "push_action_error", reqId, status }));
    if (status === 401) return json(res, 401, { error: "unauthorized" });
    return json(res, 500, { error: "server_error" });
  }
}
