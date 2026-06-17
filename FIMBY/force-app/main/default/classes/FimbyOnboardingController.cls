/**
 * @description Handles onboarding status checks, profile completion, walkthrough dismiss/complete actions,
 * and the bio-post nudge flag that drives the home-feed banner and Ask/Offer soft gate.
 * Used by fimbyOnboardingPage, fimbyIntroPostModal, fimbyHomeFeed, fimbyAskOfferComposer, and fimbyHelpSupportPage LWCs.
 */
public with sharing class FimbyOnboardingController {

    private static final Set<String> ALLOWED_PROFILE_FIELDS = new Set<String>{
        'FirstName', 'LastName', 'Email', 'Phone',
        'MailingStreet', 'MailingCity', 'MailingState', 'MailingPostalCode', 'MailingCountry',
        'Pronouns__c', 'Languages_Spoken__c', 'Accessibility_Notes__c', 'General_Availability__c',
        'About_Neighbourhood_Tenure__c', 'About_What_Brought_You__c', 'About_Local_Place__c',
        'About_Enjoys_Doing__c', 'About_Fun_Fact__c',
        'Care_Welcome_Support__c', 'Care_Unhelpful_Things__c', 'Care_How_To_Ask__c', 'Care_Hard_Nos__c',
        'Care_Standing_Visible__c', 'Care_Updated_Date__c',
        'Mask_Last_Name__c', 'Mask_Avatar__c'
    };

    private static final Set<String> BOOLEAN_PROFILE_FIELDS = new Set<String>{
        'Care_Standing_Visible__c', 'Mask_Last_Name__c', 'Mask_Avatar__c'
    };

    private static final Set<String> CARE_PROFILE_FIELDS = new Set<String>{
        'Care_Welcome_Support__c', 'Care_Unhelpful_Things__c', 'Care_How_To_Ask__c', 'Care_Hard_Nos__c',
        'Care_Standing_Visible__c'
    };

    private static final Integer DISMISS_EXPIRY_HOURS = 12;

    /**
     * @description LWC-callable method that returns onboarding status (profile completed, walkthrough status,
     * bio post completed, showWalkthrough flag). The bioPostCompleted flag drives the home-feed Say-hi banner
     * and the Ask/Offer composer soft-gate; it is set true when the user either posts or skips their
     * auto-drafted Shared Life intro.
     * @return Map with profileCompleted, walkthroughStatus, bioPostCompleted, and showWalkthrough
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getOnboardingStatus() {
        try {
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            if (contactId == null) {
                return new Map<String, Object>{
                    'profileCompleted' => true,
                    'walkthroughStatus' => FimbyConstants.ONBOARDING_COMPLETED,
                    'bioPostCompleted' => true,
                    'showWalkthrough' => false
                };
            }

            Contact c = [
                SELECT Id, Onboarding_Profile_Completed__c, Bio_Post_Completed__c,
                       Is_Organization_Contact__c
                FROM Contact
                WHERE Id = :contactId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (c.Is_Organization_Contact__c == true) {
                return organizationOnboardingStatus();
            }

            User u = [
                SELECT Id, Onboarding_Walkthrough_Status__c,
                       Onboarding_Walkthrough_Dismissed_At__c
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            Boolean profileCompleted = c.Onboarding_Profile_Completed__c;
            Boolean bioPostCompleted = c.Bio_Post_Completed__c;
            String walkthroughStatus = u.Onboarding_Walkthrough_Status__c != null
                ? u.Onboarding_Walkthrough_Status__c
                : FimbyConstants.ONBOARDING_NOT_STARTED;

            Boolean showWalkthrough = false;
            if (walkthroughStatus == FimbyConstants.ONBOARDING_NOT_STARTED) {
                showWalkthrough = true;
            } else if (walkthroughStatus != FimbyConstants.ONBOARDING_COMPLETED && walkthroughStatus != FimbyConstants.ONBOARDING_DISMISSED) {
                if (u.Onboarding_Walkthrough_Dismissed_At__c != null) {
                    DateTime dismissedAt = u.Onboarding_Walkthrough_Dismissed_At__c;
                    DateTime expiryTime = dismissedAt.addHours(DISMISS_EXPIRY_HOURS);
                    showWalkthrough = DateTime.now() > expiryTime;
                } else {
                    showWalkthrough = true;
                }
            }

            return new Map<String, Object>{
                'profileCompleted' => profileCompleted,
                'walkthroughStatus' => walkthroughStatus,
                'bioPostCompleted' => bioPostCompleted,
                'showWalkthrough' => showWalkthrough
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error checking onboarding status: ' + e.getMessage());
        }
    }

    /**
     * @description Lightweight LWC-callable check for the home-feed Say-hi banner and the
     * Ask/Offer composer soft-gate. Returns true if the acting Contact has either posted
     * their bio or explicitly skipped past the prompt.
     * @return true when Bio_Post_Completed__c is true on the acting Contact, false otherwise.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean getBioPostStatus() {
        try {
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            if (contactId == null) {
                return true;
            }

            Contact c = [
                SELECT Id, Bio_Post_Completed__c, Is_Organization_Contact__c
                FROM Contact
                WHERE Id = :contactId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (c.Is_Organization_Contact__c == true) {
                return true;
            }

            return c.Bio_Post_Completed__c == true;
        } catch (Exception e) {
            throw new AuraHandledException('Error checking bio post status: ' + e.getMessage());
        }
    }

    /**
     * @description Marks the acting Contact's Bio_Post_Completed__c flag true. Called by
     * fimbyIntroPostModal on both Post and Skip paths so the flag means "decision made"
     * rather than "story posted." Once true, the home-feed banner disappears and the
     * Ask/Offer soft gate no longer triggers.
     * @param posted true when the user posted the auto-drafted intro (informational; flag
     *               flips either way). The storyId param is accepted for future audit/log
     *               wiring and is otherwise ignored here.
     * @param storyId Id of the newly created Story__c, or null when the user skipped.
     * @return Map with success status
     */
    @AuraEnabled
    public static Map<String, Object> markBioPostCompleted(Boolean posted, Id storyId) {
        try {
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            if (contactId == null) {
                throw new AuraHandledException('No contact associated with current user.');
            }

            // Only flip the flag when the user actually posted a bio. A skip
            // intentionally leaves the flag false so the soft-gate banner and
            // the onboarding modal keep nudging until a bio is published.
            Boolean isPosted = posted == true;
            if (!isPosted) {
                return new Map<String, Object>{ 'success' => true, 'skipped' => true };
            }

            Contact c = new Contact(
                Id = contactId,
                Bio_Post_Completed__c = true
            );
            new ContactUpdater().doUpdate(c);

            return new Map<String, Object>{ 'success' => true };
        } catch (Exception e) {
            throw new AuraHandledException('Error marking bio post completed: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that completes profile setup by updating allowed Contact fields and setting Onboarding_Profile_Completed__c.
     * @param fieldValues Map of field names to values (only ALLOWED_PROFILE_FIELDS accepted)
     * @return Map with success status
     */
    @AuraEnabled
    public static Map<String, Object> completeProfileSetup(Map<String, String> fieldValues) {
        try {
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            if (contactId == null) {
                throw new AuraHandledException('No contact associated with current user.');
            }

            if (isOrganizationContact(contactId)) {
                stampOrganizationOnboardingComplete(contactId);
                return new Map<String, Object>{ 'success' => true };
            }

            Contact c = new Contact(Id = contactId);
            Boolean careTouched = false;
            for (String fieldName : fieldValues.keySet()) {
                if (!ALLOWED_PROFILE_FIELDS.contains(fieldName)) {
                    throw new AuraHandledException('Field not allowed: ' + fieldName);
                }
                if (CARE_PROFILE_FIELDS.contains(fieldName)) {
                    careTouched = true;
                }
                if (BOOLEAN_PROFILE_FIELDS.contains(fieldName)) {
                    c.put(fieldName, 'true'.equalsIgnoreCase(fieldValues.get(fieldName)));
                } else {
                    c.put(fieldName, fieldValues.get(fieldName));
                }
            }
            if (careTouched) {
                c.Care_Updated_Date__c = Date.today();
            }
            c.Onboarding_Profile_Completed__c = true;

            new ContactUpdater().doUpdate(c);

            return new Map<String, Object>{ 'success' => true };
        } catch (Exception e) {
            throw new AuraHandledException('Error completing profile setup: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that dismisses the walkthrough; optionally marks it permanently dismissed.
     * @param permanent If true, sets Onboarding_Walkthrough_Status__c to DISMISSED; otherwise just records dismiss time for expiry
     * @return Map with success status
     */
    @AuraEnabled
    public static Map<String, Object> dismissWalkthrough(Boolean permanent) {
        try {
            User u = new User(Id = UserInfo.getUserId());
            if (permanent) {
                u.Onboarding_Walkthrough_Status__c = FimbyConstants.ONBOARDING_DISMISSED;
            }
            u.Onboarding_Walkthrough_Dismissed_At__c = DateTime.now();
            new UserUpdater().doUpdate(u);

            return new Map<String, Object>{ 'success' => true };
        } catch (Exception e) {
            throw new AuraHandledException('Error dismissing walkthrough: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that marks the walkthrough as completed.
     * @return Map with success status
     */
    @AuraEnabled
    public static Map<String, Object> completeWalkthrough() {
        try {
            User u = new User(Id = UserInfo.getUserId());
            u.Onboarding_Walkthrough_Status__c = FimbyConstants.ONBOARDING_COMPLETED;
            new UserUpdater().doUpdate(u);

            return new Map<String, Object>{ 'success' => true };
        } catch (Exception e) {
            throw new AuraHandledException('Error completing walkthrough: ' + e.getMessage());
        }
    }

    /**
     * @description Saves the user's quiet hours preference during onboarding or from settings.
     * @param preference The Quiet_Hours_Preference__c picklist value (e.g. '10PM_6AM', 'NONE')
     */
    @AuraEnabled
    public static void saveQuietHoursPreference(String preference) {
        try {
            User u = new User(Id = UserInfo.getUserId(), Quiet_Hours_Preference__c = preference);
            new UserUpdater().doUpdate(u);
        } catch (Exception e) {
            throw new AuraHandledException('Error saving quiet hours preference: ' + e.getMessage());
        }
    }

    /**
     * @description Deprecated. The walkthrough is now hard-coded into fimbyOnboardingPage and
     * fimbyWalkthroughContent.js; CMS-driven slides have been retired. This stub returns an
     * empty list so the legacy fimbyOnboardingModal bundle (which still imports this method)
     * keeps compiling until it is removed in a follow-up cleanup PR.
     * @return Empty list of slide data.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getWalkthroughSlides() {
        return new List<Map<String, String>>();
    }

    private static Map<String, Object> organizationOnboardingStatus() {
        return new Map<String, Object>{
            'profileCompleted' => true,
            'walkthroughStatus' => FimbyConstants.ONBOARDING_COMPLETED,
            'bioPostCompleted' => true,
            'showWalkthrough' => false
        };
    }

    private static Boolean isOrganizationContact(Id contactId) {
        if (contactId == null) {
            return false;
        }
        Contact c = [
            SELECT Is_Organization_Contact__c
            FROM Contact
            WHERE Id = :contactId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return c.Is_Organization_Contact__c == true;
    }

    private static void stampOrganizationOnboardingComplete(Id contactId) {
        new ContactUpdater().doUpdate(new Contact(
            Id = contactId,
            Onboarding_Profile_Completed__c = true,
            Bio_Post_Completed__c = true
        ));
    }

    /**
     * @description Without-sharing helper for Contact updates.
     */
    private without sharing class ContactUpdater {
        /**
         * @description Updates a Contact record without sharing.
         * @param c The Contact record to update
         */
        public void doUpdate(Contact c) {
            update c;
        }
    }

    /**
     * @description Without-sharing helper for User updates.
     */
    private without sharing class UserUpdater {
        /**
         * @description Updates a User record without sharing.
         * @param u The User record to update
         */
        public void doUpdate(User u) {
            update u;
        }
    }
}
