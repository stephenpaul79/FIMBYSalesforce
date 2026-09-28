/**

 * @description Schedulable that kicks off the digest email batch.

 * - Daily at 6 AM: new FimbyDigestEmailScheduler('Daily') — runs every day including Sunday

 *   (Include_Sundays recipients only on Sun/Mon; see FimbyDigestEmailBatch).

 * - Monday 6 AM catch-up: new FimbyDigestEmailScheduler('DailySundayRestCatchUp')

 * - Weekly Saturday 6 AM: new FimbyDigestEmailScheduler('Weekly')

 * - Monthly first Tuesday 7 AM: new FimbyDigestEmailScheduler('Monthly') — Library email
 *   (Items To Borrow + Skills On Offer) via FimbyMonthlyDirectoryBatch

 *

 * Checks the global feature flag before launching.

 *

 * Schedule examples:

 *   System.schedule('FIMBY Daily Digest', '0 0 6 * * ?', new FimbyDigestEmailScheduler('Daily'));

 *   System.schedule('FIMBY Monday Sunday-Rest Digest', '0 0 6 ? * MON', new FimbyDigestEmailScheduler('DailySundayRestCatchUp'));

 *   System.schedule('FIMBY Weekly Digest', '0 0 6 ? * SAT', new FimbyDigestEmailScheduler('Weekly'));

 *   System.schedule('FIMBY Monthly Library & Skills', '0 0 7 ? * 3#1', new FimbyDigestEmailScheduler('Monthly'));

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



        if (frequency == FimbyMonthlyDirectoryBatch.CADENCE_MONTHLY) {
            Database.executeBatch(new FimbyMonthlyDirectoryBatch(), 1);
            return;
        }

        if (frequency == FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST && !isMondayNow()) {

            return;

        }



        // Scope 1: an async batch execute may enqueue only one queueable, and each
        // neighbourhood dispatches one sender chain.
        Database.executeBatch(new FimbyDigestEmailBatch(frequency), 1);

    }



    public static Boolean isSundayNow() {

        return dayOfWeekIso() == '7';

    }



    public static Boolean isMondayNow() {

        return dayOfWeekIso() == '1';

    }



    @TestVisible

    private static String dayOfWeekIso() {

        Date today = Date.today();

        Datetime dt = Datetime.newInstance(today.year(), today.month(), today.day());

        return dt.format('u');

    }

}

