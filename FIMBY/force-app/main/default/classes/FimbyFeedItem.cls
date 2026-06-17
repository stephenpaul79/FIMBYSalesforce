/**
 * @description Unified feed card DTO for home feed, profile activity, and related lists.
 */
public class FimbyFeedItem implements Comparable {
    @AuraEnabled public String recordId { get; set; }
    @AuraEnabled public String name { get; set; }
    @AuraEnabled public String description { get; set; }
    @AuraEnabled public String feedType { get; set; }
    @AuraEnabled public String itemType { get; set; }
    @AuraEnabled public String category { get; set; }
    @AuraEnabled public Datetime createdDate { get; set; }
    @AuraEnabled public String postedByName { get; set; }
    @AuraEnabled public String postedByImageUrl { get; set; }
    @AuraEnabled public String imageUrl { get; set; }
    @AuraEnabled public String imageRatio { get; set; }
    @AuraEnabled public Boolean hasImage { get; set; }
    @AuraEnabled public String objectApiName { get; set; }
    @AuraEnabled public String image2Url { get; set; }
    @AuraEnabled public String image2Ratio { get; set; }
    @AuraEnabled public String image3Url { get; set; }
    @AuraEnabled public String image3Ratio { get; set; }
    @AuraEnabled public String image4Url { get; set; }
    @AuraEnabled public String image4Ratio { get; set; }
    @AuraEnabled public String typeValue { get; set; }
    @AuraEnabled public Integer engagementCount { get; set; }
    @AuraEnabled public String recordTypeName { get; set; }
    @AuraEnabled public Decimal totalReserved { get; set; }
    @AuraEnabled public Decimal totalQuantity { get; set; }
    @AuraEnabled public Decimal ownerShares { get; set; }
    @AuraEnabled public Decimal totalAvailable { get; set; }
    @AuraEnabled public String activeReserverIds { get; set; }
    @AuraEnabled public Boolean isOrgContact { get; set; }
    @AuraEnabled public String orgAccountId { get; set; }
    @AuraEnabled public String eventDetails { get; set; }
    @AuraEnabled public String location { get; set; }
    @AuraEnabled public String eventType { get; set; }
    @AuraEnabled public String eventLinkUrl { get; set; }
    @AuraEnabled public String ownerContactId { get; set; }
    @AuraEnabled public String realAuthorContactId { get; set; }
    @AuraEnabled public Boolean isUrgent { get; set; }
    @AuraEnabled public String sourceScope { get; set; }
    @AuraEnabled public Boolean isRecurring { get; set; }

    private Datetime sortDate;

    public FimbyFeedItem() {}

    public FimbyFeedItem(Story__c story) {
        this.recordId = story.Id;
        this.name = story.Name;
        this.description = story.Message__c;
        this.feedType = 'story';
        this.itemType = story.Type__c;
        this.category = story.Type__c;
        this.createdDate = story.CreatedDate;
        this.sortDate = story.CreatedDate;
        this.postedByName = story.Posted_By__r?.Full_Name__c;
        this.isOrgContact = story.Posted_By__r?.Is_Organization_Contact__c == true;
        this.orgAccountId = story.Posted_By__r?.Organization_Account__c;
        if (this.isOrgContact && story.Posted_By__r?.Organization_Account__r?.Logo_URL__c != null) {
            this.postedByImageUrl = story.Posted_By__r.Organization_Account__r.Logo_URL__c;
        } else {
            this.postedByImageUrl = story.Posted_By__r?.Display_Avatar_URL__c;
        }
        this.hasImage = String.isNotBlank(story.Image_URL__c);
        this.imageUrl = story.Image_URL__c;
        this.imageRatio = story.Image_Ratio__c;
        this.objectApiName = 'Story__c';
        this.typeValue = story.Type__c;
        this.engagementCount = story.Comment_Count__c != null
            ? (Integer) story.Comment_Count__c
            : 0;
        this.ownerContactId = story.Posted_By__c;
        this.realAuthorContactId = story.Contact__c;
    }

    public FimbyFeedItem(Needs_Offers__c item) {
        this.recordId = item.Id;
        this.name = item.Name;
        this.description = item.Details__c;
        this.feedType = 'askOffer';
        this.itemType = item.RecordType?.Name;
        this.category = item.Category__c;
        this.createdDate = item.CreatedDate;
        this.sortDate = item.Posted_Date__c != null ? item.Posted_Date__c : item.CreatedDate;
        Boolean hasContact = item.Contact__r?.Full_Name__c != null;
        this.postedByName = hasContact ? item.Contact__r.Full_Name__c : item.Posted_By__r?.Full_Name__c;
        this.isOrgContact = hasContact
            ? (item.Contact__r.Is_Organization_Contact__c == true)
            : (item.Posted_By__r?.Is_Organization_Contact__c == true);
        this.orgAccountId = hasContact
            ? item.Contact__r.Organization_Account__c
            : item.Posted_By__r?.Organization_Account__c;
        if (this.isOrgContact) {
            String logoUrl = hasContact
                ? item.Contact__r.Organization_Account__r?.Logo_URL__c
                : item.Posted_By__r?.Organization_Account__r?.Logo_URL__c;
            this.postedByImageUrl = logoUrl != null
                ? logoUrl
                : (hasContact ? item.Contact__r.Display_Avatar_URL__c : item.Posted_By__r?.Display_Avatar_URL__c);
        } else {
            this.postedByImageUrl = hasContact ? item.Contact__r.Display_Avatar_URL__c : item.Posted_By__r?.Display_Avatar_URL__c;
        }
        this.hasImage = String.isNotBlank(item.Image_1_URL__c);
        this.imageUrl = item.Image_1_URL__c;
        this.imageRatio = item.Image_1_Ratio__c;
        this.image2Url = item.Image_2_URL__c;
        this.image2Ratio = item.Image_2_Ratio__c;
        this.image3Url = item.Image_3_URL__c;
        this.image3Ratio = item.Image_3_Ratio__c;
        this.image4Url = item.Image_4_URL__c;
        this.image4Ratio = item.Image_4_Ratio__c;
        this.objectApiName = 'Needs_Offers__c';
        this.typeValue = item.Type__c;
        this.engagementCount = item.Total_Accepted__c != null ? (Integer) item.Total_Accepted__c : 0;
        this.recordTypeName = item.RecordType?.Name;
        this.totalReserved = item.Total_Reserved__c;
        this.totalQuantity = item.Total_Quantity__c;
        this.ownerShares = item.Owner_Shares__c;
        this.totalAvailable = item.Total_Available__c;
        this.activeReserverIds = item.Active_Reserver_Ids__c;
        this.eventDetails = item.Event_Details__c;
        this.location = item.Location__c;
        this.eventType = item.Event_Type__c;
        this.eventLinkUrl = item.Event_Link__c;
        this.ownerContactId = item.Contact__c;
        this.realAuthorContactId = item.Posted_By__c;
        this.isUrgent = item.Is_Urgent__c == true;
        this.isRecurring = String.isNotBlank(item.Recurrence_Frequency__c)
            || item.Series_Parent__c != null;
    }

    public FimbyFeedItem(Library_Item__c item) {
        this.recordId = item.Id;
        this.name = item.Name;
        this.description = item.Description__c;
        this.feedType = 'library';
        this.itemType = 'Library Item';
        this.category = item.Category__c;
        this.createdDate = item.CreatedDate;
        this.sortDate = item.CreatedDate;
        this.postedByName = item.Owner_Contact__r?.Full_Name__c;
        this.isOrgContact = item.Owner_Contact__r?.Is_Organization_Contact__c == true;
        this.orgAccountId = item.Owner_Contact__r?.Organization_Account__c;
        if (this.isOrgContact && item.Owner_Contact__r?.Organization_Account__r?.Logo_URL__c != null) {
            this.postedByImageUrl = item.Owner_Contact__r.Organization_Account__r.Logo_URL__c;
        } else {
            this.postedByImageUrl = item.Owner_Contact__r?.Display_Avatar_URL__c;
        }
        this.hasImage = String.isNotBlank(item.Image_URL__c);
        this.imageUrl = item.Image_URL__c;
        this.imageRatio = item.Image_Ratio__c;
        this.objectApiName = 'Library_Item__c';
        this.typeValue = null;
        this.engagementCount = 0;
        this.ownerContactId = item.Owner_Contact__c;
        this.realAuthorContactId = item.Listed_By__c;
    }

    public Integer compareTo(Object compareTo) {
        FimbyFeedItem other = (FimbyFeedItem) compareTo;
        if (this.sortDate > other.sortDate) {
            return -1;
        }
        if (this.sortDate < other.sortDate) {
            return 1;
        }
        return 0;
    }
}
