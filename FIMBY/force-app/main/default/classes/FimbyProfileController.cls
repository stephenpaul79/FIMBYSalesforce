/**
 * @description Handles profile data (Contact, acting-as) and settings data (User, real user).
 * Used by fimbyUserProfileView and fimbySettingsView LWCs.
 */
public with sharing class FimbyProfileController {

    /** Contact fields mirrored to User when the neighbour edits their own profile. */
    private static final Set<String> USER_SYNC_CONTACT_FIELDS = new Set<String>{
        'FirstName', 'LastName', 'Email'
    };

    private static final Set<String> ALLOWED_CONTACT_FIELDS = new Set<String>{
        'FirstName', 'LastName', 'Email', 'Phone',
        'MailingStreet', 'MailingCity', 'MailingState', 'MailingPostalCode', 'MailingCountry',
        'Pronouns__c', 'Languages_Spoken__c', 'Accessibility_Notes__c', 'General_Availability__c',
        'About_Neighbourhood_Tenure__c', 'About_What_Brought_You__c', 'About_Local_Place__c',
        'About_Enjoys_Doing__c', 'About_Fun_Fact__c',
        'Care_Welcome_Support__c', 'Care_Unhelpful_Things__c', 'Care_How_To_Ask__c', 'Care_Hard_Nos__c'
    };

    private static final Set<String> ALLOWED_USER_STRING_FIELDS = new Set<String>{
        'FIMBY_Summary_Emails__c', 'TimeZoneSidKey', 'LocaleSidKey', 'LanguageLocaleKey',
        'Theme_Preference__c', 'Quiet_Hours_Preference__c'
    };

    private static final Set<String> ALLOWED_USER_BOOLEAN_FIELDS = new Set<String>{
        'Push_Notifications_Enabled__c', 'Push_Messages__c', 'Push_Needs_Offers__c',
        'Push_Library__c', 'Push_Stories__c', 'Push_Reminders__c', 'Push_Bulk_Buy__c',
        'Push_Events__c',
        'Email_Alerts_Enabled__c', 'Email_Alert_Messages__c', 'Email_Alert_Needs_Offers__c',
        'Email_Alert_Library__c', 'Email_Alert_Stories__c', 'Email_Alert_Reminders__c',
        'Email_Alert_Bulk_Buy__c', 'Email_Alert_Events__c',
        'Include_Sundays__c',
        'FIMBY_Operating_Updates_Enabled__c',
        'Celebration_Confetti_Enabled__c', 'Celebration_Memes_Enabled__c'
    };

    private static final Set<String> ALLOWED_FIRST_CELEBRATION_FIELDS = new Set<String>{
        'First_Post_Celebrated__c', 'First_Response_Celebrated__c',
        'First_Library_Item_Celebrated__c', 'First_Story_Celebrated__c',
        'First_Bulk_Buy_Celebrated__c', 'First_Bulk_Buy_Reserve_Celebrated__c'
    };

    /**
     * @description LWC-callable method that loads the acting-as Contact's profile data for display.
     * @return Map with contact fields (firstName, lastName, email, etc.) and success status
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getProfileData() {
        try {
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            if (contactId == null) {
                throw new AuraHandledException('No contact associated with current user.');
            }

            Contact c = [
                SELECT Id, FirstName, LastName, Full_Name__c, Email, Phone,
                       MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry,
                       Pronouns__c, Image_URL__c, Image_Ratio__c,
                       Account.Name, CreatedDate,
                       Languages_Spoken__c, Accessibility_Notes__c, General_Availability__c,
                       About_Neighbourhood_Tenure__c, About_What_Brought_You__c,
                       About_Local_Place__c, About_Enjoys_Doing__c, About_Fun_Fact__c,
                       Care_Welcome_Support__c, Care_Unhelpful_Things__c,
                       Care_How_To_Ask__c, Care_Hard_Nos__c,
                       Vouched_Status__c, Vouching_Disabled__c
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];

            return new Map<String, Object>{
                'success' => true,
                'contactId' => c.Id,
                'firstName' => c.FirstName,
                'lastName' => c.LastName,
                'fullName' => c.Full_Name__c,
                'email' => c.Email,
                'phone' => c.Phone,
                'mailingStreet' => c.MailingStreet,
                'mailingCity' => c.MailingCity,
                'mailingState' => c.MailingState,
                'mailingPostalCode' => c.MailingPostalCode,
                'mailingCountry' => c.MailingCountry,
                'pronouns' => c.Pronouns__c,
                'imageUrl' => c.Image_URL__c,
                'imageRatio' => c.Image_Ratio__c,
                'neighbourhood' => c.Account?.Name,
                'memberSince' => c.CreatedDate,
                'languagesSpoken' => c.Languages_Spoken__c,
                'accessibilityNotes' => c.Accessibility_Notes__c,
                'generalAvailability' => c.General_Availability__c,
                'aboutNeighbourhoodTenure' => c.About_Neighbourhood_Tenure__c,
                'aboutWhatBroughtYou' => c.About_What_Brought_You__c,
                'aboutLocalPlace' => c.About_Local_Place__c,
                'aboutEnjoysDoing' => c.About_Enjoys_Doing__c,
                'aboutFunFact' => c.About_Fun_Fact__c,
                'careWelcomeSupport' => c.Care_Welcome_Support__c,
                'careUnhelpfulThings' => c.Care_Unhelpful_Things__c,
                'careHowToAsk' => c.Care_How_To_Ask__c,
                'careHardNos' => c.Care_Hard_Nos__c,
                'vouchedStatus' => c.Vouched_Status__c,
                'vouchingDisabled' => c.Vouching_Disabled__c
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error loading profile: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that updates allowed Contact profile fields for the acting-as contact.
     * @param fieldValues Map of field names to values (only ALLOWED_CONTACT_FIELDS accepted)
     * @return Map with success status
     */
    @AuraEnabled
    public static Map<String, Object> updateProfileSection(Map<String, String> fieldValues) {
        try {
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            if (contactId == null) {
                throw new AuraHandledException('No contact associated with current user.');
            }

            Contact c = new Contact(Id = contactId);
            for (String fieldName : fieldValues.keySet()) {
                if (!ALLOWED_CONTACT_FIELDS.contains(fieldName)) {
                    throw new AuraHandledException('Field not allowed: ' + fieldName);
                }
                c.put(fieldName, fieldValues.get(fieldName));
            }

            new ContactUpdater().doUpdate(c);

            syncUserIdentityFields(contactId, fieldValues);

            return new Map<String, Object>{ 'success' => true };
        } catch (Exception e) {
            throw new AuraHandledException('Error updating profile: ' + e.getMessage());
        }
    }

    /**
     * @description Mirrors FirstName, LastName, and Email to the running User when
     *              the neighbour is editing their own Contact (not acting as someone else).
     *
     *              Published as a Fimby_User_Sync_Event__e (PublishAfterCommit) rather
     *              than written inline or via a Queueable. The platform-event subscriber
     *              runs as the Automated Process user, so the User.Email change is treated
     *              as an administrative change and persists immediately. An in-transaction
     *              or same-user async write is a SELF-SERVICE email change, which Salesforce
     *              holds pending email confirmation (silently no-ops on Email while names
     *              still sync) and also trips MIXED_DML_OPERATION against the Contact update.
     */
    private static void syncUserIdentityFields(Id actingAsContactId, Map<String, String> fieldValues) {
        Id realContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
        if (realContactId == null || realContactId != actingAsContactId) {
            return;
        }

        Map<String, String> userFields = new Map<String, String>();
        for (String fieldName : fieldValues.keySet()) {
            if (USER_SYNC_CONTACT_FIELDS.contains(fieldName)) {
                userFields.put(fieldName, fieldValues.get(fieldName));
            }
        }

        if (userFields.isEmpty()) {
            return;
        }

        Fimby_User_Sync_Event__e evt = new Fimby_User_Sync_Event__e(
            User_Id__c = UserInfo.getUserId()
        );
        if (userFields.containsKey('FirstName')) {
            evt.First_Name__c = userFields.get('FirstName');
        }
        if (userFields.containsKey('LastName')) {
            evt.Last_Name__c = userFields.get('LastName');
        }
        if (userFields.containsKey('Email')) {
            evt.Email__c = userFields.get('Email');
        }
        EventBus.publish(evt);
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getSettingsData() {
        try {
            // SYSTEM_MODE: community profiles often lack FLS read on standard User
            // regional fields (TimeZoneSidKey, LocaleSidKey) even though the member
            // may update them from Settings. Scoped strictly to the running user.
            User u = new UserSettingsReader().getCurrentUserSettings();

            List<Map<String, String>> tzOptions = getPicklistOptions(User.TimeZoneSidKey, u.TimeZoneSidKey);
            List<Map<String, String>> localeOptions = getPicklistOptions(User.LocaleSidKey, u.LocaleSidKey);
            List<Map<String, String>> langOptions = getPicklistOptions(User.LanguageLocaleKey, u.LanguageLocaleKey);

            Id realContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();
            Boolean isActingAsSelf = (realContactId != null && realContactId == actingAsContactId);

            return new Map<String, Object>{
                'success' => true,
                'userId' => u.Id,
                'username' => u.Username,
                'isActingAsSelf' => isActingAsSelf,
                'summaryEmailFrequency' => u.FIMBY_Summary_Emails__c,
                'pushNotificationsEnabled' => u.Push_Notifications_Enabled__c,
                'pushMessages' => u.Push_Messages__c,
                'pushNeedsOffers' => u.Push_Needs_Offers__c,
                'pushLibrary' => u.Push_Library__c,
                'pushStories' => u.Push_Stories__c,
                'pushReminders' => u.Push_Reminders__c,
                'pushBulkBuy' => u.Push_Bulk_Buy__c,
                'pushEvents' => u.Push_Events__c,
                'quietHoursPreference' => u.Quiet_Hours_Preference__c,
                'emailAlertsEnabled' => u.Email_Alerts_Enabled__c,
                'emailAlertMessages' => u.Email_Alert_Messages__c,
                'emailAlertNeedsOffers' => u.Email_Alert_Needs_Offers__c,
                'emailAlertLibrary' => u.Email_Alert_Library__c,
                'emailAlertStories' => u.Email_Alert_Stories__c,
                'emailAlertReminders' => u.Email_Alert_Reminders__c,
                'emailAlertBulkBuy' => u.Email_Alert_Bulk_Buy__c,
                'emailAlertEvents' => u.Email_Alert_Events__c,
                'includeSundays' => u.Include_Sundays__c,
                'fimbyOperatingUpdatesEnabled' => u.FIMBY_Operating_Updates_Enabled__c,
                'timeZone' => u.TimeZoneSidKey,
                'locale' => u.LocaleSidKey,
                'language' => u.LanguageLocaleKey,
                'celebrationConfettiEnabled' => u.Celebration_Confetti_Enabled__c,
                'celebrationMemesEnabled' => u.Celebration_Memes_Enabled__c,
                'themePreference' => u.Theme_Preference__c != null ? u.Theme_Preference__c : 'Auto',
                'timeZoneLabel' => getLabelForValue(tzOptions, u.TimeZoneSidKey),
                'localeLabel' => getLabelForValue(localeOptions, u.LocaleSidKey),
                'languageLabel' => getLabelForValue(langOptions, u.LanguageLocaleKey),
                'timeZoneOptions' => tzOptions,
                'localeOptions' => localeOptions,
                'languageOptions' => langOptions
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error loading settings: ' + e.getMessage());
        }
    }

    private static List<Map<String, String>> getPicklistOptions(Schema.SObjectField field, String currentValue) {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Boolean currentIncluded = false;
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive() || entry.getValue() == currentValue) {
                options.add(new Map<String, String>{
                    'label' => entry.getLabel(),
                    'value' => entry.getValue()
                });
                if (entry.getValue() == currentValue) {
                    currentIncluded = true;
                }
            }
        }
        if (String.isNotBlank(currentValue) && !currentIncluded) {
            options.add(0, new Map<String, String>{
                'label' => currentValue,
                'value' => currentValue
            });
        }
        return options;
    }

    private static String getLabelForValue(List<Map<String, String>> options, String val) {
        if (val == null) return '';
        for (Map<String, String> opt : options) {
            if (opt.get('value') == val) return opt.get('label');
        }
        return val;
    }

    /**
     * @description LWC-callable method that updates a string setting (e.g. summary email frequency, timezone, locale).
     * @param fieldName Allowed User field (e.g. FIMBY_Summary_Emails__c, TimeZoneSidKey)
     * @param value New value
     * @return Map with success status
     */
    @AuraEnabled
    public static Map<String, Object> updateSettingsField(String fieldName, String value) {
        try {
            if (!ALLOWED_USER_STRING_FIELDS.contains(fieldName)) {
                throw new AuraHandledException('Field not allowed: ' + fieldName);
            }

            User u = new User(Id = UserInfo.getUserId());
            u.put(fieldName, value);
            new UserUpdater().doUpdate(u);

            return new Map<String, Object>{ 'success' => true };
        } catch (Exception e) {
            throw new AuraHandledException('Error updating setting: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that updates a boolean setting (push notifications, celebration toggles).
     * @param fieldName Allowed User boolean field (e.g. Push_Notifications_Enabled__c)
     * @param value New value
     * @return Map with success status
     */
    @AuraEnabled
    public static Map<String, Object> updateSettingsToggle(String fieldName, Boolean value) {
        try {
            if (!ALLOWED_USER_BOOLEAN_FIELDS.contains(fieldName)) {
                throw new AuraHandledException('Field not allowed: ' + fieldName);
            }

            User u = new User(Id = UserInfo.getUserId());
            u.put(fieldName, value);
            new UserUpdater().doUpdate(u);

            return new Map<String, Object>{ 'success' => true };
        } catch (Exception e) {
            throw new AuraHandledException('Error updating toggle: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that sends a password reset email to the current user.
     * @return Map with success and message
     */
    @AuraEnabled
    public static Map<String, Object> triggerPasswordReset() {
        try {
            System.resetPassword(UserInfo.getUserId(), true);
            return new Map<String, Object>{
                'success' => true,
                'message' => 'Password reset email sent to your registered email address.'
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error sending password reset: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that initiates in-app account deletion.
     * Default path: stamps Grace_Started_At__c=now (no Deactivation_Requested__c yet),
     * sends the delete-with-grace confirmation email containing a 30-day restore
     * magic link, and enqueues FimbyDeactivateUserQueueable to flip User.IsActive
     * immediately. FimbyGraceExpiryBatch flips Deactivation_Requested__c=true once
     * the grace window elapses, at which point the nightly scrub batch runs.
     *
     * skipGrace=true path: existing behaviour — sets Deactivation_Requested__c=true
     * immediately so tonight's scrub batch runs, no restore email. For neighbours
     * in urgent situations (abuse escape, harassment, crisis) who don't want their
     * data to linger 30 days.
     *
     * @param skipGrace If true, skip the 30-day grace and delete on tonight's batch.
     * @return Map with success and message
     */
    @AuraEnabled
    public static Map<String, Object> requestAccountDeletion(Boolean skipGrace) {
        try {
            Id realContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            if (realContactId == null) {
                throw new AuraHandledException('No contact associated with current user.');
            }

            // Account deletion is a legal action only the account-holder can take.
            // Supporters acting as someone else cannot delete that person's account
            // from the in-app flow; supportees who can't sign in directly use the
            // help@fimby.com paper-form pathway.
            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();
            if (actingAsContactId != null && actingAsContactId != realContactId) {
                throw new AuraHandledException(
                    'Switch back to your own identity to delete your account.'
                );
            }

            Id userId = UserInfo.getUserId();
            Boolean skip = (skipGrace == true);

            if (skip) {
                Contact c = new Contact(
                    Id = realContactId,
                    Deactivation_Requested__c = true,
                    Grace_Started_At__c = null
                );
                new ContactUpdater().doUpdate(c);
            } else {
                Contact c = new Contact(
                    Id = realContactId,
                    Grace_Started_At__c = System.now()
                );
                new ContactUpdater().doUpdate(c);

                FimbyReactivationEmailService.sendDeleteWithGraceConfirmation(
                    realContactId, userId);
            }

            System.enqueueJob(new FimbyDeactivateUserQueueable(userId));

            String msg = skip
                ? 'Your account has been deleted. You will be logged out shortly.'
                : 'Your account has been deactivated and is scheduled for deletion in 30 days. ' +
                  'Check your email for a restore link if you change your mind. ' +
                  'You will be logged out shortly.';

            return new Map<String, Object>{
                'success' => true,
                'message' => msg
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error requesting account deletion: ' + e.getMessage());
        }
    }

    /**
     * @description Back-compat shim for callers still on the old name. Routes to
     * the new graceful-default flow. New LWCs should call requestAccountDeletion
     * directly with an explicit skipGrace flag.
     */
    @AuraEnabled
    public static Map<String, Object> requestAccountDeactivation() {
        return requestAccountDeletion(false);
    }

    // User deactivation is now handled by FimbyDeactivateUserQueueable (Queueable + Finalizer).
    // The former @future method was removed per best-practices rule.

    /**
     * @description LWC-callable cacheable method that returns celebration flags and posting counts for first-time celebration detection.
     * @return Map with confettiEnabled, memesEnabled, posting counts, and first-celebration flags
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getCelebrationContext() {
        try {
            User u = [
                SELECT Celebration_Confetti_Enabled__c, Celebration_Memes_Enabled__c,
                       Last_App_Visit__c
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            String contactId = FimbyIdentityRepository.getActingAsContactId();
            Map<String, Object> result = new Map<String, Object>{
                'confettiEnabled' => u.Celebration_Confetti_Enabled__c,
                'memesEnabled' => u.Celebration_Memes_Enabled__c,
                'lastAppVisit' => u.Last_App_Visit__c
            };

            if (contactId != null) {
                Contact c = [
                    SELECT Need_Postings_For_Self__c, Offer_Postings_For_Self__c,
                           Responses_Posted__c, Stories_Posted__c, Library_Items_Posted__c,
                           Completed_Bulk_Buys__c,
                           First_Post_Celebrated__c, First_Response_Celebrated__c,
                           First_Library_Item_Celebrated__c, First_Story_Celebrated__c,
                           First_Bulk_Buy_Celebrated__c, First_Bulk_Buy_Reserve_Celebrated__c
                    FROM Contact
                    WHERE Id = :contactId
                    LIMIT 1
                ];
                result.put('needPostings', c.Need_Postings_For_Self__c);
                result.put('offerPostings', c.Offer_Postings_For_Self__c);
                result.put('responsesPosted', c.Responses_Posted__c);
                result.put('storiesPosted', c.Stories_Posted__c);
                result.put('libraryItemsPosted', c.Library_Items_Posted__c);
                result.put('completedBulkBuys', c.Completed_Bulk_Buys__c);
                result.put('firstPostCelebrated', c.First_Post_Celebrated__c);
                result.put('firstResponseCelebrated', c.First_Response_Celebrated__c);
                result.put('firstLibraryItemCelebrated', c.First_Library_Item_Celebrated__c);
                result.put('firstStoryCelebrated', c.First_Story_Celebrated__c);
                result.put('firstBulkBuyCelebrated', c.First_Bulk_Buy_Celebrated__c);
                result.put('firstBulkBuyReserveCelebrated', c.First_Bulk_Buy_Reserve_Celebrated__c);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading celebration context: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void markFirstCelebration(String fieldName) {
        try {
            if (!ALLOWED_FIRST_CELEBRATION_FIELDS.contains(fieldName)) {
                throw new AuraHandledException('Field not allowed: ' + fieldName);
            }
            String contactId = FimbyIdentityRepository.getActingAsContactId();
            if (contactId == null) {
                throw new AuraHandledException('No contact associated with current user.');
            }
            Contact c = new Contact(Id = contactId);
            c.put(fieldName, true);
            new ContactUpdater().doUpdate(c);
        } catch (Exception e) {
            throw new AuraHandledException('Error marking first celebration: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable cacheable method that returns the active seasonal theme from FimbyCacheService.
     * @return Map with seasonal theme data
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getActiveSeasonalTheme() {
        try {
            return FimbyCacheService.getSeasonalTheme();
        } catch (Exception e) {
            throw new AuraHandledException('Error checking seasonal theme: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable cacheable method that returns celebration action config from FimbyCacheService.
     * @return List of celebration action Maps
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCelebrationActions() {
        try {
            return FimbyCacheService.getCelebrationActions();
        } catch (Exception e) {
            throw new AuraHandledException('Error loading celebration actions: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable cacheable method that returns loading messages from FimbyCacheService.
     * @return List of loading message Maps
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getLoadingMessages() {
        try {
            return FimbyCacheService.getLoadingMessages();
        } catch (Exception e) {
            throw new AuraHandledException('Error loading messages: ' + e.getMessage());
        }
    }

    /**
     * @description Single cacheable call returning seasonal theme, celebration actions,
     * and loading messages. Replaces 3 separate @wire calls with one round-trip.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getUiMetadataBundle() {
        try {
            return new Map<String, Object>{
                'seasonalTheme' => FimbyCacheService.getSeasonalTheme(),
                'celebrationActions' => FimbyCacheService.getCelebrationActions(),
                'loadingMessages' => FimbyCacheService.getLoadingMessages()
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error loading UI metadata: ' + e.getMessage());
        }
    }

    /**
     * @description LWC-callable method that updates the current user's Last_App_Visit__c to now.
     */
    @AuraEnabled
    public static void updateLastAppVisit() {
        try {
            User u = new User(Id = UserInfo.getUserId(), Last_App_Visit__c = DateTime.now());
            new UserUpdater().doUpdate(u);
        } catch (Exception e) {
            // Non-critical -- silently fail
            FimbyLogger.warn('FimbyProfileController', 'updateLastAppVisit', e.getMessage());
        }
    }

    private without sharing class ContactUpdater {
        public void doUpdate(Contact c) {
            update c;
        }
    }

    /**
     * @description Without-sharing helper for User updates.
     */
    private without sharing class UserSettingsReader {
        public User getCurrentUserSettings() {
            List<User> rows = Database.queryWithBinds(
                'SELECT Id, Username,' +
                ' FIMBY_Summary_Emails__c,' +
                ' Push_Notifications_Enabled__c, Push_Messages__c,' +
                ' Push_Needs_Offers__c, Push_Library__c,' +
                ' Push_Stories__c, Push_Reminders__c, Push_Bulk_Buy__c,' +
                ' Push_Events__c,' +
                ' Quiet_Hours_Preference__c,' +
                ' Email_Alerts_Enabled__c, Email_Alert_Messages__c,' +
                ' Email_Alert_Needs_Offers__c, Email_Alert_Library__c,' +
                ' Email_Alert_Stories__c, Email_Alert_Reminders__c,' +
                ' Email_Alert_Bulk_Buy__c, Email_Alert_Events__c,' +
                ' Include_Sundays__c,' +
                ' FIMBY_Operating_Updates_Enabled__c,' +
                ' Celebration_Confetti_Enabled__c, Celebration_Memes_Enabled__c,' +
                ' TimeZoneSidKey, LocaleSidKey, LanguageLocaleKey,' +
                ' Theme_Preference__c' +
                ' FROM User WHERE Id = :userId LIMIT 1',
                new Map<String, Object>{ 'userId' => UserInfo.getUserId() },
                AccessLevel.SYSTEM_MODE
            );
            if (rows.isEmpty()) {
                throw new AuraHandledException('User record not found.');
            }
            return rows[0];
        }
    }

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
