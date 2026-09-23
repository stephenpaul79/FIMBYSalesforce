/**
 * @description Resolves which `FIMBY_Seasonal_Theme__mdt` record is active today.
 *
 * Holidays move. Easter is a lunisolar computation, Thanksgiving is the second
 * Monday of October, Advent starts on the fourth Sunday before Christmas. Storing
 * a literal Month/Day for those means the greeting drifts a little further off
 * every year. `Date_Rule__c` picks the branch used to resolve the start date for
 * the current year; `Fixed` (and blank, for every pre-existing record) keeps the
 * original Month/Day behaviour.
 *
 * Single source of truth for both consumers — `FimbyCacheService.getSeasonalTheme()`
 * (home feed banner + login confetti) and `FimbyEmailHtmlBuilder.getSeasonalLine()`
 * (email footer). They previously carried separate copies of the window maths and
 * could disagree.
 */
public with sharing class FimbySeasonalThemeResolver {

    /** 1900-01-07 was a Sunday. Anchors weekday maths without touching locale-sensitive APIs. */
    private static final Date SUNDAY_EPOCH = Date.newInstance(1900, 1, 7);

    private static final Map<String, Integer> WEEKDAY_INDEX = new Map<String, Integer>{
        'Sunday' => 0, 'Monday' => 1, 'Tuesday' => 2, 'Wednesday' => 3,
        'Thursday' => 4, 'Friday' => 5, 'Saturday' => 6
    };

    public class ActiveTheme {
        public String name;
        public String title;
        public String emojiList;
        public Boolean fireOnLogin;
        public String animationStyle;
        public Date startDate;
        public Date endDate;
    }

    /**
     * @description Highest-priority active theme covering today, or null.
     */
    public static ActiveTheme getActiveTheme() {
        return getActiveTheme(Date.today());
    }

    /**
     * @description Resolution against an explicit date, so the rule branches are
     * testable without CMDT inserts (which Apex does not allow).
     */
    @TestVisible
    private static ActiveTheme getActiveTheme(Date today) {
        for (FIMBY_Seasonal_Theme__mdt theme : [
            SELECT DeveloperName, Month__c, Day__c, Duration_Days__c,
                   Emoji_List__c, Title__c, Fire_On_Login__c, Animation_Style__c,
                   Date_Rule__c, Easter_Offset_Days__c, Weekday__c,
                   Week_Ordinal__c, Year_Dates__c, Priority__c
            FROM FIMBY_Seasonal_Theme__mdt
            WHERE Active__c = true
            ORDER BY Priority__c DESC NULLS LAST, DeveloperName ASC
        ]) {
            // A window opened late in December can still be running in January, so
            // last year's start is checked too.
            if (covers(theme, today, today.year()) || covers(theme, today, today.year() - 1)) {
                return toActiveTheme(theme, today);
            }
        }
        return null;
    }

    private static Boolean covers(FIMBY_Seasonal_Theme__mdt theme, Date today, Integer year) {
        Date startDate = resolveStartDate(theme, year);
        if (startDate == null) return false;
        return today >= startDate && today <= startDate.addDays(durationOf(theme) - 1);
    }

    private static ActiveTheme toActiveTheme(FIMBY_Seasonal_Theme__mdt theme, Date today) {
        Date startDate = resolveStartDate(theme, today.year());
        if (startDate == null || today < startDate) {
            startDate = resolveStartDate(theme, today.year() - 1);
        }
        ActiveTheme result = new ActiveTheme();
        result.name = theme.DeveloperName;
        result.title = theme.Title__c;
        result.emojiList = theme.Emoji_List__c;
        result.fireOnLogin = theme.Fire_On_Login__c;
        result.animationStyle = theme.Animation_Style__c;
        result.startDate = startDate;
        result.endDate = startDate == null ? null : startDate.addDays(durationOf(theme) - 1);
        return result;
    }

    private static Integer durationOf(FIMBY_Seasonal_Theme__mdt theme) {
        Integer duration = theme.Duration_Days__c == null ? 1 : Integer.valueOf(theme.Duration_Days__c);
        return duration < 1 ? 1 : duration;
    }

    /**
     * @description Start date for the given year, or null when the record is
     * misconfigured or a Year Table has no row for that year. A null skips the
     * theme rather than throwing — a wrong greeting is bad, a broken home feed
     * is worse.
     */
    @TestVisible
    private static Date resolveStartDate(FIMBY_Seasonal_Theme__mdt theme, Integer year) {
        String rule = String.isBlank(theme.Date_Rule__c) ? 'Fixed' : theme.Date_Rule__c;

        if (rule == 'Easter_Offset') {
            Integer offset = theme.Easter_Offset_Days__c == null ? 0 : Integer.valueOf(theme.Easter_Offset_Days__c);
            return easterSunday(year).addDays(offset);
        }
        if (rule == 'Nth_Weekday') {
            return nthWeekdayOfMonth(year, intOf(theme.Month__c), theme.Weekday__c, intOf(theme.Week_Ordinal__c));
        }
        if (rule == 'Weekday_Before_Anchor') {
            Date anchor = fixedDate(year, intOf(theme.Month__c), intOf(theme.Day__c));
            return anchor == null
                ? null
                : nthWeekdayBefore(anchor, theme.Weekday__c, intOf(theme.Week_Ordinal__c));
        }
        if (rule == 'Year_Table') {
            return dateForYear(theme.Year_Dates__c, year);
        }
        return fixedDate(year, intOf(theme.Month__c), intOf(theme.Day__c));
    }

    private static Integer intOf(Decimal value) {
        return value == null ? null : Integer.valueOf(value);
    }

    private static Date fixedDate(Integer year, Integer month, Integer day) {
        if (month == null || day == null || month < 1 || month > 12 || day < 1 || day > 31) return null;
        if (day > Date.daysInMonth(year, month)) return null;
        return Date.newInstance(year, month, day);
    }

    /**
     * @description Easter Sunday by the Anonymous Gregorian computus.
     * 2026-04-05, 2027-03-28, 2028-04-16.
     */
    @TestVisible
    private static Date easterSunday(Integer year) {
        Integer a = Math.mod(year, 19);
        Integer b = year / 100;
        Integer c = Math.mod(year, 100);
        Integer d = b / 4;
        Integer e = Math.mod(b, 4);
        Integer f = (b + 8) / 25;
        Integer g = (b - f + 1) / 3;
        Integer h = Math.mod(19 * a + b - d - g + 15, 30);
        Integer i = c / 4;
        Integer k = Math.mod(c, 4);
        Integer l = Math.mod(32 + 2 * e + 2 * i - h - k, 7);
        Integer m = (a + 11 * h + 22 * l) / 451;
        Integer month = (h + l - 7 * m + 114) / 31;
        Integer day = Math.mod(h + l - 7 * m + 114, 31) + 1;
        return Date.newInstance(year, month, day);
    }

    /** 0 = Sunday … 6 = Saturday. */
    private static Integer dayOfWeek(Date value) {
        return Math.mod(SUNDAY_EPOCH.daysBetween(value), 7);
    }

    /**
     * @description Nth occurrence of a weekday within a month. Ordinal -1 takes the
     * last occurrence; a 5th that spills into the next month returns null.
     */
    @TestVisible
    private static Date nthWeekdayOfMonth(Integer year, Integer month, String weekday, Integer ordinal) {
        Integer targetDow = WEEKDAY_INDEX.get(weekday);
        if (targetDow == null || month == null || month < 1 || month > 12 || ordinal == null || ordinal == 0) {
            return null;
        }
        Date firstOfMonth = Date.newInstance(year, month, 1);
        Date firstMatch = firstOfMonth.addDays(Math.mod(targetDow - dayOfWeek(firstOfMonth) + 7, 7));

        if (ordinal > 0) {
            Date result = firstMatch.addDays((ordinal - 1) * 7);
            return result.month() == month ? result : null;
        }
        Date last = firstMatch;
        while (last.addDays(7).month() == month) {
            last = last.addDays(7);
        }
        return last;
    }

    /**
     * @description Nth occurrence of a weekday strictly before an anchor date.
     * Advent Sunday = 4th Sunday before Dec 25, including the year Christmas
     * itself lands on a Sunday.
     */
    @TestVisible
    private static Date nthWeekdayBefore(Date anchor, String weekday, Integer ordinal) {
        Integer targetDow = WEEKDAY_INDEX.get(weekday);
        if (targetDow == null || ordinal == null || ordinal < 1) return null;

        Date dayBefore = anchor.addDays(-1);
        Date firstMatch = dayBefore.addDays(-Math.mod(dayOfWeek(dayBefore) - targetDow + 7, 7));
        return firstMatch.addDays(-7 * (ordinal - 1));
    }

    /**
     * @description Picks the `YYYY-MM-DD` entry for the given year out of
     * `Year_Dates__c`. Accepts newline or comma separation.
     */
    @TestVisible
    private static Date dateForYear(String yearDates, Integer year) {
        if (String.isBlank(yearDates)) return null;
        String prefix = String.valueOf(year) + '-';

        for (String entry : yearDates.split('[\\r\\n,]')) {
            String trimmed = entry.trim();
            if (!trimmed.startsWith(prefix)) continue;
            try {
                List<String> parts = trimmed.split('-');
                return Date.newInstance(
                    Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), Integer.valueOf(parts[2])
                );
            } catch (Exception e) {
                return null; // Malformed row — skip the theme rather than break the page.
            }
        }
        return null;
    }
}
