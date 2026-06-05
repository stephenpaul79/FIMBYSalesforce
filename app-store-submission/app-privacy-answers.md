# App Privacy ("Privacy Nutrition Label") — answers to enter in App Store Connect

Source of truth for the App Store Connect → App Privacy questionnaire.
Grounded in the codebase (Salesforce Contact fields, mobile app token handling)
and `fimby-mobile-app/STORE_READINESS.md`.

## Step 1 — Data Collection

**Do you or your third-party partners collect data from this app?**
→ **Yes, we collect data from this app.**

There are no analytics SDKs, ad networks, or third-party data partners in the
build today. All data goes to FIMBY's own Salesforce org + auth bridge.

## Global answers (apply to every type below)

- **Used for tracking?** → **No** for every type. No third-party advertising,
  no data brokers, no ATT prompt (`NSUserTrackingUsageDescription` is not set).
- **Linked to the user's identity?** → **Yes** for every type. Everything is
  tied to the neighbour's account (Salesforce Contact).
- **Purpose** → **App Functionality** for every type (authenticate the user,
  enable features, run the neighbourhood service). Nothing is for analytics,
  personalization, or marketing.

## Data types to declare

| Apple category | Data type               | Collected | Linked | Tracking | Purpose           | What it maps to in FIMBY                                                  |
| -------------- | ----------------------- | --------- | ------ | -------- | ----------------- | ------------------------------------------------------------------------ |
| Contact Info   | Name                    | Yes       | Yes    | No       | App Functionality | Neighbour identity on posts/messages                                     |
| Contact Info   | Email Address           | Yes       | Yes    | No       | App Functionality | Sign-in / account / email notifications                                  |
| Contact Info   | Phone Number            | Yes       | Yes    | No       | App Functionality | Only when a neighbour opts into contact sharing (still "collected")      |
| Contact Info   | Physical Address        | Yes       | Yes    | No       | App Functionality | Address / neighbourhood scoping                                          |
| User Content   | Photos or Videos        | Yes       | Yes    | No       | App Functionality | Library item / story / profile / message images                         |
| User Content   | Emails or Text Messages | Yes       | Yes    | No       | App Functionality | In-app direct & group messaging (Apple counts non-SMS messages here)     |
| User Content   | Other User Content      | Yes       | Yes    | No       | App Functionality | Asks/offers, events, stories, comments, bio, care preferences, accessibility notes |
| User Content   | Customer Support        | Yes       | Yes    | No       | App Functionality | Feedback + content reports + help requests                              |
| Identifiers    | User ID                 | Yes       | Yes    | No       | App Functionality | Salesforce Contact ID, app-issued JWT `sub`                              |
| Identifiers    | Device ID               | Yes       | Yes    | No       | App Functionality | Expo/APNs push token (notifications only)                                |

## Do NOT declare (not collected today)

- **Sensitive Info** — FIMBY does not collect a person's classification (race,
  sexual orientation, religion, disability, political opinion, etc.). The two
  fields that look adjacent are not sensitive-info collection: **Accessibility
  Notes** is an optional free-text field (Apple's free-form guidance maps generic
  free text to *Other User Content*, already declared), and **Care preferences**
  is a support-type picklist (meal drop-off, errands, prayer, company…) — a
  preference for a kind of help, not a declared belief. Both are covered under
  *Other User Content*.
- **Location (Precise/Coarse)** — no device location services; neighbourhood is
  derived from the address the user types, declared above as Physical Address.
- **Diagnostics / Crash Data / Performance Data** — no Sentry/analytics SDK in
  the build. **If you add crash reporting later, come back and add Crash Data.**
- **Product Interaction / Usage Data** — not collected; no behavioural analytics.
- **Search History** — in-app searches hit Salesforce live; not retained as a
  per-user search-history dataset. (Revisit if that changes.)
- **Payment / Financial Info** — no in-app payments; donations happen on the
  marketing website outside the app.
- **Contacts** — the app never reads the device address book.

## One judgment call: IP address

The auth bridge (Vercel) and Salesforce see IP addresses for security and rate
limiting. Apple's rule: data sent only to service a request / for security and
**not retained in an identifiable form** does not need to be declared. FIMBY's
rate-limit keys are short-lived and error logs de-identify the contact
reference, so the default position is **do not declare IP**.

→ **Declare only if** your Vercel or Salesforce logs persist IP tied to a user
beyond servicing the request. If so, add **Diagnostics → Other Diagnostic Data**
(App Functionality, Linked, No tracking). Do not declare Coarse Location — IP is
not geolocated into a stored location.

## Privacy links (App Privacy → Privacy links)

- **Privacy Policy URL (required)**: `https://fimby.com/privacy`
- **Privacy Choices URL (optional)**: `https://fimby.com/delete-account`

## Before you finish

- [ ] Confirm `fimby.com/privacy` actually names: photos, in-app messages, push
      tokens, care preferences / accessibility notes (as user content), and the
      deletion path. Apple cross-checks the label against the policy text.
- [ ] Re-open this label if you ever add analytics or crash reporting.
