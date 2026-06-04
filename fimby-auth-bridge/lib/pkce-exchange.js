const DEBUG = process.env.DEBUG_AUTH === "true";
const log = (...args) => DEBUG && console.log(...args);

function normalizeOrigin(raw) {
  if (!raw || typeof raw !== "string") return null;
  try {
    const u = new URL(raw);
    if (u.protocol !== "https:") return null;
    return u.origin;
  } catch {
    return null;
  }
}

function normalizeHttpsBase(raw) {
  if (!raw || typeof raw !== "string") return null;
  try {
    const u = new URL(raw);
    if (u.protocol !== "https:") return null;
    return u.href.replace(/\/+$/, "");
  } catch {
    return null;
  }
}

function resolveAuthHost(sf_auth_host) {
  const envLoginHost = normalizeHttpsBase(process.env.SF_OAUTH_BASE);
  const envTokenHost = normalizeHttpsBase(process.env.SF_OAUTH_BASE) || envLoginHost;
  const envTokenOrigin = normalizeOrigin(envTokenHost);

  if (!envLoginHost) {
    const err = new Error("server_misconfigured_login_host");
    err.statusCode = 500;
    err.code = "server_error";
    throw err;
  }
  if (!envTokenHost || !envTokenOrigin) {
    const err = new Error("server_misconfigured_token_host");
    err.statusCode = 500;
    err.code = "server_error";
    throw err;
  }

  const allowedOrigins = new Set(
    (process.env.SF_ALLOWED_AUTH_HOSTS || envTokenOrigin)
      .split(",")
      .map((s) => normalizeOrigin(s.trim()))
      .filter(Boolean)
  );

  const reqBase = normalizeHttpsBase(sf_auth_host);
  let authHost = envTokenHost;

  if (process.env.NODE_ENV !== "production") {
    const candidateBase = reqBase || envTokenHost;
    const candidateOrigin = normalizeOrigin(candidateBase);
    if (!candidateOrigin || !allowedOrigins.has(candidateOrigin)) {
      const err = new Error("invalid_auth_host");
      err.statusCode = 400;
      err.code = "invalid_request";
      throw err;
    }
    authHost = candidateBase;
  } else if (!allowedOrigins.has(envTokenOrigin)) {
    const err = new Error("server_misconfigured_allowlist");
    err.statusCode = 500;
    err.code = "server_error";
    throw err;
  }

  return authHost;
}

/**
 * PKCE authorization-code exchange → Salesforce identity { userId, username }.
 */
export async function exchangePkceCode({ code, code_verifier, redirect_uri, sf_auth_host }) {
  if (!code || !code_verifier || !redirect_uri) {
    const err = new Error("missing_parameters");
    err.statusCode = 400;
    err.code = "invalid_request";
    throw err;
  }

  const clientId = process.env.SF_PKCE_CLIENT_ID;
  if (!clientId) {
    const err = new Error("server_misconfigured_client");
    err.statusCode = 500;
    err.code = "server_error";
    throw err;
  }

  const authHost = resolveAuthHost(sf_auth_host);

  const params = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: clientId,
    code,
    code_verifier,
    redirect_uri,
  });

  log("[LOGIN] token url (debug)", `${authHost}/services/oauth2/token`);

  const tokenResp = await fetch(`${authHost}/services/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });

  const tokenText = await tokenResp.text();

  if (!tokenResp.ok) {
    if (DEBUG) {
      log("[LOGIN] token exchange failed (debug)", {
        status: tokenResp.status,
        body: tokenText,
      });
    }
    const err = new Error("token_exchange_failed");
    err.statusCode = tokenResp.status === 403 ? 403 : tokenResp.status === 401 || tokenResp.status === 400 ? 401 : 502;
    err.code =
      tokenResp.status === 403
        ? "access_denied"
        : tokenResp.status === 400 || tokenResp.status === 401
          ? "invalid_grant"
          : "server_error";
    throw err;
  }

  let tokenJson;
  try {
    tokenJson = JSON.parse(tokenText);
  } catch {
    const err = new Error("token_parse_failed");
    err.statusCode = 502;
    err.code = "server_error";
    throw err;
  }

  const idUrl = tokenJson.id;
  const accessToken = tokenJson.access_token;

  if (!idUrl || !accessToken) {
    const err = new Error("token_shape_invalid");
    err.statusCode = 502;
    err.code = "server_error";
    throw err;
  }

  const idResp = await fetch(idUrl, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  const idText = await idResp.text();

  if (!idResp.ok) {
    const err = new Error("identity_fetch_failed");
    err.statusCode = 401;
    err.code = "invalid_token";
    throw err;
  }

  let identity;
  try {
    identity = JSON.parse(idText);
  } catch {
    const err = new Error("identity_parse_failed");
    err.statusCode = 502;
    err.code = "server_error";
    throw err;
  }

  const userId = identity.user_id;
  const username = identity.username;

  if (!username || !userId) {
    const err = new Error("identity_shape_invalid");
    err.statusCode = 401;
    err.code = "unauthorized_client";
    throw err;
  }

  return { userId, username };
}
