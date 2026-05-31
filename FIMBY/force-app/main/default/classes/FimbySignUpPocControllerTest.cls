/**
 * @description Coverage for the throwaway FimbySignUpPocController. Safe to
 *              delete alongside the controller once the POC is validated.
 */
@IsTest
private class FimbySignUpPocControllerTest {

    @IsTest
    static void ping_echoesInputAndReturnsContext() {
        Test.startTest();
        FimbySignUpPocController.PingResult result =
            FimbySignUpPocController.ping('V6A 1A1');
        Test.stopTest();

        System.assertEquals('V6A 1A1', result.echo, 'Echo should match input');
        System.assertNotEquals(null, result.serverTime, 'Server time should be populated');
        System.assertNotEquals(null, result.userType, 'User type should be populated');
        System.assertNotEquals(null, result.userName, 'User name should be populated');
    }

    @IsTest
    static void ping_handlesBlankInput() {
        Test.startTest();
        FimbySignUpPocController.PingResult result =
            FimbySignUpPocController.ping('');
        Test.stopTest();

        System.assertEquals('', result.echo, 'Echo should reflect blank input');
        System.assertEquals(null, result.postalMatchFound,
            'Postal lookup should be skipped for blank input');
    }
}
