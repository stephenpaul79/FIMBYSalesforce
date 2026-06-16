// scripts/find-user-keys.js
// One-off admin lookup: find every Redis key tied to a user across all token
// types, plus value-side mappings whose key does not carry the userId.
//
// Uses non-blocking SCAN (cursor-based), never KEYS. Safe to run against
// Upstash, but it still walks the whole keyspace — this is an admin tool, not
// something to call on a hot path. For live per-user lookups use
// listUserKeys() from lib/sessions.js, which is backed by the user_index SET.
//
// Usage (from fimby-auth-bridge/, with REDIS_URL set in the environment):
//   node scripts/find-user-keys.js 005OL00000EJC8gYAH

import { getRedis } from "../lib/redis.js";

const userId = process.argv[2];
if (!userId) {
  console.error("Usage: node scripts/find-user-keys.js <userId>");
  process.exit(1);
}

const SCAN_COUNT = 500;

// Key patterns where the userId appears in the KEY. SCAN MATCH filters
// server-side so we only pull back relevant keys.
const KEY_PATTERNS = [
  `refresh:${userId}:*`,
  `family:${userId}:*`,
  `push_token:${userId}`,
  `user_index:${userId}`,
];

// push_token_user:<token> stores the userId in its VALUE, so MATCH can't find
// it. We scan that namespace and filter by fetched value.
const VALUE_PATTERN = "push_token_user:*";

async function scanMatch(redis, match) {
  const found = [];
  let cursor = "0";
  do {
    const reply = await redis.scan(cursor, { MATCH: match, COUNT: SCAN_COUNT });
    cursor = String(reply.cursor);
    if (reply.keys && reply.keys.length) found.push(...reply.keys);
  } while (cursor !== "0");
  return found;
}

async function main() {
  const redis = await getRedis();

  const byKey = [];
  for (const pattern of KEY_PATTERNS) {
    byKey.push(...(await scanMatch(redis, pattern)));
  }

  // Value-side mappings: scan the namespace, keep ones whose value is our user.
  const byValue = [];
  const candidates = await scanMatch(redis, VALUE_PATTERN);
  for (const key of candidates) {
    const val = await redis.get(key);
    if (val === userId) byValue.push(key);
  }

  const all = [...new Set([...byKey, ...byValue])].sort();

  console.log(`\nKeys for user ${userId} (${all.length} found):\n`);
  for (const key of all) {
    const ttl = await redis.ttl(key);
    const type = await redis.type(key);
    console.log(`  ${key}  [type=${type}, ttl=${ttl}s]`);
  }
  console.log("");

  await redis.quit();
}

main().catch((err) => {
  console.error("find-user-keys failed:", err);
  process.exit(1);
});
