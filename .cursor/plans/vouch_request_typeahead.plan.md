# Vouch Request — Typeahead Picker (replace free text)

## Goal

Replace the free-text "Their full name / Their email / Or a community group" form in `fimbyVouchingRequiredModal` with a single typeahead that searches eligible **vouchers** in the requester's neighbourhood. A radio toggle switches the data source between **Neighbour** and **Community group**.

Why: today's free-text path does an exact `Email`/`Account.Name` match, silently returning a generic "could not deliver" for any miss. The data is already visible to the user under the sharing model — we just surface it. Off-platform invitations are intentionally out of scope (a stranger has no reputation to vouch with).

## Eligibility constraints (server-enforced)

These must drive **both** the typeahead search and a re-validation on submit.

### Peer (neighbour) path — must show only contacts that are:
- In the requester's neighbourhood (`AccountId = neighbourhoodId`)
- `Vouched_Status__c = 'Vouched'` (settling-in users cannot vouch)
- `Vouching_Disabled__c != true` (paused vouchers excluded)
- `Is_Organization_Contact__c != true` (org contacts only available on CG path)
- Not the requester themselves
- Not blocked by the requester (`Blocked_Contact__c` where `Blocker__c = requester`)
- Not blocking the requester (`Blocked_Contact__c` where `Blocked__c = requester`) — bidirectional

### Community group path — must show only orgs that are:
- Linked to the requester's neighbourhood via `Community_Group_Neighbourhood__c` (`Status__c = 'Active'`)
- `Active__c = 'Yes'`
- `Is_Approved_Community_Group__c = true`
- Have an Approved `Community_Group_Rep` `Support_Relationship__c` (no rep ⇒ nowhere to route)
- The rep contact themselves passes the peer-side block + `Vouching_Disabled__c` checks

### Search behaviour
- Search-as-you-type with 250ms debounce
- Minimum 2 characters before querying
- Cap to 10 results per query
- `WHERE Name LIKE '%term%'` (allow mid-string matches; users may search by last name)
- Order by Name ASC for deterministic results

## Apex changes (`FimbyVouchController`)

### New method: `searchVouchers`
```apex
@AuraEnabled(cacheable=true)
public static List<VoucherOption> searchVouchers(String searchTerm, String voucherType)
```
- `voucherType` ∈ `{'peer', 'community_group'}`
- Returns `List<VoucherOption>` with: `id`, `name`, `subtitle` (e.g. "Community group" or rep first name preview)
- Server-side filters per the eligibility lists above
- Marked `cacheable=true` so wire is reactive
- Pulls `requesterContactId` + `neighbourhoodId` from `FimbyIdentityRepository` — never accept these from the client

### New method: `submitVoucherRequest`
```apex
@AuraEnabled
public static SubmitResult submitVoucherRequest(String voucherType, Id referenceId)
```
- `referenceId` is the Account.Id (for community_group) or Contact.Id (for peer)
- Re-runs the full eligibility check before inserting `Vouch_Record__c` (never trust the client)
- Same `one active request at a time` guard as today via `hasPendingRequest`
- Reuses `requestVouchInternal` helper for the actual insert + conversation
- Returns `SubmitResult` (delivered / vouchRecordId / message)

### Deprecation
- `submitVoucherDetails(fullName, email, organizationName)` → keep as a thin shim that returns "This flow has been replaced." for ~1 release in case any client is still on the old payload. Mark `@deprecated` in ApexDoc. Remove its helpers (`findOrgAccountByName`, `findPeerByEmail`) once the shim is removed.

### Wire type
```apex
public class VoucherOption {
    @AuraEnabled public Id id;
    @AuraEnabled public String voucherType; // 'peer' | 'community_group'
    @AuraEnabled public String name;
    @AuraEnabled public String subtitle;
}
```

### Side-finding (do **not** fix in this plan, but flag)
The current `findOrgAccountByName` does not filter by neighbourhood — an org name that exists in any other neighbourhood would match. The new flow makes this moot, but the legacy method is still callable until the shim is removed. Track as separate cleanup if the shim sticks around.

## LWC changes (`fimbyVouchingRequiredModal`)

### Template (form state)
Replace the three `<input>` rows with:
1. **Radio segmented toggle** (`role="radiogroup"`): "Neighbour" / "Community group"
2. **Search input** with magnifying icon — placeholder swaps with toggle
3. **Results dropdown** (only when `searchResults.length`) — mirrors `fimbyRelationshipSetupModal` pattern
4. **Selected pill** (when a result is chosen): name + small `×` to clear
5. **Empty state** (≥2 chars typed, 0 results): muted text "No matches in your neighbourhood." (same wording for both paths — no enumeration leak)
6. **Helper text** under input: "We'll let them know you're asking for an introduction. They will only see your name."

### State
```js
@track voucherType = 'peer';
@track searchTerm = '';
@track searchResults = [];
@track selectedVoucher = null; // { id, name, subtitle, voucherType }
@track isSearching = false;
```

### Behaviour
- Toggle change ⇒ clear `searchTerm`, `searchResults`, `selectedVoucher`
- Search debounce 250ms; min 2 chars; uses imperative Apex (`searchVouchers`) rather than wire, so we can cancel in-flight on rapid input
- Selecting a result populates `selectedVoucher`, hides the dropdown
- `Send introduction` enabled only when `selectedVoucher` is set
- Submit calls `submitVoucherRequest({ voucherType, referenceId: selectedVoucher.id })`
- Error from Apex: render `errorMessage`, do not clear selection
- Success: existing close-after-1500ms behaviour preserved

### CSS
- Reuse the dropdown / search-results / selected-pill patterns already established in `fimbyRelationshipSetupModal.css` — same colours and spacing for consistency
- Add a segmented toggle style (rounded teal pill with active/inactive states) using existing `--fimby-*` tokens

## Tests

### `FimbyVouchControllerTest` — add cases
- `searchVouchers` peer path:
  - Excludes self
  - Excludes settling-in / vouch_requested / new contacts
  - Excludes `Vouching_Disabled__c = true`
  - Excludes contacts blocked by requester
  - Excludes contacts blocking requester (reverse direction)
  - Excludes contacts in different neighbourhood
  - Excludes `Is_Organization_Contact__c = true`
  - Returns ≤10 results
  - Min 2 char enforced (returns empty for 0/1 char input)
- `searchVouchers` community_group path:
  - Excludes orgs not in neighbourhood
  - Excludes orgs not approved / not active
  - Excludes orgs without an Approved CG-Rep Support_Relationship
- `submitVoucherRequest`:
  - Happy path peer ⇒ creates Vouch_Record, conversation, notification
  - Happy path community_group ⇒ resolves rep contact, creates same artefacts
  - Rejects ineligible reference (e.g. self-vouch attempt)
  - Rejects when requester already has pending request
- Existing `submitVoucherDetails` test ⇒ now asserts the shim returns the deprecation message

### Smoke (manual QA, desktop + mobile via Playwright)
- New user (Vouched_Status = New) opens library, taps "Request a vouch"
- Modal renders explainer → "Request a vouch"
- Form shows toggle + empty search
- Typing 2+ chars returns vouched neighbours only (Desktop Tester should appear when logged in as Mobile Tester pre-vouch)
- Switching toggle to "Community group" clears and searches orgs in neighbourhood
- Selecting a result, clearing it with ×, re-selecting works
- Submit creates Vouch_Record, the selected voucher receives a notification

## Out of scope (intentionally not in this PR)

- "Invite a friend who isn't on FIMBY" — strangers are not eligible references
- A "recently declined by this person" exclusion — future enhancement
- Searching by partial email — names are sufficient and emails are PII we should not surface

## Deployment & manual setup

- No new metadata objects, fields, profiles, or pages
- Net new code is Apex methods + LWC changes only — no profile updates required
- No Experience Builder changes
