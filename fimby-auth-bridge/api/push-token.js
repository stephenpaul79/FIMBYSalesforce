// api/push-token.js
// Stores and manages Expo Push Tokens for users

import crypto from "crypto";
import jwt from "jsonwebtoken";
import { getRedis } from "../lib/redis.js";
import { apiHygiene } from "../lib/api-hygiene.js";
import { rateLimit } from "../lib/rate-limit.js";
import { FIMBY_APP_JWT_AUDIENCE, indexUserKey, unindexUserKey } from "../lib/sessions.js";
import { pruneDeadToken } from "../lib/push-tokens.js";

const getRequestId = (req) =>
  req.headers["x-request-id"] || crypto.randomUUID();

const DEBUG = process.env.DEBUG_AUTH === "true";
const log = (...args) => DEBUG && console.log(...args);

const json = (res, status, body) => {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(body));
};

/**
 * Extract and verify app session JWT from Authorization header
 */
function getAppSession(req) {
  const authHeader = req.headers.authorization || req.headers.Authorization;
  if (!authHeader || typeof authHeader !== "string") {
    return null;
  }

  const match = authHeader.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    return null;
  }

  const token = match[1];
  const secret = process.env.APP_JWT_SIGNING_SECRET;
  const expectedIssuer = process.env.FIMBY_APP_JWT_ISSUER;

  if (!secret || !expectedIssuer) {
    log("[PUSH_TOKEN] Missing JWT configuration");
    return null;
  }

  try {
    const payload = jwt.verify(token, secret, {
      algorithms: ["HS256"],
      issuer: expectedIssuer,
      audience: FIMBY_APP_JWT_AUDIENCE,
    });

    if (payload.typ !== "access") {
      log("[PUSH_TOKEN] Invalid token type");
      return null;
    }

    return payload;
  } catch (e) {
    log("[PUSH_TOKEN] JWT verification failed:", e?.message);
    return null;
  }
}

/**
 * Validate Expo Push Token format.
 * Expo tokens look like ExponentPushToken[xxxxxxxxxxxx] or ExpoPushToken[...].
 * The body is URL-safe base64-ish; Expo uses chars A-Z a-z 0-9 _ - (and
 * historically =). We cap the length and restrict the character set to stop
 * callers from registering arbitrary strings as tokens.
 */
function isValidExpoPushToken(token) {
  if (!token || typeof token !== "string") return false;
  if (token.length > 200) return false;
  const expoPattern = /^(?:ExponentPushToken|ExpoPushToken)\[[A-Za-z0-9_\-=]{10,180}\]$/;
  return expoPattern.test(token);
}

// Push tokens expire on the server after this many seconds of idle.
// Each successful register/refresh resets the TTL. Sits well above the
// typical active-user refresh cadence but bounded so abandoned accounts
// eventually age out of Redis.
const PUSH_TOKEN_TTL_SECONDS = 60 * 60 * 24 * 180; // 180 days

export default async function handler(req, res) {
  const reqId = getRequestId(req);

  const hygiene = apiHygiene(req, res, { maxBodyBytes: 2048 });
  if (hygiene.preflight) return;
  if (!hygiene.ok && req.method !== "DELETE") {
    // DELETE has no body; don't fail on content-type
    return json(res, 400, { error: "invalid_request" });
  }

  // Require valid app session for all operations
  const session = getAppSession(req);
  if (!session) {
    console.log(JSON.stringify({ event: "push_token_unauthorized", reqId }));
    return json(res, 401, { error: "unauthorized" });
  }

  const userId = session.sub;

  // Per-user rate limit: prevents a compromised token from churning push
  // token registrations / deletions.
  const rl = await rateLimit(req, res, {
    keyPrefix: "rl:push-token:user",
    limit: 10,
    windowSeconds: 60,
    bucketKey: userId,
  });
  if (!rl.ok) return json(res, 429, { error: "slow_down" });

  try {
    const redis = await getRedis();

    if (req.method === "POST") {
      // Register push token
      const { push_token } = req.body || {};

      if (!push_token) {
        return json(res, 400, { error: "invalid_request", message: "Missing push_token" });
      }

      if (!isValidExpoPushToken(push_token)) {
        log("[PUSH_TOKEN] Invalid token format:", push_token.substring(0, 20));
        return json(res, 400, { error: "invalid_request", message: "Invalid push token format" });
      }

      // If this user previously registered a *different* token, retire the old
      // reverse mapping first. Otherwise push_token_user:<oldToken> keys orphan
      // and linger for the full TTL (180d), one per device/token rotation.
      const priorToken = await redis.get(`push_token:${userId}`);
      if (priorToken && priorToken !== push_token) {
        await redis.del(`push_token_user:${priorToken}`);
        await unindexUserKey(userId, `push_token_user:${priorToken}`);
      }

      // Store push token mapped to user ID with a TTL. Each successful
      // registration refreshes the TTL, so active users always have a
      // valid mapping while abandoned accounts age out.
      await redis.setEx(`push_token:${userId}`, PUSH_TOKEN_TTL_SECONDS, push_token);
      await redis.setEx(`push_token_user:${push_token}`, PUSH_TOKEN_TTL_SECONDS, userId);
      // Mirror both push-token keys into the per-user index so a user lookup
      // surfaces them alongside refresh tokens. push_token_user:<token> carries
      // the userId in its value, not its key, so it would otherwise be invisible.
      await indexUserKey(userId, `push_token:${userId}`);
      await indexUserKey(userId, `push_token_user:${push_token}`);

      console.log(JSON.stringify({ event: "push_token_registered", reqId, user_id: userId }));

      return json(res, 200, { success: true });

    } else if (req.method === "DELETE") {
      // Unregister push token (e.g., on logout). Shares pruneDeadToken with the
      // receipt cron so the two never drift.
      const existingToken = await redis.get(`push_token:${userId}`);

      if (existingToken) {
        await pruneDeadToken(redis, userId, existingToken, "logout");
      }

      console.log(JSON.stringify({ event: "push_token_deleted", reqId, user_id: userId }));

      return json(res, 200, { success: true });

    } else {
      res.setHeader("Allow", "POST, DELETE");
      return json(res, 405, { error: "method_not_allowed" });
    }
  } catch (e) {
    console.log(JSON.stringify({ event: "push_token_error", reqId, error: e?.message }));
    return json(res, 500, { error: "server_error" });
  }
}
