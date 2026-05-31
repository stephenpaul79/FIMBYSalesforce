import crypto from "crypto";
import jwt from "jsonwebtoken";
import { getRedis } from "./redis.js";

// ─────────────────────────────────────────────────────────────────────────────
// TTL Policy Constants
// ─────────────────────────────────────────────────────────────────────────────
const ACCESS_TTL_SECONDS = 15 * 60;              // 15 minutes
const IDLE_TTL_MS = 30 * 24 * 60 * 60 * 1000;    // 30 days (sliding)
const ABSOLUTE_TTL_MS = 90 * 24 * 60 * 60 * 1000; // 90 days (hard cap)
const REFRESH_TTL_SECONDS = 30 * 24 * 60 * 60;   // 30 days (Redis key TTL)

// ─────────────────────────────────────────────────────────────────────────────
// Night-time Cutoff Helper
// Instead of expiring mid-day, wait until 2am PST (10:00 UTC) after absolute TTL
// ─────────────────────────────────────────────────────────────────────────────
function getNextNightCutoff(afterTimestamp) {
  const d = new Date(afterTimestamp);
  // 2am PST = 10:00 UTC (PST is UTC-8)
  // Note: This uses standard time. During PDT (UTC-7), 2am PDT = 09:00 UTC
  // We use 10:00 UTC year-round for consistency (2am PST / 3am PDT)
  d.setUTCHours(10, 0, 0, 0);
  // If we're already past 10:00 UTC today, move to tomorrow
  if (d.getTime() <= afterTimestamp) {
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return d.getTime();
}

function sha256(input) {
  return crypto.createHash("sha256").update(input).digest("hex");
}

// ─────────────────────────────────────────────────────────────────────────────
// Refresh Token Format
// Token: <userId>.<createdAt>.<randomBytes>
// Key:   refresh:<userId>:<createdAt>:<shortHash>
//
// Benefits:
// - Keys sorted by user, then by time (easy to browse in Redis UI)
// - Can find all sessions for a user: KEYS refresh:<userId>:*
// - Can see at a glance when session was created
// - Still secure (random bytes + hash required for lookup)
// ─────────────────────────────────────────────────────────────────────────────
const SHORT_HASH_LENGTH = 12; // First 12 chars of hash for key suffix

function buildRefreshToken(userId, createdAt, randomBytes) {
  return `${userId}.${createdAt}.${randomBytes}`;
}

function parseRefreshToken(rawToken) {
  const parts = rawToken.split(".");
  if (parts.length !== 3) {
    throw new Error("Invalid refresh token format");
  }
  return { userId: parts[0], createdAt: parseInt(parts[1], 10), random: parts[2] };
}

function buildRefreshKey(userId, createdAt, tokenHash) {
  const shortHash = tokenHash.slice(0, SHORT_HASH_LENGTH);
  return `refresh:${userId}:${createdAt}:${shortHash}`;
}

// Default audience is the mobile bundle ID. Override via env var if you ever
// need to issue tokens to a second audience (e.g. a web console). Verifiers
// MUST require this exact audience — a mismatched token is a leaked token.
export const FIMBY_APP_JWT_AUDIENCE =
  process.env.FIMBY_APP_JWT_AUDIENCE || "com.fimby.app";

export function mintAccessToken({ sub, username }) {
  if (!process.env.APP_JWT_SIGNING_SECRET) {
    throw new Error("Missing APP_JWT_SIGNING_SECRET");
  }
  if (!process.env.FIMBY_APP_JWT_ISSUER) {
    throw new Error("Missing FIMBY_APP_JWT_ISSUER");
  }

  return jwt.sign(
    {
      iss: process.env.FIMBY_APP_JWT_ISSUER,
      aud: FIMBY_APP_JWT_AUDIENCE,
      sub,
      username,
      typ: "access",
    },
    process.env.APP_JWT_SIGNING_SECRET,
    { expiresIn: ACCESS_TTL_SECONDS, algorithm: "HS256" }
  );
}

// Family index lives under family:<sub>:<createdAt>. createdAt is preserved
// across rotations for a single session, so it doubles as a stable family
// identifier. The SET holds every refresh key in the family (rotation + the
// current one). See detectAndRevokeReuse below.
function buildFamilyKey(sub, createdAt) {
  return `family:${sub}:${createdAt}`;
}

export async function mintRefreshToken({ sub, username, createdAt = null, refreshCount = 0 }) {
  const redis = await getRedis();

  const now = Date.now();
  const sessionCreatedAt = createdAt || now;
  const randomBytes = crypto.randomBytes(32).toString("base64url");

  // Token format: <userId>.<createdAt>.<random>
  const rawToken = buildRefreshToken(sub, sessionCreatedAt, randomBytes);
  const hash = sha256(rawToken);

  // Key format: refresh:<userId>:<createdAt>:<shortHash>
  const key = buildRefreshKey(sub, sessionCreatedAt, hash);
  const familyKey = buildFamilyKey(sub, sessionCreatedAt);

  const payload = {
    sub,
    username,
    typ: "refresh",
    createdAt: sessionCreatedAt,
    lastUsedAt: now,
    refreshCount,
  };

  // Store server-side with TTL
  await redis.setEx(key, REFRESH_TTL_SECONDS, JSON.stringify(payload));
  // Track family membership so we can revoke every descendant on reuse. We
  // let the family set live slightly longer than individual tokens so the
  // index is always the last thing to expire.
  await redis.sAdd(familyKey, key);
  await redis.expire(familyKey, REFRESH_TTL_SECONDS + 60);

  return { refreshToken: rawToken, refreshHash: hash };
}

export async function validateRefreshToken(rawRefreshToken) {
  const redis = await getRedis();

  let parsed;
  try {
    parsed = parseRefreshToken(rawRefreshToken);
  } catch {
    return null; // Invalid token format
  }

  const hash = sha256(rawRefreshToken);
  const key = buildRefreshKey(parsed.userId, parsed.createdAt, hash);
  const stored = await redis.get(key);

  if (!stored) return null;

  return { key, data: JSON.parse(stored) };
}

export async function revokeRefreshToken(rawRefreshToken) {
  const redis = await getRedis();

  let parsed;
  try {
    parsed = parseRefreshToken(rawRefreshToken);
  } catch {
    return; // Invalid token format, nothing to revoke
  }

  const hash = sha256(rawRefreshToken);
  const key = buildRefreshKey(parsed.userId, parsed.createdAt, hash);
  const familyKey = buildFamilyKey(parsed.userId, parsed.createdAt);
  await redis.del(key);
  // Keep the family set in sync so it doesn't grow unboundedly.
  await redis.sRem(familyKey, key);
}

/**
 * Revoke every active refresh token in the same family (same session anchor).
 * Use this when a token-reuse attempt is detected.
 */
export async function revokeRefreshFamily({ sub, createdAt }) {
  const redis = await getRedis();
  const familyKey = buildFamilyKey(sub, createdAt);
  const members = await redis.sMembers(familyKey);
  if (Array.isArray(members) && members.length > 0) {
    await redis.del(members);
  }
  await redis.del(familyKey);
  return { revoked: Array.isArray(members) ? members.length : 0 };
}

/**
 * Family existence check. Used by the refresh endpoint to distinguish a
 * garbage token from a replayed / stolen one.
 */
export async function familyIsKnown({ sub, createdAt }) {
  const redis = await getRedis();
  const familyKey = buildFamilyKey(sub, createdAt);
  return (await redis.exists(familyKey)) === 1;
}

/**
 * True only if the presented raw token's hash is an actual member of its
 * family set — i.e. it was once a real, minted token in this session, not a
 * forged `<userId>.<createdAt>.<garbage>` string.
 *
 * Rotation in the refresh endpoint deletes the old token record but leaves its
 * key in the family set, so a genuinely rotated-out token still matches here
 * (that is exactly the reuse case we want to catch), while a fabricated token
 * whose random segment was never minted does not.
 *
 * This gates family-wide revocation so an attacker who knows only a victim's
 * user id and guesses the createdAt cannot force-log-out the victim.
 */
export async function refreshTokenIsFamilyMember(rawRefreshToken) {
  let parsed;
  try {
    parsed = parseRefreshToken(rawRefreshToken);
  } catch {
    return false;
  }
  const redis = await getRedis();
  const hash = sha256(rawRefreshToken);
  const key = buildRefreshKey(parsed.userId, parsed.createdAt, hash);
  const familyKey = buildFamilyKey(parsed.userId, parsed.createdAt);
  try {
    return (await redis.sIsMember(familyKey, key)) === true;
  } catch {
    return false;
  }
}

/**
 * Re-export for refresh.js so it can parse a raw token without duplicating
 * the format rules.
 */
export function parseRefreshTokenSafe(rawToken) {
  try {
    return parseRefreshToken(rawToken);
  } catch {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session TTL Validation
// Returns { valid: true } or { valid: false, reason, code }
// ─────────────────────────────────────────────────────────────────────────────
export function validateSessionTTL(sessionData) {
  const now = Date.now();
  const { createdAt, lastUsedAt } = sessionData;

  // 1. Check idle TTL (sliding window)
  if (lastUsedAt && now - lastUsedAt > IDLE_TTL_MS) {
    return {
      valid: false,
      code: "session_expired",
      expiry_type: "idle",
      reason: "To stay signed in, please open the app at least once every 30 days. Sign in now to continue.",
    };
  }

  // 2. Check absolute TTL with night-time cutoff
  if (createdAt) {
    const absoluteExpiry = createdAt + ABSOLUTE_TTL_MS;
    if (now >= absoluteExpiry) {
      // Absolute TTL passed - check if we're in the night-time cutoff window
      const nightCutoff = getNextNightCutoff(absoluteExpiry);
      if (now >= nightCutoff) {
        return {
          valid: false,
          code: "session_expired",
          expiry_type: "absolute",
          reason: "To keep your account secure, we ask that you sign in again every 90 days.",
        };
      }
      // We're past absolute TTL but before night cutoff - allow but flag it
      // This lets users finish their day before being logged out at 2am PST
    }
  }

  return { valid: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTE: listUserSessions / revokeAllUserSessions were removed in the Phase 1
// hardening pass. Both relied on redis.keys(...) which is O(N) and blocks
// the whole cache on Upstash. If per-user session management is needed
// again, build it on top of a maintained session-index SET
// (e.g. SADD refresh_index:<userId> <key>) rather than KEYS/SCAN.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Export TTL constants for use in refresh endpoint
// ─────────────────────────────────────────────────────────────────────────────
export const SESSION_POLICY = {
  IDLE_TTL_MS,
  ABSOLUTE_TTL_MS,
  REFRESH_TTL_SECONDS,
};
