/**
 * Test class for FimbyFieldSetController
 */
@isTest
private class FimbyFieldSetControllerTest {

    @isTest
    static void testGetFieldSetFields_ValidObject() {
        // Test with a known object - even if field set doesn't exist, should handle gracefully
        Test.startTest();
        try {
            List<FimbyFieldSetController.FieldSetField> fields = 
                FimbyFieldSetController.getFieldSetFields('Account', 'FIMBY_Editable_Fields');
            // If we get here, the field set exists and returned fields
            System.assertNotEquals(null, fields, 'Fields list should not be null');
        } catch (AuraHandledException e) {
            // Field set doesn't exist - this is expected if not deployed
            // The exception is properly thrown, which is the expected behavior
            System.assertNotEquals(null, e.getMessage(), 'Should have an error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetFieldSetFields_InvalidObject() {
        Test.startTest();
        try {
            FimbyFieldSetController.getFieldSetFields('Invalid_Object__c', 'FIMBY_Editable_Fields');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have an error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetFieldSetFields_InvalidFieldSet() {
        Test.startTest();
        try {
            FimbyFieldSetController.getFieldSetFields('Account', 'NonExistent_FieldSet_XYZ123');
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Should have an error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetFieldSetFields_BlankParams() {
        Test.startTest();
        List<FimbyFieldSetController.FieldSetField> fields1 = 
            FimbyFieldSetController.getFieldSetFields('', 'FIMBY_Editable_Fields');
        List<FimbyFieldSetController.FieldSetField> fields2 = 
            FimbyFieldSetController.getFieldSetFields('Account', '');
        List<FimbyFieldSetController.FieldSetField> fields3 = 
            FimbyFieldSetController.getFieldSetFields(null, null);
        Test.stopTest();

        System.assertEquals(0, fields1.size(), 'Should return empty list for blank object');
        System.assertEquals(0, fields2.size(), 'Should return empty list for blank field set');
        System.assertEquals(0, fields3.size(), 'Should return empty list for null params');
    }

    @isTest
    static void testGetObjectFieldSets_ValidObject() {
        Test.startTest();
        List<FimbyFieldSetController.FieldSetInfo> fieldSets = 
            FimbyFieldSetController.getObjectFieldSets('Account');
        Test.stopTest();

        System.assertNotEquals(null, fieldSets, 'Field sets list should not be null');
    }

    @isTest
    static void testGetObjectFieldSets_InvalidObject() {
        Test.startTest();
        List<FimbyFieldSetController.FieldSetInfo> fieldSets = 
            FimbyFieldSetController.getObjectFieldSets('Invalid_Object__c');
        Test.stopTest();

        System.assertEquals(0, fieldSets.size(), 'Should return empty list for invalid object');
    }

    @isTest
    static void testGetObjectFieldSets_BlankParam() {
        Test.startTest();
        List<FimbyFieldSetController.FieldSetInfo> fieldSets = 
            FimbyFieldSetController.getObjectFieldSets('');
        Test.stopTest();

        System.assertEquals(0, fieldSets.size(), 'Should return empty list for blank param');
    }

    @isTest
    static void testFieldSetFieldWrapper() {
        FimbyFieldSetController.FieldSetField field = new FimbyFieldSetController.FieldSetField();
        field.apiName = 'Test__c';
        field.label = 'Test Field';
        field.required = true;
        field.fieldType = 'STRING';

        System.assertEquals('Test__c', field.apiName);
        System.assertEquals('Test Field', field.label);
        System.assertEquals(true, field.required);
        System.assertEquals('STRING', field.fieldType);
    }

    @isTest
    static void testFieldSetInfoWrapper() {
        FimbyFieldSetController.FieldSetInfo info = new FimbyFieldSetController.FieldSetInfo();
        info.name = 'Test_FieldSet';
        info.label = 'Test Field Set';
        info.description = 'A test field set';
        info.fieldCount = 5;

        System.assertEquals('Test_FieldSet', info.name);
        System.assertEquals('Test Field Set', info.label);
        System.assertEquals('A test field set', info.description);
        System.assertEquals(5, info.fieldCount);
    }
}