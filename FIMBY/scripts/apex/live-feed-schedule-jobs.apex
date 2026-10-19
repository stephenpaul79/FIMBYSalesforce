// Live Feed Lifecycle: schedule the replacement jobs.
// Run as an America/Vancouver admin only AFTER the FlowDefinitions are inactive and
// live-feed-cutover-reconcile.apex has been applied.
//
//   sf apex run --file scripts/apex/live-feed-schedule-jobs.apex

Set<String> names = new Set<String>{ 'FIMBY Post End of Life', 'FIMBY Reply Nudges' };
for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name IN :names]) {
    System.abortJob(ct.Id);
}

System.schedule('FIMBY Post End of Life', '0 15 0 * * ?', new FimbyPostEndOfLifeJob());
System.schedule('FIMBY Reply Nudges', '0 15 9 * * ?', new FimbyReplyNudgeJob());

for (CronTrigger ct : [
    SELECT CronJobDetail.Name, CronExpression, State, NextFireTime, TimeZoneSidKey
    FROM CronTrigger WHERE CronJobDetail.Name IN :names
]) {
    System.debug(ct.CronJobDetail.Name + ' | ' + ct.CronExpression + ' | ' + ct.State
        + ' | next ' + ct.NextFireTime.format('yyyy-MM-dd HH:mm', 'America/Vancouver') + ' PT | tz ' + ct.TimeZoneSidKey);
}
