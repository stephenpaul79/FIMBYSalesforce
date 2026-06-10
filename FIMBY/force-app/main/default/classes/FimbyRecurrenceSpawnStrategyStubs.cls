/**
 * @description Deferred spawn strategies against the FimbyRecurrenceSpawnStrategy seam.
 *
 * **Bulk buy** — carry forward buy template fields; reset reservations on each spawn.
 * **Cadence pantry** (Phase 2 consumer) — carry forward standing offer template;
 *   reset Total_Reserved__c / availability on each spawn.
 *
 * Neither is implemented in v1. Add thin classes implementing FimbyRecurrenceSpawnStrategy
 * and register them in FimbyRecurrenceService.getStrategies() when ready.
 */
public with sharing class FimbyRecurrenceSpawnStrategyStubs {
    private FimbyRecurrenceSpawnStrategyStubs() {}

    @TestVisible
    static String deferredLabel() {
        return 'Deferred';
    }

    @TestVisible
    static Integer deferredStrategyCount() {
        return 2;
    }
}
