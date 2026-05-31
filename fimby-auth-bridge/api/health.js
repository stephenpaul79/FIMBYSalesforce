import crypto from "crypto";
import { getRedis } from "../lib/redis.js";

// Timing-safe compare that tolerates unequal lengths without leaking them.
function timingSafeEqualStrings(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const aBuf = Buffer.from(a, "utf8");
  const bBuf = Buffer.from(b, "utf8");
  if (aBuf.length !== bBuf.length) {
    crypto.timingSafeEqual(bBuf, bBuf);
    return false;
  }
  return crypto.timingSafeEqual(aBuf, bBuf);
}

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).end("Method Not Allowed");
  }

  res.setHeader("Cache-Control", "no-store");

  // Public liveness check
  const mode = req.query.mode || "basic";
  if (mode === "basic") {
    return res.status(200).json({ ok: true });
  }

  // Anything deeper requires admin key (timing-safe compare)
  const adminKey = process.env.ADMIN_KEY;
  const provided = req.headers["x-admin-key"];
  if (!adminKey || !timingSafeEqualStrings(String(provided || ""), adminKey)) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  const redis = await getRedis();
  await redis.setEx("ping", 60, "pong");
  const value = await redis.get("ping");

  return res.status(200).json({ ok: true, redis: value === "pong" });
}
