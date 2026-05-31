# Store Readiness Checklist — FIMBY Mobile

This document covers the **off-device** store submission tasks for the
Apple App Store and Google Play Store. All items here are filled in
through the respective developer consoles — there is nothing to change
in this repo once the technical mitigations in
`.cursor/plans/fimby_mobile_security_audit_3bc1c9cc.plan.md` have shipped.

Check items off as they are completed for your submission.

---

## Privacy Policy & Support URLs (prerequisites)

Both stores require a **publicly accessible** Privacy Policy URL and a
Support URL. Host them on `fimby.com` (the marketing site).

- [ ] Privacy Policy published at **`https://fimby.com/privacy`**
      (URL must respond 200 without auth)
- [ ] Support page published at **`https://fimby.com/help`**
- [ ] Policy lists every category of data FIMBY collects and why
      (see the Data Collection table below)
- [ ] Policy explicitly covers push notification tokens, in-app
      identifiers, and how a user can request deletion

---

## Apple App Store — App Store Connect

### 1. App Privacy ("Privacy Nutrition Label")

*App Store Connect → My Apps → FIMBY → App Privacy*

Declare each category FIMBY collects, links it to user identity, and
whether it's used for tracking.

| Data Type                      | Collected | Linked to User | Tracking | Notes                                           |
|--------------------------------|-----------|----------------|----------|-------------------------------------------------|
| Name                           | Yes       | Yes            | No       | Neighbour identity in posts / messages          |
| Email address                  | Yes       | Yes            | No       | Auth only                                       |
| Physical address / neighbourhood | Yes     | Yes            | No       | Required for neighbourhood scoping              |
| Phone number                   | Conditional | Yes          | No       | Only if neighbour opts into contact sharing     |
| User content (posts, messages) | Yes       | Yes            | No       | Core product                                    |
| User content (photos)          | Yes       | Yes            | No       | Library items, stories                          |
| User ID                        | Yes       | Yes            | No       | Salesforce Contact ID, app-issued JWT `sub`     |
| Device ID                      | Yes       | Yes            | No       | Expo push token (used for notifications only)   |
| Diagnostics                    | No        | —              | —        | Only if/when you add Sentry — update if so      |
| Crash data                     | No        | —              | —        | Same as above                                   |
| Product interaction            | No        | —              | —        | Not tracked                                     |

- [ ] Each row filled in correctly in the App Privacy questionnaire
- [ ] "Tracking" answered **No** for every category (we do not share data
      with third parties for advertising)

### 2. Account Deletion requirement (Apple Guideline 5.1.1(v))

Apps that let users create accounts must let users **delete them from
within the app**. This ships in `fimbySettingsView`; the auditor needs
to verify it is reachable.

- [ ] **"Delete my account"** (exact wording — matches the App Store
      listing and `delete-account.html`) is reachable from a visible
      entry point in `fimbySettingsView` within **3 taps** from the
      home screen (bottom nav → My Stuff → Settings → Delete account)
- [ ] Confirm modal explains the **30-day grace window** (default):
      login revoked immediately, restore link emailed, data scrubbed
      on day 30 unless restored
- [ ] Confirm modal exposes the opt-in **"Skip the 30-day grace
      period — delete immediately"** checkbox for users in urgent
      situations (abuse escape, harassment, crisis)
- [ ] User sees a confirmation that the request was received
- [ ] App Store listing links to
      **`https://fimby.com/delete-account`** (public page that documents
      the process — Apple accepts this as a secondary path)

### 3. App Tracking Transparency

- [ ] `NSUserTrackingUsageDescription` is **not** set in
      `app.json → ios.infoPlist` (we don't track — leaving it off
      avoids a false-positive ATT prompt)

### 4. Associated Domains (App Links)

- [x] `app.fimby.com` shows a working `apple-app-site-association`
      file (see `fimby-applinks/README.md` for verification)
- [x] Team ID filled into the AASA file (`V2NKUL8JF4`)

> **Status**: Scaffolding is live (AASA served, `associatedDomains`
> declared, Salesforce Connected App accepts both
> `https://app.fimby.com/oauth/callback` and
> `fimbymobileapp://oauth/callback`) but the OAuth flow currently uses
> the **custom scheme** redirect. Expo SDK 54's `AuthSession` /
> `ASWebAuthenticationSession` does not expose the
> `preferUniversalLinks` opt-in needed to deliver HTTPS callbacks to
> the app on iOS — that shipped in Expo SDK 56 (see expo/expo #44452).
>
> **Future migration** (post-SDK 56 upgrade):
> 1. In `fimby-mobile-app/app/index.tsx`, change `makeRedirectUri` back
>    to `{ native: "https://app.fimby.com/oauth/callback" }`.
> 2. Pass `preferUniversalLinks: true` to `promptAsync`.
> 3. Smoke-test OAuth on a real device (simulator won't honour AASA).
> 4. Remove the custom-scheme entry from the Salesforce Connected App
>    callback URL allowlist once the HTTPS flow is proven.

### 5. Encryption disclosure

- [ ] `ITSAppUsesNonExemptEncryption: false` in `app.json` ✅ (already
      set)

### 6. Age Rating

- [ ] 17+ — user-generated content (posts, messages) requires this
      rating to avoid review pushback
- [ ] In-app moderation controls documented (block, report, mute)

---

## Google Play — Play Console

### 1. Data Safety form

*Play Console → Policy → App content → Data safety*

Same categories as Apple, phrased differently.

| Google Category      | FIMBY answer                                                          |
|----------------------|-----------------------------------------------------------------------|
| Data collection      | Yes                                                                   |
| Data sharing         | No (data stays within FIMBY's Salesforce org)                         |
| Data encrypted in transit | Yes (HTTPS-only; `networkSecurityConfig` disallows cleartext)    |
| Data encrypted at rest | Yes (Salesforce platform + Redis TLS)                               |
| User can request deletion | Yes (in-app + via `https://fimby.com/delete-account`)            |

Specific data types to declare:

- **Personal info**: Name, Email, Phone number (optional), Address
- **Messages**: In-app messages to other users
- **Photos and videos**: User-uploaded library/story images
- **App activity**: App interactions (posts, responses)
- **App info and performance**: Crash logs (only if Sentry enabled)
- **Device or other IDs**: Push notification token

For each row:
- [ ] "Collected" = Yes, "Shared" = No
- [ ] Purpose = "App functionality" (and "Account management" for auth)
- [ ] Processing = "Data is processed ephemerally" = No (we persist it)

### 2. Account deletion

Play has the same in-app deletion requirement as Apple (since 2024) and
also requires a **public web URL**.

- [ ] In-app deletion reachable within 3 taps (same flow as Apple)
- [ ] Public web URL filled in Play Console: **`https://fimby.com/delete-account`**
- [ ] Web page describes what is deleted, what is retained (e.g. legal
      minimums), and how long deletion takes

### 3. Target API level (Google's policy floor)

- [ ] `android.targetSdkVersion` >= 34 (handled via Expo config; verify
      at build time)

### 4. App Links verification

- [ ] `app.fimby.com/.well-known/assetlinks.json` returns 200 with
      `Content-Type: application/json`
- [ ] SHA-256 fingerprint in the file matches the Play App Signing key
      (Play Console → Setup → App signing)

### 5. Permissions disclosure

- [ ] `android.permission.POST_NOTIFICATIONS` declared (handled by
      `expo-notifications`)
- [ ] No unused permissions present — run `./gradlew :app:dependencies`
      during EAS build to confirm

### 6. Content rating

- [ ] IARC questionnaire completed
- [ ] Answered "Yes" to user-generated content → enables the
      social-features flag

---

## Cross-store checks

- [ ] App name: **FIMBY** (or localized)
- [ ] Short description ≤ 80 chars, no keyword stuffing
- [ ] Screenshots show the actual in-app experience (no mockups with
      fake content)
- [ ] App icon matches the one in `fimby-mobile-app/assets/images/icon.png`
- [ ] Release notes don't mention vulnerabilities or
      security-sensitive changes — keep them user-focused
