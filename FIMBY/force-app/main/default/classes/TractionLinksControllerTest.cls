@isTest
private class TractionLinksControllerTest {
	
	@isTest static void getLinksTest() {
		URL_Links__c link = new URL_Links__c(Name='test', Link__c='www.test.com');
		insert link;
		Test.startTest();
		List<URL_Links__c> links = TractionLinksController.getLinks();
		Test.stopTest();

		System.assertEquals(links.size(), 1, 'Should be one link returned');
		System.assertEquals(links[0].id, link.id, 'Link id returned should match test link created');
	}
}