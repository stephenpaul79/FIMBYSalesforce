/**
 *  @description Controller for List View Override Lightning Component
 *  @author      Jeremy Horan, Traction on Demand.
 *  @date        1/18/2018
 */
public with sharing class trac_Aura_ListViewOverrideCtlr {

    /**
     *  @description Get List View for Object Type and Developer Name
     *  @author      Jeremy Horan, Traction on Demand.
     *  @date        1/18/2018
     */
    @AuraEnabled
    public static String getListViewId(String sobjectType, String developerName) {
        String listViewId = [
                SELECT Id, DeveloperName, SobjectType
                FROM ListView
                WHERE SobjectType = :sobjectType AND DeveloperName = :developerName
        ].Id;

        return listViewId;
    }


}