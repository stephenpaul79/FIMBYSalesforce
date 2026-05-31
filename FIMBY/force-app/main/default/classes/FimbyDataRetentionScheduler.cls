/**
 * @description Schedulable wrapper that kicks off the data retention batch chain.
 * Ships dormant — admin enables via Setup > Apex Jobs or anonymous Apex.
 *
 * Schedule weekly on Sundays at 2 AM:
 *   System.schedule('FIMBY Data Retention', '0 0 2 ? * SUN', new FimbyDataRetentionScheduler());
 *
 * Dry run (no deletes, logs only):
 *   Database.executeBatch(new FimbyDataRetentionBatch('A', true), 50);
 *
 * Unschedule:
 *   for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = 'FIMBY Data Retention'])
 *       System.abortJob(ct.Id);
 */
public without sharing class FimbyDataRetentionScheduler implements Schedulable {

    public void execute(SchedulableContext sc) {
        Database.executeBatch(
            new FimbyDataRetentionBatch('A'),
            FimbySettings.dataRetentionBatchSize()
        );
    }
}
