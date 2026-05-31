/**
 * @description Provides field set information to LWC components for dynamic form rendering.
 * Used by fimbyRecordEditModal to get editable fields for any object.
 */
public with sharing class FimbyFieldSetController {

    /**
     * @description LWC-callable method that returns fields from a field set for a given object.
     * @param objectApiName The API name of the object (e.g., 'Story__c')
     * @param fieldSetName The developer name of the field set (e.g., 'FIMBY_Editable_Fields')
     * @return List of FieldSetField wrapper objects
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldSetField> getFieldSetFields(String objectApiName, String fieldSetName) {
        List<FieldSetField> fields = new List<FieldSetField>();
        
        if (String.isBlank(objectApiName) || String.isBlank(fieldSetName)) {
            return fields;
        }

        try {
            // Get the SObject type
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                throw new AuraHandledException('Object not found: ' + objectApiName);
            }

            // Get the field set
            Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
            Map<String, Schema.FieldSet> fieldSetMap = describeResult.fieldSets.getMap();
            
            Schema.FieldSet fieldSet = fieldSetMap.get(fieldSetName);
            if (fieldSet == null) {
                // Try with namespace prefix variations
                fieldSet = fieldSetMap.get('FIMBY__' + fieldSetName);
                if (fieldSet == null) {
                    throw new AuraHandledException('Field set not found: ' + fieldSetName + ' on ' + objectApiName);
                }
            }

            // Get the fields from the field set
            for (Schema.FieldSetMember member : fieldSet.getFields()) {
                // Check if user has access to the field
                Schema.DescribeFieldResult fieldDescribe = member.getSObjectField().getDescribe();
                
                if (fieldDescribe.isAccessible() && fieldDescribe.isUpdateable()) {
                    FieldSetField field = new FieldSetField();
                    field.apiName = member.getFieldPath();
                    field.label = member.getLabel();
                    field.required = member.getRequired() || member.getDbRequired();
                    field.fieldType = String.valueOf(fieldDescribe.getType());
                    fields.add(field);
                }
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading field set: ' + e.getMessage());
        }

        return fields;
    }

    /**
     * @description LWC-callable method that returns all available field sets for an object.
     * @param objectApiName The API name of the object
     * @return List of FieldSetInfo wrapper objects
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldSetInfo> getObjectFieldSets(String objectApiName) {
        List<FieldSetInfo> fieldSets = new List<FieldSetInfo>();
        
        if (String.isBlank(objectApiName)) {
            return fieldSets;
        }

        try {
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                return fieldSets;
            }

            Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
            Map<String, Schema.FieldSet> fieldSetMap = describeResult.fieldSets.getMap();
            
            for (String fieldSetName : fieldSetMap.keySet()) {
                Schema.FieldSet fs = fieldSetMap.get(fieldSetName);
                FieldSetInfo info = new FieldSetInfo();
                info.name = fs.getName();
                info.label = fs.getLabel();
                info.description = fs.getDescription();
                info.fieldCount = fs.getFields().size();
                fieldSets.add(info);
            }
        } catch (Exception e) {
            FimbyLogger.error('FimbyFieldSetController', 'getObjectFieldSets', e);
        }

        return fieldSets;
    }

    /**
     * @description Wrapper class for field set field information.
     */
    public class FieldSetField {
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Boolean required { get; set; }
        @AuraEnabled public String fieldType { get; set; }
    }

    /**
     * @description Wrapper class for field set information.
     */
    public class FieldSetInfo {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Integer fieldCount { get; set; }
    }
}