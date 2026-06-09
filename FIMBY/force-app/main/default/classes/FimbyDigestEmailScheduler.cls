/**

 * @description Schedulable that kicks off the digest email batch.

 * - Daily at 6 AM: new FimbyDigestEmailScheduler('Daily') — runs every day including Sunday

 *   (Include_Sundays recipients only on Sun/Mon; see FimbyDigestEmailBatch).

 * - Monday 6 AM catch-up: new FimbyDigestEmailScheduler('DailySundayRestCatchUp')

 * - Weekly Saturday 6 AM: new FimbyDigestEmailScheduler('Weekly')

 *

 * Checks the global feature flag before launching.

 *

 * Schedule examples:

 *   System.schedule('FIMBY Daily Digest', '0 0 6 * * ?', new FimbyDigestEmailScheduler('Daily'));

 *   System.schedule('FIMBY Monday Sunday-Rest Digest', '0 0 6 ? * MON', new FimbyDigestEmailScheduler('DailySundayRestCatchUp'));

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



        if (frequency == FimbyDigestEmailBatch.CADENCE_DAILY_SUNDAY_REST && !isMondayNow()) {

            return;

        }



        Database.executeBatch(new FimbyDigestEmailBatch(frequency), 5);

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

