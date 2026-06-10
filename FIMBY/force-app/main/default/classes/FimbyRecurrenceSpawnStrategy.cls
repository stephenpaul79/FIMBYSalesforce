/**
 * @description Per-post-type spawn strategy seam for FimbyRecurrenceService.
 * Event strategy is implemented in FimbyEventRecurrenceSpawnStrategy.
 * Bulk buy and cadence pantry are deferred thin additions — see FimbyRecurrenceSpawnStrategyStubs.
 */
public interface FimbyRecurrenceSpawnStrategy {
    Boolean supports(Needs_Offers__c parent);
    Needs_Offers__c buildOccurrence(
        Needs_Offers__c parent,
        Needs_Offers__c priorOccurrence,
        Date occurrenceStartDate,
        Date occurrenceEndDate
    );
}
