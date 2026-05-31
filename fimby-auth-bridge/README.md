# FIMBY Auth Bridge

Node.js serverless API on **Vercel** that sits between the FIMBY mobile app and Salesforce. It exchanges the on-device OAuth PKCE authorization code for **app-scoped JWTs** (Salesforce tokens never reach the device), stores refresh-token families in **Redis (Upstash)**, mints Salesforce frontdoor URLs for the WebView, and relays push notifications from Salesforce to **Expo Push**.

Production base URL: **`https://fimby-auth-bridge.vercel.app`**

| Layer | Location |
|-------|----------|
| Mobile client | [`../fimby-mobile-app/`](../fimby-mobile-app/) |
| This service | `fimby-auth-bridge/` (this repo folder) |
| Experience Cloud UI | [`../FIMBY/`](../FIMBY/) Salesforce org |

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `POST` | `/api/login` | — | PKCE code exchange → app access + refresh JWTs |
| `POST` | `/api/session/refresh` | refresh body | Rotate refresh token; mint new access token |
| `POST` | `/api/logout` | refresh body (+ optional access Bearer) | Revoke refresh token server-side |
| `GET` / `POST` | `/api/frontdoor` | Bearer access JWT | Salesforce JWT bearer + `/singleaccess` → WebView URL |
| `POST` / `DELETE` | `/api/push-token` | Bearer access JWT | Register / remove Expo push token in Redis |
| `POST` | `/api/notifications/push` | `X-SF-Secret` header | Salesforce → Expo push (single or batch) |
| `GET` | `/api/health` | — | Liveness (`?mode=basic`) or Redis ping (`?mode=deep` + `X-Admin-Key`) |

Structured JSON logs use `event` names such as `login_success`, `refresh_reuse_detected`, `frontdoor_success`, `push_sent`. No PII in logs.

## Session policy

| Token | TTL |
|-------|-----|
| Access JWT | 15 minutes |
| Refresh token (Redis) | 30 days sliding idle; 90 days absolute (logout at next 2am PST/PDT cutoff after absolute cap) |
| Push token mapping | 180 days (refreshed on each register) |

Refresh rotation uses **token families**. Replaying a rotated refresh token triggers `refresh_reuse_detected` and revokes the whole family.

## Environment variables

Set in **Vercel → Project → Settings → Environment Variables** for Production (and Preview/Development as needed). Never commit values — see `.gitignore`.

### Required (production)

| Variable | Used by | Notes |
|----------|---------|-------|
| `SF_OAUTH_BASE` | login | HTTPS Salesforce OAuth base (e.g. `https://login.salesforce.com` or My Domain). Token exchange hits `{base}/services/oauth2/token`. |
| `SF_PKCE_CLIENT_ID` | login | Connected App consumer key for the mobile PKCE client. |
| `APP_JWT_SIGNING_SECRET` | login, refresh, frontdoor, push-token, logout | HS256 secret for app access/refresh JWTs. **Rotating invalidates all active sessions.** |
| `FIMBY_APP_JWT_ISSUER` | login, refresh, frontdoor, push-token | Issuer claim (`iss`) on app JWTs. |
| `SF_PRIVATE_KEY_BASE64` | frontdoor | Base64-encoded RSA private key for Salesforce JWT bearer flow. No filesystem fallback. |
| `SF_CONSUMER_KEY` | frontdoor | Connected App consumer key for JWT bearer (integration user). |
| `SF_LOGIN_HOST` | frontdoor | Salesforce login host used as JWT `aud` and for token/singleaccess URLs. |
| `REDIS_URL` | all session/push paths | Upstash **`rediss://`** URL. Plain `redis://` is rejected when `NODE_ENV=production`. |
| `SF_PUSH_SECRET` | notifications/push | Shared secret; Salesforce sends as `X-SF-Secret`. |

### Optional

| Variable | Default | Notes |
|----------|---------|-------|
| `FIMBY_APP_JWT_AUDIENCE` | `com.fimby.app` | JWT `aud` — must match mobile bundle ID. |
| `SF_ALLOWED_AUTH_HOSTS` | origin of `SF_OAUTH_BASE` | Comma-separated HTTPS origins allowed for dev host override. |
| `ALLOWED_ORIGINS` | (none) | Comma-separated browser origins for CORS. Native apps omit `Origin`; leave empty unless you need browser callers. |
| `DEBUG_AUTH` | off | Set to `true` for verbose debug logs (never in production unless investigating). |
| `ADMIN_KEY` | — | Enables `/api/health?mode=deep` when passed as `X-Admin-Key`. |
| `NODE_ENV` | set by Vercel | `production` on Production deployments. |

### Local development

Copy env vars into **`.env.development.local`** (gitignored). Vercel CLI loads this for `vercel dev`. The Salesforce private key must come from `SF_PRIVATE_KEY_BASE64` only — do not place `.pem` / `.key` files in the repo.

## Deploy

From this directory:

```bash
npm install
vercel --prod
```

Or push to the branch connected to Vercel for automatic Production deploys.

After changing env vars in the Vercel dashboard, **redeploy** (env changes do not apply to already-running instances until the next deployment).

Preview deployments use Preview env vars; confirm Redis and Salesforce credentials point at non-production targets when testing.

## Rotation runbook

### `APP_JWT_SIGNING_SECRET`

1. Generate a new strong random secret.
2. Update Vercel Production env var.
3. Redeploy.
4. **Effect:** all users must sign in again (all access/refresh JWTs invalid).

### `SF_PUSH_SECRET`

1. Generate new secret.
2. Update Vercel **and** the matching Salesforce outbound config (Named Credential / custom setting that sends `X-SF-Secret`).
3. Redeploy bridge.
4. **Effect:** push delivery fails until both sides match.

### `SF_PRIVATE_KEY_BASE64` / JWT bearer cert

1. Upload new cert to Salesforce Connected App (integration user).
2. Base64-encode the new private key; update `SF_PRIVATE_KEY_BASE64` in Vercel.
3. Redeploy.
4. **Effect:** frontdoor minting fails until aligned; active app JWTs unaffected until they expire/refresh.

### `SF_PKCE_CLIENT_ID` / PKCE Connected App

1. Change in Salesforce Connected App and Vercel together.
2. Redeploy.
3. **Effect:** new logins fail until aligned; existing refresh sessions may still work until idle/absolute expiry.

### `REDIS_URL` (Upstash)

1. Create new Upstash database or rotate credentials in Upstash console.
2. Update `REDIS_URL` in Vercel (must stay `rediss://` in production).
3. Redeploy.
4. **Effect:** all refresh sessions and push token mappings lost — users re-login and re-register push.

## Operations monitoring

Watch Vercel **Production → Logs** (JSON lines):

| Event | Meaning |
|-------|---------|
| `refresh_reuse_detected` | Possible stolen refresh token; family revoked (expected occasionally; investigate clusters) |
| `login_token_exchange_failed` | PKCE/code issue or Salesforce OAuth misconfig |
| `frontdoor_error` | JWT bearer or singleaccess failure |
| `push_unauthorized` | Bad or missing `X-SF-Secret` from Salesforce |
| `push_no_token` | User has no registered Expo token (benign) |

Deep health check (requires `ADMIN_KEY`):

```http
GET /api/health?mode=deep
X-Admin-Key: <ADMIN_KEY>
```

## Security notes

- Salesforce access tokens from PKCE exchange are used only server-side during login; the mobile app receives app JWTs only.
- CORS blocks browser cross-origin abuse; mobile native clients are unaffected.
- Rate limits are per-IP and per-user on sensitive routes; Redis errors **fail open** on rate limiting only (auth still works).
- Private keys and `.env*` files must never be committed. `.vercelignore` excludes secrets from deploy bundles.

## License

© Strathcona Vineyard Church. Internal operations service — not licensed for redistribution.
