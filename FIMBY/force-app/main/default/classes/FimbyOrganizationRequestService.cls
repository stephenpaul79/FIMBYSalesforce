/**
 * @description Self-service community group org creation and verification uploads.
 * Runs without sharing with system-mode Account DML so community users can submit
 * pending organizations for moderator review.
 */
public without sharing class FimbyOrganizationRequestService {

    @AuraEnabled
    public static String uploadOrganizationVerificationDoc(
        String fileData, String fileName, Id accountId, Integer imageWidth, Integer imageHeight
    ) {
        try {
            if (accountId == null) {
                throw handledException('Organization Id is required.');
            }
            if (String.isBlank(fileData) || String.isBlank(fileName)) {
                throw handledException('Missing file data or file name');
            }
            String url = FimbyContentDistributionHelper.uploadAndLink(fileData, fileName, accountId);
            update new Account(
                Id = accountId,
                Verification_Document_URL__c = url
            );
            return 'ok';
        } catch (AuraHandledException ae) {
            if (String.isNotBlank(ae.getMessage()) && ae.getMessage() != 'Script-thrown exception') {
                throw ae;
            }
            throw handledException('Error uploading verification document.');
        } catch (Exception e) {
            throw handledException('Error uploading verification document: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Map<String, Object> createOrganizationRequest(Map<String, Object> params) {
        try {
            Id myContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            if (myContactId == null) {
                throw handledException('No Contact associated with current user');
            }

            String orgName = trimParam(params, 'orgName');
            String billingStreet = trimParam(params, 'billingStreet');
            String billingCity = trimParam(params, 'billingCity');
            String billingState = trimParam(params, 'billingState');
            String billingPostalCode = trimParam(params, 'billingPostalCode');
            String billingCountry = trimParam(params, 'billingCountry');
            String orgType = trimParam(params, 'orgType');
            String requesterOrgRole = trimParam(params, 'requesterOrgRole');
            String authImageUrl = trimParam(params, 'authorizationImageUrl');
            String authImageData = trimParam(params, 'authorizationImageData');
            String authImageFileName = trimParam(params, 'authorizationImageFileName');
            String notes = trimParam(params, 'notes');
            String website = trimParam(params, 'website');
            String description = trimParam(params, 'description');
            String orgPhone = trimParam(params, 'orgPhone');
            String orgEmail = trimParam(params, 'orgEmail');
            String charityUrl = trimParam(params, 'charityVerificationUrl');
            String charityNumber = trimParam(params, 'charityRegistrationNumber');
            String verificationDocData = trimParam(params, 'verificationDocData');
            String verificationDocFileName = trimParam(params, 'verificationDocFileName');
            String cgaVersion = trimParam(params, 'cgaVersion');
            Object cgaAcceptedRaw = params.get('cgaAccepted');
            Boolean cgaAccepted = (cgaAcceptedRaw instanceof Boolean) ? (Boolean) cgaAcceptedRaw : false;
            Object isCharityRaw = params.get('isRegisteredCharity');
            Boolean isRegisteredCharity = (isCharityRaw instanceof Boolean) ? (Boolean) isCharityRaw : false;

            validateOrganizationRequestInputs(
                orgName, billingPostalCode, orgType, requesterOrgRole, cgaAccepted,
                isRegisteredCharity, charityUrl, charityNumber, orgPhone, orgEmail,
                verificationDocData
            );

            Id neighbourhoodId = resolveNeighbourhoodFromPostalCode(billingPostalCode);

            List<String> verificationMethods = buildVerificationMethods(
                isRegisteredCharity, charityUrl, charityNumber, orgPhone, orgEmail, verificationDocData
            );

            Id orgRtId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization').getRecordTypeId();

            OrganizationRequestHelper helper = new OrganizationRequestHelper();
            Id orgOwnerId = helper.resolveOrganizationOwnerId(neighbourhoodId);

            Account org = new Account(
                Name = orgName,
                RecordTypeId = orgRtId,
                OwnerId = orgOwnerId,
                Type = orgType,
                BillingStreet = billingStreet,
                BillingCity = billingCity,
                BillingState = String.isNotBlank(billingState) ? billingState : 'BC',
                BillingPostalCode = billingPostalCode,
                BillingCountry = String.isNotBlank(billingCountry) ? billingCountry : 'Canada',
                Phone = orgPhone,
                Org_Email__c = String.isNotBlank(orgEmail) ? orgEmail : null,
                Website = website,
                Description = description,
                Is_Approved_Community_Group__c = false,
                Verification_Status__c = 'Pending',
                Is_Registered_Charity__c = isRegisteredCharity,
                Charity_Verification_URL__c = isRegisteredCharity ? charityUrl : null,
                Charity_Registration_Number__c = isRegisteredCharity ? charityNumber : null,
                Verification_Method__c = String.join(verificationMethods, ';'),
                Submitted_By__c = myContactId,
                Submitted_Date__c = Datetime.now()
            );

            Id accountId;
            try {
                accountId = helper.insertAccount(org);
            } catch (Exception ex) {
                throw handledException('insertAccount failed: ' + ex.getMessage());
            }

            Community_Group_Neighbourhood__c junction = new Community_Group_Neighbourhood__c(
                Organization__c = accountId,
                Neighbourhood__c = neighbourhoodId,
                Status__c = 'Inactive',
                Is_Primary__c = false
            );
            try {
                helper.insertJunction(junction);
            } catch (Exception ex) {
                throw handledException('insertJunction failed: ' + ex.getMessage());
            }

            Support_Relationship__c rel = new Support_Relationship__c(
                Contact__c = myContactId,
                Relationship_Type__c = 'Community_Group_Rep',
                Related_Organization__c = accountId,
                Neighbourhood__c = neighbourhoodId,
                Notes__c = notes,
                Requester_Org_Role__c = requesterOrgRole,
                Status__c = 'Pending'
            );
            Id srId;
            try {
                srId = helper.insertRelationship(rel);
            } catch (Exception srErr) {
                throw handledException(
                    'Error creating representative request: ' + srErr.getMessage());
            }

            stampAuthorizationImage(srId, authImageData, authImageFileName, authImageUrl);

            try {
                helper.stampCga(accountId, cgaVersion, myContactId);
            } catch (Exception ex) {
                throw handledException('stampCga failed: ' + ex.getMessage());
            }

            stampVerificationDocument(accountId, verificationDocData, verificationDocFileName);

            FimbyModeratorTaskService.TaskRequest orgTask = new FimbyModeratorTaskService.TaskRequest();
            orgTask.neighbourhoodId = neighbourhoodId;
            orgTask.category = 'Organization_Approval';
            orgTask.priority = 'Standard';
            orgTask.subjectContactId = myContactId;
            orgTask.relatedRecordId = String.valueOf(accountId);
            orgTask.relatedRecordType = 'Account';
            orgTask.summary = 'New organization: ' + orgName;
            orgTask.sourceType = 'Lifecycle_Request';
            orgTask.sourceRecordId = String.valueOf(srId);
            orgTask.reporterContactId = myContactId;
            List<String> detailLines = new List<String>{ 'Requester role: ' + requesterOrgRole };
            if (String.isNotBlank(orgEmail)) {
                detailLines.add('Org email: ' + orgEmail);
            }
            orgTask.details = String.join(detailLines, '\n');
            try {
                helper.fileOrgApprovalTask(orgTask);
            } catch (Exception taskErr) {
                FimbyLogger.error('FimbyOrganizationRequestService', 'createOrganizationRequest.orgTask', taskErr);
                throw handledException(
                    'Error filing organization review task: ' + taskErr.getMessage());
            }

            return new Map<String, Object>{
                'accountId' => accountId,
                'supportRelationshipId' => srId
            };
        } catch (AuraHandledException ae) {
            if (String.isNotBlank(ae.getMessage()) && ae.getMessage() != 'Script-thrown exception') {
                throw ae;
            }
            throw handledException('Organization request failed.');
        } catch (Exception e) {
            FimbyLogger.error('FimbyOrganizationRequestService', 'createOrganizationRequest', e);
            throw handledException(
                'Error submitting organization request: ' + e.getTypeName() + ': ' + e.getMessage());
        }
    }

    private static String trimParam(Map<String, Object> params, String key) {
        Object raw = params.get(key);
        return raw == null ? null : String.valueOf(raw).trim();
    }

    private static AuraHandledException handledException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    @TestVisible
    static Id resolveNeighbourhoodFromPostalCode(String postalCode) {
        FimbyPostalResolver.Result result = FimbyPostalResolver.resolveSingle(postalCode);
        if (result == null || result.isMatchFound != true) {
            throw handledException(
                'We don\'t recognize that postal code. FIMBY may not be active in that area yet.');
        }
        if (result.isActiveNeighbourhood != true || result.neighbourhoodAccountId == null) {
            throw handledException(
                'FIMBY isn\'t open in that neighbourhood yet. Check back soon, or contact us for help.');
        }
        return result.neighbourhoodAccountId;
    }

    @TestVisible
    static void validateOrganizationRequestInputs(
        String orgName,
        String billingPostalCode,
        String orgType,
        String requesterOrgRole,
        Boolean cgaAccepted,
        Boolean isRegisteredCharity,
        String charityUrl,
        String charityNumber,
        String orgPhone,
        String orgEmail,
        String verificationDocData
    ) {
        if (String.isBlank(orgName)) {
            throw handledException('Organization name is required.');
        }
        if (String.isBlank(billingPostalCode)) {
            throw handledException('Postal code is required.');
        }
        if (String.isBlank(orgType)) {
            throw handledException('Organization type is required.');
        }
        if (String.isBlank(requesterOrgRole)) {
            throw handledException('Your role at the organization is required.');
        }
        if (cgaAccepted != true) {
            throw handledException('Please confirm you have read and agree to the Community Group Agreement.');
        }
        if (isRegisteredCharity == true) {
            if (String.isBlank(charityUrl) && String.isBlank(charityNumber)) {
                throw handledException(
                    'Registered charities need a CRA charity listing URL or registration number.');
            }
        } else {
            Boolean hasDoc = String.isNotBlank(verificationDocData);
            Boolean hasPhone = String.isNotBlank(orgPhone);
            Boolean hasEmail = String.isNotBlank(orgEmail);
            if (!(hasDoc || hasPhone || hasEmail)) {
                throw handledException(
                    'Please provide at least one way to verify your group: a document, phone number, or email.');
            }
        }
    }

    @TestVisible
    static List<String> buildVerificationMethods(
        Boolean isRegisteredCharity,
        String charityUrl,
        String charityNumber,
        String orgPhone,
        String orgEmail,
        String verificationDocData
    ) {
        List<String> methods = new List<String>();
        if (isRegisteredCharity == true) {
            if (String.isNotBlank(charityUrl)) {
                methods.add('CRA_URL');
            }
            if (String.isNotBlank(charityNumber)) {
                methods.add('Charity_Registration_Number');
            }
        }
        if (String.isNotBlank(verificationDocData)) {
            methods.add('Uploaded_Document');
        }
        if (String.isNotBlank(orgPhone)) {
            methods.add('Phone');
        }
        if (String.isNotBlank(orgEmail)) {
            methods.add('Email');
        }
        return methods;
    }

    private class OrganizationRequestHelper {
        public Id resolveOrganizationOwnerId(Id neighbourhoodId) {
            if (neighbourhoodId != null) {
                List<Account> neighbourhoods = [
                    SELECT OwnerId, Owner.UserType
                    FROM Account
                    WHERE Id = :neighbourhoodId
                    LIMIT 1
                ];
                if (!neighbourhoods.isEmpty()) {
                    Account neighbourhood = neighbourhoods[0];
                    if (neighbourhood.OwnerId != null && !isPortalUserType(neighbourhood.Owner.UserType)) {
                        return neighbourhood.OwnerId;
                    }
                }
            }

            List<User> internalUsers = [
                SELECT Id
                FROM User
                WHERE IsActive = true
                  AND UserType IN ('Standard', 'Admin')
                ORDER BY CreatedDate
                LIMIT 1
            ];
            if (!internalUsers.isEmpty()) {
                return internalUsers[0].Id;
            }
            throw new DmlException('Unable to assign organization owner.');
        }

        private Boolean isPortalUserType(String userType) {
            return userType == 'CspLitePortal'
                || userType == 'CspPortal'
                || userType == 'PowerCustomerSuccess'
                || userType == 'PowerPartner'
                || userType == 'Guest';
        }

        public Id insertAccount(Account org) {
            Database.SaveResult sr = Database.insert(org, AccessLevel.SYSTEM_MODE);
            if (!sr.isSuccess()) {
                throw new DmlException(
                    'Account insert failed: ' + sr.getErrors()[0].getMessage());
            }
            return org.Id;
        }

        public void insertJunction(Community_Group_Neighbourhood__c junction) {
            insert junction;
        }

        public Id insertRelationship(Support_Relationship__c rel) {
            insert rel;
            return rel.Id;
        }

        public void fileOrgApprovalTask(FimbyModeratorTaskService.TaskRequest req) {
            FimbyModeratorTaskService.createOrUpdateTask(req);
        }

        public void stampCga(Id accountId, String version, Id contactId) {
            String versionToWrite = String.isNotBlank(FimbySettings.cgaCurrentVersion())
                ? FimbySettings.cgaCurrentVersion()
                : version;
            Account acct = new Account(
                Id = accountId,
                CGA_Accepted_Date__c = Datetime.now(),
                CGA_Version__c = versionToWrite,
                CGA_Accepted_By__c = contactId
            );
            Database.SaveResult sr = Database.update(acct, AccessLevel.SYSTEM_MODE);
            if (!sr.isSuccess()) {
                throw new DmlException(
                    'CGA stamp failed: ' + sr.getErrors()[0].getMessage());
            }
        }
    }

    private static void stampAuthorizationImage(
        Id supportRelationshipId,
        String fileData,
        String fileName,
        String legacyUrl
    ) {
        String url = legacyUrl;
        if (String.isNotBlank(fileData) && String.isNotBlank(fileName)) {
            url = FimbyContentDistributionHelper.uploadAndLink(fileData, fileName, supportRelationshipId);
        }
        if (String.isNotBlank(url)) {
            update new Support_Relationship__c(
                Id = supportRelationshipId,
                Authorization_Image_URL__c = url
            );
        }
    }

    private static void stampVerificationDocument(Id accountId, String fileData, String fileName) {
        if (String.isBlank(fileData) || String.isBlank(fileName)) {
            return;
        }
        String url = FimbyContentDistributionHelper.uploadAndLink(fileData, fileName, accountId);
        update new Account(
            Id = accountId,
            Verification_Document_URL__c = url
        );
    }
}
