# Salesforce Apex Best Practices

Senior full-stack Salesforce standards. Outline the approach, confirm the plan (per CLAUDE.md §1 Confirm Before Implement), then write the code. Primary reference: [Apex Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_dev_guide.htm).

## Core requirements
- Enums over string constants (`ALL_CAPS_SNAKE_CASE`, no spaces).
- `Database.*` DML methods with exception handling. Return-early pattern. ApexDocs comments on classes.
- **Triggers:** one-trigger-per-object + handler class; use `Trigger.new/old` efficiently; guard recursion with a static boolean flag; bulkify; correct before/after split.

## Governor limits & SOQL
- **Never** SOQL/DML in loops — bulkify with collections. ≤100 SOQL, ≤150 DML per transaction.
- Selective queries with proper `WHERE`; indexed fields; `LIMIT`; no `SELECT *`.
- try-catch around DML; meaningful exception handling.
- `Database.Stateful` in batches only when needed.

## Security & access control
- Run in user mode: `[SELECT Id FROM Account WITH USER_MODE]`, `Database.insert(accts, AccessLevel.USER_MODE)`.
- Check FLS before accessing fields; respect sharing rules / OWD; `with sharing` where appropriate (FIMBY uses `without sharing` inner helpers deliberately for elevated DML — see fimby-apex SKILL).
- Sanitize inputs (`String.escapeSingleQuotes`) — prevent SOQL injection.

## Prohibited
- No hardcoded IDs or URLs (FIMBY: use `FimbySettings`/`FimbyPublicWebsiteLinks`).
- No SOQL/DML in loops. No `System.debug()` in production. No recursive triggers.
- **Never `@future`.** Use `Queueable` and implement `System.Finalizer`:
```apex
public class ExampleQueueable implements System.Finalizer, System.Queueable {
    public void execute(System.FinalizerContext fc) {
        switch on fc?.getResult() {
            when UNHANDLED_EXCEPTION { /* failure path */ }
            when else { /* success */ }
        }
    }
    public void execute(System.QueueableContext qc) { /* async logic */ }
}
```

## Design & style
- Null Object pattern + polymorphism over deeply nested conditionals.
- Don't append type to names; Maps use `keyToValue` (`idToAccount`, `accountIdToOpportunities`).
- **Repositories over Selectors** unless the codebase already uses Selectors — centralize DML/queries for testability.
- Builder for complex construction; Factory for creation; Dependency Injection for testability; Command for complex operations.
- "Newspaper" method ordering (methods appear in reference order); separate instance/static fields with blank lines.
- Don't modify unrelated code except to suggest related refactors. Don't over-comment — comments explain unidiomatic choices / platform oddities. Mark issues with `TODO:` comments.
- Mindsets: testability, simplicity (best line is the one never written), readability (no cleverness), performance (don't over-optimize at readability's cost), maintainability, reusability.

## Testing
- ≥75% coverage (FIMBY targets 80%+; see deployment rules in CLAUDE.md §6). Meaningful assertions, not just coverage.
- `Test.startTest()`/`stopTest()`; `@TestSetup` for shared data; mock callouts; test bulk; negative/edge cases.
- No `SeeAllData=true`. `System.runAs()` for user contexts. Proper isolation — no inter-test dependencies. `Test.loadData()` for large datasets.
- FIMBY test-data lookup: never query Users by email — tie to the `@TestSetup` Contact (see fimby-apex SKILL).

When instructions are unclear, ask rather than assume.
