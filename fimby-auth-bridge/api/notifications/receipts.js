// api/notifications/receipts.js
// Phase 5 — receipt poller. Runs on a Vercel Cron (~every 15 min). Pops a slice
// of pending Expo receipt ids, asks Expo for their final delivery status, and
// prunes any token Expo reports as DeviceNotRegistered. Reliability only — it
// changes nothing the neighbour sees; it stops FIMBY shouting at dead phones.
//
// Internal endpoint: requires the Vercel Cron secret (Authorization: Bearer
// <CRON_SECRET>, which Vercel sends for scheduled invocations). Never exposed
// unauthenticated.

import crypto from "crypto";
import { getRedis } from "../../lib/redis.js";
import {
  pruneDeadToken,
  receiptKey,
  RECEIPT_PENDING_SET,
} from "../../lib/push-tokens.js";

const EXPO_RECEIPTS_URL = "https://exp.host/--/api/v2/push/getReceipts";
const RECEIPT_BATCH = 1000; // Expo getReceipts cap per call
const MAX_CHUNKS = 20;      // backstop: ≤20k receipts per daily run; rest stays queued

const getRequestId = (req) =>
  req.headers["x-request-id"] || crypto.randomUUID();

const json = (res, status, body) => {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(body));
};

// Vercel sends `Authorization: Bearer <CRON_SECRET>` on cron invocations.
// Accept that, or an explicit x-cron-secret header for manual/testing calls.
function isAuthorizedCron(req) {
  const secret = process.env.CRON_SECRET;
  if (!secret) return false;
  const auth = req.headers.authorization || req.headers.Authorization;
  if (typeof auth === "string" && auth === `Bearer ${secret}`) return true;
  const header = req.headers["x-cron-secret"];
  if (typeof header === "string" && header.length === secret.length) {
    try {
      if (crypto.timingSafeEqual(Buffer.from(header), Buffer.from(secret))) return true;
    } catch {
      return false;
    }
  }
  return false;
}

export default async function handler(req, res) {
  const reqId = getRequestId(req);

  if (req.method !== "POST" && req.method !== "GET") {
    res.setHeader("Allow", "POST, GET");
    return json(res, 405, { error: "method_not_allowed" });
  }

  if (!isAuthorizedCron(req)) {
    console.log(JSON.stringify({ event: "receipts_unauthorized", reqId }));
    return json(res, 401, { error: "unauthorized" });
  }

  try {
    const redis = await getRedis();

    let polled = 0;
    let okCount = 0;
    let pruned = 0;
    let requeued = 0;

    // The cron runs once a day (Hobby plan), so drain the whole backlog in
    // ≤1000-id chunks rather than a single slice that would leave the rest
    // waiting another full day. MAX_CHUNKS caps a runaway worklist; anything
    // beyond it stays queued for the next run.
    for (let chunk = 0; chunk < MAX_CHUNKS; chunk++) {
      const ids = await redis.sPop(RECEIPT_PENDING_SET, RECEIPT_BATCH);
      const idList = Array.isArray(ids) ? ids : ids ? [ids] : [];
      if (idList.length === 0) {
        break; // worklist drained
      }

      const resp = await fetch(EXPO_RECEIPTS_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Accept: "application/json",
          "Accept-Encoding": "gzip, deflate",
        },
        body: JSON.stringify({ ids: idList }),
      });

      if (!resp.ok) {
        // Couldn't reach Expo: re-queue this chunk and stop; a later run retries.
        await redis.sAdd(RECEIPT_PENDING_SET, idList);
        console.log(JSON.stringify({ event: "receipts_expo_error", reqId, status: resp.status }));
        return json(res, 502, { error: "expo_error", polled, pruned });
      }

      const payload = await resp.json();
      const receipts = payload?.data || {};

      for (const id of idList) {
        const receipt = receipts[id];
        const stashRaw = await redis.get(receiptKey(id));
        let stash = null;
        if (stashRaw) {
          try {
            stash = JSON.parse(stashRaw);
          } catch {
            stash = null;
          }
        }

        // No receipt yet for this id (Expo not ready): re-queue, keep the stash.
        if (!receipt) {
          await redis.sAdd(RECEIPT_PENDING_SET, id);
          requeued++;
          continue;
        }

        polled++;
        if (receipt.status === "ok") {
          okCount++;
        } else if (receipt.status === "error") {
          const code = receipt?.details?.error;
          if (code === "DeviceNotRegistered" && stash?.userId && stash?.token) {
            await pruneDeadToken(redis, stash.userId, stash.token, "DeviceNotRegistered");
            pruned++;
          } else if (code) {
            console.log(JSON.stringify({ event: "receipt_error", reqId, code }));
          }
        }

        // Receipt resolved (ok or actioned error): drop the stash.
        await redis.del(receiptKey(id));
      }

      // A short chunk means the set is empty now; avoid an extra empty sPop.
      if (idList.length < RECEIPT_BATCH) {
        break;
      }
    }

    console.log(JSON.stringify({
      event: "receipts_polled",
      reqId,
      polled,
      ok: okCount,
      pruned,
      requeued,
    }));

    return json(res, 200, { polled, ok: okCount, pruned, requeued });
  } catch (e) {
    console.log(JSON.stringify({ event: "receipts_error", reqId, message: e?.message }));
    return json(res, 500, { error: "server_error" });
  }
}
