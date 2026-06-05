/**
 * @description Mirrors Contact identity fields (FirstName, LastName, Email) onto
 * the linked community User. Invoked from FimbyUserSyncEventTrigger, which runs
 * as the Automated Process user. Because the running user is NOT the User being
 * edited, the Email change is treated as an administrative change and persists
 * immediately, rather than being held pending self-service email confirmation
 * (the reason the previous in-transaction / queueable approach silently no-opped
 * on Email while names synced fine).
 */
public without sharing class FimbyUserSyncEventHandler {

    public static void handle(List<Fimby_User_Sync_Event__e> events) {
        Map<Id, Fimby_User_Sync_Event__e> latestByUserId = new Map<Id, Fimby_User_Sync_Event__e>();
        for (Fimby_User_Sync_Event__e evt : events) {
            if (String.isBlank(evt.User_Id__c)) {
                continue;
            }
            Id userId;
            try {
                userId = Id.valueOf(evt.User_Id__c);
            } catch (Exception e) {
                continue;
            }
            // Last event for a given user wins within this batch.
            latestByUserId.put(userId, evt);
        }

        if (latestByUserId.isEmpty()) {
            return;
        }

        Set<Id> existingIds = new Map<Id, User>([
            SELECT Id FROM User WHERE Id IN :latestByUserId.keySet()
        ]).keySet();

        List<User> toUpdate = new List<User>();
        for (Id userId : latestByUserId.keySet()) {
            if (!existingIds.contains(userId)) {
                continue;
            }
            Fimby_User_Sync_Event__e evt = latestByUserId.get(userId);

            User u = new User(Id = userId);
            Boolean hasChange = false;

            if (String.isNotBlank(evt.First_Name__c)) {
                u.FirstName = evt.First_Name__c;
                hasChange = true;
            }
            if (String.isNotBlank(evt.Last_Name__c)) {
                u.LastName = evt.Last_Name__c;
                hasChange = true;
            }
            if (String.isNotBlank(evt.Email__c)) {
                u.Email = evt.Email__c.trim();
                hasChange = true;
            }

            if (hasChange) {
                toUpdate.add(u);
            }
        }

        if (toUpdate.isEmpty()) {
            return;
        }

        List<Database.SaveResult> results = Database.update(toUpdate, false);
        for (Integer i = 0; i < results.size(); i++) {
            Database.SaveResult sr = results[i];
            if (!sr.isSuccess()) {
                String errorMsg = '';
                for (Database.Error err : sr.getErrors()) {
                    errorMsg += err.getMessage() + '; ';
                }
                FimbyLogger.warn('FimbyUserSyncEventHandler', 'handle',
                    'User identity sync failed for ' + toUpdate[i].Id + ': ' + errorMsg);
            }
        }
    }
}
