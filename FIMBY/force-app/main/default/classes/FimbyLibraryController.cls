/**
 * @description Handles Library Items, Image Uploads, and Lending functionality.
 * Refactored — other methods moved to FimbyContactController, FimbyAskOfferController, FimbyResponseController, FimbyStoryCommentController.
 */
public with sharing class FimbyLibraryController {

    // ============================================
    // LIBRARY ITEM METHODS
    // ============================================

    /**
     * Get picklist values for Library_Item__c.Category__c
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getCategoryPicklistValues() {
        List<Map<String, String>> options = new List<Map<String, String>>();

        Schema.DescribeFieldResult fieldResult = Library_Item__c.Category__c.getDescribe();
        List<Schema.PicklistEntry> entries = fieldResult.getPicklistValues();

        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                options.add(new Map<String, String>{
                    'label' => entry.getLabel(),
                    'value' => entry.getValue()
                });
            }
        }

        return options;
    }

    /**
     * Get the FIMBY record type ID for Library_Item__c
     */
    @AuraEnabled(cacheable=true)
    public static String getFimbyRecordTypeId() {
        RecordType rt = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Library_Item__c'
            AND Name = 'FIMBY'
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return rt.Id;
    }

    /**
     * Create a new Library Item with all required fields from the flow
     */
    @AuraEnabled
    public static Map<String, Object> createLibraryItem(String itemData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(itemData);

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Contact actingAsContact = [
                SELECT Id, AccountId, Is_Organization_Contact__c, Organization_Account__c
                FROM Contact
                WHERE Id = :actingAsContactId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Get the FIMBY record type
            List<RecordType> fimbyRTList = [
                SELECT Id
                FROM RecordType
                WHERE SobjectType = 'Library_Item__c'
                AND DeveloperName = 'FIMBY'
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            Id fimbyRecordTypeId = null;
            if (!fimbyRTList.isEmpty()) {
                fimbyRecordTypeId = fimbyRTList[0].Id;
            }

            Library_Item__c newItem = new Library_Item__c();

            // Required fields
            newItem.Name = (String) data.get('title');
            newItem.Description__c = (String) data.get('description');
            newItem.Category__c = (String) data.get('category');
            newItem.Max_Lending_Time_In_Days__c = data.get('maxLendingDays') != null
                ? Decimal.valueOf(String.valueOf(data.get('maxLendingDays')))
                : 7;

            newItem.Owner_Contact__c = actingAsContactId;
            newItem.Listed_By__c = realContactId;
            newItem.Neighbourhood__c = identity.neighbourhoodId;

            if (actingAsContact.Is_Organization_Contact__c == true
                && actingAsContact.Organization_Account__c != null) {
                newItem.Owned_By__c = 'Organization';
                newItem.Owner_Organization__c = actingAsContact.Organization_Account__c;
            } else {
                newItem.Owned_By__c = 'Self';
            }

            // Settings
            newItem.Auto_Accept_Requests__c = data.get('autoAcceptRequests') == true;
            newItem.Auto_Share_Contact_Info__c = data.get('autoShareContactInfo') == true;
            newItem.Damage_Waiver_Confirmed__c = data.get('damageWaiverConfirmed') == true;

            // Record type and status
            if (fimbyRecordTypeId != null) {
                newItem.RecordTypeId = fimbyRecordTypeId;
            }
            newItem.Status__c = FimbyConstants.LIBRARY_AVAILABLE;
            newItem.Visibility_Scope__c = 'Adjacent';

            Database.insert(newItem, true);

            // Build the URL for the new item
            String itemUrl = FimbySettings.getUrl('Library_Item', newItem.Id);

            return new Map<String, Object>{
                'success' => true,
                'recordId' => newItem.Id,
                'itemUrl' => itemUrl,
                'message' => 'Library item created successfully'
            };

        } catch (Exception e) {
            FimbyLogger.error('FimbyLibraryController', 'createLibraryItem', e);
            AuraHandledException ex = new AuraHandledException('Error creating library item: ' + e.getMessage());
            ex.setMessage('Error creating library item: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Update an existing Library_Item__c (org ownership fields excluded after publish).
     */
    @AuraEnabled
    public static Map<String, Object> updateLibraryItem(String itemData) {
        try {
            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(itemData);
            String recordId = (String) data.get('recordId');
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required.');
            }

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id realContactId = identity.currentUser.ContactId;
            Id actingAsContactId = identity.actingAsContactId;

            Library_Item__c item = new LibraryItemUpdateHelper().queryItem(recordId);
            if (item == null) {
                throw new AuraHandledException('Library item not found.');
            }

            if (item.Listed_By__c != realContactId && item.Owner_Contact__c != actingAsContactId) {
                throw new AuraHandledException('You can only edit library items you listed.');
            }

            if (data.containsKey('title')) {
                item.Name = (String) data.get('title');
            }
            if (data.containsKey('description')) {
                item.Description__c = (String) data.get('description');
            }
            if (data.containsKey('category')) {
                item.Category__c = (String) data.get('category');
            }
            if (data.containsKey('maxLendingDays')) {
                item.Max_Lending_Time_In_Days__c = data.get('maxLendingDays') != null
                    ? Decimal.valueOf(String.valueOf(data.get('maxLendingDays'))) : null;
            }
            if (data.containsKey('autoAcceptRequests')) {
                item.Auto_Accept_Requests__c = data.get('autoAcceptRequests') == true;
            }
            if (data.containsKey('autoShareContactInfo')) {
                item.Auto_Share_Contact_Info__c = data.get('autoShareContactInfo') == true;
            }

            new LibraryItemUpdateHelper().updateItem(item);

            return new Map<String, Object>{
                'success' => true,
                'recordId' => item.Id,
                'message' => 'Library item updated successfully'
            };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error('FimbyLibraryController', 'updateLibraryItem', e);
            AuraHandledException ex = new AuraHandledException('Error updating library item: ' + e.getMessage());
            ex.setMessage('Error updating library item: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Launch the photo upload flow for a library item
     * This is called after the item is created to upload a photo
     */
    @AuraEnabled
    public static Map<String, Object> getPhotoUploadFlowInputs(String recordId) {
        try {
            return new Map<String, Object>{
                'success' => true,
                'recordId' => recordId,
                'flowName' => 'Upload_Library_Item_Photo'
            };
        } catch (Exception e) {
            throw new AuraHandledException('Error preparing photo upload: ' + e.getMessage());
        }
    }

    // ============================================
    // LENDING REQUEST METHODS
    // ============================================

    /**
     * Get Library Item details for the lending request flow
     * Checks if item is available for lending
     */
    @AuraEnabled
    public static Map<String, Object> getLibraryItemForLending(String recordId) {
        try {
            Library_Item__c item = [
                SELECT Id, Name, Description__c, Status__c, Image_URL__c, Image__c,
                       Max_Lending_Time_In_Days__c, Expected_Return_Date__c,
                       Owner_Contact__c, Owner_Contact__r.Name, Owner_Contact__r.Full_Name__c
                FROM Library_Item__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Check if item can be lent (flow logic)
            Boolean canBeLent = item.Status__c != FimbyConstants.LIBRARY_UNAVAILABLE &&
                               item.Status__c != FimbyConstants.LIBRARY_REMOVED;

            return new Map<String, Object>{
                'success' => true,
                'canBeLent' => canBeLent,
                'item' => new Map<String, Object>{
                    'id' => item.Id,
                    'name' => item.Name,
                    'description' => item.Description__c,
                    'status' => item.Status__c,
                    'imageUrl' => item.Image_URL__c,
                    'maxLendingDays' => item.Max_Lending_Time_In_Days__c,
                    'expectedReturnDate' => item.Expected_Return_Date__c,
                    'ownerContactId' => item.Owner_Contact__c,
                    'ownerName' => item.Owner_Contact__r?.Full_Name__c
                }
            };
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error getting library item: ' + e.getMessage());
            ex.setMessage('Error getting library item: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Check if user already has a request for this item
     * Returns existing request info if found
     */
    @AuraEnabled
    public static Map<String, Object> checkExistingLendingRequest(String itemId, String requestedById) {
        try {
            List<Lending_Request__c> existingRequests = [
                SELECT Id, Waitlist_Position__c, Status__c
                FROM Lending_Request__c
                WHERE Library_Item__c = :itemId
                AND Requested_By__c = :requestedById
                AND Status__c NOT IN ('Cancelled', 'Declined', 'Completed', 'Returned')
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (!existingRequests.isEmpty()) {
                Lending_Request__c existing = existingRequests[0];
                return new Map<String, Object>{
                    'success' => true,
                    'hasExistingRequest' => true,
                    'existingRequest' => new Map<String, Object>{
                        'id' => existing.Id,
                        'waitlistPosition' => existing.Waitlist_Position__c,
                        'status' => existing.Status__c
                    }
                };
            }

            return new Map<String, Object>{
                'success' => true,
                'hasExistingRequest' => false
            };
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error checking existing request: ' + e.getMessage());
            ex.setMessage('Error checking existing request: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Create a new Lending Request
     * Implements the flow logic including waitlist position calculation
     */
    /**
     * @description True when the acting Contact may borrow from the lending library.
     *              Vouched peers, Community Group org contacts, and supportees of Vouched
     *              supporters can borrow. New / Vouch_Requested / Vouch_Declined cannot.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isVouchedForBorrowing() {
        Id actingId = FimbyIdentityRepository.getActingAsContactId();
        if (actingId == null) return false;

        for (Contact c : [
            SELECT Id, Vouched_Status__c, Is_Organization_Contact__c
            FROM Contact WHERE Id = :actingId LIMIT 1
        ]) {
            if (c.Is_Organization_Contact__c == true) return true;
            if ('Vouched'.equals(c.Vouched_Status__c)) return true;
        }

        // Supportee path: if I'm being supported by someone who is Vouched, I inherit.
        for (Support_Relationship__c sr : [
            SELECT Contact__c, Contact__r.Vouched_Status__c
            FROM Support_Relationship__c
            WHERE Related_Contact__c = :actingId
              AND Status__c = 'Approved'
            LIMIT 5
        ]) {
            if ('Vouched'.equals(sr.Contact__r?.Vouched_Status__c)) return true;
        }

        return false;
    }

    @AuraEnabled
    public static Map<String, Object> createLendingRequest(String requestData) {
        try {
            // Server-side defence: only Vouched users (or CG-rep org contacts / vouched supportees) can borrow.
            if (!isVouchedForBorrowing()) {
                throw new AuraHandledException('vouching-required');
            }

            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(requestData);

            String itemId = (String) data.get('itemId');
            String requestedById = (String) data.get('requestedById');
            String requestedByRealContactId = (String) data.get('requestedByRealContactId');
            String requestedDateStr = (String) data.get('requestedDate');
            Integer daysNeeded = Integer.valueOf(data.get('daysNeeded'));
            String message = (String) data.get('message');

            // Server-side fallback: when LWC doesn't pass it explicitly, derive real Contact from running user
            if (String.isBlank(requestedByRealContactId)) {
                requestedByRealContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            }

            Library_Item__c item = [
                SELECT Id, Owner_Contact__c, Name,
                       Auto_Accept_Requests__c, Auto_Share_Contact_Info__c
                FROM Library_Item__c
                WHERE Id = :itemId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Get requester's neighbourhood (AccountId)
            Contact requester = [
                SELECT Id, AccountId
                FROM Contact
                WHERE Id = :requestedById
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Calculate waitlist position (flow formula logic)
            // Get the highest waitlist position for this item
            List<Lending_Request__c> otherRequests = [
                SELECT Id, Waitlist_Position__c
                FROM Lending_Request__c
                WHERE Library_Item__c = :itemId
                AND Status__c NOT IN ('Cancelled', 'Declined', 'Completed', 'Returned')
                WITH SECURITY_ENFORCED
                ORDER BY Waitlist_Position__c DESC
                LIMIT 1
            ];

            Integer waitlistPosition = 1;
            if (!otherRequests.isEmpty() && otherRequests[0].Waitlist_Position__c != null) {
                waitlistPosition = (Integer) otherRequests[0].Waitlist_Position__c + 1;
            }

            Boolean itemOnLoan = [
                SELECT COUNT()
                FROM Loaned_Item__c
                WHERE Library_Item__c = :itemId
                AND Returned_Date__c = NULL
                WITH SECURITY_ENFORCED
            ] > 0;

            // Position 1 is Pending Approval only when the item is available; on-loan requests waitlist.
            String status = (!itemOnLoan && waitlistPosition == 1)
                ? FimbyConstants.LENDING_PENDING_APPROVAL
                : FimbyConstants.LENDING_WAITLISTED;

            // Parse the requested date (null for waitlisted users — collected at confirmation)
            Date requestedDate = String.isNotBlank(requestedDateStr)
                ? Date.valueOf(requestedDateStr) : null;

            // Dual-stamp the lending request: Requested_By__c is the represented identity,
            // Requested_By_Real_Contact__c is the user who physically submitted (audit trail).
            Lending_Request__c newRequest = new Lending_Request__c(
                Library_Item__c = itemId,
                Item_Owner__c = item.Owner_Contact__c,
                Requested_By__c = requestedById,
                Requested_By_Real_Contact__c = requestedByRealContactId,
                of_Days_Needed__c = daysNeeded,
                Neighbourhood__c = FimbyIdentityRepository.getNeighbourhoodId(),
                Status__c = status,
                Waitlist_Position__c = waitlistPosition
            );

            if (requestedDate != null) {
                newRequest.Requested_Date__c = requestedDate;
            }
            if (String.isNotBlank(message)) {
                newRequest.Message__c = message;
            }

            Database.insert(newRequest, true);

            Boolean autoApproved = false;
            Boolean contactInfoShared = false;

            if (item.Auto_Accept_Requests__c == true && waitlistPosition == 1) {
                // Build auto-share data if enabled
                String autoShareData = null;
                if (item.Auto_Share_Contact_Info__c == true && item.Owner_Contact__c != null) {
                    Contact ownerC = [
                        SELECT Id, Email, Phone, MailingStreet, MailingCity,
                               MailingState, MailingPostalCode, MailingCountry
                        FROM Contact
                        WHERE Id = :item.Owner_Contact__c
                        LIMIT 1
                    ];
                    Map<String, Object> shareMap = new Map<String, Object>{
                        'shareEmail' => String.isNotBlank(ownerC.Email),
                        'sharePhone' => String.isNotBlank(ownerC.Phone),
                        'shareAddress' => String.isNotBlank(ownerC.MailingStreet),
                        'email' => ownerC.Email != null ? ownerC.Email : '',
                        'phone' => ownerC.Phone != null ? ownerC.Phone : '',
                        'street' => ownerC.MailingStreet != null ? ownerC.MailingStreet : '',
                        'city' => ownerC.MailingCity != null ? ownerC.MailingCity : '',
                        'state' => ownerC.MailingState != null ? ownerC.MailingState : '',
                        'postalCode' => ownerC.MailingPostalCode != null ? ownerC.MailingPostalCode : '',
                        'country' => ownerC.MailingCountry != null ? ownerC.MailingCountry : ''
                    };
                    if ((Boolean) shareMap.get('shareEmail') || (Boolean) shareMap.get('sharePhone') || (Boolean) shareMap.get('shareAddress')) {
                        autoShareData = JSON.serialize(shareMap);
                        contactInfoShared = true;
                    }
                }

                FimbyLendingController.autoApproveRequest(
                    newRequest.Id,
                    requestedDateStr,
                    autoShareData
                );
                autoApproved = true;

                // Send informational notification to lender (they opted into auto-accept)
                if (item.Owner_Contact__c != null) {
                    Contact reqContact = [SELECT Id, FirstName FROM Contact WHERE Id = :requestedById WITH SECURITY_ENFORCED LIMIT 1];
                    String reqName = reqContact.FirstName != null ? reqContact.FirstName : 'A neighbour';
                    FimbyNotificationService.createNotification(
                        item.Owner_Contact__c,
                        FimbyConstants.NOTIF_LENDING_REQUEST,
                        reqName + ' is borrowing ' + item.Name,
                        'Auto-approved. Pickup date: ' + requestedDateStr + '.',
                        newRequest.Id,
                        'Lending_Request__c',
                        FimbySettings.getUrl('Library_Item', itemId),
                        reqName
                    );
                }
            } else {
                // Normal flow: notify owner to review
                if (waitlistPosition == 1 && item.Owner_Contact__c != null && item.Owner_Contact__c != requestedById) {
                    Contact reqContact = [SELECT Id, FirstName FROM Contact WHERE Id = :requestedById WITH SECURITY_ENFORCED LIMIT 1];
                    String reqName = reqContact.FirstName != null ? reqContact.FirstName : 'A neighbour';
                    String actionUrl = FimbySettings.getUrl('Library_Item', itemId,
                        '?action=reviewRequest&requestId=' + newRequest.Id);
                    FimbyNotificationService.createNotification(
                        item.Owner_Contact__c,
                        FimbyConstants.NOTIF_LENDING_REQUEST,
                        reqName + ' wants to borrow your item',
                        String.isNotBlank(message) ? message : '',
                        newRequest.Id,
                        'Lending_Request__c',
                        actionUrl,
                        reqName
                    );
                }
            }

            if (!autoApproved && waitlistPosition > 1) {
                FimbyNotificationService.createNotification(
                    requestedById,
                    FimbyConstants.NOTIF_LENDING_REQUEST,
                    'You\'re #' + waitlistPosition + ' on the waitlist for ' + item.Name,
                    'We\'ll let you know when it\'s your turn.',
                    newRequest.Id,
                    'Lending_Request__c',
                    FimbySettings.getUrl('Library_Item', itemId),
                    'FIMBY',
                    true
                );
            }

            Lending_Request__c createdRequest = [
                SELECT Id, Waitlist_Position__c, Status__c, Estimated_Available_Date__c
                FROM Lending_Request__c
                WHERE Id = :newRequest.Id
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            return new Map<String, Object>{
                'success' => true,
                'requestId' => createdRequest.Id,
                'waitlistPosition' => createdRequest.Waitlist_Position__c,
                'status' => createdRequest.Status__c,
                'estimatedAvailableDate' => createdRequest.Estimated_Available_Date__c,
                'isFirstInLine' => (waitlistPosition == 1),
                'autoApproved' => autoApproved,
                'contactInfoShared' => contactInfoShared,
                'confirmationWindowDays' => FimbySettings.lendingConfirmationExpiryDays()
            };

        } catch (Exception e) {
            FimbyLogger.error('FimbyLibraryController', 'createLendingRequest', e);
            AuraHandledException ex = new AuraHandledException('Error creating lending request: ' + e.getMessage());
            ex.setMessage('Error creating lending request: ' + e.getMessage());
            throw ex;
        }
    }

    // ============================================
    // LIBRARY ITEM USER CONTEXT
    // ============================================

    /**
     * Returns the acting-as user's relationship to a specific library item:
     * active lending request (if any) and active loan (if any).
     * Does not replace getRecord for the base item — only fills contextual gaps.
     */
    @AuraEnabled
    public static Map<String, Object> getLibraryItemUserContext(String itemId) {
        try {
            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();
            Map<String, Object> result = new Map<String, Object>{ 'success' => true };

            // Active lending request
            List<Lending_Request__c> requests = [
                SELECT Id, Status__c, Waitlist_Position__c, Requested_Date__c
                FROM Lending_Request__c
                WHERE Library_Item__c = :itemId
                AND Requested_By__c = :actingAsContactId
                AND Status__c NOT IN ('Cancelled', 'Declined')
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (!requests.isEmpty()) {
                Lending_Request__c req = requests[0];
                Map<String, Object> reqMap = new Map<String, Object>{
                    'id' => req.Id,
                    'status' => req.Status__c,
                    'waitlistPosition' => req.Waitlist_Position__c,
                    'requestedDate' => req.Requested_Date__c
                };

                // Add conversation for Approved requests
                if (req.Status__c == FimbyConstants.LENDING_APPROVED) {
                    List<Conversation__c> reqConvs = [
                        SELECT Id FROM Conversation__c
                        WHERE Context_Type__c = :FimbyConstants.CTX_LIBRARY_LENDING
                        AND Related_Record_Id__c = :String.valueOf(req.Id)
                        LIMIT 1
                    ];
                    if (!reqConvs.isEmpty()) {
                        reqMap.put('conversationId', String.valueOf(reqConvs[0].Id));
                    }
                }

                result.put('hasActiveRequest', true);
                result.put('request', reqMap);
            } else {
                result.put('hasActiveRequest', false);
            }

            // Active loan — includes "Owner to Confirm Return" where Returned_Date__c is set but owner hasn't finalized
            List<Loaned_Item__c> loans = [
                SELECT Id, Status__c, Loan_Due_Date__c, Loan_Start_Date__c,
                       Requested_Due_Date_Extension__c, Return_Confirmed_By_Borrower__c
                FROM Loaned_Item__c
                WHERE Library_Item__c = :itemId
                AND Loaned_To__c = :actingAsContactId
                AND (Returned_Date__c = null OR Return_Confirmed_By_Borrower__c = true)
                LIMIT 1
            ];

            if (!loans.isEmpty()) {
                Loaned_Item__c loan = loans[0];
                String loanPhase = deriveLoanPhase(loan.Status__c);

                String loanConvId = null;
                List<Conversation__c> loanConvs = [
                    SELECT Id FROM Conversation__c
                    WHERE Context_Type__c = :FimbyConstants.CTX_LIBRARY_LENDING
                    AND Related_Record_Id__c = :String.valueOf(loan.Id)
                    LIMIT 1
                ];
                if (!loanConvs.isEmpty()) loanConvId = String.valueOf(loanConvs[0].Id);

                result.put('hasActiveLoan', true);
                result.put('loan', new Map<String, Object>{
                    'id' => loan.Id,
                    'status' => loan.Status__c,
                    'loanStatusDerived' => loanPhase,
                    'dueDate' => loan.Loan_Due_Date__c,
                    'startDate' => loan.Loan_Start_Date__c,
                    'conversationId' => loanConvId,
                    'requestedDueDateExtension' => loan.Requested_Due_Date_Extension__c,
                    'returnConfirmedByBorrower' => loan.Return_Confirmed_By_Borrower__c
                });
            } else {
                result.put('hasActiveLoan', false);
            }

            // Borrower's lending history for this item
            List<Lending_History__c> borrowerHist = [
                SELECT Id, Start_Date__c, End_Date__c, Condition_Upon_Return__c,
                       Lent_By__r.Full_Name__c, Lent_By__r.Image_URL__c, Lent_By__r.Display_Avatar_URL__c
                FROM Lending_History__c
                WHERE Borrowed_By__c = :actingAsContactId
                AND Library_Item__c = :itemId
                ORDER BY End_Date__c DESC
                LIMIT 5
            ];

            if (!borrowerHist.isEmpty()) {
                Set<String> bhIdStrings = new Set<String>();
                for (Lending_History__c bh : borrowerHist) {
                    bhIdStrings.add(String.valueOf(bh.Id));
                }
                Map<String, Id> bhConvMap = new Map<String, Id>();
                for (Conversation__c c : [
                    SELECT Id, Related_Record_Id__c FROM Conversation__c
                    WHERE Context_Type__c = :FimbyConstants.CTX_LIBRARY_LENDING
                    AND Related_Record_Id__c IN :bhIdStrings
                ]) {
                    bhConvMap.put(c.Related_Record_Id__c, c.Id);
                }

                List<Map<String, Object>> bhList = new List<Map<String, Object>>();
                for (Lending_History__c bh : borrowerHist) {
                    Map<String, Object> bhMap = new Map<String, Object>{
                        'id' => bh.Id,
                        'startDate' => bh.Start_Date__c,
                        'endDate' => bh.End_Date__c,
                        'condition' => bh.Condition_Upon_Return__c,
                        'lenderName' => bh.Lent_By__r?.Full_Name__c,
                        'lenderAvatar' => bh.Lent_By__r?.Display_Avatar_URL__c
                    };
                    String bhIdStr = String.valueOf(bh.Id);
                    if (bhConvMap.containsKey(bhIdStr)) {
                        bhMap.put('conversationId', String.valueOf(bhConvMap.get(bhIdStr)));
                    }
                    bhList.add(bhMap);
                }
                result.put('borrowerHistory', bhList);
            }

            return result;

        } catch (Exception e) {
            FimbyLogger.error('FimbyLibraryController', 'getLibraryItemUserContext', e);
            AuraHandledException ex = new AuraHandledException('Error loading user context: ' + e.getMessage());
            ex.setMessage('Error loading user context: ' + e.getMessage());
            throw ex;
        }
    }

    // ============================================
    // LIBRARY ITEM ADMIN (OWNER-ONLY)
    // ============================================

    /**
     * Returns owner admin data: current loan, active lending requests, and recent history.
     * Uses canonical ownership rule: Owner_Contact__c == actingAsContactId.
     */
    @AuraEnabled
    public static Map<String, Object> getLibraryItemAdmin(String itemId) {
        try {
            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();

            Library_Item__c item = [
                SELECT Id, Owner_Contact__c
                FROM Library_Item__c
                WHERE Id = :itemId
                LIMIT 1
            ];

            if (item.Owner_Contact__c != actingAsContactId) {
                throw new AuraHandledException('You can only manage items you own.');
            }

            Map<String, Object> result = new Map<String, Object>{ 'success' => true };

            // Current loan — includes "Owner to Confirm Return" where borrower has set Returned_Date__c
            List<Loaned_Item__c> activeLoans = [
                SELECT Id, Status__c, Loan_Due_Date__c, Loan_Start_Date__c,
                       Loaned_To__r.Full_Name__c, Loaned_To__r.Image_URL__c, Loaned_To__r.Display_Avatar_URL__c,
                       Requested_Due_Date_Extension__c, Return_Confirmed_By_Borrower__c
                FROM Loaned_Item__c
                WHERE Library_Item__c = :itemId
                AND (Returned_Date__c = null OR Return_Confirmed_By_Borrower__c = true)
                LIMIT 1
            ];

            if (!activeLoans.isEmpty()) {
                Loaned_Item__c loan = activeLoans[0];
                String loanPhase = deriveLoanPhase(loan.Status__c);

                // Find conversation linked to this loan
                String loanConvId = null;
                List<Conversation__c> loanConvs = [
                    SELECT Id FROM Conversation__c
                    WHERE Context_Type__c = :FimbyConstants.CTX_LIBRARY_LENDING
                    AND Related_Record_Id__c = :String.valueOf(loan.Id)
                    LIMIT 1
                ];
                if (!loanConvs.isEmpty()) loanConvId = loanConvs[0].Id;

                result.put('currentLoan', new Map<String, Object>{
                    'id' => loan.Id,
                    'status' => loan.Status__c,
                    'loanStatusDerived' => loanPhase,
                    'dueDate' => loan.Loan_Due_Date__c,
                    'startDate' => loan.Loan_Start_Date__c,
                    'borrowerName' => loan.Loaned_To__r?.Full_Name__c,
                    'borrowerAvatar' => loan.Loaned_To__r?.Display_Avatar_URL__c,
                    'conversationId' => loanConvId,
                    'requestedDueDateExtension' => loan.Requested_Due_Date_Extension__c,
                    'returnConfirmedByBorrower' => loan.Return_Confirmed_By_Borrower__c
                });
            }

            // Active lending requests (waitlist) — enriched with conversation IDs for Approved
            List<Lending_Request__c> reqRecords = [
                SELECT Id, Status__c, Waitlist_Position__c, Requested_Date__c,
                       of_Days_Needed__c, Estimated_Available_Date__c,
                       Requested_By__r.Full_Name__c, Requested_By__r.Image_URL__c, Requested_By__r.Display_Avatar_URL__c
                FROM Lending_Request__c
                WHERE Library_Item__c = :itemId
                AND Status__c NOT IN ('Cancelled', 'Declined')
                ORDER BY Waitlist_Position__c ASC
                LIMIT 20
            ];

            // Batch-fetch conversations for Approved requests
            Set<String> approvedIds = new Set<String>();
            for (Lending_Request__c req : reqRecords) {
                if (req.Status__c == FimbyConstants.LENDING_APPROVED) {
                    approvedIds.add(String.valueOf(req.Id));
                }
            }
            Map<String, Id> reqConvMap = new Map<String, Id>();
            if (!approvedIds.isEmpty()) {
                for (Conversation__c c : [
                    SELECT Id, Related_Record_Id__c FROM Conversation__c
                    WHERE Context_Type__c = :FimbyConstants.CTX_LIBRARY_LENDING
                    AND Related_Record_Id__c IN :approvedIds
                ]) {
                    reqConvMap.put(c.Related_Record_Id__c, c.Id);
                }
            }

            List<Map<String, Object>> requestList = new List<Map<String, Object>>();
            for (Lending_Request__c req : reqRecords) {
                Map<String, Object> reqMap = new Map<String, Object>{
                    'id' => req.Id,
                    'status' => req.Status__c,
                    'waitlistPosition' => req.Waitlist_Position__c,
                    'requestedDate' => req.Requested_Date__c,
                    'daysNeeded' => req.of_Days_Needed__c,
                    'estimatedAvailableDate' => req.Estimated_Available_Date__c,
                    'requesterName' => req.Requested_By__r?.Full_Name__c,
                    'requesterAvatar' => req.Requested_By__r?.Display_Avatar_URL__c
                };
                if (reqConvMap.containsKey(String.valueOf(req.Id))) {
                    reqMap.put('conversationId', String.valueOf(reqConvMap.get(String.valueOf(req.Id))));
                }
                requestList.add(reqMap);
            }
            result.put('lendingRequests', requestList);

            // Lending history (recent 10)
            List<Lending_History__c> histRecords = [
                SELECT Id, Start_Date__c, End_Date__c, Condition_Upon_Return__c,
                       Lender_Rating__c, Borrow_Rating__c,
                       Borrowed_By__r.Full_Name__c, Borrowed_By__r.Image_URL__c, Borrowed_By__r.Display_Avatar_URL__c
                FROM Lending_History__c
                WHERE Library_Item__c = :itemId
                ORDER BY End_Date__c DESC
                LIMIT 10
            ];

            // Batch-fetch conversations linked to history records
            Set<String> histIdStrings = new Set<String>();
            for (Lending_History__c h : histRecords) {
                histIdStrings.add(String.valueOf(h.Id));
            }
            Map<String, Id> histConvMap = new Map<String, Id>();
            if (!histIdStrings.isEmpty()) {
                for (Conversation__c c : [
                    SELECT Id, Related_Record_Id__c FROM Conversation__c
                    WHERE Context_Type__c = :FimbyConstants.CTX_LIBRARY_LENDING
                    AND Related_Record_Id__c IN :histIdStrings
                ]) {
                    histConvMap.put(c.Related_Record_Id__c, c.Id);
                }
            }

            List<Map<String, Object>> historyList = new List<Map<String, Object>>();
            for (Lending_History__c hist : histRecords) {
                Map<String, Object> histMap = new Map<String, Object>{
                    'id' => hist.Id,
                    'startDate' => hist.Start_Date__c,
                    'endDate' => hist.End_Date__c,
                    'condition' => hist.Condition_Upon_Return__c,
                    'lenderRating' => hist.Lender_Rating__c,
                    'borrowRating' => hist.Borrow_Rating__c,
                    'borrowerName' => hist.Borrowed_By__r?.Full_Name__c,
                    'borrowerAvatar' => hist.Borrowed_By__r?.Display_Avatar_URL__c
                };
                String histIdStr = String.valueOf(hist.Id);
                if (histConvMap.containsKey(histIdStr)) {
                    histMap.put('conversationId', String.valueOf(histConvMap.get(histIdStr)));
                }
                historyList.add(histMap);
            }
            result.put('lendingHistory', historyList);

            return result;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            FimbyLogger.error('FimbyLibraryController', 'getLibraryItemAdmin', e);
            AuraHandledException ex = new AuraHandledException('Error loading admin data: ' + e.getMessage());
            ex.setMessage('Error loading admin data: ' + e.getMessage());
            throw ex;
        }
    }

    // ============================================
    // DELETE LIBRARY ITEM
    // ============================================

    /**
     * Delete a Library_Item__c record (with ownership check via acting-as contact)
     */
    @AuraEnabled
    public static Map<String, Object> deleteLibraryItem(String recordId) {
        try {
            Map<String, Object> actingAs = FimbyContactController.getActingAsContact();
            String actingAsContactId = (String) actingAs.get('contactId');

            Library_Item__c item = [
                SELECT Id, Owner_Contact__c, OwnerId
                FROM Library_Item__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (item.Owner_Contact__c != actingAsContactId) {
                throw new AuraHandledException('You can only delete items you own.');
            }

            new LibraryItemHelper().deleteItem(item);

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Item deleted successfully'
            };
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error deleting item: ' + e.getMessage());
            ex.setMessage('Error deleting item: ' + e.getMessage());
            throw ex;
        }
    }

    // ============================================
    // IMAGE UPLOAD METHODS
    // ============================================

    /**
     * Get image upload settings from custom setting
     * Returns defaults if no custom setting configured
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getImageUploadSettings() {
        FIMBY_Image_Settings__c settings = FIMBY_Image_Settings__c.getInstance();

        // Use defaults if settings not configured
        Integer maxDimension = settings?.Max_Image_Dimension__c != null
            ? (Integer) settings.Max_Image_Dimension__c
            : 1200;
        Decimal jpegQuality = settings?.JPEG_Quality__c != null
            ? settings.JPEG_Quality__c
            : 0.8;
        Integer maxFileSizeMB = settings?.Max_File_Size_MB__c != null
            ? (Integer) settings.Max_File_Size_MB__c
            : 10;

        return new Map<String, Object>{
            'maxDimension' => maxDimension,
            'jpegQuality' => jpegQuality,
            'maxFileSizeMB' => maxFileSizeMB,
            'maxFileSizeBytes' => maxFileSizeMB * 1024 * 1024
        };
    }

    /**
     * Upload an image file and update the target record
     * Supports: Contact, Story__c, Library_Item__c, Needs_Offers__c (with image slot 1-4)
     *
     * @param fileData Base64 encoded file data (after client-side compression)
     * @param fileName Original file name
     * @param recordId The record to attach the image to
     * @param objectApiName The object type (Contact, Story__c, etc.)
     * @param imageSlot For Needs_Offers__c, which image slot (1-4). Ignored for other objects.
     * @param imageWidth The width of the compressed image in pixels
     * @param imageHeight The height of the compressed image in pixels
     */
    @AuraEnabled
    public static Map<String, Object> uploadImage(String fileData, String fileName, String recordId,
                                                   String objectApiName, Integer imageSlot,
                                                   Integer imageWidth, Integer imageHeight) {
        try {
            // Validate inputs
            if (String.isBlank(fileData) || String.isBlank(recordId) || String.isBlank(objectApiName)) {
                throw new AuraHandledException('Missing required parameters');
            }

            // Remove data URL prefix if present (data:image/jpeg;base64,)
            String base64Data = fileData;
            if (fileData.contains(',')) {
                base64Data = fileData.substringAfter(',');
            }

            // Decode base64 to blob
            Blob fileBlob = EncodingUtil.base64Decode(base64Data);

            // Create ContentVersion
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = fileBlob;
            cv.IsMajorVersion = true;
            Database.insert(cv, true);

            // Get the ContentDocumentId
            cv = [SELECT Id, ContentDocumentId, ContentBodyId FROM ContentVersion WHERE Id = :cv.Id WITH SECURITY_ENFORCED LIMIT 1];

            // Link to the record
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = cv.ContentDocumentId;
            cdl.LinkedEntityId = recordId;
            cdl.ShareType = 'V'; // Viewer permission
            cdl.Visibility = 'AllUsers';
            Database.insert(cdl, true);

            // Create ContentDistribution for public URL
            ContentDistribution cd = new ContentDistribution();
            cd.ContentVersionId = cv.Id;
            cd.Name = fileName;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesNotifyOnVisit = false;
            cd.PreferencesPasswordRequired = false;
            cd.PreferencesAllowOriginalDownload = true;
            Database.insert(cd, true);

            // Query back to get the DistributionPublicUrl
            cd = [SELECT Id, DistributionPublicUrl FROM ContentDistribution WHERE Id = :cd.Id WITH SECURITY_ENFORCED LIMIT 1];

            // Build the view URL (same format as GoogleDriveAPIController)
            String versionId15 = String.valueOf(cv.Id).substring(0, 15);
            String contentBodyId15 = String.valueOf(cv.ContentBodyId).substring(0, 15);
            String baseUrl = cd.DistributionPublicUrl.substringBefore('/sfc');
            baseUrl = baseUrl.replace('my.salesforce', 'file.force');
            String ending = cd.DistributionPublicUrl.substringAfterLast('/a/');

            String viewUrl = baseUrl
                + FimbySettings.getUrl('File_Download') + '?rendition=ORIGINAL_Jpg'
                + '&versionId=' + versionId15
                + '&operationContext=DELIVERY&contentId=' + contentBodyId15
                + '&page=0&d=/a/' + ending
                + '&oid=';

            // Calculate thumbnail ratio (max 200px, same as existing system)
            Integer maxThumb = 200;
            Double scaleFactor = (Double) maxThumb / Math.max(imageWidth, imageHeight);
            Integer thumbWidth = (Integer) Math.round(imageWidth * scaleFactor);
            Integer thumbHeight = (Integer) Math.round(imageHeight * scaleFactor);
            String imageRatio = String.valueOf(thumbWidth) + 'X' + String.valueOf(thumbHeight);

            // Update the target record with image URL (without org ID — formula field appends it)
            new ImageRecordUpdater().updateRecordImage(
                recordId, objectApiName, imageSlot, viewUrl, imageRatio
            );

            // Return the full URL with org ID for immediate LWC preview
            String previewUrl = viewUrl + UserInfo.getOrganizationId();

            return new Map<String, Object>{
                'success' => true,
                'contentVersionId' => cv.Id,
                'contentDocumentId' => cv.ContentDocumentId,
                'viewUrl' => previewUrl,
                'imageRatio' => imageRatio,
                'message' => 'Image uploaded successfully'
            };

        } catch (Exception e) {
            FimbyLogger.error('FimbyLibraryController', 'uploadImage', e);
            AuraHandledException ex = new AuraHandledException('Error uploading image: ' + e.getMessage());
            ex.setMessage('Error uploading image: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Remove an image from a Needs_Offers__c record and consolidate remaining slots
     * so they are contiguous starting from slot 1. Returns the updated slot data.
     */
    @AuraEnabled
    public static Map<String, Object> removeAndConsolidateImage(String recordId, Integer removedSlot) {
        try {
            SObject record = Database.query(
                'SELECT Id, Image_1_URL__c, Image_1_Ratio__c, Image_2_URL__c, Image_2_Ratio__c, ' +
                'Image_3_URL__c, Image_3_Ratio__c, Image_4_URL__c, Image_4_Ratio__c ' +
                'FROM Needs_Offers__c WHERE Id = :recordId WITH SECURITY_ENFORCED LIMIT 1'
            );

            List<Map<String, String>> images = new List<Map<String, String>>();
            for (Integer i = 1; i <= 4; i++) {
                if (i == removedSlot) continue;
                String url = (String) record.get('Image_' + i + '_URL__c');
                String ratio = (String) record.get('Image_' + i + '_Ratio__c');
                if (String.isNotBlank(url)) {
                    images.add(new Map<String, String>{ 'url' => url, 'ratio' => ratio });
                }
            }

            SObject updated = Schema.getGlobalDescribe().get('Needs_Offers__c').newSObject();
            updated.put('Id', recordId);
            for (Integer i = 1; i <= 4; i++) {
                if (i <= images.size()) {
                    updated.put('Image_' + i + '_URL__c', images[i - 1].get('url'));
                    updated.put('Image_' + i + '_Ratio__c', images[i - 1].get('ratio'));
                } else {
                    updated.put('Image_' + i + '_URL__c', null);
                    updated.put('Image_' + i + '_Ratio__c', null);
                }
            }
            new ImageRecordUpdater().updateRecord(updated);

            List<Map<String, Object>> slots = new List<Map<String, Object>>();
            for (Integer i = 0; i < images.size(); i++) {
                String url = images[i].get('url');
                if (url != null && url.endsWith('&oid=')) {
                    url += UserInfo.getOrganizationId();
                }
                slots.add(new Map<String, Object>{
                    'slot' => i + 1,
                    'imageUrl' => url,
                    'imageRatio' => images[i].get('ratio')
                });
            }

            return new Map<String, Object>{ 'success' => true, 'slots' => slots };
        } catch (Exception e) {
            FimbyLogger.error('FimbyLibraryController', 'removeAndConsolidateImage', e);
            AuraHandledException ex = new AuraHandledException('Error removing image: ' + e.getMessage());
            ex.setMessage('Error removing image: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Remove an image from a record
     * Clears the Image_URL__c and Image_Ratio__c fields
     */
    @AuraEnabled
    public static Map<String, Object> removeImage(String recordId, String objectApiName, Integer imageSlot) {
        try {
            new ImageRecordUpdater().updateRecordImage(recordId, objectApiName, imageSlot, null, null);

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Image removed successfully'
            };
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error removing image: ' + e.getMessage());
            ex.setMessage('Error removing image: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get all image slots (1-4) for a Needs_Offers__c record in a single call.
     */
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getAllImageSlots(String recordId) {
        try {
            SObject record = Database.query(
                'SELECT Id, Image_1_URL__c, Image_1_Ratio__c, Image_2_URL__c, Image_2_Ratio__c, ' +
                'Image_3_URL__c, Image_3_Ratio__c, Image_4_URL__c, Image_4_Ratio__c ' +
                'FROM Needs_Offers__c WHERE Id = :recordId WITH SECURITY_ENFORCED LIMIT 1'
            );

            List<Map<String, Object>> slots = new List<Map<String, Object>>();
            String orgId = UserInfo.getOrganizationId();
            for (Integer i = 1; i <= 4; i++) {
                String url = (String) record.get('Image_' + i + '_URL__c');
                String ratio = (String) record.get('Image_' + i + '_Ratio__c');
                if (String.isNotBlank(url)) {
                    if (url.endsWith('&oid=')) {
                        url += orgId;
                    }
                    slots.add(new Map<String, Object>{
                        'slot' => i,
                        'imageUrl' => url,
                        'imageRatio' => ratio
                    });
                }
            }
            return slots;
        } catch (Exception e) {
            FimbyLogger.error('FimbyLibraryController', 'getAllImageSlots', e);
            AuraHandledException ex = new AuraHandledException('Error loading images: ' + e.getMessage());
            ex.setMessage('Error loading images: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get current image URL for a record
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getCurrentImage(String recordId, String objectApiName, Integer imageSlot) {
        try {
            String urlField = getImageUrlFieldName(objectApiName, imageSlot);
            String ratioField = getImageRatioFieldName(objectApiName, imageSlot);

            String query = 'SELECT Id, ' + urlField + ', ' + ratioField +
                          ' FROM ' + objectApiName + ' WHERE Id = :recordId WITH SECURITY_ENFORCED LIMIT 1';
            SObject record = Database.query(query);

            String imageUrl = (String) record.get(urlField);
            if (imageUrl != null && imageUrl.endsWith('&oid=')) {
                imageUrl += UserInfo.getOrganizationId();
            }

            return new Map<String, Object>{
                'success' => true,
                'imageUrl' => imageUrl,
                'imageRatio' => (String) record.get(ratioField)
            };
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error getting current image: ' + e.getMessage());
            ex.setMessage('Error getting current image: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get the Image URL field name based on object and slot
     */
    private static String getImageUrlFieldName(String objectApiName, Integer imageSlot) {
        if (objectApiName == 'Needs_Offers__c' && imageSlot != null && imageSlot >= 1 && imageSlot <= 4) {
            return 'Image_' + imageSlot + '_URL__c';
        }
        return 'Image_URL__c';
    }

    /**
     * Get the Image Ratio field name based on object and slot
     */
    private static String getImageRatioFieldName(String objectApiName, Integer imageSlot) {
        if (objectApiName == 'Needs_Offers__c' && imageSlot != null && imageSlot >= 1 && imageSlot <= 4) {
            return 'Image_' + imageSlot + '_Ratio__c';
        }
        return 'Image_Ratio__c';
    }

    // ============================================
    // HELPER CLASSES
    // ============================================

    /**
     * @description Helper class for deleting library items without sharing restrictions.
     */
    private static String deriveLoanPhase(String formulaStatus) {
        if (String.isBlank(formulaStatus)) return 'onLoan';
        String lower = formulaStatus.toLowerCase();
        if (lower.contains('overdue')) return 'overdue';
        if (lower.contains('extension requested')) return 'extensionRequested';
        if (lower.contains('owner to confirm return') || lower.contains('return')) return 'returnPending';
        return 'onLoan';
    }

    private without sharing class LibraryItemUpdateHelper {
        public Library_Item__c queryItem(Id recordId) {
            List<Library_Item__c> rows = [
                SELECT Id, Listed_By__c, Owner_Contact__c, Name, Description__c, Category__c,
                       Max_Lending_Time_In_Days__c, Auto_Accept_Requests__c, Auto_Share_Contact_Info__c
                FROM Library_Item__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            return rows.isEmpty() ? null : rows[0];
        }

        public void updateItem(Library_Item__c item) {
            update item;
        }
    }

    private without sharing class LibraryItemHelper {
        /**
         * @description Deletes a library item record (DML without sharing).
         * @param item The Library_Item__c record to delete
         */
        public void deleteItem(Library_Item__c item) {
            delete item;
        }
    }

    /**
     * @description Helper class to update image fields on records without sharing.
     */
    private without sharing class ImageRecordUpdater {
        /**
         * @description Updates Image_URL and Image_Ratio fields on the target record (Contact, Story__c, Library_Item__c, or Needs_Offers__c).
         * @param recordId Id of the record to update
         * @param objectApiName Object API name (e.g. Contact, Story__c)
         * @param imageSlot For Needs_Offers__c, slot 1–4; ignored for other objects
         * @param imageUrl URL to set, or null to clear
         * @param imageRatio Ratio string (e.g. 200X150), or null to clear
         */
        public void updateRecord(SObject record) {
            update record;
        }

        public void updateRecordImage(String recordId, String objectApiName, Integer imageSlot,
                                      String imageUrl, String imageRatio) {
            String urlField = getImageUrlFieldName(objectApiName, imageSlot);
            String ratioField = getImageRatioFieldName(objectApiName, imageSlot);

            SObject record = Schema.getGlobalDescribe().get(objectApiName).newSObject();
            record.put('Id', recordId);
            record.put(urlField, imageUrl);
            record.put(ratioField, imageRatio);

            update record;
        }

        private String getImageUrlFieldName(String objectApiName, Integer imageSlot) {
            if (objectApiName == 'Needs_Offers__c' && imageSlot != null && imageSlot >= 1 && imageSlot <= 4) {
                return 'Image_' + imageSlot + '_URL__c';
            }
            return 'Image_URL__c';
        }

        private String getImageRatioFieldName(String objectApiName, Integer imageSlot) {
            if (objectApiName == 'Needs_Offers__c' && imageSlot != null && imageSlot >= 1 && imageSlot <= 4) {
                return 'Image_' + imageSlot + '_Ratio__c';
            }
            return 'Image_Ratio__c';
        }
    }

    /**
     * @description Visibility check for a single Library_Item__c. Mirrors the
     * moderation + neighbourhood/scope filters used by the library feed query.
     * Returns { visible: true } when the item is visible to the running user;
     * otherwise returns { removed: true, message: '...' } so detail LWCs can
     * render a "no longer available" state instead of leaking the record via
     * UI API getRecord (which ignores Moderation_Status__c).
     */
    @AuraEnabled(cacheable=true)
    public static VisibilityResult getLibraryItemVisibility(Id recordId) {
        if (recordId == null) {
            return new VisibilityResult(false, true, 'This item is no longer available.');
        }

        try {
            String neighbourhoodAccountId = FimbyIdentityRepository.getNeighbourhoodId();
            Set<Id> adjacentIds = FimbyNeighbourhoodService.getAdjacentNeighbourhoodIds();
            Set<Id> sharedContactIds = FimbyNeighbourhoodService.getAdjacentSharedContactIds();

            String query = 'SELECT Id FROM Library_Item__c WHERE Id = :recordId '
                + 'AND (Moderation_Status__c = null OR Moderation_Status__c = \'Visible\')';

            // Mirror library list query: only apply neighbourhood filter when context is resolvable.
            if (String.isNotBlank(neighbourhoodAccountId)) {
                query += ' AND (Neighbourhood__c = :neighbourhoodAccountId'
                    + ' OR (Neighbourhood__c IN :adjacentIds AND Visibility_Scope__c IN (\'Adjacent\',\'Regional\'))'
                    + ' OR (Neighbourhood__c IN :adjacentIds AND Owner_Contact__c IN :sharedContactIds))';
            }

            query += ' LIMIT 1';

            List<Library_Item__c> rows = Database.query(query);

            return rows.isEmpty()
                ? new VisibilityResult(false, true, 'This item is no longer available.')
                : new VisibilityResult(true, false, null);

        } catch (Exception e) {
            FimbyLogger.error('FimbyLibraryController', 'getLibraryItemVisibility', e);
            return new VisibilityResult(false, true, 'This item is no longer available.');
        }
    }

    public class VisibilityResult {
        @AuraEnabled public Boolean visible { get; set; }
        @AuraEnabled public Boolean removed { get; set; }
        @AuraEnabled public String message { get; set; }

        public VisibilityResult(Boolean visible, Boolean removed, String message) {
            this.visible = visible;
            this.removed = removed;
            this.message = message;
        }
    }
}