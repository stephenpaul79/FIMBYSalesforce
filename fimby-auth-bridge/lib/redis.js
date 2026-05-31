import { createClient } from "redis";

let client;

export async function getRedis() {
  if (!client) {
    const url = process.env.REDIS_URL;
    if (!url || !url.trim()) {
      throw new Error("Missing env var: REDIS_URL");
    }

    // Require TLS in production. Upstash exposes a rediss:// endpoint; any
    // plain redis:// URL in a production deploy points at a misconfigured or
    // downgraded connection and should fail loud before any session data
    // round-trips across an unencrypted link.
    if (process.env.NODE_ENV === "production" && !/^rediss:\/\//i.test(url)) {
      throw new Error(
        "REDIS_URL must use TLS (rediss://) in production. " +
        "Check your Vercel env var — Upstash exposes a rediss:// endpoint."
      );
    }

    client = createClient({ url });
    client.on("error", (err) => console.error("Redis Client Error", err));
    await client.connect();
  }
  return client;
}
