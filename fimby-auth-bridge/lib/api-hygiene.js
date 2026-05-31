// lib/api-hygiene.js
// Lightweight request hygiene guards: CORS, Content-Type, body size

/**
 * Allowed origins for CORS. Mobile native apps don't send Origin headers,
 * so this primarily blocks browser-based cross-origin abuse.
 * Set ALLOWED_ORIGINS env var as comma-separated list, or leave empty to block all browser origins.
 */
const getAllowedOrigins = () => {
  const env = process.env.ALLOWED_ORIGINS || "";
  if (!env.trim()) return new Set(); // No browser origins allowed by default
  return new Set(env.split(",").map((s) => s.trim()).filter(Boolean));
};

/**
 * Set CORS headers. For mobile-only APIs, we block all browser cross-origin requests.
 * Native mobile clients don't send Origin headers and ignore CORS entirely.
 *
 * @param {object} req - Request object
 * @param {object} res - Response object
 * @returns {{ ok: boolean, preflight?: boolean }} - ok=false means request should be rejected
 */
export function handleCors(req, res) {
  const origin = req.headers.origin;
  const allowedOrigins = getAllowedOrigins();

  // Handle preflight OPTIONS request
  if (req.method === "OPTIONS") {
    if (origin && allowedOrigins.has(origin)) {
      res.setHeader("Access-Control-Allow-Origin", origin);
      res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
      res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
      res.setHeader("Access-Control-Max-Age", "86400"); // 24 hours
    }
    // Always respond 204 to OPTIONS (browser expects it)
    res.statusCode = 204;
    res.end();
    return { ok: true, preflight: true };
  }

  // For actual requests with an Origin header (i.e. a browser).
  if (origin) {
    if (allowedOrigins.has(origin)) {
      res.setHeader("Access-Control-Allow-Origin", origin);
    } else {
      // Browser request from a non-allowlisted origin: reject outright rather
      // than processing it. Native React Native fetch does not send an Origin
      // header, so this only ever blocks real cross-origin browser callers.
      return { ok: false, errorCode: "forbidden_origin" };
    }
  }

  // No Origin header = native mobile client or server-to-server, always allowed
  return { ok: true, preflight: false };
}

/**
 * Validate Content-Type header for POST requests.
 * Requires application/json.
 *
 * @param {object} req - Request object
 * @returns {{ ok: boolean, error?: string }}
 */
export function validateContentType(req) {
  // Only validate POST/PUT/PATCH requests that should have a body
  if (!["POST", "PUT", "PATCH"].includes(req.method)) {
    return { ok: true };
  }

  const contentType = req.headers["content-type"] || "";
  // Accept application/json with optional charset
  if (!contentType.toLowerCase().startsWith("application/json")) {
    return {
      ok: false,
      error: "Content-Type must be application/json",
    };
  }

  return { ok: true };
}

/**
 * Check request body size against a limit.
 * Uses Content-Length header if available.
 *
 * @param {object} req - Request object
 * @param {number} maxBytes - Maximum allowed body size in bytes (default 5KB)
 * @returns {{ ok: boolean, error?: string }}
 */
export function validateBodySize(req, maxBytes = 5120) {
  const contentLength = req.headers["content-length"];

  if (contentLength) {
    const size = parseInt(contentLength, 10);
    if (!isNaN(size) && size > maxBytes) {
      return {
        ok: false,
        error: `Request body too large (max ${maxBytes} bytes)`,
      };
    }
  }

  // If Vercel has already parsed the body, check its size
  if (req.body && typeof req.body === "object") {
    const bodyStr = JSON.stringify(req.body);
    if (bodyStr.length > maxBytes) {
      return {
        ok: false,
        error: `Request body too large (max ${maxBytes} bytes)`,
      };
    }
  }

  return { ok: true };
}

/**
 * Combined hygiene check: CORS + Content-Type + Body Size
 * Call at the start of your handler.
 *
 * @param {object} req - Request object
 * @param {object} res - Response object
 * @param {object} options - Configuration options
 * @param {number} options.maxBodyBytes - Max body size (default 5KB)
 * @returns {{ ok: boolean, preflight?: boolean, error?: string, errorCode?: string }}
 */
export function apiHygiene(req, res, options = {}) {
  const { maxBodyBytes = 5120 } = options;

  // 1. Handle CORS
  const cors = handleCors(req, res);
  if (cors.preflight) {
    return { ok: true, preflight: true };
  }
  if (!cors.ok) {
    return {
      ok: false,
      error: cors.error || "Origin not allowed",
      errorCode: cors.errorCode || "forbidden_origin",
    };
  }

  // 2. Validate Content-Type
  const contentType = validateContentType(req);
  if (!contentType.ok) {
    return {
      ok: false,
      error: contentType.error,
      errorCode: "invalid_content_type",
    };
  }

  // 3. Validate body size
  const bodySize = validateBodySize(req, maxBodyBytes);
  if (!bodySize.ok) {
    return {
      ok: false,
      error: bodySize.error,
      errorCode: "payload_too_large",
    };
  }

  return { ok: true };
}
