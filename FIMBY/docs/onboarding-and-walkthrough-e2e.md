# Onboarding and Walkthrough — E2E Reference

## Profile onboarding (4 steps)

1. Name + pronouns + privacy toggles
2. Profile photo
3. About you (minimum 2 of 5 fields)
4. Care welcome multi-select only

On **Finish**: `completeProfileSetup`, silent default quiet hours (`10PM_6AM`), `sessionStorage.fimby_tour_pending = '1'`, redirect to `/`.

## Tour entry

| Trigger | Behavior |
|---------|----------|
| Home after onboarding | Autostart when `liveTourEnabled`, `Live_Tour_Status__c = Not Started`, and `fimby_tour_pending` |
| Later Home visits (Not Started, no flag) | No autostart |
| Home banner | When status = `Dismissed`: **Take the tour** / **I'll explore on my own** (permanent → `Completed`) |

## Essentials (7 steps)

C0 welcome → C1 feed → C2 create → C3 library → C4 messages → values → everyday-trust (off-ramp).

- C0 from onboarding: “Welcome in, {firstName}” + profile-ready line
- C3 names vouch expectation (aligned with library settling-in banner)
- Off-ramp on everyday-trust: **Take me Home** / **Show me a bit more**

## Extended (5 steps)

open-menu → account-controls → manage-identities → your-corner → capstone (trellisafter, no vine).

## Deferred nudges

- Settings: quiet-hours hint on first visit when still default
- Profile: care expander hint when welcome set but `Care_How_To_Ask__c` empty
- Library: settling-in banner + vouch modal copy aligned with C3

## QA paths

1. New user: complete 4 profile steps → land on Home → tour autostarts → skip → banner appears → Take the tour
2. Complete Essentials → Take me Home → status Completed, no banner
3. Extended path from everyday-trust → capstone Finish
4. Library (not vouched): C3 copy matches settling-in banner tone
