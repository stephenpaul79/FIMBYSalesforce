// lib/rate-limit.js
// Shared IP / key-bucket rate limiter backed by Redis INCR + EXPIRE.
//
// On a Redis error we no longer fail fully open. Instead we degrade to an
// in-process counter so a single warm instance still throttles, and we emit a
// structured log line so the bypass is observable instead of silent. This
// trades the old "never brick auth" behaviour for "never silently disable all
// rate limiting": availability is preserved (a Redis blip still serves
// requests) but unbounded brute-force during an outage is contained.

import { getRedis } from "./redis.js";

// In-process fallback buckets, used only when Redis is unavailable. Keys embed
// the time bucket, so stale entries naturally stop being incremented; we cap
// the map size and clear it wholesale if it ever grows large (cheap because
// buckets are short-lived).
const memBuckets = new Map();
const MEM_MAX_KEYS = 10000;

function memIncr(key) {
  if (memBuckets.size > MEM_MAX_KEYS) memBuckets.clear();
  const count = (memBuckets.get(key) || 0) + 1;
  memBuckets.set(key, count);
  return count;
}

/**
 * Extract the best-effort client IP from Vercel / proxy headers.
 */
export function getClientIp(req) {
  const xf = req.headers["x-vercel-forwarded-for"] || req.headers["x-forwarded-for"];
  const ip =
    (typeof xf === "string" && xf.split(",")[0].trim()) ||
    (Array.isArray(xf) && xf[0]) ||
    req.headers["x-real-ip"] ||
    req.socket?.remoteAddress ||
    "unknown";
  return String(ip);
}

/**
 * Bucketed rate limit. Counts calls per (bucketKey, windowSeconds) and
 * increments once per request. Returns { ok } so callers can decide the
 * response shape.
 *
 * @param {object} req
 * @param {object} res
 * @param {object} opts
 * @param {string} opts.keyPrefix - e.g. "rl:login"
 * @param {number} opts.limit - max calls per window
 * @param {number} opts.windowSeconds - window size in seconds
 * @param {string} [opts.bucketKey] - custom key (e.g. userId). Defaults to client IP.
 */
export async function rateLimit(req, res, { keyPrefix, limit, windowSeconds, bucketKey }) {
  const id = bucketKey || getClientIp(req);
  const bucket = Math.floor(Date.now() / 1000 / windowSeconds);
  const key = `${keyPrefix}:${id}:${bucket}`;

  try {
    const redis = await getRedis();
    const count = await redis.incr(key);
    if (count === 1) await redis.expire(key, windowSeconds);

    const remaining = Math.max(0, limit - count);
    res.setHeader("X-RateLimit-Limit", String(limit));
    res.setHeader("X-RateLimit-Remaining", String(remaining));

    if (count > limit) {
      res.setHeader("Retry-After", String(windowSeconds));
      return { ok: false, key, count };
    }
    return { ok: true, key, count };
  } catch (e) {
    // Redis is unavailable: fall back to a per-instance counter rather than
    // letting every request through. Emit a structured event so an outage that
    // degrades throttling is alertable instead of invisible.
    console.log(
      JSON.stringify({
        event: "rate_limit_redis_error",
        keyPrefix,
        error: e?.message || String(e),
      })
    );

    const count = memIncr(key);
    res.setHeader("X-RateLimit-Limit", String(limit));
    res.setHeader("X-RateLimit-Remaining", String(Math.max(0, limit - count)));

    if (count > limit) {
      res.setHeader("Retry-After", String(windowSeconds));
      return { ok: false, key, count, degraded: true };
    }
    return { ok: true, key, count, degraded: true };
  }
}
