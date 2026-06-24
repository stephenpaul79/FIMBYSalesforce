/**
 * @description Handles shared contact/identity methods used across multiple LWCs.
 * Extracted from FimbyLibraryController for better maintainability.
 * Used by fimbyMarketplaceComposer, fimbyAddLibraryItem, fimbyBorrowingFlow,
 * fimbyCommentComposer, fimbyQuickResponse, fimbyResponseReply.
 */
public with sharing class FimbyContactController {

    /**
     * Get the current user's Contact info and "acting as" Contact info
     * Returns BOTH:
     *   - realContactId: The logged-in user's actual Contact.Id (who physically clicked)
     *   - actingAsContactId: The Logged_In_As_Contact__c (who they're acting on behalf of)
     *
     * Use Case Pattern (Needs_Offers__c):
     *   - Contact__c = actingAsContactId (the represented identity / who has the need)
     *   - Posted_By__c = realContactId (who physically typed the post)
     * Use Case Pattern (Messages / Response Messages):
     *   - Sender__c = realContactId
     *   - On_Behalf_Of__c = actingAsContactId
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getActingAsContact() {
        try {
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();

            if (identity.currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact associated with current user');
            }

            Contact realContact = identity.contact;
            Id actingAsId = identity.actingAsContactId;

            // Get the "acting as" contact details (may be same as real contact)
            Contact actingAsContact;
            if (actingAsId == realContact.Id) {
                actingAsContact = realContact;
            } else {
                actingAsContact = [
                    SELECT Id, Name, FirstName, LastName, AccountId, Account.Name,
                           Image_URL__c, Is_Organization_Contact__c,
                           Organization_Account__c, Organization_Account__r.Name,
                           Organization_Account__r.Logo_URL__c
                    FROM Contact
                    WHERE Id = :actingAsId
                    LIMIT 1
                ];
            }

            Boolean isActingAsSelf = (realContact.Id == actingAsContact.Id);

            Boolean isOrgContact = actingAsContact.Is_Organization_Contact__c == true;
            String orgDisplayName = isOrgContact
                ? FimbyIdentityRepository.buildOrgDisplayName(
                      actingAsContact.Organization_Account__r?.Name,
                      realContact.FirstName
                  )
                : actingAsContact.Name;

            String realAvatarUrl = realContact.Image_URL__c;
            String actingAsAvatarUrl;
            if (isOrgContact && actingAsContact.Organization_Account__r?.Logo_URL__c != null) {
                actingAsAvatarUrl = actingAsContact.Organization_Account__r.Logo_URL__c;
            } else {
                actingAsAvatarUrl = actingAsContact.Image_URL__c;
            }

            Boolean tosReacceptanceRequired = realContact.Tos_Reacceptance_Required__c == true;
            Boolean hasPriorTosAcceptance = realContact.Tos_Accepted_Date__c != null;

            return new Map<String, Object>{
                'success' => true,
                'realContactId' => realContact.Id,
                'realContactName' => realContact.Name,
                'realContactFirstName' => realContact.FirstName,
                'realContactAvatarUrl' => realAvatarUrl,
                'actingAsContactId' => actingAsContact.Id,
                'actingAsContactName' => orgDisplayName,
                'actingAsAvatarUrl' => actingAsAvatarUrl,
                'accountId' => FimbyIdentityRepository.getNeighbourhoodId(),
                'accountName' => actingAsContact.Account?.Name,
                'isActingAsSelf' => isActingAsSelf,
                'isActingAsOrg' => isOrgContact,
                'firstName' => actingAsContact.FirstName,
                'postingAsDisplayName' => orgDisplayName,
                'isOrganizationContact' => isOrgContact,
                'organizationAccountId' => actingAsContact.Organization_Account__c,
                'tosReacceptanceRequired' => tosReacceptanceRequired,
                'hasPriorTosAcceptance' => hasPriorTosAcceptance,
                // Legacy aliases
                'contactId' => actingAsContact.Id,
                'contactName' => actingAsContact.Name
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error getting acting as contact: ' + e.getMessage());
        }
    }

    /**
     * Search for Organizations (Accounts) for the Organization lookup
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> searchOrganizations(String searchTerm) {
        List<Map<String, String>> results = new List<Map<String, String>>();

        String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';

        List<Account> accounts = [
            SELECT Id, Name
            FROM Account
            WHERE Name LIKE :searchPattern
            AND RecordType.Name = 'Organization'
            AND Is_Approved_Community_Group__c = true
            ORDER BY Name
            LIMIT 20
        ];

        for (Account acc : accounts) {
            results.add(new Map<String, String>{
                'id' => acc.Id,
                'name' => acc.Name
            });
        }

        return results;
    }

    /**
     * Stamp Last_App_Open_At__c on the current User (throttled to 1 DML per 5-min window)
     * and return the user's Quiet_Hours_Preference__c for the mobile app postMessage bridge.
     */
    @AuraEnabled
    public static Map<String, Object> recordAppOpen() {
        try {
            User u = [
                SELECT Id, Last_App_Open_At__c, Quiet_Hours_Preference__c
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            String quietHours = String.isNotBlank(u.Quiet_Hours_Preference__c)
                ? u.Quiet_Hours_Preference__c
                : '10PM_6AM';

            if (u.Last_App_Open_At__c == null ||
                u.Last_App_Open_At__c.addMinutes(5) < Datetime.now()) {
                new AppOpenHelper().stampAppOpen(u.Id);
            }

            return new Map<String, Object>{
                'quietHoursPreference' => quietHours
            };
        } catch (Exception e) {
            FimbyLogger.error('FimbyContactController', 'recordAppOpen', e);
            return new Map<String, Object>{
                'quietHoursPreference' => '10PM_6AM'
            };
        }
    }

    private without sharing class AppOpenHelper {
        public void stampAppOpen(Id userId) {
            update new User(Id = userId, Last_App_Open_At__c = Datetime.now());
        }
    }

    /**
     * Search contacts for "On Behalf Of" lookup.
     * Scoped to the caller's neighbourhood (the trust boundary) and excludes the
     * caller themselves, so the support-person lookup never surfaces people from
     * outside the linked boundary account.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> searchContactsForOnBehalfOf(String searchTerm) {
        List<Map<String, String>> results = new List<Map<String, String>>();

        try {
            Id neighbourhoodId = FimbyIdentityRepository.getNeighbourhoodId();
            if (neighbourhoodId == null) {
                return results;
            }
            Id myContactId = FimbyIdentityRepository.getCurrentUser().ContactId;

            String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';

            List<Contact> contacts = [
                SELECT Id, Name, FirstName, LastName
                FROM Contact
                WHERE Name LIKE :searchPattern
                  AND Is_Organization_Contact__c = false
                  AND AccountId = :neighbourhoodId
                  AND Id != :myContactId
                ORDER BY Name
                LIMIT 20
            ];

            for (Contact c : contacts) {
                results.add(new Map<String, String>{
                    'id' => c.Id,
                    'name' => c.Name
                });
            }
        } catch (Exception e) {
            FimbyLogger.error('FimbyContactController', 'searchContactsForOnBehalfOf', e);
        }

        return results;
    }
}