// api/frontdoor.js
import crypto from "crypto";
import jwt from "jsonwebtoken";
import { apiHygiene } from "../lib/api-hygiene.js";
import { rateLimit } from "../lib/rate-limit.js";
import { FIMBY_APP_JWT_AUDIENCE } from "../lib/sessions.js";
import { buildFrontdoorPayload, normalizeFrontdoorRet } from "../lib/frontdoor-core.js";

const DEBUG = process.env.DEBUG_AUTH === "true";
const log = (...args) => DEBUG && console.log(...args);

const getRequestId = (req) =>
  req.headers["x-request-id"] || crypto.randomUUID();

function requireEnv(name) {
  const v = process.env[name];
  if (!v || !v.trim()) throw new Error(`Missing env var: ${name}`);
  return v.trim();
}

const oauthError = (res, httpStatus, error, error_description) =>
  res
    .status(httpStatus)
    .json({ error, ...(error_description ? { error_description } : {}) });

function getBearerToken(req) {
  const h = req.headers?.authorization || req.headers?.Authorization;
  if (!h || typeof h !== "string") return null;
  const m = h.match(/^Bearer\s+(.+)$/i);
  return m ? m[1] : null;
}

function requireAppSession(req) {
  const secret = requireEnv("APP_JWT_SIGNING_SECRET");
  const expectedIssuer = requireEnv("FIMBY_APP_JWT_ISSUER");
  const token = getBearerToken(req);

  if (!token) {
    const err = new Error("unauthorized");
    err.statusCode = 401;
    err.code = "invalid_token";
    throw err;
  }

  let payload;
  try {
    payload = jwt.verify(token, secret, {
      algorithms: ["HS256"],
      issuer: expectedIssuer,
      audience: FIMBY_APP_JWT_AUDIENCE,
    });
  } catch (e) {
    const err = new Error("unauthorized");
    err.statusCode = 401;
    err.code = "invalid_token";
    err._debug = { reason: "jwt_verify_failed", message: e?.message };
    throw err;
  }

  const fail = (reason, extra = {}) => {
    const err = new Error("unauthorized");
    err.statusCode = 401;
    err.code = "invalid_token";
    err._debug = { reason, ...extra };
    throw err;
  };

  if (payload?.typ !== "access") {
    fail("invalid_token_type", { expectedTyp: "access", gotTyp: payload?.typ });
  }

  if (typeof payload?.sub !== "string" || !payload.sub.trim()) {
    fail("invalid_sub");
  }

  if (typeof payload?.username !== "string" || !payload.username.trim()) {
    fail("invalid_username");
  }

  const username = payload.username.trim();

  if (username.length > 80) fail("username_too_long");
  if (/\s/.test(username)) fail("username_contains_whitespace");
  if (!/^[a-z0-9]/i.test(username)) fail("username_bad_prefix");
  if (!username.includes("@")) fail("username_missing_at");

  return payload;
}

export default async function handler(req, res) {
  const reqId = getRequestId(req);

  if (req.method !== "GET" && req.method !== "POST") {
    res.setHeader("Allow", "GET, POST");
    return oauthError(res, 405, "invalid_request");
  }

  const hygiene = apiHygiene(req, res, { maxBodyBytes: 2048 });
  if (hygiene.preflight) return;
  if (!hygiene.ok) {
    console.log(JSON.stringify({ event: "frontdoor_hygiene_error", reqId, code: hygiene.errorCode }));
    return oauthError(res, 400, "invalid_request");
  }

  const ipRl = await rateLimit(req, res, { keyPrefix: "rl:frontdoor:ip", limit: 30, windowSeconds: 60 });
  if (!ipRl.ok) return oauthError(res, 429, "slow_down", "Too many requests");

  try {
    const appSession = requireAppSession(req);

    const userRl = await rateLimit(req, res, {
      keyPrefix: "rl:frontdoor:user",
      limit: 20,
      windowSeconds: 60,
      bucketKey: appSession.sub,
    });
    if (!userRl.ok) return oauthError(res, 429, "slow_down", "Too many requests");

    const rawRet = (req.query.ret || "/").toString();
    log("[FRONTDOOR] ret (debug)", normalizeFrontdoorRet(rawRet));
    log("[FRONTDOOR] username_fp (debug)", String(appSession.username).slice(0, 3));

    const payload = await buildFrontdoorPayload(
      appSession.username,
      appSession.sub,
      rawRet,
      { deferPrefs: true }
    );

    console.log(JSON.stringify({ event: "frontdoor_success", reqId, sub: appSession.sub }));

    return res.status(200).json(payload);
  } catch (e) {
    const status = e?.statusCode || 500;
    const code = e?.code || "server_error";

    if (DEBUG) {
      log("[FRONTDOOR] error (debug)", {
        status,
        code,
        message: e?.message,
        debug: e?._debug,
      });
    }
    console.log(JSON.stringify({ event: "frontdoor_error", reqId, status, code }));

    if (status === 401) return oauthError(res, 401, "invalid_token");
    if (status === 403) return oauthError(res, 403, "access_denied");
    if (status === 400) return oauthError(res, 400, "invalid_request");

    return oauthError(res, 500, "server_error");
  }
}
