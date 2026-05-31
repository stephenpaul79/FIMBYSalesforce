/**
 * @description Invocable action that executes steps 4–7 of a neighbourhood split:
 *   Step 4 — Move Contacts whose postal code is in the moved set to the new Account.
 *   Step 5 — Restamp Neighbourhood__c on content records owned by moved Contacts.
 *   Step 6 — Recalculate summary counts on both source and new Accounts.
 *   Step 7 — (Optional) Create welcome Notification__c records for moved Contacts.
 * Supports resumeFromStep to skip previously completed steps on retry.
 */
public without sharing class FimbyNeighbourhoodSplitAction {

    private static final Integer DML_SAFETY_THRESHOLD = 8000;

    public class SplitInput {
        @InvocableVariable(required=true label='Source Account ID')
        public Id sourceAccountId;

        @InvocableVariable(required=true label='New Account ID')
        public Id newAccountId;

        @InvocableVariable(required=true label='Split Record ID')
        public Id splitRecordId;

        @InvocableVariable(required=true label='Moved Postal Code IDs')
        public List<Id> movedPostalCodeIds;

        @InvocableVariable(label='Send Notification')
        public Boolean sendNotification;

        @InvocableVariable(label='Resume From Step')
        public Integer resumeFromStep;
    }

    @InvocableMethod(label='Execute Neighbourhood Split Steps 4-7'
                     description='Moves contacts, restamps content, recalculates counts, and optionally notifies moved contacts')
    public static void execute(List<SplitInput> inputs) {
        for (SplitInput input : inputs) {
            executeSplit(input);
        }
    }

    private static void executeSplit(SplitInput input) {
        Integer startStep = input.resumeFromStep != null ? input.resumeFromStep : 4;

        try {
            Set<Id> movedContactIds = new Set<Id>();

            if (startStep <= 4) {
                movedContactIds = step4MoveContacts(input);
            } else {
                // Resuming past step 4 — resolve moved contacts from the new account
                movedContactIds = resolveMovedContactIds(input.newAccountId);
            }

            if (startStep <= 5) {
                step5RestampContent(input, movedContactIds);
            }

            if (startStep <= 6) {
                step6RecalculateCounts(input);
            }

            if (startStep <= 7 && input.sendNotification == true) {
                step7Notify(input, movedContactIds);
            }

            Neighbourhood_Split__c split = new Neighbourhood_Split__c(
                Id = input.splitRecordId,
                Status__c = 'Completed',
                Completed_At__c = Datetime.now()
            );
            Database.update(split, true);

        } catch (Exception e) {
            FimbyLogger.error('FimbyNeighbourhoodSplitAction', 'executeSplit', e);
            try {
                Neighbourhood_Split__c split = new Neighbourhood_Split__c(
                    Id = input.splitRecordId,
                    Status__c = 'Failed',
                    Error_Detail__c = truncate(e.getMessage(), 255)
                );
                Database.update(split, false);
            } catch (Exception ex2) {
                FimbyLogger.error('FimbyNeighbourhoodSplitAction', 'executeSplit.errorUpdate', ex2);
            }
        }
    }

    // ─── Step 4: Move Contacts ───────────────────────────────────────────

    private static Set<Id> step4MoveContacts(SplitInput input) {
        Set<String> postalCodeNames = resolvePostalCodeNames(input.movedPostalCodeIds);

        List<Contact> contacts = [
            SELECT Id, MailingPostalCode
            FROM Contact
            WHERE AccountId = :input.sourceAccountId
            AND MailingPostalCode IN :postalCodeNames
        ];

        Set<Id> movedContactIds = new Set<Id>();
        List<Contact> toUpdate = new List<Contact>();
        for (Contact c : contacts) {
            movedContactIds.add(c.Id);
            toUpdate.add(new Contact(
                Id = c.Id,
                AccountId = input.newAccountId,
                npsp__Primary_Affiliation__c = input.newAccountId
            ));
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, true);
        }

        updateSplitStep(input.splitRecordId, 4, 'Contacts_Moved__c', toUpdate.size());
        return movedContactIds;
    }

    private static Set<String> resolvePostalCodeNames(List<Id> postalCodeIds) {
        Set<String> names = new Set<String>();
        for (Postal_Codes__c pc : [
            SELECT Name FROM Postal_Codes__c WHERE Id IN :postalCodeIds
        ]) {
            names.add(pc.Name);
            names.add(pc.Name.replaceAll('\\s', ''));
        }
        return names;
    }

    // ─── Step 5: Restamp Content ─────────────────────────────────────────

    private static void step5RestampContent(SplitInput input, Set<Id> movedContactIds) {
        if (movedContactIds.isEmpty()) {
            updateSplitStep(input.splitRecordId, 5, 'Records_Restamped__c', 0);
            return;
        }

        List<SObject> toUpdate = new List<SObject>();

        for (Needs_Offers__c no : [
            SELECT Id FROM Needs_Offers__c
            WHERE Neighbourhood__c = :input.sourceAccountId
            AND (Posted_By__c IN :movedContactIds OR Contact__c IN :movedContactIds)
        ]) {
            toUpdate.add(new Needs_Offers__c(Id = no.Id, Neighbourhood__c = input.newAccountId));
        }

        for (Story__c s : [
            SELECT Id FROM Story__c
            WHERE Neighbourhood__c = :input.sourceAccountId
            AND (Posted_By__c IN :movedContactIds OR Contact__c IN :movedContactIds)
        ]) {
            toUpdate.add(new Story__c(Id = s.Id, Neighbourhood__c = input.newAccountId));
        }

        for (Library_Item__c li : [
            SELECT Id FROM Library_Item__c
            WHERE Neighbourhood__c = :input.sourceAccountId
            AND (Owner_Contact__c IN :movedContactIds OR Listed_By__c IN :movedContactIds)
        ]) {
            toUpdate.add(new Library_Item__c(Id = li.Id, Neighbourhood__c = input.newAccountId));
        }

        for (Shared_Contact_Info__c sci : [
            SELECT Id, Contact__c, Shared_To__c
            FROM Shared_Contact_Info__c
            WHERE Contact__c IN :movedContactIds OR Shared_To__c IN :movedContactIds
        ]) {
            Shared_Contact_Info__c upd = new Shared_Contact_Info__c(Id = sci.Id);
            if (movedContactIds.contains(sci.Contact__c)) {
                upd.Contact_Neighbourhood__c = input.newAccountId;
            }
            if (movedContactIds.contains(sci.Shared_To__c)) {
                upd.Shared_To_Neighbourhood__c = input.newAccountId;
            }
            toUpdate.add(upd);
        }

        if (toUpdate.size() > DML_SAFETY_THRESHOLD) {
            System.enqueueJob(new FimbyNeighbourhoodSplitQueueable(toUpdate, input.splitRecordId));
            updateSplitStep(input.splitRecordId, 5, null, null);
        } else {
            if (!toUpdate.isEmpty()) {
                Database.update(toUpdate, false);
            }
            updateSplitStep(input.splitRecordId, 5, 'Records_Restamped__c', toUpdate.size());
        }
    }

    // ─── Step 6: Recalculate Counts ──────────────────────────────────────

    private static void step6RecalculateCounts(SplitInput input) {
        recalculateAccountCounts(input.sourceAccountId);
        recalculateAccountCounts(input.newAccountId);
        updateSplitStep(input.splitRecordId, 6, null, null);
    }

    private static void recalculateAccountCounts(Id accountId) {
        Integer needCount = [SELECT COUNT() FROM Needs_Offers__c WHERE Neighbourhood__c = :accountId AND RecordType.DeveloperName = 'Need'];
        Integer offerCount = [SELECT COUNT() FROM Needs_Offers__c WHERE Neighbourhood__c = :accountId AND RecordType.DeveloperName = 'Offer'];
        Integer eventCount = [SELECT COUNT() FROM Needs_Offers__c WHERE Neighbourhood__c = :accountId AND Type__c = 'Event'];
        Integer storyCount = [SELECT COUNT() FROM Story__c WHERE Neighbourhood__c = :accountId];
        Integer libraryCount = [SELECT COUNT() FROM Library_Item__c WHERE Neighbourhood__c = :accountId];

        Account acct = new Account(
            Id = accountId,
            Need_Summary_Count__c = needCount,
            Offer_Summary_Count__c = offerCount,
            Summary_Count__c = eventCount,
            Story_Summary_Count__c = storyCount,
            Library_Item_Count__c = libraryCount
        );
        Database.update(acct, true);
    }

    // ─── Step 7: Notify ──────────────────────────────────────────────────

    private static void step7Notify(SplitInput input, Set<Id> movedContactIds) {
        if (movedContactIds.isEmpty()) return;

        Account newAcct = [SELECT Name FROM Account WHERE Id = :input.newAccountId LIMIT 1];
        String title = 'Your neighbourhood is now ' + newAcct.Name;
        String body = 'Everything you posted moved with you. Nothing else changes.';

        List<Notification__c> notifications = new List<Notification__c>();
        for (Id contactId : movedContactIds) {
            notifications.add(new Notification__c(
                Contact__c = contactId,
                Type__c = FimbyConstants.NOTIF_SYSTEM_NEIGHBOURHOOD_CHANGE,
                Title__c = title,
                Body__c = body,
                Related_Record_Id__c = String.valueOf(input.newAccountId),
                Related_Record_Type__c = 'Account',
                Action_URL__c = FimbySettings.getUrl('Settings'),
                Actor_Name__c = 'FIMBY'
            ));
        }

        if (!notifications.isEmpty()) {
            FimbyNotificationService.createNotifications(notifications);
        }

        updateSplitStep(input.splitRecordId, 7, null, null);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    private static Set<Id> resolveMovedContactIds(Id newAccountId) {
        Set<Id> ids = new Set<Id>();
        for (Contact c : [SELECT Id FROM Contact WHERE AccountId = :newAccountId]) {
            ids.add(c.Id);
        }
        return ids;
    }

    private static void updateSplitStep(Id splitRecordId, Integer step, String countField, Integer count) {
        Neighbourhood_Split__c split = new Neighbourhood_Split__c(
            Id = splitRecordId,
            Current_Step__c = step
        );
        if (countField == 'Contacts_Moved__c' && count != null) {
            split.Contacts_Moved__c = count;
        } else if (countField == 'Records_Restamped__c' && count != null) {
            split.Records_Restamped__c = count;
        }
        Database.update(split, false);
    }

    private static String truncate(String value, Integer maxLen) {
        if (String.isBlank(value)) return value;
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }
}
