// lib/push-tokens.js
// Shared push-token lifecycle helpers so the register/DELETE endpoint and the
// receipt cron prune dead tokens identically (no drift).

import { unindexUserKey } from "./sessions.js";

/**
 * Remove a user's push-token mapping. Used on logout (DELETE) and when a
 * delivery receipt reports the token is dead (DeviceNotRegistered).
 *
 * The `current === token` guard matters: between a send and its receipt the
 * neighbour may have reinstalled and registered a fresh token. We must never
 * delete the live mapping — only retire the specific stale token's reverse key.
 *
 * @param {object} redis  connected redis client
 * @param {string} userId Salesforce user id (owner of the token)
 * @param {string} token  the Expo push token to retire
 * @param {string} reason structured-log reason (e.g. "DeviceNotRegistered", "logout")
 */
export async function pruneDeadToken(redis, userId, token, reason = "unknown") {
  if (!userId || !token) return;

  const current = await redis.get(`push_token:${userId}`);
  if (current && current === token) {
    await redis.del(`push_token:${userId}`);
    await unindexUserKey(userId, `push_token:${userId}`);
  }
  await redis.del(`push_token_user:${token}`);
  await unindexUserKey(userId, `push_token_user:${token}`);

  console.log(JSON.stringify({ event: "push_token_pruned", user_id: userId, reason }));
}

// Redis keys for the receipt worklist (Phase 5). A pending receipt id maps to
// the { userId, token } we'll need to prune later without a second lookup.
export const RECEIPT_PENDING_SET = "push_receipts_pending";
export const receiptKey = (receiptId) => `push_receipt:${receiptId}`;

// Expo keeps receipts ~24h. The prune cron runs once a day on the Hobby plan,
// so a 24h stash TTL could expire a receipt right as the next daily run reaches
// it. 48h gives a full day of headroom so a once-daily run never races the TTL;
// the worklist still self-cleans if runs are missed.
export const RECEIPT_TTL_SECONDS = 60 * 60 * 48;
