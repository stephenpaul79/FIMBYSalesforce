// Confirms each Year_Table anchor resolves on its listed date, using the same
// resolver path pickRuleAnchor uses. Read-only.
Map<String, List<Date>> expected = new Map<String, List<Date>>{
    'OBS_Sukkot' => new List<Date>{
        Date.newInstance(2027,10,16), Date.newInstance(2029,9,24), Date.newInstance(2035,10,18)
    },
    'OBS_Mid_Autumn_Festival' => new List<Date>{
        Date.newInstance(2027,9,15), Date.newInstance(2031,10,1), Date.newInstance(2035,9,16)
    },
    'OBS_Diwali' => new List<Date>{
        Date.newInstance(2027,10,29), Date.newInstance(2031,11,14), Date.newInstance(2035,10,30)
    }
};

for (FIMBY_Digest_Anchor__mdt r : [
    SELECT DeveloperName, Title__c, Date_Rule__c, Year_Dates__c
    FROM FIMBY_Digest_Anchor__mdt
    WHERE Date_Rule__c = 'Year_Table' AND Active__c = true
]) {
    FimbySeasonalThemeResolver.RuleSpec spec = new FimbySeasonalThemeResolver.RuleSpec();
    spec.rule = r.Date_Rule__c;
    spec.yearDates = r.Year_Dates__c;

    for (Date want : expected.get(r.DeveloperName)) {
        Date got = FimbySeasonalThemeResolver.resolveStartDate(spec, want.year());
        System.debug(
            (got == want ? 'OK   ' : 'FAIL ') + r.DeveloperName
            + ' ' + want.year() + ' expected ' + want + ' got ' + got
        );
    }
}
