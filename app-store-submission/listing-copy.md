# FIMBY — Store Listing Copy

Paste-ready text for App Store Connect and Google Play Console. Character counts are against each store's limit. No em dashes anywhere (on-voice, clean).

Canonical URLs:

- Support: `https://fimby.com/help`
- Privacy: `https://fimby.com/privacy`
- Account deletion: `https://fimby.com/delete-account`
- Marketing: `https://fimby.com/`

---

## Apple App Store

### App name (limit 30)

```
FIMBY
```

`5/30`. Alternative for more search weight: `FIMBY: Know Your Neighbours` (`27/30`).

### Subtitle (limit 30)

```
Neighbours who know your name
```

`29/30`

### Promotional text (limit 170, editable anytime)

```
Turn the place you live into a place you belong. Ask, offer, lend, borrow, and gather with the neighbours right around you. No ads, no feeds, no strangers.
```

`155/170`

### Keywords (limit 100, comma-separated, no spaces after commas)

```
neighbors,mutual aid,community,lending,bulk buy,borrow,sharing,local,care,events,tools,potluck
```

`94/100`. "neighbours" intentionally omitted — Apple already indexes subtitle words; US spelling "neighbors" added for search.

### Description (limit 4000)

```
FIMBY (Family In My Backyard) turns the place you live into a place you belong.

Most apps teach us to scroll past each other. FIMBY helps neighbours slow down, notice each other, and share everyday life close to home.

It is built on a simple hope: that a neighbourhood shaped by generosity and love can feel different from one shaped by scarcity and fear.

FIMBY is a neighbourhood app for the people around you, not a city-wide feed. Ask for help, offer what you have, lend and borrow everyday things, coordinate shared purchases, gather, and stay connected in small, ordinary ways.

WHAT YOU CAN DO

Ask and offer
Post what you need or what you can share, from moving help to extra soup.

Lend and borrow
Create a neighbourhood lending library for tools, books, kitchen gear, and other useful things. Borrowers and return dates are tracked for you.

Bulk buys
Split large purchases with neighbours. Reserve shares and let FIMBY keep the allocations organized.

Gather
Host a dinner, plan a cleanup day, share a block party, or pass along a local event worth knowing about.

Share life
Post a story, a thank you, a hard moment, or a prayer request (if that is something you do).  

Messages
Coordinate through response threads, direct messages, and group chats, all in one inbox.

BUILT FOR REAL NEIGHBOURS

Local by design
You see the same neighbours over time, not thousands of strangers. Names become familiar. Small acts of care start becoming real relationships.

Belonging over performance
No likes. No followers. No trending. FIMBY is for showing up, not showing off.

Care preferences
During onboarding, you can share how neighbours can care for you, on your terms. What kind of support is welcome, what feels unhelpful, and how people should reach out. Everything is optional and editable.

Support people
Someone you trust can help you use FIMBY, including posting and messaging on your behalf. Built for elders, disabled neighbours, people with low tech confidence, and anyone who would rather have a trusted someone help them take part.

Local organizations
Community centres, shelters, churches, and other local groups can share events, meal times, programs, and practical information in the same neighbourhood feed.

PRIVACY AND RESPECT

No ads. No data harvesting. No engagement metrics. Your neighbours are not an audience to be monetized.

You choose what to share, with whom, and you can change your mind. Contact sharing is granular and revocable. Blocking is bidirectional.

Quiet by design
Set quiet hours, choose what you hear about, and let the rest wait for morning. FIMBY is a doorbell, not a slot machine.

Delete anytime
Go to Settings, then Delete my account. Your login is revoked right away, with a 30-day grace window to restore your account if you change your mind.

WHO IT IS FOR

FIMBY is for adults 19 and older who live in an active FIMBY neighbourhood. It is open to everyone, whatever your background or beliefs. You do not need to belong to any organization, church, or community group to find a place here.

FIMBY grew out of more than 20 years of neighbouring in Vancouver's Downtown Eastside: shared meals, prayer, lending, checking in, practical help, and local groups trying to care well for the same place.

FIMBY is not a replacement for shelters, health care, crisis lines, detox, or other essential services. It is one small way to help neighbours and local groups share everyday life and practical care, close to home.

Technology can make needs visible. It can make generosity easier to act on. It can open a door. But it cannot make us love our neighbours. That part is still ours to live. FIMBY helps make it a little less hard to start.

Currently available in Vancouver's V6A neighbourhood, and growing neighbourhood by neighbourhood.
```

### What's New / release notes (v1.0.0)

```
Welcome to FIMBY. This is our first release.

FIMBY helps neighbours ask, offer, lend, borrow, gather, and stay connected, close to home. We are starting in Vancouver's V6A and growing neighbourhood by neighbourhood. We would love your feedback.
```

### Single-value fields


| Field              | Value                                                |
| ------------------ | ---------------------------------------------------- |
| Support URL        | `https://fimby.com/help`                             |
| Marketing URL      | `https://fimby.com/`                                 |
| Privacy Policy URL | `https://fimby.com/privacy`                          |
| Copyright          | `© 2026 Strathcona Vineyard Church`                  |
| Primary category   | Social Networking (suggested)                        |
| Secondary category | Lifestyle (suggested)                                |
| Age rating         | 17+ (frequent/intense UGC + unrestricted web access) |


### App Review notes

```
FIMBY is a charity-operated neighbourhood mutual-aid app for adults 19+, operated by Strathcona Vineyard Church (registered Canadian charity, BC). It is invite-only and neighbourhood-scoped, so a normal account only sees its own neighbourhood. We have pre-seeded a "Reviewer's Neighbourhood" so you can review the full experience without involving real neighbours.

Demo account (sign-in required):
Email: reviewer@fimby.com (reset in your profile after initial login to receive email notifications)
Password: [INSERT BEFORE SUBMITTING]

The native iOS client integrates with platform capabilities that a website cannot: Apple Push Notifications for neighbour messages and lending reminders, on-device OAuth PKCE sign-in with credentials secured in the iOS Keychain (via expo-secure-store) so backend tokens never persist on the device, Universal Links for the sign-in callback, and per-user quiet hours that suppress notifications on-device. The app is a full neighbourhood mutual-aid client (asks, offers, lending library with due-date tracking, bulk-buy coordination, events, direct and group messaging), not a single-page utility or content feed.

Account deletion is in-app at Settings > Delete my account, and is also documented at https://fimby.com/delete-account. Reporting and blocking are available on every post, profile, conversation, and message thread; reports are reviewed promptly per our Community Standards.

Contact during review: Stephen Rathjen, 604 318 1387, fimby@strathconavineyard.com
```

**Before submitting:** fill the demo account password (Phase 5) and the review-contact line.

---

## Google Play Store

### Title (limit 30)

```
FIMBY
```

`5/30`

### Short description (limit 80)

```
Ask, offer, lend, and gather with the neighbours right around you.
```

`66/80`

### Full description (limit 4000)

Same body as the App Store description above. Play renders plain text; the section headings and line breaks carry over fine.

```
FIMBY (Family In My Backyard) turns the place you live into a place you belong.

Most apps teach us to scroll past each other. FIMBY helps neighbours slow down, notice each other, and share everyday life close to home.

It is built on a simple hope: that a neighbourhood shaped by generosity and love can feel different from one shaped by scarcity and fear.

FIMBY is a neighbourhood app for the people around you, not a city-wide feed. Ask for help, offer what you have, lend and borrow everyday things, coordinate shared purchases, gather, and stay connected in small, ordinary ways.

WHAT YOU CAN DO

Ask and offer
Post what you need or what you can share, from moving help to extra tomato starts.

Lend and borrow
Create a neighbourhood lending library for tools, books, kitchen gear, and other useful things. Return dates are tracked for you.

Bulk buys
Split large purchases with neighbours. Reserve shares and let FIMBY keep the allocations straight.

Gather
Host a dinner, organize a cleanup, share a block party, or pass along a local event worth knowing about.

Share life
Post a story, a thank you, a hard moment, or a prayer request, if that is part of your life. No one is ever expected to join in.

Messages
Coordinate through response threads, direct messages, and group chats, all in one inbox.

BUILT FOR REAL NEIGHBOURS

Local by design
You see the same neighbours over time, not thousands of strangers. Names become familiar. Small acts of care start becoming real relationships.

Belonging over performance
No likes. No followers. No trending. FIMBY is for showing up, not showing off.

Care preferences
During onboarding, you can share how neighbours can care for you well, on your terms. What kind of support is welcome, what feels unhelpful, and how people should reach out. Everything is optional and editable.

Support people
Someone you trust can help you use FIMBY, including posting and messaging on your behalf. Built for elders, disabled neighbours, people with low tech confidence, and anyone who would rather have someone close help them take part.

Local organizations
Community centres, shelters, churches, and other local groups can share events, meal times, programs, and practical information in the same neighbourhood feed.

PRIVACY AND RESPECT

No ads. No data harvesting. No engagement metrics. Your neighbours are not an audience to be monetized.

You choose what to share, with whom, and you can change your mind. Contact sharing is granular and revocable. Blocking is bidirectional.

Quiet by design
Set quiet hours, choose what you hear about, and let the rest wait for morning. FIMBY is a doorbell, not a slot machine.

Delete anytime
Go to Settings, then Delete my account. Your login is revoked right away, with a 30-day grace window to restore your account if you change your mind.

WHO IT IS FOR

FIMBY is for adults 19 and older who live in an active FIMBY neighbourhood. It is open to everyone, whatever your background or beliefs. You do not need to belong to any organization, church, or community group to find a place here.

FIMBY grew out of more than 20 years of neighbouring in Vancouver's Downtown Eastside: shared meals, prayer, lending, checking in, practical help, and local groups trying to care well for the same place.

FIMBY is not a replacement for shelters, health care, crisis lines, detox, or other essential services. It is one small way to help neighbours and local groups share everyday life and practical care, close to home.

Technology can make needs visible. It can make generosity easier to act on. It can open a door. But it cannot make us love our neighbours. That part is still ours to live. FIMBY helps make it a little less hard to start.

Currently available in Vancouver's V6A neighbourhood, and growing neighbourhood by neighbourhood.
```

### Play single-value fields


| Field                | Value                                                             |
| -------------------- | ----------------------------------------------------------------- |
| Privacy Policy URL   | `https://fimby.com/privacy`                                       |
| Support email        | `help@fimby.com`                                                  |
| Support website      | `https://fimby.com/help`                                          |
| Account deletion URL | `https://fimby.com/delete-account`                                |
| Category             | Social (suggested)                                                |
| Content rating       | Complete IARC questionnaire; answer Yes to user-generated content |


```

```

