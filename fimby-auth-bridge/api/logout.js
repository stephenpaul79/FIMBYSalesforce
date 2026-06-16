import crypto from "crypto";
import jwt from "jsonwebtoken";
import { revokeRefreshToken, revokeRefreshFamily, validateRefreshToken, denyUser, FIMBY_APP_JWT_AUDIENCE } from "../lib/sessions.js";
import { apiHygiene } from "../lib/api-hygiene.js";
import { rateLimit } from "../lib/rate-limit.js";

const DEBUG = process.env.DEBUG_AUTH === "true";
const log = (...args) => DEBUG && console.log(...args);

// Always-on structured event log (mirrors refresh.js). Carries no token
// material — only the event name, request id, and revoke outcome — so it is
// safe to emit unconditionally and turns the blank logout log line into a
// definitive "did this actually revoke?" answer.
const getRequestId = (req) => req.headers["x-request-id"] || crypto.randomUUID();
const event = (obj) => console.log(JSON.stringify(obj));

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

// Best-effort access token verify. Returns payload or null.
function verifyAccessToken(token) {
  const secret = process.env.APP_JWT_SIGNING_SECRET;
  const expectedIssuer = process.env.FIMBY_APP_JWT_ISSUER;
  if (!secret || !expectedIssuer) return null;
  try {
    const p = jwt.verify(token, secret, {
      algorithms: ["HS256"],
      issuer: expectedIssuer,
      audience: FIMBY_APP_JWT_AUDIENCE,
    });
    if (p?.typ !== "access") return null;
    if (typeof p?.sub !== "string" || !p.sub.trim()) return null;
    return p;
  } catch {
    return null;
  }
}

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return oauthError(res, 405, "invalid_request", "Method not allowed");
  }

  const hygiene = apiHygiene(req, res, { maxBodyBytes: 2048 });
  if (hygiene.preflight) return;
  if (!hygiene.ok) {
    return oauthError(res, 400, "invalid_request");
  }

  // IP rate limit: blunt protection before auth work.
  const rl = await rateLimit(req, res, { keyPrefix: "rl:logout:ip", limit: 20, windowSeconds: 60 });
  if (!rl.ok) return oauthError(res, 429, "slow_down", "Too many requests");

  const reqId = getRequestId(req);

  try {
    const { refresh_token } = req.body || {};
    if (!refresh_token || typeof refresh_token !== "string") {
      log("[LOGOUT] Missing or malformed refresh_token in request body");
      event({ event: "logout_missing_token", reqId });
      return oauthError(res, 400, "invalid_request", "Missing refresh_token");
    }

    // Resolve the refresh token against Redis once so we know the owning sub.
    const session = await validateRefreshToken(refresh_token);
    if (!session) {
      // Token isn't active. Treat as idempotent success so legitimate clients
      // don't get stuck on retry, but do not try to revoke anything. This is
      // the silent-failure path: a 200 here means NOTHING was revoked (e.g. the
      // client sent an already-rotated token while a live one persists).
      log("[LOGOUT] Unknown/expired refresh token — nothing to revoke");
      event({ event: "logout_no_active_token", reqId });
      return res.status(200).json({ success: true });
    }

    const refreshSub = session.data?.sub;
    if (typeof refreshSub !== "string" || !refreshSub.trim()) {
      log("[LOGOUT] Refresh record missing sub");
      event({ event: "logout_missing_sub", reqId });
      return oauthError(res, 400, "invalid_request");
    }
    const refreshCreatedAt = session.data?.createdAt;

    // If an access token is present it MUST match. If it's absent we still
    // allow logout since the real owner of the refresh token is (by design)
    // the device that possesses it, and the token sits in Redis with a TTL.
    const bearer = getBearerToken(req);
    if (bearer) {
      const access = verifyAccessToken(bearer);
      if (!access || access.sub !== refreshSub) {
        log("[LOGOUT] access token sub does not match refresh token sub");
        event({ event: "logout_access_sub_mismatch", reqId });
        return oauthError(res, 401, "invalid_token");
      }
    }

    // A logout should end the whole session, not just retire the one token the
    // device happens to hold. Revoke the entire family (every rotated token
    // anchored on this createdAt) so no descendant survives to auto-login.
    // Fall back to single-token revoke if the record predates createdAt.
    // Neutralize any still-valid access token for this user. Revoking the
    // refresh family only stops auto-login; the held 15-min access JWT keeps
    // working at frontdoor until this denylist entry blocks it.
    await denyUser(refreshSub);

    log("[LOGOUT] Revoking refresh token family (fp):", refresh_token.slice(0, 8));
    if (typeof refreshCreatedAt === "number" && Number.isFinite(refreshCreatedAt)) {
      const { revoked } = await revokeRefreshFamily({ sub: refreshSub, createdAt: refreshCreatedAt });
      log("[LOGOUT] Family revoked, members removed:", revoked);
      event({ event: "logout_revoked", reqId, sub: refreshSub, mode: "family", revoked });
    } else {
      await revokeRefreshToken(refresh_token);
      log("[LOGOUT] Single token revoked (no createdAt anchor)");
      event({ event: "logout_revoked", reqId, sub: refreshSub, mode: "single" });
    }

    return res.status(200).json({ success: true });
  } catch (e) {
    // Do NOT swallow: a failed revoke means a still-valid token is left in
    // Redis. Returning 500 lets the client retry instead of stranding it.
    if (DEBUG) log("[LOGOUT] handler error (debug)", e);
    else console.log("[LOGOUT] handler error:", e?.message || e);
    event({ event: "logout_error", reqId, error: e?.message || String(e) });
    return oauthError(res, 500, "server_error");
  }
}
