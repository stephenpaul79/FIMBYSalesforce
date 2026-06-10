/**
 * @description Event spawn strategy — carry-forward template + dual-stamp + clean RSVP list per occurrence.
 */
public with sharing class FimbyEventRecurrenceSpawnStrategy implements FimbyRecurrenceSpawnStrategy {

    public Boolean supports(Needs_Offers__c parent) {
        return parent != null && parent.Type__c == 'Event';
    }

    public Needs_Offers__c buildOccurrence(
        Needs_Offers__c parent,
        Needs_Offers__c priorOccurrence,
        Date occurrenceStartDate,
        Date occurrenceEndDate
    ) {
        Needs_Offers__c child = new Needs_Offers__c(
            RecordTypeId = parent.RecordTypeId,
            Series_Parent__c = parent.Id,
            Name = parent.Name,
            Details__c = parent.Details__c,
            Full_Details__c = parent.Full_Details__c,
            Status__c = FimbyConstants.NEEDS_OFFERS_POSTED,
            Type__c = 'Event',
            Event_Type__c = parent.Event_Type__c,
            Contact__c = parent.Contact__c,
            Posted_By__c = parent.Posted_By__c,
            Neighbourhood__c = parent.Neighbourhood__c,
            Giver_Recipient_Type__c = parent.Giver_Recipient_Type__c,
            Visibility_Scope__c = parent.Visibility_Scope__c,
            Total_Quantity__c = parent.Total_Quantity__c,
            Per_Response_Limit__c = parent.Per_Response_Limit__c,
            Start_Date__c = occurrenceStartDate,
            End_Date__c = occurrenceEndDate,
            Start_Time__c = parent.Start_Time__c,
            Start_Time_Text__c = parent.Start_Time_Text__c,
            End_Time__c = parent.End_Time__c,
            End_Time_Text__c = parent.End_Time_Text__c,
            Location__c = parent.Location__c,
            Event_Link__c = parent.Event_Link__c,
            Event_Notes__c = parent.Event_Notes__c,
            Expected_Attendance__c = parent.Expected_Attendance__c,
            Auto_Accept_Responses__c = parent.Auto_Accept_Responses__c,
            Auto_Share_Contact_Info__c = parent.Auto_Share_Contact_Info__c,
            Image_1_URL__c = parent.Image_1_URL__c,
            Image_1_Ratio__c = parent.Image_1_Ratio__c,
            Image_1_Dimensions__c = parent.Image_1_Dimensions__c,
            Image_2_URL__c = parent.Image_2_URL__c,
            Image_2_Ratio__c = parent.Image_2_Ratio__c,
            Image_3_URL__c = parent.Image_3_URL__c,
            Image_3_Ratio__c = parent.Image_3_Ratio__c,
            Image_4_URL__c = parent.Image_4_URL__c,
            Image_4_Ratio__c = parent.Image_4_Ratio__c
        );

        if (child.Event_Type__c == 'Open_Event') {
            child.Auto_Accept_Responses__c = true;
        }

        return child;
    }
}
