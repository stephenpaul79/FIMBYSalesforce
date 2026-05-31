# FIMBY Mobile App

Native iOS and Android client for **FIMBY** (Family In My Backyard) — a charity-operated neighbourhood mutual-aid platform run by Strathcona Vineyard Church (Canadian registered charity, BC). FIMBY helps verified neighbours within a defined geographic boundary share asks and offers, lend belongings, coordinate group buys, run small events, and have private one-to-one or group conversations — with strong consent, neighbourhood-scoped trust, and no advertising.

The app combines a native identity, presence, and notification layer with a Salesforce-hosted community-data platform. The two layers are co-designed:

- The **native layer** owns everything that has to happen on-device for the product to work safely and feel native: an on-device OAuth PKCE flow (Salesforce credentials and tokens never reach the device — only short-lived app-scoped JWTs do), refresh tokens encrypted in iOS Keychain / Android Keystore via `expo-secure-store`, Apple and Google push notifications routed through a hardcoded payload allowlist (no arbitrary URL execution), Universal Links / App Links handling for the OAuth callback, a quiet-hours "do not disturb" screen that respects per-user preferences before any content is fetched, splash video, biometric-friendly auth bootstrap, and a same-origin enforcement layer that hands off-domain links to the system browser so session cookies cannot leak to third-party content.
- The **community-data layer** is a custom Salesforce Experience Cloud application with neighbourhood-scoped data sovereignty: more than 100 custom Lightning Web Components covering the community feed, lending-library lifecycle (request → approve → loan → return), real-time messaging, in-app notifications, group buying with accountability check-ins, consent-gated contact sharing, bidirectional blocking, in-app reporting with 24-hour moderation SLA, and an in-app account deletion flow. Every record is stamped with a neighbourhood ID; users never see content from outside their neighbourhood.

Both layers ship and version together, and a substantial portion of the app's value — particularly identity, privacy, presence, and trust — could not be delivered by a web-only experience.

| | |
|---|---|
| iOS bundle ID | `com.fimby.app` |
| Android package | `com.fimby.app` |
| Apple Team ID | `V2NKUL8JF4` |
| Universal Links domain | `app.fimby.com` |
| Min iOS | 15.1 |
| Min Android SDK | 24 (target 35) |

## Architecture

| Layer | Tech | Where |
|---|---|---|
| Mobile shell | Expo SDK 54, React Native, expo-router | this repo |
| Auth bridge | Node serverless on Vercel + Upstash Redis | [`../fimby-auth-bridge/`](../fimby-auth-bridge/) |
| Backend + UI | Salesforce Experience Cloud, Apex, LWC | [`../FIMBY/`](../FIMBY/) |
| Marketing + policy site | Static HTML on WordPress (`fimby.com`) | [`../FIMBY Website/`](../FIMBY%20Website/) |

**Auth flow**: app starts PKCE in `ASWebAuthenticationSession` → Salesforce login → callback to auth bridge → bridge mints app-scoped JWTs (15 min access / 30 day refresh) → app calls Salesforce `/singleaccess` with the JWT to get a frontdoor URL → WebView loads the frontdoor URL. Session-level rotation, family-replay revocation, idle/absolute caps, and per-user/IP rate limits all live in the auth bridge.

**Native entry point**: `app/index.tsx` is the single expo-router route. It runs the auth bootstrap, splash video, quiet-hours screen, and OAuth dispatcher, then hands off to the community-data layer. Native-side deep link handling for push payloads and Universal Links is implemented through a postMessage bridge in `index.tsx`, so the native runtime always controls which routes can be opened — payload URLs are validated against an allowlist before any navigation occurs.

## Privacy posture

- No third-party analytics, ad SDKs, or trackers
- No `NSUserTrackingUsageDescription` — we do not track
- No `NSPhotoLibraryUsageDescription` — file inputs use PHPicker (out-of-process; no permission needed)
- `NSCameraUsageDescription` declared — required for photo capture from inside the WebView
- `ITSAppUsesNonExemptEncryption: false` — HTTPS only, no custom crypto
- Diagnostics / crash reporting intentionally **off** to keep App Privacy disclosures honest

See [`STORE_READINESS.md`](./STORE_READINESS.md) for the full App Privacy / Data Safety disclosure matrix used for store listings.

## Release process

Build profiles live in [`eas.json`](./eas.json). Versioning: `expo.version` is set in [`app.json`](./app.json) and bumped per public release; `buildNumber` / `versionCode` is owned by EAS (`appVersionSource: remote`).

| Profile | Command | Purpose |
|---|---|---|
| `preview` | `eas build --platform ios --profile preview` | Internal-only install link for vouched neighbours and pre-release smoke tests. No version bump. |
| `production` | `eas build --platform ios --profile production` | Auto-increments build number, uploads to App Store Connect, routes through TestFlight → App Store. |
| `production` (Android) | `eas build --platform android --profile production` | Routes to Play Console internal testing → production track. |

Submission is automated through `eas submit -p ios` (credentials configured in `eas.json` → `submit.production.ios`).

## Store launch tracking

See the live phase-by-phase plan: [`fimby_app_store_launch_cac0fad0.plan.md`](../.cursor/plans/fimby_app_store_launch_cac0fad0.plan.md).

Off-device submission tasks (App Privacy, Data Safety, screenshots, reviewer notes, demo accounts): [`STORE_READINESS.md`](./STORE_READINESS.md).

## Operations

- **Auth bridge** runtime, env vars, and rotation runbook: [`../fimby-auth-bridge/README.md`](../fimby-auth-bridge/README.md)
- **Salesforce ops** (deploy windows, error log triage, deletion intake monitoring): [`../FIMBY/docs/operations-playbook.md`](../FIMBY/docs/operations-playbook.md)
- **Day-1 monitoring after release**: Vercel auth-bridge logs (watch for `refresh_reuse_detected` clustering), Salesforce `Error_Log__c`, `FimbyDeletionIntakeService` queue, App Store Connect / Play Console weekly summaries.

## License & ownership

© Strathcona Vineyard Church. All rights reserved. This source is not licensed for redistribution.
