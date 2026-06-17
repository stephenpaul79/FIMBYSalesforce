// api/notifications/push.js
// Receives push notification requests from Salesforce and sends to Expo Push Service

import crypto from "crypto";
import { getRedis } from "../../lib/redis.js";
import { apiHygiene } from "../../lib/api-hygiene.js";
import { rateLimit } from "../../lib/rate-limit.js";
import {
  pruneDeadToken,
  receiptKey,
  RECEIPT_PENDING_SET,
  RECEIPT_TTL_SECONDS,
} from "../../lib/push-tokens.js";

// Ticket-time error codes that mean the token is dead — prune immediately, no
// receipt poll needed. Other errors (MessageRateExceeded, MessageTooBig) are
// sender-side and must NOT prune a token.
const DEAD_TOKEN_TICKET_ERRORS = new Set(["DeviceNotRegistered", "MismatchSenderId"]);

/**
 * Phase 5: process Expo tickets index-aligned to `toSend`. Dead-token tickets
 * are pruned now; `ok` tickets stash their receiptId for the cron to poll.
 * Best-effort — never throws into the push response path.
 */
async function captureTickets(redis, tickets, toSend, reqId) {
  let pruned = 0;
  let pending = 0;
  for (let i = 0; i < toSend.length; i++) {
    const ticket = tickets[i];
    const entry = toSend[i];
    if (!ticket || !entry) continue;
    try {
      if (ticket.status === "ok" && ticket.id) {
        await redis.setEx(
          receiptKey(ticket.id),
          RECEIPT_TTL_SECONDS,
          JSON.stringify({ userId: entry.user_id, token: entry.pushToken })
        );
        await redis.sAdd(RECEIPT_PENDING_SET, ticket.id);
        pending++;
      } else if (ticket.status === "error") {
        const code = ticket?.details?.error;
        if (DEAD_TOKEN_TICKET_ERRORS.has(code)) {
          await pruneDeadToken(redis, entry.user_id, entry.pushToken, code);
          pruned++;
        } else if (code) {
          // Sender-side (rate/size) — log, do not touch the token.
          console.log(JSON.stringify({ event: "push_ticket_error", reqId, code }));
        }
      }
    } catch (e) {
      console.log(JSON.stringify({ event: "push_ticket_capture_error", reqId, message: e?.message }));
    }
  }
  if (pruned || pending) {
    console.log(JSON.stringify({ event: "push_tickets_captured", reqId, pruned, pending }));
  }
}

const EXPO_PUSH_URL = "https://exp.host/--/api/v2/push/send";

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
 * Validate request is from Salesforce using shared secret
 */
function validateSalesforceOrigin(req) {
  const provided = req.headers["x-sf-secret"];
  const expectedSecret = process.env.SF_PUSH_SECRET;

  if (!expectedSecret) {
    console.log("[PUSH] Server misconfigured: missing SF_PUSH_SECRET");
    return false;
  }

  if (typeof provided !== "string" || provided.length === 0) {
    log("[PUSH] Missing X-SF-Secret header");
    return false;
  }

  // Timing-safe comparison to avoid leaking length/prefix of the secret.
  const a = Buffer.from(provided, "utf8");
  const b = Buffer.from(expectedSecret, "utf8");
  if (a.length !== b.length) {
    // Still do a constant-time compare against b itself to keep timing flat.
    crypto.timingSafeEqual(b, b);
    log("[PUSH] Invalid X-SF-Secret header (length mismatch)");
    return false;
  }
  if (!crypto.timingSafeEqual(a, b)) {
    log("[PUSH] Invalid X-SF-Secret header");
    return false;
  }

  return true;
}

// Replay protection. The shared secret authenticates the caller, but a
// captured-and-replayed request would otherwise re-send a notification. A
// fresh timestamp plus a single-use nonce (deduped in Redis) closes that.
//
// Backward compatible: if the Salesforce caller does not yet send the
// X-SF-Timestamp / X-SF-Nonce headers we skip the check, UNLESS
// SF_PUSH_REQUIRE_NONCE === "true". Rollout: update the push job to send the
// headers, confirm pushes still land, then set SF_PUSH_REQUIRE_NONCE=true in
// Vercel to make replay protection mandatory.
const REPLAY_WINDOW_SECONDS = 300;

async function checkPushReplay(req) {
  const required = process.env.SF_PUSH_REQUIRE_NONCE === "true";
  const ts = req.headers["x-sf-timestamp"];
  const nonce = req.headers["x-sf-nonce"];

  if (!ts && !nonce) {
    return required
      ? { ok: false, reason: "missing_replay_headers" }
      : { ok: true, skipped: true };
  }

  if (typeof ts !== "string" || typeof nonce !== "string") {
    return { ok: false, reason: "invalid_replay_headers" };
  }

  const tsNum = parseInt(ts, 10);
  if (!Number.isFinite(tsNum)) return { ok: false, reason: "invalid_timestamp" };
  const nowSec = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSec - tsNum) > REPLAY_WINDOW_SECONDS) {
    return { ok: false, reason: "stale_timestamp" };
  }

  if (!/^[A-Za-z0-9_-]{8,128}$/.test(nonce)) {
    return { ok: false, reason: "invalid_nonce" };
  }

  try {
    const redis = await getRedis();
    // SET NX: succeeds once per nonce; a second use returns null (= replay).
    // TTL is double the window so the dedup record outlives the freshness check.
    const set = await redis.set(`push_nonce:${nonce}`, "1", {
      NX: true,
      EX: REPLAY_WINDOW_SECONDS * 2,
    });
    if (set === null) return { ok: false, reason: "replayed_nonce" };
  } catch {
    // Redis unavailable: don't brick legitimate pushes. The shared secret and
    // timestamp freshness still gate the request.
    return { ok: true, degraded: true };
  }

  return { ok: true };
}

// Length / shape limits for incoming push payload. Keeps Expo + device UIs
// happy and prevents a poisoned Salesforce caller from blasting multi-MB
// strings into user notifications.
const PUSH_LIMITS = {
  userIdMax: 32, // Salesforce 18-char IDs with headroom
  titleMax: 120,
  bodyMax: 500,
  dataKeyMax: 40,
  dataValueMax: 400,
  dataKeyCount: 20,
  allowedChannelIds: new Set(["messages", "messages_quiet", "activity", "default"]),
  notificationTypeMax: 40,
  collapseIdMax: 64,
};

// iOS interruption levels (passive = quiet, in-place refresh; no sound/banner).
const ALLOWED_INTERRUPTION = new Set(["active", "passive", "time-sensitive", "critical"]);

// Top-level notification_type values originate in Salesforce
// (FimbyPushNotificationService.NotificationType). The bridge only checks shape;
// Salesforce auth (X-SF-Secret) is the gatekeeper for which types are sent.
function isSafeNotificationType(v) {
  if (typeof v !== "string") return false;
  const len = v.length;
  if (len === 0 || len > PUSH_LIMITS.notificationTypeMax) return false;
  return /^[A-Za-z][A-Za-z0-9_]*$/.test(v);
}

function isPlainObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

function isSafeString(v, max) {
  if (typeof v !== "string") return false;
  if (v.length === 0 || v.length > max) return false;
  // Reject control chars (except common whitespace).
  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x08\x0b-\x1f\x7f]/.test(v)) return false;
  return true;
}

/**
 * Validate a single notification payload shape. Returns { ok, reason } and a
 * sanitized subset so downstream code only sees what we expect.
 */
function validatePushNotification(n) {
  if (!isPlainObject(n)) return { ok: false, reason: "not_object" };

  if (!isSafeString(n.user_id, PUSH_LIMITS.userIdMax)) {
    return { ok: false, reason: "invalid_user_id" };
  }
  if (!isSafeString(n.title, PUSH_LIMITS.titleMax)) {
    return { ok: false, reason: "invalid_title" };
  }
  if (n.body !== undefined && n.body !== null) {
    if (typeof n.body !== "string" || n.body.length > PUSH_LIMITS.bodyMax) {
      return { ok: false, reason: "invalid_body" };
    }
  }
  if (n.badge !== undefined && n.badge !== null) {
    if (!Number.isInteger(n.badge) || n.badge < 0 || n.badge > 9999) {
      return { ok: false, reason: "invalid_badge" };
    }
  }
  if (n.notification_type !== undefined && n.notification_type !== null) {
    if (!isSafeNotificationType(n.notification_type)) {
      return { ok: false, reason: "invalid_notification_type" };
    }
  }
  if (n.collapse_id !== undefined && n.collapse_id !== null) {
    if (typeof n.collapse_id !== "string" ||
        n.collapse_id.length === 0 ||
        n.collapse_id.length > PUSH_LIMITS.collapseIdMax ||
        !/^[A-Za-z0-9:_-]+$/.test(n.collapse_id)) {
      return { ok: false, reason: "invalid_collapse_id" };
    }
  }
  if (n.interruption_level !== undefined && n.interruption_level !== null) {
    if (typeof n.interruption_level !== "string" ||
        !ALLOWED_INTERRUPTION.has(n.interruption_level)) {
      return { ok: false, reason: "invalid_interruption_level" };
    }
  }

  // Data is a shallow string-keyed bag. Reject arrays, deep trees, oversized
  // values, and anything we haven't explicitly allowed.
  let cleanData = {};
  if (n.data !== undefined && n.data !== null) {
    if (!isPlainObject(n.data)) return { ok: false, reason: "invalid_data_shape" };
    const keys = Object.keys(n.data);
    if (keys.length > PUSH_LIMITS.dataKeyCount) {
      return { ok: false, reason: "too_many_data_keys" };
    }
    for (const k of keys) {
      if (typeof k !== "string" || k.length === 0 || k.length > PUSH_LIMITS.dataKeyMax) {
        return { ok: false, reason: "invalid_data_key" };
      }
      const v = n.data[k];
      // Allow primitives only.
      const tv = typeof v;
      if (v === null || tv === "boolean" || tv === "number") {
        cleanData[k] = v;
      } else if (tv === "string") {
        if (v.length > PUSH_LIMITS.dataValueMax) {
          return { ok: false, reason: "invalid_data_value_len" };
        }
        cleanData[k] = v;
      } else {
        return { ok: false, reason: "invalid_data_value_type" };
      }
    }
    // channelId must match the allowlist if present.
    if (
      cleanData.channelId !== undefined &&
      (typeof cleanData.channelId !== "string" ||
        !PUSH_LIMITS.allowedChannelIds.has(cleanData.channelId))
    ) {
      return { ok: false, reason: "invalid_channel_id" };
    }
  }

  return {
    ok: true,
    clean: {
      user_id: n.user_id,
      title: n.title,
      body: typeof n.body === "string" ? n.body : undefined,
      data: cleanData,
      badge: Number.isInteger(n.badge) ? n.badge : undefined,
      notification_type:
        typeof n.notification_type === "string" ? n.notification_type : undefined,
      collapse_id: typeof n.collapse_id === "string" ? n.collapse_id : undefined,
      interruption_level:
        typeof n.interruption_level === "string" ? n.interruption_level : undefined,
    },
  };
}

/**
 * Send notification via Expo Push API
 */
async function sendToExpo(pushToken, notification) {
  const data = notification.data || {};
  const message = {
    to: pushToken,
    sound: "default",
    title: notification.title,
    body: notification.body,
    data,
  };

  if (notification.badge !== undefined && notification.badge !== null) {
    message.badge = notification.badge;
  }

  if (notification.notification_type) {
    message.categoryId = notification.notification_type.toLowerCase();
  }

  if (data.channelId) {
    message.channelId = data.channelId;
  }

  if (notification.collapse_id) {
    message.collapseId = notification.collapse_id; // iOS apns-collapse-id + Android collapse_key
    message.tag = notification.collapse_id;        // Android: replace already-displayed
  }

  if (notification.interruption_level === "passive") {
    message.interruptionLevel = "passive";
    delete message.sound; // no sound for a quiet, in-place refresh
  } else if (notification.interruption_level) {
    message.interruptionLevel = notification.interruption_level;
  }

  log("[PUSH] Sending to Expo:", JSON.stringify(message));

  const response = await fetch(EXPO_PUSH_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "Accept-Encoding": "gzip, deflate",
    },
    body: JSON.stringify(message),
  });

  const result = await response.json();
  return { success: response.ok, result };
}

/**
 * Handle batch of notifications (for future batch mode)
 */
async function sendBatchToExpo(notifications) {
  const messages = notifications.map((n) => {
    const data = n.data || {};
    const passive = n.interruption_level === "passive";
    return {
      to: n.pushToken,
      // Passive (quiet) refresh: no sound. Otherwise default alert sound.
      ...(passive ? {} : { sound: "default" }),
      title: n.title,
      body: n.body,
      data,
      ...(n.badge !== undefined && { badge: n.badge }),
      ...(n.notification_type && { categoryId: n.notification_type.toLowerCase() }),
      ...(data.channelId && { channelId: data.channelId }),
      ...(n.collapse_id && { collapseId: n.collapse_id, tag: n.collapse_id }),
      ...(n.interruption_level && { interruptionLevel: n.interruption_level }),
    };
  });

  log("[PUSH] Sending batch of", messages.length, "notifications to Expo");

  const response = await fetch(EXPO_PUSH_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "Accept-Encoding": "gzip, deflate",
    },
    body: JSON.stringify(messages),
  });

  const result = await response.json();
  return { success: response.ok, result };
}

export default async function handler(req, res) {
  const reqId = getRequestId(req);

  // Hygiene: CORS, Content-Type, body size. 64KB cap so a large batch can
  // still land (up to ~100 notifications at ~500b each).
  const hygiene = apiHygiene(req, res, { maxBodyBytes: 65536 });
  if (hygiene.preflight) return;
  if (!hygiene.ok) {
    return json(res, hygiene.errorCode === "payload_too_large" ? 413 : 400, {
      error: hygiene.errorCode || "invalid_request",
    });
  }

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return json(res, 405, { error: "method_not_allowed" });
  }

  // Validate Salesforce origin first so failed auth attempts get rate-limited
  // against a noisy IP but won't land on a valid-auth bucket.
  if (!validateSalesforceOrigin(req)) {
    const rl = await rateLimit(req, res, {
      keyPrefix: "rl:push:unauth",
      limit: 20,
      windowSeconds: 60,
    });
    console.log(JSON.stringify({ event: "push_unauthorized", reqId }));
    if (!rl.ok) return json(res, 429, { error: "slow_down" });
    return json(res, 401, { error: "unauthorized" });
  }

  // Authenticated SF origin: per-IP ceiling to contain a compromised secret.
  const rl = await rateLimit(req, res, {
    keyPrefix: "rl:push:sf",
    limit: 300,
    windowSeconds: 60,
  });
  if (!rl.ok) return json(res, 429, { error: "slow_down" });

  // Replay protection (timestamp + single-use nonce). No-op until the caller
  // sends the headers / SF_PUSH_REQUIRE_NONCE is enabled (see checkPushReplay).
  const replay = await checkPushReplay(req);
  if (!replay.ok) {
    console.log(JSON.stringify({ event: "push_replay_rejected", reqId, reason: replay.reason }));
    return json(res, 401, { error: "unauthorized", reason: replay.reason });
  }

  try {
    const body = req.body || {};

    // Support both single notification and batch
    const isBatch = Array.isArray(body.notifications);

    if (isBatch) {
      // Batch mode
      const { notifications } = body;

      if (!notifications || notifications.length === 0) {
        return json(res, 400, { error: "invalid_request", message: "No notifications provided" });
      }
      if (notifications.length > 200) {
        return json(res, 400, { error: "invalid_request", message: "Batch too large (max 200)" });
      }

      log("[PUSH] Processing batch of", notifications.length, "notifications");

      const redis = await getRedis();
      const toSend = [];
      const skipped = [];

      // Look up push tokens for each user
      for (const notification of notifications) {
        const v = validatePushNotification(notification);
        if (!v.ok) {
          skipped.push({ user_id: notification?.user_id, reason: v.reason });
          continue;
        }
        const clean = v.clean;

        const pushToken = await redis.get(`push_token:${clean.user_id}`);

        if (!pushToken) {
          skipped.push({ user_id: clean.user_id, reason: "no_push_token" });
          continue;
        }

        toSend.push({
          user_id: clean.user_id,
          pushToken,
          title: clean.title,
          body: clean.body,
          data: clean.data,
          badge: clean.badge,
          notification_type: clean.notification_type,
          collapse_id: clean.collapse_id,
          interruption_level: clean.interruption_level,
        });
      }

      // skipped entries (no token / invalid) are not-accepted from the start.
      const skippedResults = skipped.map((s) => ({
        user_id: s.user_id,
        accepted: false,
        reason: s.reason,
      }));

      if (toSend.length === 0) {
        console.log(JSON.stringify({ event: "push_batch_empty", reqId, skipped: skipped.length }));
        return json(res, 200, {
          sent: 0,
          skipped: skipped.length,
          details: skipped,
          results: skippedResults,
        });
      }

      // Send batch to Expo
      const { success, result } = await sendBatchToExpo(toSend);

      // Expo's ticket array is index-aligned to the messages we sent, so
      // ticket i maps to toSend[i].user_id. 'ok' = ingest-accepted (NOT
      // delivered — Phase 5's receipt poll keyed by receiptId is authoritative).
      const tickets = Array.isArray(result?.data) ? result.data : [];
      const sentResults = toSend.map((entry, i) => {
        const ticket = tickets[i];
        const accepted = success && ticket?.status === "ok";
        return {
          user_id: entry.user_id,
          accepted,
          ...(accepted ? {} : { reason: ticket?.details?.error || ticket?.message || "ticket_error" }),
          ...(ticket?.id ? { receipt_id: ticket.id } : {}),
        };
      });
      const results = [...sentResults, ...skippedResults];

      // Phase 5: capture tickets — prune dead tokens now, stash ok receiptIds
      // for the cron to poll. Best-effort; never blocks the response.
      await captureTickets(redis, tickets, toSend, reqId);

      const passiveCount = toSend.filter((n) => n.interruption_level === "passive").length;
      if (passiveCount > 0) {
        console.log(JSON.stringify({ event: "push_passive_sent", reqId, count: passiveCount }));
      }

      console.log(JSON.stringify({
        event: "push_batch_sent",
        reqId,
        sent: toSend.length,
        skipped: skipped.length,
        passive: passiveCount,
        success
      }));

      return json(res, 200, {
        sent: toSend.length,
        skipped: skipped.length,
        success,
        results,
        result,
      });

    } else {
      // Single notification mode
      const v = validatePushNotification(body);
      if (!v.ok) {
        console.log(JSON.stringify({ event: "push_invalid", reqId, reason: v.reason }));
        return json(res, 400, { error: "invalid_request", message: v.reason });
      }
      const { user_id, title, body: notifBody, data, badge, notification_type, collapse_id, interruption_level } = v.clean;

      const redis = await getRedis();
      const pushToken = await redis.get(`push_token:${user_id}`);

      if (!pushToken) {
        console.log(JSON.stringify({ event: "push_no_token", reqId, user_id }));
        return json(res, 200, { sent: false, reason: "no_push_token" });
      }

      // Generic payload only — no deep-link URL. Cold-start navigates to /notifications.
      const notificationData = {
        ...data,
        ...(notification_type && { notification_type }),
      };

      const { success, result } = await sendToExpo(pushToken, {
        title,
        body: notifBody,
        data: notificationData,
        badge,
        notification_type,
        collapse_id,
        interruption_level,
      });

      console.log(JSON.stringify({
        event: success ? "push_sent" : "push_failed",
        reqId,
        user_id,
        notification_type
      }));

      return json(res, 200, { sent: success, result });
    }
  } catch (e) {
    console.log(JSON.stringify({ event: "push_error", reqId, error: e?.message }));
    return json(res, 500, { error: "server_error" });
  }
}
