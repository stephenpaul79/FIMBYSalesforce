/**
 * @description Controller for the Support Relationship / Logged In As framework.
 * Handles identity switching, relationship management, and the management page.
 */
public with sharing class FimbySupportRelationshipController {

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getAvailableIdentities() {
        try {
            Id myContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            if (myContactId == null) {
                return new List<Map<String, Object>>();
            }

            List<Support_Relationship__c> rels = [
                SELECT Id, Relationship_Type__c, Neighbourhood__c, Neighbourhood__r.Name,
                       Related_Contact__c, Related_Contact__r.Name, Related_Contact__r.Full_Name__c,
                       Related_Contact__r.Image_URL__c, Related_Contact__r.Display_Avatar_URL__c,
                       Related_Organization__c, Related_Organization__r.Name,
                       Related_Organization__r.Logo_URL__c, Related_Organization__r.Organization_Contact__c
                FROM Support_Relationship__c
                WHERE Contact__c = :myContactId
                  AND Status__c = 'Approved'
                ORDER BY Approved_Date__c DESC
            ];

            List<Map<String, Object>> identities = new List<Map<String, Object>>();
            for (Support_Relationship__c rel : rels) {
                Map<String, Object> identity = new Map<String, Object>();
                identity.put('relationshipId', rel.Id);
                identity.put('type', rel.Relationship_Type__c);
                identity.put('neighbourhoodName', rel.Neighbourhood__r.Name);
                identity.put('neighbourhoodId', rel.Neighbourhood__c);

                if (rel.Relationship_Type__c == 'Support_Person') {
                    identity.put('name', rel.Related_Contact__r.Full_Name__c);
                    identity.put('avatarUrl', rel.Related_Contact__r.Display_Avatar_URL__c);
                    identity.put('targetContactId', rel.Related_Contact__c);
                } else {
                    identity.put('name', rel.Related_Organization__r.Name);
                    identity.put('avatarUrl', rel.Related_Organization__r.Logo_URL__c);
                    identity.put('targetContactId', rel.Related_Organization__r.Organization_Contact__c);
                }
                identities.add(identity);
            }
            return identities;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading identities: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void switchIdentity(Id relationshipId) {
        try {
            User currentUser = FimbyIdentityRepository.getCurrentUser();
            if (currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact associated with current user');
            }

            Support_Relationship__c rel = [
                SELECT Id, Status__c, Contact__c, Related_Contact__c,
                       Related_Organization__c, Related_Organization__r.Organization_Contact__c,
                       Relationship_Type__c, Neighbourhood__c
                FROM Support_Relationship__c
                WHERE Id = :relationshipId
                  AND Contact__c = :currentUser.ContactId
                LIMIT 1
            ];

            if (rel.Status__c != 'Approved') {
                throw new AuraHandledException('This connection is not currently active.');
            }

            Id targetContactId;
            if (rel.Relationship_Type__c == 'Support_Person') {
                targetContactId = rel.Related_Contact__c;
            } else {
                targetContactId = rel.Related_Organization__r.Organization_Contact__c;
            }

            if (targetContactId == null) {
                throw new AuraHandledException('Unable to resolve the target identity.');
            }

            IdentityHelper helper = new IdentityHelper();
            helper.setIdentity(currentUser.ContactId, targetContactId, rel.Neighbourhood__c);

            FimbyIdentityRepository.clearCache();
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error switching identity: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void switchToSelf() {
        try {
            User currentUser = FimbyIdentityRepository.getCurrentUser();
            if (currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact associated with current user');
            }

            IdentityHelper helper = new IdentityHelper();
            helper.setIdentity(currentUser.ContactId, null, null);

            FimbyIdentityRepository.clearCache();
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error switching to self: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getManagedRelationships() {
        try {
            Id myContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            if (myContactId == null) {
                return new Map<String, Object>();
            }

            List<Support_Relationship__c> iSupport = [
                SELECT Id, Related_Contact__c, Related_Contact__r.Name,
                       Related_Contact__r.Image_URL__c, Status__c, Neighbourhood__c,
                       Neighbourhood__r.Name, Approved_Date__c, Ended_Date__c,
                       Subject_Confirmed__c
                FROM Support_Relationship__c
                WHERE Contact__c = :myContactId
                  AND Relationship_Type__c = 'Support_Person'
                  AND Dismissed_By_Helper__c = false
                ORDER BY Status__c ASC, Approved_Date__c DESC
            ];

            List<Support_Relationship__c> supportMe = [
                SELECT Id, Contact__c, Contact__r.Name, Contact__r.Image_URL__c,
                       Status__c, Neighbourhood__c, Neighbourhood__r.Name,
                       Approved_Date__c, Ended_Date__c,
                       Subject_Confirmed__c, Subject_Confirmed_Date__c
                FROM Support_Relationship__c
                WHERE Related_Contact__c = :myContactId
                  AND Relationship_Type__c = 'Support_Person'
                  AND Dismissed_By_Subject__c = false
                ORDER BY Status__c ASC, Approved_Date__c DESC
            ];

            List<Support_Relationship__c> myGroups = [
                SELECT Id, Related_Organization__c, Related_Organization__r.Name,
                       Related_Organization__r.Logo_URL__c, Status__c,
                       Neighbourhood__c, Neighbourhood__r.Name,
                       Approved_Date__c, Ended_Date__c
                FROM Support_Relationship__c
                WHERE Contact__c = :myContactId
                  AND Relationship_Type__c = 'Community_Group_Rep'
                  AND Dismissed_By_Helper__c = false
                ORDER BY Status__c ASC, Approved_Date__c DESC
            ];

            Set<Id> orgIds = new Set<Id>();
            for (Support_Relationship__c rel : myGroups) {
                if (rel.Related_Organization__c != null) {
                    orgIds.add(rel.Related_Organization__c);
                }
            }

            return new Map<String, Object>{
                'peopleISupport' => iSupport,
                'peopleWhoSupportMe' => supportMe,
                'communityGroups' => myGroups,
                'orgAvatarUrls' => new OrgAvatarHelper().getAvatarUrlsByOrgId(orgIds),
                'orgNames' => new OrgAvatarHelper().getNamesByOrgId(orgIds)
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error loading relationships: ' + e.getMessage());
        }
    }

    /**
     * @description Returns neighbourhoods the given organization is linked to via Community_Group_Neighbourhood__c.
     * Used when a user selects "Represent a community group" to choose which neighbourhood they will represent the org in.
     * Uses NeighbourhoodHelper (without sharing) so community users can see org-neighbourhood links for orgs they selected.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getNeighbourhoodsForOrganization(Id organizationId) {
        try {
            if (organizationId == null) {
                return new List<Map<String, String>>();
            }
            return new NeighbourhoodHelper().getNeighbourhoodsForOrg(organizationId);
        } catch (Exception e) {
            throw new AuraHandledException('Error loading neighbourhoods: ' + e.getMessage());
        }
    }

    /**
     * @description Uploads an authorization image linked to the Support_Relationship__c record.
     * Returns the file.force URL (ending in oid=) stored in Authorization_Image_URL__c.
     */
    @AuraEnabled
    public static String uploadAuthorizationImage(
        String fileData, String fileName, Id supportRelationshipId, Integer imageWidth, Integer imageHeight
    ) {
        try {
            if (supportRelationshipId == null) {
                throw new AuraHandledException('Support relationship Id is required.');
            }
            if (String.isBlank(fileData) || String.isBlank(fileName)) {
                throw new AuraHandledException('Missing file data or file name');
            }
            String url = FimbyContentDistributionHelper.uploadAndLink(
                fileData, fileName, supportRelationshipId
            );
            new RelationshipHelper().updateRelationship(new Support_Relationship__c(
                Id = supportRelationshipId,
                Authorization_Image_URL__c = url
            ));
            return url;
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error uploading image: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String uploadOrganizationVerificationDoc(
        String fileData, String fileName, Id accountId, Integer imageWidth, Integer imageHeight
    ) {
        return FimbyOrganizationRequestService.uploadOrganizationVerificationDoc(
            fileData, fileName, accountId, imageWidth, imageHeight
        );
    }

    @AuraEnabled
    public static Map<String, Object> createOrganizationRequest(Map<String, Object> params) {
        return FimbyOrganizationRequestService.createOrganizationRequest(params);
    }

    @AuraEnabled
    public static Id submitRelationshipRequest(Map<String, Object> params) {
        try {
            Id myContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            if (myContactId == null) {
                throw new AuraHandledException('No Contact associated with current user');
            }

            String relType = (String) params.get('relationshipType');
            Id relatedContactId = (Id) params.get('relatedContactId');
            Id relatedOrgId = (Id) params.get('relatedOrganizationId');
            Id neighbourhoodId = (Id) params.get('neighbourhoodId');
            String authImageUrl = (String) params.get('authorizationImageUrl');
            String authImageData = (String) params.get('authorizationImageData');
            String authImageFileName = (String) params.get('authorizationImageFileName');
            String notes = (String) params.get('notes');
            Object cgaAcceptedRaw = params.get('cgaAccepted');
            Boolean cgaAccepted = (cgaAcceptedRaw instanceof Boolean) ? (Boolean) cgaAcceptedRaw : false;
            String cgaVersion = (String) params.get('cgaVersion');

            if (relType == 'Community_Group_Rep') {
                if (relatedOrgId == null) {
                    throw new AuraHandledException('A community group selection is required.');
                }
                if (cgaAccepted != true) {
                    throw new AuraHandledException('Please confirm you have read and agree to the Community Group Agreement.');
                }
            }

            Support_Relationship__c rel = new Support_Relationship__c(
                Contact__c = myContactId,
                Relationship_Type__c = relType,
                Related_Contact__c = relatedContactId,
                Related_Organization__c = relatedOrgId,
                Neighbourhood__c = neighbourhoodId,
                Notes__c = notes,
                Status__c = 'Pending'
            );

            new RelationshipHelper().insertRelationship(rel);

            if (String.isNotBlank(authImageData) && String.isNotBlank(authImageFileName)) {
                String url = FimbyContentDistributionHelper.uploadAndLink(
                    authImageData, authImageFileName, rel.Id
                );
                new RelationshipHelper().updateRelationship(new Support_Relationship__c(
                    Id = rel.Id,
                    Authorization_Image_URL__c = url
                ));
            } else if (String.isNotBlank(authImageUrl)) {
                new RelationshipHelper().updateRelationship(new Support_Relationship__c(
                    Id = rel.Id,
                    Authorization_Image_URL__c = authImageUrl
                ));
            }

            if (relType == 'Community_Group_Rep' && relatedOrgId != null) {
                FimbyTosController.acceptCga(relatedOrgId, cgaVersion);
            }

            if (relType == 'Support_Person' && relatedContactId != null) {
                createRelationshipNotification(
                    relatedContactId,
                    'Relationship_Request',
                    FimbyIdentityRepository.getCurrentContact().Name + ' offered to support you',
                    'We\'re checking in with the neighbourhood team.',
                    rel.Id,
                    'Support_Relationship__c',
                    FimbySettings.getUrl('Manage_Identities'),
                    'care'
                );
            }

            return rel.Id;
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error submitting request: ' + e.getMessage());
        }
    }

    /**
     * @description Wrapper around supportee identifier inputs for the paper-form path.
     * The LWC builds this client-side from the identifier-collection step; Apex
     * uses it to create a draft Contact + draft Support_Relationship__c.
     */
    public class PaperDraftInput {
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public Date birthdate;
        @AuraEnabled public String mailingStreet;
        @AuraEnabled public String mailingCity;
        @AuraEnabled public String mailingPostalCode;
        @AuraEnabled public String mailingState;
        @AuraEnabled public String phone;
        @AuraEnabled public String email;
        @AuraEnabled public String supporteeRelationship;
        @AuraEnabled public String notes;
    }

    /**
     * @description Step one of the paper-form path. Creates a draft Contact
     * holding supportee identifiers, plus a Support_Relationship__c with
     * Status = Draft, then dispatches the Day-0 email (PDF attachment + deep
     * link). Returns the SR Id so the LWC can route to the email-sent
     * confirmation screen.
     *
     * Identifiers are stored on the Contact using standard fields (FirstName,
     * LastName, Birthdate, Mailing*, Phone, Email) per the architecture rule —
     * no new Contact fields are added for paper-form data.
     */
    @AuraEnabled
    public static Id createPaperDraft(PaperDraftInput input) {
        try {
            if (input == null) {
                throw new AuraHandledException('Supportee details are required.');
            }
            if (String.isBlank(input.firstName) || String.isBlank(input.lastName)) {
                throw new AuraHandledException('Please provide the supportee first and last name.');
            }

            User currentUser = FimbyIdentityRepository.getCurrentUser();
            if (currentUser == null || currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact associated with current user');
            }
            Id supporterContactId = currentUser.ContactId;
            Id neighbourhoodId = resolveSupporterNeighbourhoodId(supporterContactId);
            if (neighbourhoodId == null) {
                throw new AuraHandledException('Could not determine your neighbourhood. Please contact support.');
            }

            Contact draft = new Contact(
                FirstName = input.firstName,
                LastName = input.lastName,
                Birthdate = input.birthdate,
                MailingStreet = input.mailingStreet,
                MailingCity = input.mailingCity,
                MailingPostalCode = input.mailingPostalCode,
                MailingState = String.isNotBlank(input.mailingState) ? input.mailingState : 'BC',
                Phone = input.phone,
                Email = input.email,
                AccountId = neighbourhoodId
            );

            new PaperDraftHelper().insertDraftContact(draft);

            Support_Relationship__c rel = new Support_Relationship__c(
                Contact__c = supporterContactId,
                Relationship_Type__c = 'Support_Person',
                Related_Contact__c = draft.Id,
                Neighbourhood__c = neighbourhoodId,
                Notes__c = input.notes,
                Supportee_Relationship__c = input.supporteeRelationship,
                Status__c = 'Draft',
                Consent_Method__c = 'Written'
            );
            new RelationshipHelper().insertRelationship(rel);

            try {
                FimbySupportRelationshipEmailService.sendDay0Email(rel.Id);
            } catch (Exception emailErr) {
                FimbyLogger.error('FimbySupportRelationshipController', 'createPaperDraft.sendDay0Email', emailErr);
            }

            return rel.Id;
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            FimbyLogger.error('FimbySupportRelationshipController', 'createPaperDraft', e);
            AuraHandledException ah = new AuraHandledException('Error creating paper draft: ' + e.getMessage());
            ah.setMessage('Error creating paper draft: ' + e.getMessage());
            throw ah;
        }
    }

    /**
     * @description Step two of the paper-form path. Links the uploaded scan
     * (already inserted as ContentVersion) to the Support_Relationship__c
     * record and flips Status from Draft to Pending Paper Review. Idempotent:
     * if the SR is no longer a Draft, the call is a no-op.
     */
    @AuraEnabled
    public static void submitPaperUpload(Id srId, Id contentVersionId) {
        try {
            if (srId == null) {
                throw new AuraHandledException('Support relationship Id is required.');
            }
            if (contentVersionId == null) {
                throw new AuraHandledException('Please attach the signed form before submitting.');
            }

            User currentUser = FimbyIdentityRepository.getCurrentUser();
            if (currentUser == null || currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact associated with current user');
            }

            new PaperDraftHelper().linkScanAndAdvance(srId, contentVersionId, currentUser.ContactId);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error submitting paper form: ' + e.getMessage());
        }
    }

    /**
     * @description Returns the supporter's draft + active paper-form
     * relationships for the My Stuff "Your support relationships" list.
     * Drafts and pending-review rows are the primary backup re-entry path
     * for supporters who lost the Day-0 email.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getMyPaperRelationships() {
        try {
            Id myContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            if (myContactId == null) {
                return new List<Map<String, Object>>();
            }
            List<Support_Relationship__c> rels = [
                SELECT Id, Status__c, Day0_Email_Sent_Date__c,
                       Last_Reminder_Sent_Date__c, Approved_Date__c, Ended_Date__c,
                       Related_Contact__c, Related_Contact__r.Name, Related_Contact__r.Full_Name__c,
                       Related_Contact__r.MailingCity,
                       Supportee_Relationship__c
                FROM Support_Relationship__c
                WHERE Contact__c = :myContactId
                  AND Relationship_Type__c = 'Support_Person'
                  AND Status__c IN ('Draft', 'Pending Paper Review',
                                    'Pending Verification', 'Approved',
                                    'Rejected', 'Expired')
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];

            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            for (Support_Relationship__c r : rels) {
                rows.add(new Map<String, Object>{
                    'id' => r.Id,
                    'status' => r.Status__c,
                    'supporteeName' => r.Related_Contact__r != null ? r.Related_Contact__r.Full_Name__c : 'Pending',
                    'supporteeCity' => r.Related_Contact__r?.MailingCity,
                    'supporteeRelationship' => r.Supportee_Relationship__c,
                    'day0Sent' => r.Day0_Email_Sent_Date__c,
                    'lastReminderSent' => r.Last_Reminder_Sent_Date__c,
                    'approvedDate' => r.Approved_Date__c,
                    'endedDate' => r.Ended_Date__c
                });
            }
            return rows;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading paper relationships: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void revokeRelationship(Id relationshipId) {
        try {
            Id myContactId = FimbyIdentityRepository.getCurrentUser().ContactId;

            Support_Relationship__c rel = [
                SELECT Id, Status__c, Contact__c, Contact__r.Name,
                       Related_Contact__c, Related_Contact__r.Name, Related_Contact__r.Full_Name__c,
                       Contact__r.Logged_In_As_Contact__c
                FROM Support_Relationship__c
                WHERE Id = :relationshipId
                LIMIT 1
            ];

            if (rel.Status__c != 'Approved') {
                throw new AuraHandledException('This connection is not currently active.');
            }

            rel.Status__c = 'Revoked';
            rel.Ended_By__c = myContactId;
            rel.Ended_Date__c = DateTime.now();
            new RelationshipHelper().updateRelationship(rel);

            if (rel.Contact__r.Logged_In_As_Contact__c == rel.Related_Contact__c) {
                IdentityHelper helper = new IdentityHelper();
                helper.setIdentity(rel.Contact__c, null, null);
            }

            createRelationshipNotification(
                rel.Contact__c,
                'Relationship_Revoked',
                rel.Related_Contact__r.Full_Name__c + ' updated their support preferences',
                '',
                rel.Id,
                'Support_Relationship__c',
                FimbySettings.getUrl('Manage_Identities'),
                'care'
            );
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error revoking access: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deactivateRelationship(Id relationshipId) {
        try {
            Id myContactId = FimbyIdentityRepository.getCurrentUser().ContactId;

            Support_Relationship__c rel = [
                SELECT Id, Status__c, Contact__c, Related_Contact__c,
                       Related_Contact__r.Name, Related_Organization__c,
                       Related_Organization__r.Name, Relationship_Type__c,
                       Approved_By__c
                FROM Support_Relationship__c
                WHERE Id = :relationshipId
                  AND Contact__c = :myContactId
                LIMIT 1
            ];

            if (rel.Status__c != 'Approved') {
                throw new AuraHandledException('This connection is not currently active.');
            }

            rel.Status__c = 'Inactive';
            rel.Ended_By__c = myContactId;
            rel.Ended_Date__c = DateTime.now();
            new RelationshipHelper().updateRelationship(rel);

            IdentityHelper helper = new IdentityHelper();
            helper.setIdentity(myContactId, null, null);
            FimbyIdentityRepository.clearCache();

            Id recipientId;
            String message;
            if (rel.Relationship_Type__c == 'Support_Person') {
                recipientId = rel.Related_Contact__c;
                message = FimbyIdentityRepository.getCurrentContact().Name +
                    ' has stepped back from supporting you. Your account and content are unchanged.';
            } else {
                recipientId = rel.Approved_By__c;
                message = FimbyIdentityRepository.getCurrentContact().Name +
                    ' is no longer representing ' + rel.Related_Organization__r.Name + '.';
            }

            if (recipientId != null) {
                createRelationshipNotification(
                    recipientId,
                    'Relationship_Deactivated',
                    'Support relationship updated',
                    message,
                    rel.Id,
                    'Support_Relationship__c',
                    FimbySettings.getUrl('Manage_Identities'),
                    'care'
                );
            }
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException('Error stepping back: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void dismissRelationship(Id relationshipId, String viewerSide) {
        try {
            Support_Relationship__c rel = new Support_Relationship__c(Id = relationshipId);
            if (viewerSide == 'subject') {
                rel.Dismissed_By_Subject__c = true;
            } else {
                rel.Dismissed_By_Helper__c = true;
            }
            new RelationshipHelper().updateRelationship(rel);
        } catch (Exception e) {
            throw new AuraHandledException('Error dismissing: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void confirmRelationship(Id relationshipId) {
        try {
            Support_Relationship__c rel = new Support_Relationship__c(
                Id = relationshipId,
                Subject_Confirmed__c = true,
                Subject_Confirmed_Date__c = DateTime.now(),
                Consent_Method__c = 'In_App'
            );
            new RelationshipHelper().updateRelationship(rel);
        } catch (Exception e) {
            throw new AuraHandledException('Error confirming: ' + e.getMessage());
        }
    }

    /**
     * @description Filed by an approved Community Group representative who
     * wants the group's neighbourhood presence closed or deleted. Per the
     * prelaunch product alignment plan A2, this never mutates the
     * organization Account directly from the LWC path. Instead, it creates
     * a Moderator_Task__c (Category = Community_Group_Lifecycle) so a
     * moderator/admin can review and apply the change consistently with
     * neighbour-facing notice obligations (Terms section 23).
     *
     * Authorization: only the requesting helper Contact (the running user's
     * realContactId) can file a task for a Support_Relationship__c they own,
     * and only when that relationship is an Approved Community_Group_Rep.
     * @param relationshipId Support_Relationship__c whose Related_Organization__c is the group.
     * @param action 'Close' or 'Delete'. Anything else is rejected.
     * @param reason Optional free-text context the rep wants to include.
     */
    @AuraEnabled
    public static void requestCommunityGroupLifecycleAction(
        Id relationshipId, String action, String reason
    ) {
        try {
            if (relationshipId == null) {
                throw new AuraHandledException('Relationship Id is required.');
            }
            String normalized = (action == null) ? '' : action.trim();
            if (normalized != 'Close' && normalized != 'Delete') {
                throw new AuraHandledException(
                    'Unsupported action. Allowed values are Close or Delete.');
            }

            User currentUser = FimbyIdentityRepository.getCurrentUser();
            if (currentUser == null || currentUser.ContactId == null) {
                throw new AuraHandledException('No Contact associated with current user.');
            }

            Support_Relationship__c rel = [
                SELECT Id, Status__c, Relationship_Type__c, Contact__c,
                       Contact__r.Name, Contact__r.Full_Name__c,
                       Related_Organization__c, Related_Organization__r.Name,
                       Neighbourhood__c
                FROM Support_Relationship__c
                WHERE Id = :relationshipId
                LIMIT 1
            ];

            if (rel.Contact__c != currentUser.ContactId) {
                throw new AuraHandledException(
                    'You can only request lifecycle actions for groups you represent.');
            }
            if (rel.Relationship_Type__c != 'Community_Group_Rep') {
                throw new AuraHandledException(
                    'This action is only available for Community Group representatives.');
            }
            if (rel.Status__c != 'Approved') {
                throw new AuraHandledException(
                    'Only an active (Approved) representative can request this.');
            }
            if (rel.Related_Organization__c == null) {
                throw new AuraHandledException(
                    'This relationship has no group on file. Contact help@fimby.com.');
            }

            String groupName = (rel.Related_Organization__r != null
                ? rel.Related_Organization__r.Name : 'this group');
            String repName = (rel.Contact__r != null
                ? rel.Contact__r.Name : 'a representative');

            FimbyModeratorTaskService.TaskRequest req = new FimbyModeratorTaskService.TaskRequest();
            req.neighbourhoodId = rel.Neighbourhood__c;
            req.category = 'Community_Group_Lifecycle';
            // Lifecycle requests are operator-reviewed; default Standard is fine.
            // FimbyModeratorTaskService normalises null to 'Standard' too.
            req.priority = 'Standard';
            // Subject_Contact__c is a Contact lookup. The "subject" of this
            // task is the human filing the request — the moderator can see
            // who asked for the change. The group itself is captured below
            // via Related_Record_*.
            req.subjectContactId = currentUser.ContactId;
            req.relatedRecordId = String.valueOf(rel.Related_Organization__c);
            req.relatedRecordType = 'Account';
            req.summary = (normalized == 'Close' ? 'Close group: ' : 'Delete group: ')
                + groupName + ' \u2014 requested by ' + repName;
            // sourceType 'Lifecycle_Request' makes this distinguishable from
            // user-content reports in the Moderator dashboard. The dedup key
            // built by FimbyModeratorTaskService keys off neighbourhood +
            // category + relatedRecordId, so a duplicate request from the
            // same rep folds into the same open task instead of spawning a
            // new one.
            req.sourceType = 'Lifecycle_Request';
            req.reasonCode = normalized;
            req.details = String.isNotBlank(reason) ? reason : null;
            req.reporterContactId = currentUser.ContactId;

            new ModeratorTaskBridge().fileLifecycleTask(req);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error filing the request: ' + e.getMessage());
        }
    }

    /**
     * @description Without-sharing bridge so a Customer Community supporter
     * can file a moderator task without holding direct CRUD on
     * Moderator_Task__c. FimbyModeratorTaskService is itself without sharing,
     * but reaching it from the @AuraEnabled context above goes through this
     * helper to keep the elevated DML pattern explicit and consistent with
     * the other inner helpers in this controller.
     */
    private without sharing class ModeratorTaskBridge {
        public void fileLifecycleTask(FimbyModeratorTaskService.TaskRequest req) {
            FimbyModeratorTaskService.createOrUpdateTask(req);
        }
    }

    private static void createRelationshipNotification(
        Id recipientContactId,
        String type,
        String title,
        String body,
        Id relatedRecordId,
        String relatedRecordType,
        String actionUrl,
        String actorIcon
    ) {
        try {
            FimbyNotificationService.createNotification(
                recipientContactId,
                type,
                title,
                body,
                relatedRecordId,
                relatedRecordType,
                actionUrl,
                actorIcon
            );
        } catch (Exception e) {
            FimbyLogger.error('FimbySupportRelationshipController', 'createRelationshipNotification', e);
        }
    }

    /**
     * @description Resolves the supporter's home neighbourhood Id. Prefers
     * Contact.AccountId when it points to a Boundary_Account (the canonical
     * neighbourhood RecordType). Falls back to the first Boundary_Account
     * accessible to the running user when NPSP has reparented the Contact
     * to a Household Account in test contexts.
     */
    @TestVisible
    private static Id resolveSupporterNeighbourhoodId(Id supporterContactId) {
        if (supporterContactId == null) return null;
        return new NeighbourhoodResolverHelper().resolve(supporterContactId);
    }

    private without sharing class NeighbourhoodResolverHelper {
        public Id resolve(Id supporterContactId) {
            List<Contact> rows = [
                SELECT Id, AccountId, Account.RecordType.DeveloperName
                FROM Contact
                WHERE Id = :supporterContactId
                LIMIT 1
            ];
            if (!rows.isEmpty()
                    && rows[0].AccountId != null
                    && rows[0].Account.RecordType.DeveloperName == 'Boundary_Account') {
                return rows[0].AccountId;
            }
            List<Account> fallback = [
                SELECT Id FROM Account
                WHERE RecordType.DeveloperName = 'Boundary_Account'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            return fallback.isEmpty() ? null : fallback[0].Id;
        }
    }

    private without sharing class NeighbourhoodHelper {
        public List<Map<String, String>> getNeighbourhoodsForOrg(Id organizationId) {
            List<Community_Group_Neighbourhood__c> links = [
                SELECT Neighbourhood__c, Neighbourhood__r.Name
                FROM Community_Group_Neighbourhood__c
                WHERE Organization__c = :organizationId
                  AND Status__c = 'Active'
                ORDER BY Neighbourhood__r.Name
            ];
            List<Map<String, String>> options = new List<Map<String, String>>();
            for (Community_Group_Neighbourhood__c link : links) {
                if (link.Neighbourhood__c != null) {
                    options.add(new Map<String, String>{
                        'id' => link.Neighbourhood__c,
                        'name' => link.Neighbourhood__r?.Name ?? 'Unknown'
                    });
                }
            }
            return options;
        }
    }

    private without sharing class IdentityHelper {
        public void setIdentity(Id contactId, Id targetContactId, Id neighbourhoodId) {
            Contact c = new Contact(
                Id = contactId,
                Logged_In_As_Contact__c = targetContactId,
                Logged_In_As_Neighbourhood__c = neighbourhoodId
            );
            update c;
        }
    }

    private without sharing class RelationshipHelper {
        public Id insertRelationship(Support_Relationship__c rel) {
            insert rel;
            return rel.Id;
        }
        public void updateRelationship(Support_Relationship__c rel) {
            update rel;
        }
    }

    /**
     * Resolves org avatars the same way FimbyHomeController does for feed cards:
     * Account.Logo_URL__c first, then Organization_Contact__r.Image_URL__c.
     * Without sharing so community users see logos set on the org Account.
     */
    private without sharing class OrgAvatarHelper {
        public Map<String, String> getAvatarUrlsByOrgId(Set<Id> orgIds) {
            Map<String, String> result = new Map<String, String>();
            if (orgIds == null || orgIds.isEmpty()) {
                return result;
            }
            for (Account org : [
                SELECT Id, Logo_URL__c, Organization_Contact__r.Image_URL__c
                FROM Account
                WHERE Id IN :orgIds
            ]) {
                String avatarUrl = resolveOrgAvatarUrl(org);
                if (String.isNotBlank(avatarUrl)) {
                    result.put(String.valueOf(org.Id), avatarUrl);
                }
            }
            return result;
        }

        /** Pending org Accounts are not shared to community users; resolve names in system context. */
        public Map<String, String> getNamesByOrgId(Set<Id> orgIds) {
            Map<String, String> result = new Map<String, String>();
            if (orgIds == null || orgIds.isEmpty()) {
                return result;
            }
            for (Account org : [
                SELECT Id, Name
                FROM Account
                WHERE Id IN :orgIds
            ]) {
                if (String.isNotBlank(org.Name)) {
                    result.put(String.valueOf(org.Id), org.Name);
                }
            }
            return result;
        }
    }

    private static String resolveOrgAvatarUrl(Account org) {
        if (org == null) {
            return null;
        }
        if (String.isNotBlank(org.Logo_URL__c)) {
            return org.Logo_URL__c;
        }
        return org.Organization_Contact__r?.Image_URL__c;
    }

    /**
     * @description Without-sharing helper for the paper-form path. Supporters
     * are Customer Community users who would normally not be able to insert a
     * Contact or link a ContentDocument to another record; the elevated context
     * lets them create the supportee draft and attach the signed-form upload.
     */
    private without sharing class PaperDraftHelper {
        public void insertDraftContact(Contact draft) {
            insert draft;
        }

        public void linkScanAndAdvance(Id srId, Id contentVersionId, Id supporterContactId) {
            Support_Relationship__c rel = [
                SELECT Id, Status__c, Contact__c, Related_Contact__c
                FROM Support_Relationship__c
                WHERE Id = :srId
                LIMIT 1
            ];
            if (rel.Contact__c != supporterContactId) {
                throw new AuraHandledException('You can only submit your own paper forms.');
            }
            if (rel.Status__c != 'Draft') {
                return;
            }

            ContentVersion cv = [
                SELECT Id, ContentDocumentId
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];

            Boolean alreadyLinked = ![
                SELECT Id FROM ContentDocumentLink
                WHERE ContentDocumentId = :cv.ContentDocumentId
                  AND LinkedEntityId = :rel.Id
                LIMIT 1
            ].isEmpty();
            if (!alreadyLinked) {
                ContentDocumentLink cdl = new ContentDocumentLink(
                    ContentDocumentId = cv.ContentDocumentId,
                    LinkedEntityId = rel.Id,
                    ShareType = 'V',
                    Visibility = 'AllUsers'
                );
                insert cdl;
            }

            rel.Status__c = 'Pending Paper Review';
            rel.Signed_Date__c = Date.today();
            update rel;
        }
    }
}
