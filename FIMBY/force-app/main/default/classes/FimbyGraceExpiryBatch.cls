/**
 * @description Scheduled batch that converts expired in-app delete-with-grace
 * requests into actual deletions. For each Contact whose Grace_Started_At__c
 * is older than its Grace_Window_Days__c (default 30 via
 * FIMBY_App_Settings__mdt.Default_Grace_Window_Days__c), flips
 * Deactivation_Requested__c=true so the nightly FimbyAccountDeactivationBatch
 * picks them up tonight and runs the existing scrub.
 *
 * Runs once daily, before FimbyAccountDeactivationBatch, so any account
 * expiring today is scrubbed the same night.
 *
 * Schedule via:
 *   System.schedule('FIMBY Grace Expiry', '0 30 0 * * ?', new FimbyGraceExpiryBatch());
 */
global without sharing class FimbyGraceExpiryBatch
    implements Database.Batchable<SObject>, Schedulable {

    global void execute(SchedulableContext sc) {
        Database.executeBatch(this, 200);
    }

    /**
     * @description Returns Contacts whose grace window has elapsed and that
     * have not yet been flagged for the scrub. Uses the org default grace
     * window as the SOQL cutoff because per-contact overrides are uncommon;
     * execute() re-checks each row against its own Grace_Window_Days__c so
     * overrides still win.
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        DateTime cutoff = System.now()
            .addDays(-FimbySettings.defaultGraceWindowDays());
        return Database.getQueryLocator([
            SELECT Id, Grace_Started_At__c, Grace_Window_Days__c
            FROM Contact
            WHERE Grace_Started_At__c != NULL
              AND Grace_Started_At__c <= :cutoff
              AND Deactivation_Requested__c = false
        ]);
    }

    /**
     * @description For each Contact in the batch, re-verify against its own
     * Grace_Window_Days__c override (the start() cutoff used the default), and
     * flip Deactivation_Requested__c=true on the ones whose individual window
     * has truly elapsed.
     */
    global void execute(Database.BatchableContext bc, List<Contact> contacts) {
        DateTime now = System.now();
        Integer orgDefault = FimbySettings.defaultGraceWindowDays();

        List<Contact> toFlag = new List<Contact>();
        for (Contact c : contacts) {
            if (c.Grace_Started_At__c == null) continue;
            Integer windowDays = (c.Grace_Window_Days__c != null)
                ? c.Grace_Window_Days__c.intValue()
                : orgDefault;
            DateTime expiresAt = c.Grace_Started_At__c.addDays(windowDays);
            if (expiresAt <= now) {
                toFlag.add(new Contact(
                    Id = c.Id,
                    Deactivation_Requested__c = true
                ));
            }
        }

        if (!toFlag.isEmpty()) {
            Database.update(toFlag, false);
            FimbyLogger.info('FimbyGraceExpiryBatch', 'execute',
                'Flagged ' + toFlag.size() + ' Contact(s) for tonight\'s scrub batch.');
        }
    }

    global void finish(Database.BatchableContext bc) {
    }
}
