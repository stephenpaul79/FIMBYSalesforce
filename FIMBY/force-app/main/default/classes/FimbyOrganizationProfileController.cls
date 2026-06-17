/**
 * @description Handles organization (community group) profile data for fimbyOrganizationProfile.
 * Supports viewing, editing, and logo upload for approved community group reps.
 */
public with sharing class FimbyOrganizationProfileController {

    @TestVisible
    private static String testLogoUrlOverride;

    private static final Set<String> ALLOWED_ORG_FIELDS = new Set<String>{
        'Name', 'Description', 'Website', 'Logo_URL__c',
        'Phone', 'BillingStreet', 'BillingCity', 'BillingState', 'BillingPostalCode'
    };

    /**
     * @description Returns true if the current user has an approved Support_Relationship__c
     * where they represent this organization (Community_Group_Rep).
     */
    @AuraEnabled(cacheable=true)
    public static Boolean canEditOrganization(Id organizationId) {
        try {
            if (organizationId == null) return false;
            Id myContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            if (myContactId == null) return false;

            List<Support_Relationship__c> rels = [
                SELECT Id
                FROM Support_Relationship__c
                WHERE Contact__c = :myContactId
                  AND Related_Organization__c = :organizationId
                  AND Relationship_Type__c = 'Community_Group_Rep'
                  AND Status__c = 'Approved'
                  AND Dismissed_By_Helper__c = false
                LIMIT 1
            ];
            return !rels.isEmpty();
        } catch (Exception e) {
            FimbyLogger.error('FimbyOrganizationProfileController', 'canEditOrganization', e);
            return false;
        }
    }

    /**
     * @description Loads organization profile data for display.
     * Returns org fields, neighbourhoods, and approved reps.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getOrganizationProfile(Id organizationId) {
        try {
            if (organizationId == null) {
                throw new AuraHandledException('Organization ID is required.');
            }

            Account org = new OrgProfileHelper().getAccount(organizationId);

            List<Map<String, String>> neighbourhoods = new OrgProfileHelper().getNeighbourhoods(organizationId);
            List<Map<String, Object>> people = new OrgProfileHelper().getApprovedReps(organizationId);

            return new Map<String, Object>{
                'success' => true,
                'org' => new Map<String, Object>{
                    'Id' => org.Id,
                    'Name' => org.Name,
                    'Type' => org.Type,
                    'Description' => org.Description,
                    'Website' => org.Website,
                    'Logo_URL__c' => org.Logo_URL__c,
                    'Is_Approved_Community_Group__c' => org.Is_Approved_Community_Group__c,
                    'Phone' => org.Phone,
                    'BillingStreet' => org.BillingStreet,
                    'BillingCity' => org.BillingCity,
                    'BillingState' => org.BillingState,
                    'BillingPostalCode' => org.BillingPostalCode,
                    'Email' => org.Organization_Contact__r?.Email,
                    'Organization_Contact__c' => org.Organization_Contact__c
                },
                'neighbourhoods' => neighbourhoods,
                'people' => people
            };
        } catch (Exception e) {
            FimbyLogger.error('FimbyOrganizationProfileController', 'getOrganizationProfile', e);
            throw new AuraHandledException('Error loading organization: ' + e.getMessage());
        }
    }

    /**
     * @description Updates allowed organization fields. Requires canEditOrganization.
     */
    @AuraEnabled
    public static Map<String, Object> updateOrganizationProfile(Id organizationId, Map<String, Object> fieldValues) {
        try {
            if (organizationId == null) {
                throw new AuraHandledException('Organization ID is required.');
            }
            if (!canEditOrganization(organizationId)) {
                throw new AuraHandledException('You do not have permission to edit this organization.');
            }
            if (fieldValues == null || fieldValues.isEmpty()) {
                return new Map<String, Object>{ 'success' => true };
            }

            Account acc = new Account(Id = organizationId);
            for (String fieldName : fieldValues.keySet()) {
                if (!ALLOWED_ORG_FIELDS.contains(fieldName)) {
                    throw new AuraHandledException('Field not allowed: ' + fieldName);
                }
                acc.put(fieldName, fieldValues.get(fieldName));
            }
            new OrgProfileHelper().updateAccount(acc);

            return new Map<String, Object>{ 'success' => true };
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            FimbyLogger.error('FimbyOrganizationProfileController', 'updateOrganizationProfile', e);
            throw new AuraHandledException('Error updating organization: ' + e.getMessage());
        }
    }

    /**
     * @description Uploads a logo image and updates Account.Logo_URL__c.
     * Uses ContentVersion + ContentDistribution pattern (same as authorization image).
     * Requires canEditOrganization.
     */
    @AuraEnabled
    public static String uploadOrganizationLogo(String organizationId, String fileData, String fileName,
            Integer imageWidth, Integer imageHeight) {
        try {
            Id orgId = (Id) organizationId;
            if (!canEditOrganization(orgId)) {
                throw new AuraHandledException('You do not have permission to edit this organization.');
            }
            if (String.isBlank(fileData) || String.isBlank(fileName)) {
                throw new AuraHandledException('Missing file data or file name.');
            }

            String viewUrl = new OrgLogoHelper().uploadAndGetUrl(fileData, fileName, orgId, imageWidth, imageHeight);
            new OrgProfileHelper().updateAccountLogo(orgId, viewUrl);

            return viewUrl;
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            FimbyLogger.error('FimbyOrganizationProfileController', 'uploadOrganizationLogo', e);
            throw new AuraHandledException('Error uploading logo: ' + e.getMessage());
        }
    }

    /**
     * @description Removes the organization logo. Requires canEditOrganization.
     */
    @AuraEnabled
    public static Map<String, Object> removeOrganizationLogo(Id organizationId) {
        try {
            if (organizationId == null) {
                throw new AuraHandledException('Organization ID is required.');
            }
            if (!canEditOrganization(organizationId)) {
                throw new AuraHandledException('You do not have permission to edit this organization.');
            }

            new OrgProfileHelper().updateAccountLogo(organizationId, null);

            return new Map<String, Object>{ 'success' => true };
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            FimbyLogger.error('FimbyOrganizationProfileController', 'removeOrganizationLogo', e);
            throw new AuraHandledException('Error removing logo: ' + e.getMessage());
        }
    }

    // ============================================
    // HELPERS
    // ============================================

    private without sharing class OrgProfileHelper {
        public Account getAccount(Id organizationId) {
            return [
                SELECT Id, Name, Type, Description, Website, Logo_URL__c, Is_Approved_Community_Group__c,
                       Phone, BillingStreet, BillingCity, BillingState, BillingPostalCode,
                       Organization_Contact__c, Organization_Contact__r.Email
                FROM Account
                WHERE Id = :organizationId
                LIMIT 1
            ];
        }

        public void updateAccount(Account acc) {
            update acc;
        }

        public void updateAccountLogo(Id organizationId, String logoUrl) {
            Account acc = new Account(Id = organizationId, Logo_URL__c = logoUrl);
            update acc;
        }

        public List<Map<String, String>> getNeighbourhoods(Id organizationId) {
            List<Community_Group_Neighbourhood__c> links = [
                SELECT Neighbourhood__c, Neighbourhood__r.Name
                FROM Community_Group_Neighbourhood__c
                WHERE Organization__c = :organizationId
                  AND Status__c = 'Active'
                ORDER BY Neighbourhood__r.Name
            ];
            List<Map<String, String>> result = new List<Map<String, String>>();
            for (Community_Group_Neighbourhood__c link : links) {
                if (link.Neighbourhood__c != null) {
                    String neighbourhoodName = 'Unknown';
                    if (link.Neighbourhood__r != null && !String.isBlank(link.Neighbourhood__r.Name)) {
                        neighbourhoodName = link.Neighbourhood__r.Name;
                    }
                    result.add(new Map<String, String>{
                        'id' => String.valueOf(link.Neighbourhood__c),
                        'name' => neighbourhoodName
                    });
                }
            }
            return result;
        }

        public List<Map<String, Object>> getApprovedReps(Id organizationId) {
            List<Support_Relationship__c> rels = [
                SELECT Contact__c, Contact__r.Name, Contact__r.Full_Name__c,
                       Contact__r.Image_URL__c, Contact__r.Display_Avatar_URL__c
                FROM Support_Relationship__c
                WHERE Related_Organization__c = :organizationId
                  AND Relationship_Type__c = 'Community_Group_Rep'
                  AND Status__c = 'Approved'
                  AND Dismissed_By_Helper__c = false
                ORDER BY Contact__r.Name
            ];
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            for (Support_Relationship__c rel : rels) {
                if (rel.Contact__c != null) {
                    String contactName = 'Unknown';
                    String avatarUrl = null;
                    if (rel.Contact__r != null) {
                        if (!String.isBlank(rel.Contact__r.Full_Name__c)) {
                            contactName = rel.Contact__r.Full_Name__c;
                        }
                        avatarUrl = rel.Contact__r.Display_Avatar_URL__c;
                    }
                    result.add(new Map<String, Object>{
                        'id' => rel.Contact__c,
                        'name' => contactName,
                        'avatarUrl' => avatarUrl
                    });
                }
            }
            return result;
        }
    }

    @TestVisible
    private without sharing class OrgLogoHelper {

        public String uploadAndGetUrl(String fileData, String fileName, Id organizationId,
                Integer imageWidth, Integer imageHeight) {
            if (Test.isRunningTest()) {
                if (FimbyOrganizationProfileController.testLogoUrlOverride != null) {
                    return FimbyOrganizationProfileController.testLogoUrlOverride;
                }
                return 'https://test.example.com/logo_' + fileName;
            }

            String base64Data = extractBase64Data(fileData);
            Blob fileBlob = EncodingUtil.base64Decode(base64Data);

            ContentVersion cv = createContentVersion(fileBlob, fileName);
            createContentDocumentLink(cv.ContentDocumentId, organizationId);
            ContentDistribution cd = createContentDistribution(cv.Id, fileName);

            return buildDistributionUrl(cv, cd);
        }

        @TestVisible
        private String extractBase64Data(String fileData) {
            if (fileData != null && fileData.contains(',')) {
                return fileData.substringAfter(',');
            }
            return fileData;
        }

        @TestVisible
        private ContentVersion createContentVersion(Blob fileBlob, String fileName) {
            ContentVersion cv = new ContentVersion(
                Title = fileName,
                PathOnClient = fileName,
                VersionData = fileBlob,
                IsMajorVersion = true
            );
            insert cv;

            return [
                SELECT Id, ContentDocumentId, ContentBodyId
                FROM ContentVersion
                WHERE Id = :cv.Id
                LIMIT 1
            ];
        }

        @TestVisible
        private void createContentDocumentLink(Id contentDocumentId, Id organizationId) {
            ContentDocumentLink cdl = new ContentDocumentLink(
                ContentDocumentId = contentDocumentId,
                LinkedEntityId = organizationId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
            insert cdl;
        }

        @TestVisible
        private ContentDistribution createContentDistribution(Id contentVersionId, String fileName) {
            ContentDistribution cd = new ContentDistribution(
                ContentVersionId = contentVersionId,
                Name = fileName,
                PreferencesAllowViewInBrowser = true,
                PreferencesNotifyOnVisit = false,
                PreferencesPasswordRequired = false,
                PreferencesAllowOriginalDownload = true
            );
            insert cd;

            return [
                SELECT Id, DistributionPublicUrl
                FROM ContentDistribution
                WHERE Id = :cd.Id
                LIMIT 1
            ];
        }

        @TestVisible
        private String buildDistributionUrl(ContentVersion cv, ContentDistribution cd) {
            String versionId15 = String.valueOf(cv.Id).substring(0, 15);
            String contentBodyId15 = String.valueOf(cv.ContentBodyId).substring(0, 15);
            String baseUrl = cd.DistributionPublicUrl.substringBefore('/sfc');
            baseUrl = baseUrl.replace('my.salesforce', 'file.force');
            String ending = cd.DistributionPublicUrl.substringAfterLast('/a/');

            return baseUrl
                + FimbySettings.getUrl('File_Download') + '?rendition=ORIGINAL_Jpg'
                + '&versionId=' + versionId15
                + '&operationContext=DELIVERY&contentId=' + contentBodyId15
                + '&page=0&d=/a/' + ending
                + '&oid=';
        }
    }
}
