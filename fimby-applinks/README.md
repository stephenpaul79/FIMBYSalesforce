# fimby-applinks

Static site for **`app.fimby.com`** — serves the files that Apple and Google
require to verify FIMBY's App Links / Universal Links, plus a fallback
`/oauth/callback` page for devices where the app isn't installed.

This is a standalone Vercel project. It is deliberately isolated from
`fimby-auth-bridge` so nothing here needs server-side code, secrets, or
env vars.

## What it serves

| Path                                            | Content-Type       | Purpose                                                       |
|-------------------------------------------------|--------------------|---------------------------------------------------------------|
| `/.well-known/apple-app-site-association`       | `application/json` | iOS Universal Links verification                              |
| `/.well-known/assetlinks.json`                  | `application/json` | Android App Links verification                                |
| `/oauth/callback`                               | `text/html`        | Fallback page when the OS can't hand off to the installed app |

`vercel.json` forces the correct `Content-Type` on the two well-known files
(Apple's AASA has no extension, so Vercel's auto-detect won't work).

## One-time setup

1. **Create the Vercel project**
   - In Vercel, create a new project pointed at this folder.
   - No environment variables needed.
   - Framework preset: **Other** / static.

2. **Attach the subdomain**
   - In the project's *Domains* tab, add `app.fimby.com`.
   - Vercel will show a CNAME target (e.g. `cname.vercel-dns.com`).

3. **DNS**
   - In whatever DNS provider hosts `fimby.com`, add a CNAME record:
     - Name: `app`
     - Target: the value Vercel shows
     - TTL: default is fine

4. **Fill in the app identifiers** (see below).

5. **Deploy**
   - Once DNS resolves and Vercel finishes the cert, the two well-known URLs
     should return HTTP 200 with `Content-Type: application/json`.
   - Verify:
     ```
     curl -I https://app.fimby.com/.well-known/apple-app-site-association
     curl -I https://app.fimby.com/.well-known/assetlinks.json
     ```

## Required placeholder replacements

### iOS — `public/.well-known/apple-app-site-association`

Replace `REPLACE_APPLE_TEAM_ID` with the **Apple Team ID** from
<https://developer.apple.com/account> (10-character alphanumeric).

The combined `appIDs` value must be exactly `TEAMID.com.fimby.app`. The
bundle ID `com.fimby.app` matches `ios.bundleIdentifier` in
`fimby-mobile-app/app.json`.

### Android — `public/.well-known/assetlinks.json`

Replace the placeholder fingerprint with the SHA-256 of the certificate
used to sign the APK/AAB. For EAS builds, get it with:

```
eas credentials
# -> select Android -> production -> "View credentials"
```

Or once the app is live in the Play Console: *Release → Setup → App
signing → App signing key certificate → SHA-256 certificate fingerprint*.

If you use both a debug and release keystore, include both fingerprints
in the `sha256_cert_fingerprints` array.

## Verifying the setup

- **iOS**: after TestFlight install, tap a link to `https://app.fimby.com/oauth/callback?code=...` — the app should open directly.
  Apple's AASA Validator: <https://branch.io/resources/aasa-validator/>
- **Android**: `adb shell pm get-app-links com.fimby.app` should show `verified`.
  Google's asset-links tester:
  `https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://app.fimby.com&relation=delegate_permission/common.handle_all_urls`

## Why Option C

We chose a dedicated subdomain instead of serving these files from the
main WordPress site (`fimby.com`) because:

- The files live next to a small, static deploy surface (no WordPress
  plugin drift).
- No risk of a WP cache plugin breaking the `Content-Type` header.
- It's trivial to inspect/rotate independently of the marketing site.
- Costs nothing beyond a Vercel Hobby project.
