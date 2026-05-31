import jwt from "jsonwebtoken";
import { revokeRefreshToken, validateRefreshToken, FIMBY_APP_JWT_AUDIENCE } from "../lib/sessions.js";
import { apiHygiene } from "../lib/api-hygiene.js";
import { rateLimit } from "../lib/rate-limit.js";

const DEBUG = process.env.DEBUG_AUTH === "true";
const log = (...args) => DEBUG && console.log(...args);

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

  try {
    const { refresh_token } = req.body || {};
    if (!refresh_token || typeof refresh_token !== "string") {
      log("[LOGOUT] Missing or malformed refresh_token in request body");
      return oauthError(res, 400, "invalid_request", "Missing refresh_token");
    }

    // Resolve the refresh token against Redis once so we know the owning sub.
    const session = await validateRefreshToken(refresh_token);
    if (!session) {
      // Token isn't active. Treat as idempotent success so legitimate clients
      // don't get stuck on retry, but do not try to revoke anything.
      log("[LOGOUT] Unknown/expired refresh token — nothing to revoke");
      return res.status(200).json({ success: true });
    }

    const refreshSub = session.data?.sub;
    if (typeof refreshSub !== "string" || !refreshSub.trim()) {
      log("[LOGOUT] Refresh record missing sub");
      return oauthError(res, 400, "invalid_request");
    }

    // If an access token is present it MUST match. If it's absent we still
    // allow logout since the real owner of the refresh token is (by design)
    // the device that possesses it, and the token sits in Redis with a TTL.
    const bearer = getBearerToken(req);
    if (bearer) {
      const access = verifyAccessToken(bearer);
      if (!access || access.sub !== refreshSub) {
        log("[LOGOUT] access token sub does not match refresh token sub");
        return oauthError(res, 401, "invalid_token");
      }
    }

    log("[LOGOUT] Revoking refresh token (fp):", refresh_token.slice(0, 8));
    await revokeRefreshToken(refresh_token);
    log("[LOGOUT] Token revoked successfully");

    return res.status(200).json({ success: true });
  } catch (e) {
    if (DEBUG) log("[LOGOUT] handler error (debug)", e);
    else console.log("[LOGOUT] handler error:", e?.message || e);
    return oauthError(res, 500, "server_error");
  }
}
