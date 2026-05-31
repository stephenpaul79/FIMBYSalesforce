// api/login.js
import crypto from "crypto";
import jwt from "jsonwebtoken";
import { mintAccessToken, mintRefreshToken } from "../lib/sessions.js";
import { getRedis } from "../lib/redis.js";
import { apiHygiene } from "../lib/api-hygiene.js";
import { rateLimit } from "../lib/rate-limit.js";

const getRequestId = (req) =>
  req.headers["x-request-id"] || crypto.randomUUID();

const DEBUG = process.env.DEBUG_AUTH === "true";
const log = (...args) => DEBUG && console.log(...args);

// Minimal JSON helper
const json = (res, status, body) => {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json");
  res.end(JSON.stringify(body));
};

// OAuth-ish, provider-agnostic error helper
const oauthError = (res, httpStatus, error, error_description) =>
  json(res, httpStatus, { error, ...(error_description ? { error_description } : {}) });

export default async function handler(req, res) {
  const reqId = getRequestId(req);

  // API Hygiene: CORS, Content-Type, body size
  const hygiene = apiHygiene(req, res, { maxBodyBytes: 5120 });
  if (hygiene.preflight) return; // OPTIONS handled
  if (!hygiene.ok) {
    console.log(JSON.stringify({ event: "login_hygiene_error", reqId, code: hygiene.errorCode }));
    return oauthError(res, 400, "invalid_request");
  }

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return oauthError(res, 405, "invalid_request", "Method not allowed");
  }

  const rl = await rateLimit(req, res, {
    keyPrefix: "rl:login",
    limit: 10,
    windowSeconds: 60,
  });
  if (!rl.ok) return oauthError(res, 429, "slow_down", "Too many requests");

  try {
    const { code, code_verifier, redirect_uri, sf_auth_host } = req.body || {};

    // Debug only: fingerprints (do not log secrets)
    log(
      "[LOGIN] code_fp",
      String(code || "").slice(0, 6),
      "code_len",
      String(code || "").length
    );
    log(
      "[LOGIN] verifier_len",
      String(code_verifier || "").length,
      "verifier_fp",
      String(code_verifier || "").slice(0, 6)
    );
    log("[LOGIN] redirect_uri", redirect_uri);
    log("[LOGIN] request_host_base", sf_auth_host);

    if (!code || !code_verifier || !redirect_uri) {
      return oauthError(res, 400, "invalid_request", "Missing required parameters");
    }

    const normalizeOrigin = (raw) => {
      if (!raw || typeof raw !== "string") return null;
      try {
        const u = new URL(raw);
        if (u.protocol !== "https:") return null;
        return u.origin;
      } catch {
        return null;
      }
    };

    const normalizeHttpsBase = (raw) => {
      if (!raw || typeof raw !== "string") return null;
      try {
        const u = new URL(raw);
        if (u.protocol !== "https:") return null;
        // Keep any path but remove trailing slash for consistency
        return u.href.replace(/\/+$/, "");
      } catch {
        return null;
      }
    };

    // Prefer explicit token base. Otherwise fall back.
    const envLoginHost = normalizeHttpsBase(
      process.env.SF_OAUTH_BASE
    );
    const envTokenHost = normalizeHttpsBase(process.env.SF_OAUTH_BASE) || envLoginHost;
    const envTokenOrigin = normalizeOrigin(envTokenHost);

    if (!envLoginHost) {
      // Server-side misconfig, but keep response generic
      console.log("[LOGIN] server misconfigured: missing/invalid login host");
      return oauthError(res, 500, "server_error");
    }
    if (!envTokenHost || !envTokenOrigin) {
      console.log("[LOGIN] server misconfigured: missing/invalid token host");
      return oauthError(res, 500, "server_error");
    }

    // Optional allowlist (origins only). Default to env origin if unset.
    const allowedOrigins = new Set(
      (process.env.SF_ALLOWED_AUTH_HOSTS || envTokenOrigin)
        .split(",")
        .map((s) => normalizeOrigin(s.trim()))
        .filter(Boolean)
    );

    // Client-provided host/base (dev only)
    const reqBase = normalizeHttpsBase(sf_auth_host);

    // Production: ignore request host override
    let authHost = envTokenHost;

    if (process.env.NODE_ENV !== "production") {
      // Dev: allow request override only if allowlisted; otherwise reject (generic)
      const candidateBase = reqBase || envTokenHost;
      const candidateOrigin = normalizeOrigin(candidateBase);
      if (!candidateOrigin || !allowedOrigins.has(candidateOrigin)) {
        log("[LOGIN] dev host override rejected", {
          provided: sf_auth_host,
          normalized: candidateBase,
          allowed: Array.from(allowedOrigins),
        });
        return oauthError(res, 400, "invalid_request");
      }
      authHost = candidateBase;
    } else {
      // Prod: ensure env origin is allowlisted (catch typos/misconfig)
      if (!allowedOrigins.has(envTokenOrigin)) {
        console.log("[LOGIN] server misconfigured: token host not allowlisted");
        return oauthError(res, 500, "server_error");
      }
    }

    const clientId = process.env.SF_PKCE_CLIENT_ID;
    if (!clientId) {
      console.log("[LOGIN] server misconfigured: missing client id");
      return oauthError(res, 500, "server_error");
    }
    if (!process.env.APP_JWT_SIGNING_SECRET) {
      console.log("[LOGIN] server misconfigured: missing signing secret");
      return oauthError(res, 500, "server_error");
    }
    if (!process.env.FIMBY_APP_JWT_ISSUER) {
      console.log("[LOGIN] server misconfigured: missing jwt issuer");
      return oauthError(res, 500, "server_error");
    }

    // Authorization Code + PKCE token exchange
    const params = new URLSearchParams({
      grant_type: "authorization_code",
      client_id: clientId,
      code,
      code_verifier,
      redirect_uri,
    });

    // Debug only: URLs and configuration (no always-on leakage)
    log("[LOGIN] token url (debug)", `${authHost}/services/oauth2/token`);

    const tokenResp = await fetch(`${authHost}/services/oauth2/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params.toString(),
    });

    const tokenText = await tokenResp.text();

    if (!tokenResp.ok) {
      // Log detail only when debugging. Client gets generic OAuth-ish error.
      if (DEBUG) {
        log("[LOGIN] token exchange failed (debug)", {
          status: tokenResp.status,
          statusText: tokenResp.statusText,
          body: tokenText,
        });
      }
      console.log(JSON.stringify({ event: "login_token_exchange_failed", reqId, status: tokenResp.status }));

      // Map common cases to standard lingo without naming providers
      // 400/401 are typical for invalid_grant style failures
      const status = tokenResp.status;
      if (status === 400 || status === 401) {
        return oauthError(res, 401, "invalid_grant");
      }
      if (status === 403) {
        return oauthError(res, 403, "access_denied");
      }
      return oauthError(res, 502, "server_error");
    }

    let tokenJson;
    try {
      tokenJson = JSON.parse(tokenText);
    } catch (e) {
      if (DEBUG) log("[LOGIN] token JSON parse failed (debug)", tokenText);
      console.log("[LOGIN] token JSON parse failed");
      return oauthError(res, 502, "server_error");
    }

    const idUrl = tokenJson.id;
    const accessToken = tokenJson.access_token;

    if (!idUrl || !accessToken) {
      if (DEBUG) log("[LOGIN] token response missing fields (debug)", tokenJson);
      console.log("[LOGIN] token response missing fields");
      return oauthError(res, 502, "server_error");
    }

    // Identity fetch
    const idResp = await fetch(idUrl, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    const idText = await idResp.text();

    if (!idResp.ok) {
      if (DEBUG) {
        log("[LOGIN] identity fetch failed (debug)", {
          status: idResp.status,
          statusText: idResp.statusText,
          body: idText,
        });
      }
      console.log(JSON.stringify({ event: "login_identity_fetch_failed", reqId, status: idResp.status }));

      // Provider-agnostic response
      return oauthError(res, 401, "invalid_token");
    }

    let identity;
    try {
      identity = JSON.parse(idText);
    } catch (e) {
      if (DEBUG) log("[LOGIN] identity JSON parse failed (debug)", idText);
      console.log("[LOGIN] identity JSON parse failed");
      return oauthError(res, 502, "server_error");
    }

    const userId = identity.user_id;
    const username = identity.username;

    if (!username || !userId) {
      if (DEBUG) log("[LOGIN] identity missing fields (debug)", identity);
      console.log("[LOGIN] identity missing fields");
      return oauthError(res, 401, "unauthorized_client");
    }

    // Mint app session tokens
    const access_token = mintAccessToken({ sub: userId, username });
    const { refreshToken: refresh_token } = await mintRefreshToken({
      sub: userId,
      username,
    });

    console.log(JSON.stringify({ event: "login_success", reqId, sub: userId }));

    return json(res, 200, {
      access_token,
      refresh_token,
      token_type: "bearer",
      expires_in: 15 * 60,
      user_id: userId,
    });
  } catch (e) {
    if (DEBUG) {
      log("[LOGIN] handler error (debug)", e);
    }
    console.log(JSON.stringify({ event: "login_error", reqId, error: e?.message }));
    return oauthError(res, 500, "server_error");
  }
}
