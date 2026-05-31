/**
 *  @description Tests for trac_Aura_ListViewOverrideCtlr
 *  @author      Jeremy Horan, Traction on Demand.
 *  @date        1/18/2018
 */
@IsTest
private class trac_Aura_ListViewOverrideCtlrTest {
    @isTest static void test_GetListViewId() {
        String listViewId = trac_Aura_ListViewOverrideCtlr.getListViewId('Opportunity', 'MyOpportunities');
        System.assertNotEquals(null, listViewId);
    }
}