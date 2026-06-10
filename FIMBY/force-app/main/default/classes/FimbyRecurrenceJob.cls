/**
 * @description Scheduled job that spawns the next occurrence for due recurring series.
 * Schedule daily:
 *   System.schedule('FIMBY Recurrence', '0 0 6 * * ?', new FimbyRecurrenceJob());
 */
global without sharing class FimbyRecurrenceJob implements Schedulable {

    @TestVisible
    private static Integer testMaxRows;

    global void execute(SchedulableContext ctx) {
        Integer maxRows = testMaxRows != null ? testMaxRows : 200;
        FimbyRecurrenceService.processDueSeries(maxRows);
    }
}
