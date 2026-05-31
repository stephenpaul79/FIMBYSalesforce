@IsTest
private class FimbyContentDistributionHelperTest {

    @IsTest
    static void uploadAndLink_requiresLinkedEntityId() {
        try {
            FimbyContentDistributionHelper.uploadAndLink('data', 'test.jpg', null);
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('link target'), e.getMessage());
        }
    }

    @IsTest
    static void uploadAndLink_returnsTestUrl() {
        Account acct = new Account(Name = 'Upload Target');
        insert acct;

        Test.startTest();
        String url = FimbyContentDistributionHelper.uploadAndLink(
            'data:image/jpeg;base64,/9j/4AAQ', 'letter.jpg', acct.Id
        );
        Test.stopTest();

        System.assert(url.contains('letter.jpg'), url);
        System.assert(url.endsWith('oid='), url);
    }

    @IsTest
    static void uploadAndLink_liveUploadAsAdmin() {
        FimbyContentDistributionHelper.forceLiveUploadForTests = true;
        try {
            Account acct = new Account(Name = 'Live Upload Target');
            insert acct;

            Test.startTest();
            String url = FimbyContentDistributionHelper.uploadAndLink(
                'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAn/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA8A/9k=',
                'live.jpg',
                acct.Id
            );
            Test.stopTest();

            System.assert(String.isNotBlank(url), url);
            System.assert(url.endsWith('oid='), url);
            System.assertEquals(
                1,
                [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :acct.Id]
            );
        } finally {
            FimbyContentDistributionHelper.forceLiveUploadForTests = false;
        }
    }
}
