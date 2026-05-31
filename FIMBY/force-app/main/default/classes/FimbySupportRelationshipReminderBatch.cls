/**
 * @description Daily Schedulable + Batchable that drives the reminder cadence
 * for paper-form support relationships still sitting in Draft. Sends a
 * reminder + fresh PDF on day 14 / 30 / 60 since the original Day-0 email,
 * and auto-expires (Status = Expired) on day 90.
 *
 * Reminder day buckets are computed from Day0_Email_Sent_Date__c and gated
 * by Last_Reminder_Sent_Date__c so we never double-send on the same day.
 */
public without sharing class FimbySupportRelationshipReminderBatch
    implements Schedulable, Database.Batchable<sObject> {

    private static final Integer REMINDER_DAY_14 = 14;
    private static final Integer REMINDER_DAY_30 = 30;
    private static final Integer REMINDER_DAY_60 = 60;
    private static final Integer EXPIRY_DAYS = 90;

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new FimbySupportRelationshipReminderBatch(), 50);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date cutoff = Date.today().addDays(-EXPIRY_DAYS - 1);
        return Database.getQueryLocator([
            SELECT Id, Status__c, Day0_Email_Sent_Date__c, Last_Reminder_Sent_Date__c, CreatedDate
            FROM Support_Relationship__c
            WHERE Status__c = 'Draft'
              AND Day0_Email_Sent_Date__c != null
              AND Day0_Email_Sent_Date__c >= :cutoff
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Support_Relationship__c> scope) {
        List<Support_Relationship__c> toExpire = new List<Support_Relationship__c>();
        Date today = Date.today();

        for (Support_Relationship__c rel : scope) {
            Integer daysSinceDay0 = rel.Day0_Email_Sent_Date__c.date().daysBetween(today);

            if (daysSinceDay0 >= EXPIRY_DAYS) {
                toExpire.add(new Support_Relationship__c(
                    Id = rel.Id,
                    Status__c = 'Expired',
                    Ended_Date__c = Datetime.now()
                ));
                continue;
            }

            Integer reminderBucket = pickReminderBucket(daysSinceDay0);
            if (reminderBucket == null) continue;
            if (alreadyRemindedToday(rel, today)) continue;

            try {
                FimbySupportRelationshipEmailService.sendReminderEmail(rel.Id, reminderBucket);
            } catch (Exception e) {
                FimbyLogger.error('FimbySupportRelationshipReminderBatch',
                    'execute.sendReminderEmail', e, rel.Id);
            }
        }

        if (!toExpire.isEmpty()) {
            try {
                update toExpire;
            } catch (Exception e) {
                FimbyLogger.error('FimbySupportRelationshipReminderBatch', 'execute.expire', e);
            }
        }
    }

    public void finish(Database.BatchableContext bc) { }

    private Integer pickReminderBucket(Integer daysSinceDay0) {
        if (daysSinceDay0 == REMINDER_DAY_60) return REMINDER_DAY_60;
        if (daysSinceDay0 == REMINDER_DAY_30) return REMINDER_DAY_30;
        if (daysSinceDay0 == REMINDER_DAY_14) return REMINDER_DAY_14;
        return null;
    }

    private Boolean alreadyRemindedToday(Support_Relationship__c rel, Date today) {
        if (rel.Last_Reminder_Sent_Date__c == null) return false;
        return rel.Last_Reminder_Sent_Date__c.date() == today;
    }
}
