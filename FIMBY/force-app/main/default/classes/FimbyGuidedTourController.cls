/**
 * @description Server-side state for the live guided tour (Phase 2 onboarding).
 */
public with sharing class FimbyGuidedTourController {

    /**
     * @description Returns live tour eligibility and bio-post gating for the acting Contact.
     * @return Map with liveTourStatus, bioPostCompleted, autostartEligible, liveTourEnabled
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getLiveTourState() {
        Map<String, Object> result = new Map<String, Object>{
            'liveTourStatus' => FimbyConstants.ONBOARDING_NOT_STARTED,
            'bioPostCompleted' => false,
            'autostartEligible' => false,
            'liveTourEnabled' => FimbySettings.liveTourEnabled(),
            'extendedCompleted' => false,
            'bannerEligible' => false,
            'firstName' => ''
        };

        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        if (contactId == null) {
            return result;
        }

        Contact c = new ContactReader().read(contactId);
        if (c == null) {
            return result;
        }

        if (c.Is_Organization_Contact__c == true) {
            result.put('liveTourStatus', FimbyConstants.ONBOARDING_COMPLETED);
            result.put('bioPostCompleted', true);
            return result;
        }

        String status = String.isNotBlank(c.Live_Tour_Status__c)
            ? c.Live_Tour_Status__c
            : FimbyConstants.ONBOARDING_NOT_STARTED;
        Boolean bioDone = c.Bio_Post_Completed__c == true;
        Boolean flagOn = FimbySettings.liveTourEnabled();

        result.put('liveTourStatus', status);
        result.put('bioPostCompleted', bioDone);
        result.put('extendedCompleted', c.Live_Tour_Extended_Completed__c == true);
        result.put('firstName', String.isNotBlank(c.FirstName) ? c.FirstName : '');
        result.put(
            'autostartEligible',
            flagOn && status == FimbyConstants.ONBOARDING_NOT_STARTED
        );
        result.put(
            'bannerEligible',
            flagOn && status == FimbyConstants.ONBOARDING_DISMISSED
        );
        return result;
    }

    /**
     * @description Persists live tour completion or dismissal on the acting Contact.
     * @param status Completed or Dismissed
     * @param extendedCompleted When true, marks the optional Extended segment complete
     * @return success flag
     */
    @AuraEnabled
    public static Map<String, Object> setLiveTourStatus(String status, Boolean extendedCompleted) {
        Id contactId = FimbyIdentityRepository.getActingAsContactId();
        if (contactId == null) {
            throw new AuraHandledException('We could not find your profile. Please try again.');
        }

        String normalized = normalizeStatus(status);
        Contact c = new Contact(
            Id = contactId,
            Live_Tour_Status__c = normalized
        );
        if (extendedCompleted == true) {
            c.Live_Tour_Extended_Completed__c = true;
        }

        new ContactUpdater().doUpdate(c);
        return new Map<String, Object>{ 'success' => true, 'liveTourStatus' => normalized };
    }

    private static String normalizeStatus(String status) {
        if (status == FimbyConstants.ONBOARDING_COMPLETED) {
            return FimbyConstants.ONBOARDING_COMPLETED;
        }
        if (status == FimbyConstants.ONBOARDING_DISMISSED) {
            return FimbyConstants.ONBOARDING_DISMISSED;
        }
        return FimbyConstants.ONBOARDING_NOT_STARTED;
    }

    private without sharing class ContactReader {
        public Contact read(Id contactId) {
            List<Contact> contacts = [
                SELECT Id, FirstName, Live_Tour_Status__c, Bio_Post_Completed__c,
                       Live_Tour_Extended_Completed__c, Is_Organization_Contact__c
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];
            return contacts.isEmpty() ? null : contacts[0];
        }
    }

    private without sharing class ContactUpdater {
        public void doUpdate(Contact c) {
            update c;
        }
    }
}
