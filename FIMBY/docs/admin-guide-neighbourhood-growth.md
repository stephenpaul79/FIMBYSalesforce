# Neighbourhood Growth & Health — Admin Guide

This guide covers the day-to-day administration of FIMBY's neighbourhood growth features: postal code routing, adjacency management, health monitoring, and cell division.

---

## 1. Postal Code Management

### What it does

The `Postal_Codes__c` object maps each postal code to a Boundary Account (the neighbourhood cell). When a new contact signs up with a postal code, the `Place_Contact_Into_Boundary_Neighbourhood_Accounts` flow automatically places them in the correct neighbourhood.

### How to add a new postal code

1. Go to the **Postal Codes** tab
2. Click **New**
3. Set the **Name** to the postal code (e.g. `V6A 1A1`)
4. Set **Boundary Account** to the target neighbourhood
5. Save — the `Postal_Code_No_Spaces__c` formula auto-generates

### How to verify routing

After creating the record, test by creating a Contact with that postal code. The Contact's Account should automatically populate with the Boundary Account.

### After a split

The split service reassigns postal codes automatically. Verify the mappings by checking the Postal Codes related list on both the source and new neighbourhood accounts.

---

## 2. Managing Neighbourhood Adjacencies

### What it does

`Neighbourhood_Adjacency__c` records define which neighbourhoods border each other. Each adjacency is stored as a **reciprocal pair** (one record from each side), linked by a `Mirror_Record__c` lookup. Posts with Adjacent scope and shared-contact posts cross these borders.

### When they're auto-created

The split service creates reciprocal `Split_Sibling` pairs between the two new cells automatically during a split.

### How to add a manual adjacency

1. Navigate to **Neighbourhood Adjacency** tab (or the related list on a Boundary Account)
2. Click **New**
3. Set **Core Neighbourhood** = one account
4. Set **Adjacent Neighbour** = the other account
5. Set **Adjacency Type** = `Geographic Neighbour`
6. Check **Active**
7. Save

You only need to create one record. The after-insert flow automatically creates the mirror record, links both via `Mirror_Record__c`, and updates the denormalized fields on both Accounts.

### How to deactivate an adjacency

Uncheck `Active__c` on either record. The after-update flow automatically deactivates the mirror. The `Adjacent_Neighbourhood_Ids__c` and `Adjacent_Neighbourhood_Links__c` fields update on both affected Accounts. Those neighbourhoods will no longer see each other's adjacent-scope posts.

### Verification

- Check `Adjacent_Neighbourhood_Links__c` on the Account record for clickable links to adjacent cells
- Check the **Neighbourhood Adjacency** related list on the Boundary Account layout
- If something looks wrong, run **Rebuild Adjacent Neighbourhood IDs** (the `FimbyAdjacentIdRepairBatch` invocable action) to recalculate all denormalized fields from the source-of-truth adjacency records

---

## 3. Reading the Health Dashboard

### Where to find it

**Reports** tab → **FIMBY Neighbourhood Health** folder, or the **Neighbourhood Health Dashboard** in the **FIMBY Dashboards** folder.

### Four lenses to watch

| Lens | Key Metrics | What to look for |
|------|-------------|------------------|
| **Density** | Household count, active members, posts per week | Is the neighbourhood large and active enough? Approaching the soft cap (~150 households)? |
| **Reciprocity** | Response rate, give/take balance, repeat interactions | Are people helping each other, or are asks going unanswered? |
| **Recognition** | Recognition score, shared contact density, contact share rate | Do people know each other? Are real relationships forming? |
| **Dependency** | Adjacent response %, adjacent interaction % | Is this neighbourhood healthy on its own, or propped up by its neighbours? |

### Key signals

- **Split Review Flag** (checkbox on Account): Auto-set when thresholds are crossed. This is an invitation to investigate, not an automatic trigger.
- **Declining recognition score**: People don't know each other. The neighbourhood may feel anonymous even if it's active.
- **Rising adjacent dependency**: The neighbourhood is relying on adjacent cells for responses and engagement.
- **High lurker ratio**: The neighbourhood may feel empty even if it has many members.

### Dependency Escalation Framework

| Duration | Action |
|----------|--------|
| 1–2 weeks elevated | **Monitor** — normal fluctuation, especially post-split |
| 3–5 weeks elevated | **Review** — consider seeding activity, community outreach |
| 6+ weeks elevated | **Intervene** — boundary adjustment, active recruitment, or pause further expansion |

### Post-split dependency (first 4 weeks)

Elevated dependency is normal for newly split cells. Watch for a declining trend. If dependency is NOT declining after 4 weeks, escalate to review.

### How to compare over time

Each weekly snapshot is a `Neighbourhood_Health_Snapshot__c` record. Use report date filters to see trends. Look at 4–8 week trends, not single-week blips.

### Regional rollups

Filter reports by Region Account (parent of Boundary Accounts) to see aggregate health across a geographic cluster.

---

## 4. When and How to Split a Neighbourhood

### When to consider a split

The `Split_Review_Flag__c` appears on the account, OR you notice qualitative signs:

- People saying "I don't recognize anyone"
- Posts getting no responses despite active membership
- The area has grown physically large

### Pre-split checklist — Quantitative

1. Household count exceeds soft cap (~150) OR recognition score is declining
2. Postal codes can be cleanly divided along a natural boundary
3. Both resulting cells meet minimum viable child cell thresholds:
   - At least 30 households per cell
   - At least 15 active members per cell
   - At least 8 responders per cell
   - At least 5 posts per week per cell
   - Internal tie ratio above 40%

### Pre-split checklist — Qualitative

These questions give you the story that numbers can't:

1. **Natural geographic boundary exists** — a major street, park, rail line, or landmark that people would agree makes sense as a dividing line
2. **New names feel like real places** — ask: "Would a neighbour say 'I live in [proposed name]'?"
3. **Each proposed child cell has at least one community anchor** — a local host, a gathering rhythm, visible trusted people
4. **There are offline connection points in each cell** — a community garden, café, school, or regular meetup spot

### Dry-run option

You can preview the split without executing it:

1. Navigate to the source Boundary Account
2. Launch the **Split Neighbourhood** action
3. Walk through the setup screens (name, postal codes, adjacencies)
4. Review the **viability preview** — projected metrics for BOTH child cells with pass/warn/fail indicators
5. Save as **Draft** — this creates a `Neighbourhood_Split__c` tracking record you can review and discuss with community leaders before committing

### How to execute

1. Navigate to the source Boundary Account record
2. Click the **Split Neighbourhood** action button
3. The guided screen flow walks you through:
   - Naming the new cell and selecting its Region
   - Selecting which postal codes move to the new cell
   - Confirming adjacencies
   - Reviewing the viability preview
   - Documenting your qualitative assessment in the Admin Notes field
   - Confirming the split
4. After confirmation, the flow creates the new account, adjacencies, and postal code reassignments, then calls invocable Apex for:
   - Contact moves (re-parenting to new Account)
   - Content restamping (Needs/Offers, Stories, Library Items, Shared Contact Info)
   - Summary count recalculation on both accounts
   - Optional welcome notification to moved contacts

### If something fails

The `Neighbourhood_Split__c` tracking record shows which step completed last (`Current_Step__c`). You can re-run from the failed step without repeating earlier work — set `resumeFromStep` to the failed step number. All restamping operations are safe to re-run (idempotent).

Check the `Error_Detail__c` field on the split record for details.

### Post-split verification checklist

1. Check the `Neighbourhood_Split__c` record: Status should be `Completed`, `Contacts_Moved__c` and `Records_Restamped__c` should have counts
2. On the **new** Account: verify `Active_Users_In_Boundary__c` and `All_Contacts_In_Boundary__c` are populated
3. On **both** Accounts: verify `Adjacent_Neighbourhood_Ids__c` includes the other cell
4. Spot-check a few contacts to confirm they're in the right neighbourhood
5. Log in as a community user from each cell and verify the feed shows the right content
6. Check that `Shared_Contact_Info__c` records for cross-cell shared contacts have their `Contact_Neighbourhood__c` / `Shared_To_Neighbourhood__c` updated
7. Monitor the health dashboard for the next 4 weeks — some elevated dependency on the sibling cell is normal

---

## 5. How Post Visibility Works Across Boundaries

### Visibility tiers

| Tier | Scope | Who sees it | Default for |
|------|-------|-------------|-------------|
| **1** | Neighbourhood | Only your neighbourhood | Stories, standard asks |
| **2** | Adjacent | Your neighbourhood + all adjacent neighbourhoods | Offers, library items, bulk buys, urgent asks |
| **3** | Shared Contact Override | Anyone in an adjacent neighbourhood with a shared-contact relationship to the poster | Applies on top of Tier 1 |

### Shared contacts across boundaries

If two people have exchanged contact info and are in adjacent neighbourhoods, they see each other's Neighbourhood-scoped posts (Tier 3 override). This preserves relationships after a split.

If they are NOT adjacent (e.g., one moved, or a later split made them non-adjacent), the feed override stops — but the relationship persists. They can still message each other, and the shared contact record stays active. **The relationship is sacred; the feed override is geographic.**

### @mentions

Same neighbourhood OR shared contacts in adjacent neighbourhoods. If you can see their posts, you can tag them.

### Messaging

Not affected by neighbourhood boundaries. If you've shared contacts, you can message each other regardless of which neighbourhood either person lives in.

---

## 6. Utility Tools

### Rebuild Adjacent Neighbourhood IDs

**What**: Recalculates `Adjacent_Neighbourhood_Ids__c` and `Adjacent_Neighbourhood_Links__c` on all Boundary Accounts from the source-of-truth `Neighbourhood_Adjacency__c` records.

**When to use**: If adjacency links look wrong or out of sync. Safe to run at any time.

**How**: Execute from Developer Console:
```
Database.executeBatch(new FimbyAdjacentIdRepairBatch(), 50);
```

### Backfill SCI Neighbourhood Fields

**What**: Populates `Contact_Neighbourhood__c` and `Shared_To_Neighbourhood__c` on existing `Shared_Contact_Info__c` records that are missing these values.

**When to use**: After deploying the neighbourhood fields for the first time, or if you suspect records are missing neighbourhood stamps.

**How**: Execute from Developer Console:
```
Database.executeBatch(new FimbySCINeighbourhoodBackfillBatch(), 200);
```

### Schedule the Health Batch

**What**: Runs the `FimbyNeighbourhoodHealthBatch` weekly to create health snapshots for all active Boundary Accounts.

**How**: Schedule from Developer Console:
```
System.schedule('FIMBY Health Snapshot - Weekly', '0 0 3 ? * SUN', new FimbyNeighbourhoodHealthBatch());
```

This runs every Sunday at 3 AM. Adjust the cron expression as needed.

---

## 7. Configuration — Custom Metadata Thresholds

All neighbourhood health thresholds are configurable via `FIMBY_App_Settings__mdt` (the existing FIMBY settings record). No code changes needed to adjust these values.

| Setting | Default | What it controls |
|---------|---------|-----------------|
| Neighbourhood_Soft_Cap__c | 150 | Household count that triggers split review consideration |
| Neighbourhood_Ideal_Min__c | 60 | Lower bound of the healthy range |
| Neighbourhood_Ideal_Max__c | 120 | Upper bound of the healthy range |
| Recognition_Score_Threshold__c | 0.30 | Below this, recognition is considered low |
| Lurker_Ratio_Threshold__c | 0.50 | Above this, lurking is considered high |
| Split_Review_Household_Trigger__c | 150 | Household count that auto-sets the split review flag |
| Min_Households_Per_Cell__c | 30 | Minimum viable households after a split |
| Min_Active_Members_Per_Cell__c | 15 | Minimum viable active members after a split |
| Min_Responders_Per_Cell__c | 8 | Minimum viable responders after a split |
| Min_Posts_Per_Week_Per_Cell__c | 5 | Minimum viable weekly post rate after a split |
| Min_Internal_Tie_Ratio__c | 0.40 | Minimum internal connections vs. cross-cell connections |
| Max_Dependency_Ratio__c | 0.35 | Maximum acceptable adjacent dependency |
| Dependency_Monitor_Weeks__c | 2 | Weeks before escalating from watch to monitor |
| Dependency_Review_Weeks__c | 5 | Weeks before escalating from monitor to review |
| Dependency_Intervene_Weeks__c | 8 | Weeks before escalating from review to intervene |
