// api/login-and-frontdoor.js — PKCE login + frontdoor in one round trip for mobile OAuth
import crypto from "crypto";
import { mintAccessToken, mintRefreshToken, allowUser } from "../lib/sessions.js";
import { apiHygiene } from "../lib/api-hygiene.js";
import { rateLimit } from "../lib/rate-limit.js";
import { exchangePkceCode } from "../lib/pkce-exchange.js";
import { buildFrontdoorPayload, normalizeFrontdoorRet } from "../lib/frontdoor-core.js";

const getRequestId = (req) =>
  req.headers["x-request-id"] || crypto.randomUUID();

const DEBUG = process.env.DEBUG_AUTH === "true";
const log = (...args) => DEBUG && console.log(...args);

const json = (res, status, body) => {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(body));
};

const oauthError = (res, httpStatus, error, error_description) =>
  json(res, httpStatus, { error, ...(error_description ? { error_description } : {}) });

export default async function handler(req, res) {
  const reqId = getRequestId(req);

  const hygiene = apiHygiene(req, res, { maxBodyBytes: 5120 });
  if (hygiene.preflight) return;
  if (!hygiene.ok) {
    console.log(JSON.stringify({ event: "login_frontdoor_hygiene_error", reqId, code: hygiene.errorCode }));
    return oauthError(res, 400, "invalid_request");
  }

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return oauthError(res, 405, "invalid_request", "Method not allowed");
  }

  const ipRl = await rateLimit(req, res, {
    keyPrefix: "rl:login-frontdoor:ip",
    limit: 10,
    windowSeconds: 60,
  });
  if (!ipRl.ok) return oauthError(res, 429, "slow_down", "Too many requests");

  try {
    const { code, code_verifier, redirect_uri, sf_auth_host, ret: rawRet } = req.body || {};

    if (!process.env.APP_JWT_SIGNING_SECRET || !process.env.FIMBY_APP_JWT_ISSUER) {
      console.log("[LOGIN_FRONTDOOR] server misconfigured: missing jwt env");
      return oauthError(res, 500, "server_error");
    }

    const { userId, username } = await exchangePkceCode({
      code,
      code_verifier,
      redirect_uri,
      sf_auth_host,
    });

    const userRl = await rateLimit(req, res, {
      keyPrefix: "rl:login-frontdoor:user",
      limit: 20,
      windowSeconds: 60,
      bucketKey: userId,
    });
    if (!userRl.ok) return oauthError(res, 429, "slow_down", "Too many requests");

    // Fresh OAuth login is proof of life — clear any prior revocation denylist
    // so this new session works. We never block fresh logins.
    await allowUser(userId);

    const access_token = mintAccessToken({ sub: userId, username });
    const { refreshToken: refresh_token } = await mintRefreshToken({
      sub: userId,
      username,
    });

    const frontdoor = await buildFrontdoorPayload(username, userId, rawRet ?? "/", {
      deferPrefs: true,
    });

    log("[LOGIN_FRONTDOOR] ret (debug)", normalizeFrontdoorRet(rawRet ?? "/"));

    console.log(JSON.stringify({ event: "login_frontdoor_success", reqId, sub: userId }));

    return json(res, 200, {
      access_token,
      refresh_token,
      token_type: "bearer",
      expires_in: 15 * 60,
      user_id: userId,
      url: frontdoor.url,
      quietHoursPreference: frontdoor.quietHoursPreference,
      pushNotificationsEnabled: frontdoor.pushNotificationsEnabled,
    });
  } catch (e) {
    if (DEBUG) log("[LOGIN_FRONTDOOR] error (debug)", e?.message, e?._debug);
    console.log(JSON.stringify({ event: "login_frontdoor_error", reqId, error: e?.message }));

    const status = e?.statusCode || 500;
    const code = e?.code || "server_error";

    if (status === 401) return oauthError(res, 401, code === "unauthorized_client" ? code : "invalid_grant");
    if (status === 403) return oauthError(res, 403, "access_denied");
    if (status === 400) return oauthError(res, 400, "invalid_request");

    return oauthError(res, 500, "server_error");
  }
}
