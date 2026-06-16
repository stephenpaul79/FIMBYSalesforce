import crypto from "crypto";
import {
  mintAccessToken,
  mintRefreshToken,
  validateRefreshToken,
  validateSessionTTL,
  familyIsKnown,
  refreshTokenIsFamilyMember,
  revokeRefreshFamily,
  parseRefreshTokenSafe,
  isUserDenied,
} from "../../lib/sessions.js";
import { getRedis } from "../../lib/redis.js";
import { apiHygiene } from "../../lib/api-hygiene.js";
import { rateLimit } from "../../lib/rate-limit.js";

const getRequestId = (req) =>
  req.headers["x-request-id"] || crypto.randomUUID();


const DEBUG = process.env.DEBUG_AUTH === "true";
const log = (...args) => DEBUG && console.log(...args);

const oauthError = (res, httpStatus, error, error_description) =>
  res
    .status(httpStatus)
    .json({ error, ...(error_description ? { error_description } : {}) });

export default async function handler(req, res) {
  const reqId = getRequestId(req);

  // API Hygiene: CORS, Content-Type, body size
  const hygiene = apiHygiene(req, res, { maxBodyBytes: 5120 });
  if (hygiene.preflight) return; // OPTIONS handled
  if (!hygiene.ok) {
    console.log(JSON.stringify({ event: "refresh_hygiene_error", reqId, code: hygiene.errorCode }));
    return oauthError(res, 400, "invalid_request");
  }

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return oauthError(res, 405, "invalid_request", "Method not allowed");
  }

  const rl = await rateLimit(req, res, {
    keyPrefix: "rl:refresh",
    limit: 30,
    windowSeconds: 60,
  });
  if (!rl.ok) return oauthError(res, 429, "slow_down", "Too many requests");

  try {
    const { refresh_token } = req.body || {};
    if (!refresh_token) return oauthError(res, 400, "invalid_request");

    const validated = await validateRefreshToken(refresh_token);
    if (!validated) {
      // Reuse detection: if the token parses cleanly AND the family still has
      // live members, this is almost certainly a replay of a token that was
      // rotated out. Revoke the entire family to kick both the legitimate
      // client and the attacker back to login.
      const parsed = parseRefreshTokenSafe(refresh_token);
      if (parsed && typeof parsed.userId === "string" && parsed.userId.length > 0) {
        try {
          const known = await familyIsKnown({ sub: parsed.userId, createdAt: parsed.createdAt });
          // Only revoke the family if the presented token was genuinely a
          // former member (its hash is in the family set). Otherwise a forged
          // <victimId>.<createdAt>.<garbage> token could nuke a victim's
          // session family — a forced-logout DoS — without ever holding a
          // real token.
          const isRealMember = known && (await refreshTokenIsFamilyMember(refresh_token));
          if (isRealMember) {
            const { revoked } = await revokeRefreshFamily({
              sub: parsed.userId,
              createdAt: parsed.createdAt,
            });
            console.log(JSON.stringify({
              event: "refresh_reuse_detected",
              reqId,
              sub: parsed.userId,
              revoked,
            }));
          } else {
            console.log(JSON.stringify({ event: "refresh_invalid_token", reqId }));
          }
        } catch (e) {
          console.log(JSON.stringify({ event: "refresh_reuse_check_failed", reqId, error: e?.message }));
        }
      } else {
        console.log(JSON.stringify({ event: "refresh_invalid_token", reqId }));
      }
      return oauthError(res, 401, "invalid_grant");
    }

    const { key, data } = validated;

    // Revocation check: refuse to mint new tokens for a denied user even if the
    // refresh token still validates (logout sets the denylist before the family
    // revoke completes, and this guards any token that slips past that).
    if (await isUserDenied(data.sub)) {
      console.log(JSON.stringify({ event: "refresh_denied", reqId, sub: data.sub }));
      return oauthError(res, 401, "invalid_grant");
    }

    // Debug only: fingerprints, never the token itself
    log("[REFRESH] refresh key fp (debug)", String(key || "").slice(0, 12));
    log("[REFRESH] sub fp (debug)", String(data?.sub || "").slice(0, 6));

    // ─────────────────────────────────────────────────────────────────────────
    // Enforce Session TTL Policy (idle + absolute)
    // ─────────────────────────────────────────────────────────────────────────
    const ttlCheck = validateSessionTTL(data);
    if (!ttlCheck.valid) {
      console.log(JSON.stringify({ event: "refresh_session_expired", reqId, sub: data.sub, expiry_type: ttlCheck.expiry_type }));
      // Delete the expired session
      const redis = await getRedis();
      try {
        await redis.del(key);
      } catch (e) {
        log("[REFRESH] failed to delete expired session", e?.message);
      }
      return oauthError(res, 401, ttlCheck.code, ttlCheck.reason);
    }

    const redis = await getRedis();

    // Safer rotation order:
    // 1) mint new tokens first
    // 2) delete old refresh token last
    // This avoids "logged out" edge cases if redis blips mid-flight.
    const access_token = mintAccessToken({
      sub: data.sub,
      username: data.username,
    });
    // Pass original createdAt to preserve absolute TTL anchor, increment refreshCount
    const newRefreshCount = (data.refreshCount || 0) + 1;
    const { refreshToken: new_refresh_token } = await mintRefreshToken({
      sub: data.sub,
      username: data.username,
      createdAt: data.createdAt,
      refreshCount: newRefreshCount,
    });

    try {
      await redis.del(key);
    } catch (e) {
      // Not a security issue, but worth logging. We still succeed so the user doesn't get punted.
      console.log(JSON.stringify({ event: "refresh_redis_del_failed", reqId, error: e?.message }));
    }

    console.log(JSON.stringify({ event: "refresh_success", reqId, sub: data.sub, refreshCount: newRefreshCount }));

    return res.status(200).json({
      access_token,
      refresh_token: new_refresh_token,
      token_type: "bearer",
      expires_in: 15 * 60,
    });
  } catch (e) {
    console.log(JSON.stringify({ event: "refresh_error", reqId, error: e?.message }));
    return oauthError(res, 500, "server_error");
  }
}
