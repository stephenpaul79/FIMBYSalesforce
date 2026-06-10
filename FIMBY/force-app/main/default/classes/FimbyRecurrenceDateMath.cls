/**
 * @description Date math for the recurrence engine — interval stepping with month-end edge cases.
 */
public with sharing class FimbyRecurrenceDateMath {

    /**
     * @description Advance a date by frequency × interval.
     */
    public static Date advanceDate(Date baseDate, String frequency, Decimal interval) {
        if (baseDate == null || String.isBlank(frequency)) {
            return null;
        }
        Integer step = interval != null ? interval.intValue() : 1;
        if (step < 1) {
            step = 1;
        }

        if (frequency == 'Day') {
            return baseDate.addDays(step);
        }
        if (frequency == 'Week') {
            return baseDate.addDays(step * 7);
        }
        if (frequency == 'Month') {
            return addMonthsPreserveDay(baseDate, step);
        }
        if (frequency == 'Year') {
            return addMonthsPreserveDay(baseDate, step * 12);
        }
        return baseDate.addDays(step);
    }

    /**
     * @description Handles Jan 31 + 1 month → Feb 28/29 (last day of target month when needed).
     */
    public static Date addMonthsPreserveDay(Date baseDate, Integer monthsToAdd) {
        if (baseDate == null || monthsToAdd == null) {
            return baseDate;
        }
        Integer year = baseDate.year();
        Integer month = baseDate.month();
        Integer day = baseDate.day();

        Integer totalMonths = (month - 1) + monthsToAdd;
        Integer targetYear = year + (totalMonths / 12);
        Integer targetMonth = Math.mod(totalMonths, 12) + 1;
        Integer lastDay = Date.daysInMonth(targetYear, targetMonth);
        Integer targetDay = Math.min(day, lastDay);

        return Date.newInstance(targetYear, targetMonth, targetDay);
    }

    /**
     * @description Duration in days between occurrence start and end (inclusive span for time fields).
     */
    public static Integer daysBetweenInclusive(Date startDate, Date endDate) {
        if (startDate == null || endDate == null) {
            return 0;
        }
        return startDate.daysBetween(endDate);
    }
}
