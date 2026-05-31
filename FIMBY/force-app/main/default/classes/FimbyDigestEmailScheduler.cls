/**
 * @description Schedulable that kicks off the digest email batch. Two instances run:
 * - Daily at 6 AM: new FimbyDigestEmailScheduler('Daily')
 * - Weekly Saturday 6 AM: new FimbyDigestEmailScheduler('Weekly')
 *
 * Checks the global feature flag and Sunday rest before launching.
 *
 * Schedule examples:
 *   System.schedule('FIMBY Daily Digest', '0 0 6 * * ?', new FimbyDigestEmailScheduler('Daily'));
 *   System.schedule('FIMBY Weekly Digest', '0 0 6 ? * SAT', new FimbyDigestEmailScheduler('Weekly'));
 */
global without sharing class FimbyDigestEmailScheduler implements Schedulable {

    private String frequency;

    global FimbyDigestEmailScheduler(String frequency) {
        this.frequency = frequency;
    }

    global void execute(SchedulableContext ctx) {
        if (!FimbySettings.digestEmailGlobalEnabled()) {
            return;
        }

        if (isSundayNow()) {
            return;
        }

        Database.executeBatch(new FimbyDigestEmailBatch(frequency), 5);
    }

    @TestVisible
    static Boolean isSundayNow() {
        Date today = Date.today();
        Datetime dt = Datetime.newInstance(today.year(), today.month(), today.day());
        String dayOfWeek = dt.format('u');
        return dayOfWeek == '7';
    }
}
