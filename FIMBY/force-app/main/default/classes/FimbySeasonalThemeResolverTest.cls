/**
 * @description Covers the moveable-date rules in `FimbySeasonalThemeResolver`.
 *
 * Custom metadata records cannot be inserted in a test context, so the rule
 * branches are exercised against in-memory `FIMBY_Seasonal_Theme__mdt` instances
 * and the expected dates are the real calendar dates for those years.
 */
@IsTest
private class FimbySeasonalThemeResolverTest {

    private static FIMBY_Seasonal_Theme__mdt theme(String rule) {
        return new FIMBY_Seasonal_Theme__mdt(DeveloperName = 'Test_Theme', Date_Rule__c = rule, Duration_Days__c = 1);
    }

    @IsTest
    static void easterComputusMatchesKnownYears() {
        Map<Integer, Date> expected = new Map<Integer, Date>{
            2024 => Date.newInstance(2024, 3, 31),
            2025 => Date.newInstance(2025, 4, 20),
            2026 => Date.newInstance(2026, 4, 5),
            2027 => Date.newInstance(2027, 3, 28),
            2028 => Date.newInstance(2028, 4, 16),
            2029 => Date.newInstance(2029, 4, 1),
            2030 => Date.newInstance(2030, 4, 21)
        };
        for (Integer year : expected.keySet()) {
            System.assertEquals(
                expected.get(year),
                FimbySeasonalThemeResolver.easterSunday(year),
                'Easter Sunday wrong for ' + year
            );
        }
    }

    @IsTest
    static void easterOffsetResolvesGoodFridayAndPentecost() {
        FIMBY_Seasonal_Theme__mdt goodFriday = theme('Easter_Offset');
        goodFriday.Easter_Offset_Days__c = -2;
        System.assertEquals(
            Date.newInstance(2026, 4, 3),
            FimbySeasonalThemeResolver.resolveStartDate(goodFriday, 2026),
            'Good Friday 2026 should be Apr 3'
        );

        FIMBY_Seasonal_Theme__mdt pentecost = theme('Easter_Offset');
        pentecost.Easter_Offset_Days__c = 49;
        System.assertEquals(
            Date.newInstance(2026, 5, 24),
            FimbySeasonalThemeResolver.resolveStartDate(pentecost, 2026),
            'Pentecost 2026 should be May 24'
        );
    }

    @IsTest
    static void nthWeekdayResolvesThanksgivingAndFamilyDay() {
        // Canadian Thanksgiving — second Monday of October.
        System.assertEquals(
            Date.newInstance(2026, 10, 12),
            FimbySeasonalThemeResolver.nthWeekdayOfMonth(2026, 10, 'Monday', 2),
            'Thanksgiving 2026 should be Oct 12'
        );
        System.assertEquals(
            Date.newInstance(2027, 10, 11),
            FimbySeasonalThemeResolver.nthWeekdayOfMonth(2027, 10, 'Monday', 2),
            'Thanksgiving 2027 should be Oct 11'
        );

        // BC Family Day — third Monday of February.
        System.assertEquals(
            Date.newInstance(2026, 2, 16),
            FimbySeasonalThemeResolver.nthWeekdayOfMonth(2026, 2, 'Monday', 3),
            'Family Day 2026 should be Feb 16'
        );
        System.assertEquals(
            Date.newInstance(2027, 2, 15),
            FimbySeasonalThemeResolver.nthWeekdayOfMonth(2027, 2, 'Monday', 3),
            'Family Day 2027 should be Feb 15'
        );
    }

    @IsTest
    static void nthWeekdayHandlesLastAndOverflow() {
        System.assertEquals(
            Date.newInstance(2026, 5, 25),
            FimbySeasonalThemeResolver.nthWeekdayOfMonth(2026, 5, 'Monday', -1),
            'Last Monday of May 2026 should be May 25'
        );
        System.assertEquals(
            null,
            FimbySeasonalThemeResolver.nthWeekdayOfMonth(2026, 2, 'Monday', 5),
            'A fifth Monday that does not exist should resolve to null'
        );
        System.assertEquals(
            null,
            FimbySeasonalThemeResolver.nthWeekdayOfMonth(2026, 10, 'Noneday', 2),
            'An unknown weekday should resolve to null'
        );
    }

    @IsTest
    static void adventResolvesFourthSundayBeforeChristmas() {
        Map<Integer, Date> expected = new Map<Integer, Date>{
            2022 => Date.newInstance(2022, 11, 27), // Christmas itself falls on a Sunday
            2026 => Date.newInstance(2026, 11, 29),
            2027 => Date.newInstance(2027, 11, 28),
            2028 => Date.newInstance(2028, 12, 3)
        };
        FIMBY_Seasonal_Theme__mdt advent = theme('Weekday_Before_Anchor');
        advent.Month__c = 12;
        advent.Day__c = 25;
        advent.Weekday__c = 'Sunday';
        advent.Week_Ordinal__c = 4;

        for (Integer year : expected.keySet()) {
            System.assertEquals(
                expected.get(year),
                FimbySeasonalThemeResolver.resolveStartDate(advent, year),
                'Advent Sunday wrong for ' + year
            );
        }
    }

    @IsTest
    static void yearTableReadsMatchingRowOnly() {
        FIMBY_Seasonal_Theme__mdt lunar = theme('Year_Table');
        lunar.Year_Dates__c = '2026-02-17\n2027-02-06\n2028-01-26';

        System.assertEquals(
            Date.newInstance(2027, 2, 6),
            FimbySeasonalThemeResolver.resolveStartDate(lunar, 2027),
            'Should read the 2027 row'
        );
        System.assertEquals(
            null,
            FimbySeasonalThemeResolver.resolveStartDate(lunar, 2035),
            'A year past the end of the table should resolve to null, not throw'
        );
        System.assertEquals(
            null,
            FimbySeasonalThemeResolver.dateForYear(null, 2026),
            'A blank table should resolve to null'
        );
        System.assertEquals(
            null,
            FimbySeasonalThemeResolver.dateForYear('2026-notadate', 2026),
            'A malformed row should resolve to null, not throw'
        );
    }

    @IsTest
    static void fixedRuleKeepsLegacyBehaviourAndRejectsImpossibleDates() {
        FIMBY_Seasonal_Theme__mdt fixedRule = theme(null);
        fixedRule.Month__c = 7;
        fixedRule.Day__c = 1;
        System.assertEquals(
            Date.newInstance(2026, 7, 1),
            FimbySeasonalThemeResolver.resolveStartDate(fixedRule, 2026),
            'A blank Date Rule should behave exactly as Fixed'
        );

        FIMBY_Seasonal_Theme__mdt leapDay = theme('Fixed');
        leapDay.Month__c = 2;
        leapDay.Day__c = 29;
        System.assertEquals(
            Date.newInstance(2028, 2, 29),
            FimbySeasonalThemeResolver.resolveStartDate(leapDay, 2028),
            'Feb 29 should resolve in a leap year'
        );
        System.assertEquals(
            null,
            FimbySeasonalThemeResolver.resolveStartDate(leapDay, 2027),
            'Feb 29 should resolve to null in a non-leap year'
        );

        FIMBY_Seasonal_Theme__mdt incomplete = theme('Fixed');
        System.assertEquals(
            null,
            FimbySeasonalThemeResolver.resolveStartDate(incomplete, 2026),
            'A record with no Month/Day should resolve to null'
        );
    }

    @IsTest
    static void getActiveThemeRunsAgainstOrgMetadata() {
        Test.startTest();
        FimbySeasonalThemeResolver.ActiveTheme today = FimbySeasonalThemeResolver.getActiveTheme();
        FimbySeasonalThemeResolver.ActiveTheme christmas =
            FimbySeasonalThemeResolver.getActiveTheme(Date.newInstance(Date.today().year(), 12, 25));
        Test.stopTest();

        // Org metadata drives the outcome, so assert the contract rather than a value:
        // a returned theme must always carry a title and a resolved window.
        for (FimbySeasonalThemeResolver.ActiveTheme result : new List<FimbySeasonalThemeResolver.ActiveTheme>{ today, christmas }) {
            if (result == null) continue;
            System.assertNotEquals(null, result.name, 'An active theme must expose its DeveloperName');
            System.assertNotEquals(null, result.startDate, 'An active theme must expose a resolved start date');
            System.assert(
                result.endDate >= result.startDate,
                'An active theme window must not end before it starts'
            );
        }
    }
}
