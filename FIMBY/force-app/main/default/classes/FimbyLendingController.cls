/**
 * @description Handles Lending Request approval, confirmation, and extension operations.
 * Converted from Lending_Request_Approval.flow (SystemModeWithoutSharing).
 */
public with sharing class FimbyLendingController {

    /**
     * Get Lending Request details for the approval form
     * Validates that current user is the item owner and request is pending
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLendingRequestForApproval(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'noRecordId',
                    'message' => 'No lending request specified.'
                };
            }

            // Get lending request with related data
            Lending_Request__c lendingRequest = [
                SELECT Id, Name, Status__c, Requested_Date__c, of_Days_Needed__c,
                       Requested_By__c, Requested_By__r.Full_Name__c, Requested_By__r.FirstName,
                       Library_Item__c, Library_Item__r.Id, Library_Item__r.Name,
                       Library_Item__r.OwnerId, Library_Item__r.RecordType.Name,
                       Item_Owner__c, Item_Owner__r.Id, Item_Owner__r.FirstName, Item_Owner__r.LastName,
                       Item_Owner__r.Email, Item_Owner__r.Phone,
                       Item_Owner__r.MailingStreet, Item_Owner__r.MailingCity,
                       Item_Owner__r.MailingState, Item_Owner__r.MailingPostalCode,
                       Item_Owner__r.MailingCountry
                FROM Lending_Request__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            User currentUser = FimbyIdentityRepository.getCurrentUser();

            String currentUserId18 = currentUser.User_ID_18_Digits__c != null
                ? currentUser.User_ID_18_Digits__c
                : UserInfo.getUserId();
            String itemOwnerId = String.valueOf(lendingRequest.Library_Item__r.OwnerId);

            if (currentUserId18 != itemOwnerId && UserInfo.getUserId() != lendingRequest.Library_Item__r.OwnerId) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notOwner',
                    'message' => 'You are not the owner of this item.'
                };
            }

            // Validate: Request must be Pending Approval
            if (lendingRequest.Status__c != FimbyConstants.LENDING_PENDING_APPROVAL) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'nothingToApprove',
                    'message' => 'This request does not require approval.'
                };
            }

            // Format requested date
            String requestedDateStr = lendingRequest.Requested_Date__c != null
                ? lendingRequest.Requested_Date__c.format()
                : 'Not specified';

            return new Map<String, Object>{
                'success' => true,
                'lendingRequest' => new Map<String, Object>{
                    'id' => lendingRequest.Id,
                    'name' => lendingRequest.Name,
                    'status' => lendingRequest.Status__c,
                    'requestedDate' => requestedDateStr,
                    'daysNeeded' => lendingRequest.of_Days_Needed__c,
                    'requestedById' => lendingRequest.Requested_By__c
                },
                'libraryItem' => new Map<String, Object>{
                    'id' => lendingRequest.Library_Item__r.Id,
                    'name' => lendingRequest.Library_Item__r.Name,
                    'recordTypeName' => lendingRequest.Library_Item__r.RecordType?.Name
                },
                'requesterName' => lendingRequest.Requested_By__r?.Full_Name__c != null
                    ? lendingRequest.Requested_By__r.Full_Name__c
                    : lendingRequest.Requested_By__r?.FirstName,
                'ownerContact' => new Map<String, Object>{
                    'id' => lendingRequest.Item_Owner__r?.Id,
                    'firstName' => lendingRequest.Item_Owner__r?.FirstName,
                    'lastName' => lendingRequest.Item_Owner__r?.LastName,
                    'email' => lendingRequest.Item_Owner__r?.Email,
                    'phone' => lendingRequest.Item_Owner__r?.Phone,
                    'mailingStreet' => lendingRequest.Item_Owner__r?.MailingStreet,
                    'mailingCity' => lendingRequest.Item_Owner__r?.MailingCity,
                    'mailingState' => lendingRequest.Item_Owner__r?.MailingState,
                    'mailingPostalCode' => lendingRequest.Item_Owner__r?.MailingPostalCode,
                    'mailingCountry' => lendingRequest.Item_Owner__r?.MailingCountry
                }
            };

        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error loading lending request: ' + e.getMessage());
            ex.setMessage('Error loading lending request: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Approve a lending request
     * - Updates status to Approved
     * - Sets approval date and pickup date
     * - Shares contact info with requester
     * - Sends approval email
     */
    @AuraEnabled
    public static Map<String, Object> approveLendingRequest(String recordId, String pickupDate, String shareContactData) {
        try {
            // Use without sharing helper for DML
            return new LendingHelper().approveRequestInternal(recordId, pickupDate, shareContactData);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error approving request: ' + e.getMessage());
            ex.setMessage('Error approving request: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Auto-approve a lending request (called internally by FimbyLibraryController when Auto_Accept_Requests__c is true).
     * Not @AuraEnabled — Apex-only entry point.
     */
    public static Map<String, Object> autoApproveRequest(String recordId, String pickupDate, String shareContactData) {
        return new LendingHelper().approveRequestInternal(recordId, pickupDate, shareContactData);
    }

    /**
     * Decline a lending request
     * - Updates status to Declined
     * - Sets decline reason
     * - Sends decline email
     */
    @AuraEnabled
    public static Map<String, Object> declineLendingRequest(String recordId, String declineReason) {
        try {
            // Use without sharing helper for DML
            return new LendingHelper().declineRequestInternal(recordId, declineReason);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error declining request: ' + e.getMessage());
            ex.setMessage('Error declining request: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get Lending Request details for the confirmation form (waitlist confirmation)
     * Validates that current user is the requester and request is on waitlist
     */
    @AuraEnabled
    public static Map<String, Object> getLendingRequestForConfirmation(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'noRecordId',
                    'message' => 'No lending request specified.'
                };
            }

            // Get lending request with related data
            Lending_Request__c lendingRequest = [
                SELECT Id, Name, Status__c, Waitlist_Position__c, CreatedDate,
                       Requested_By__c, Requested_By_Real_Contact__c,
                       Library_Item__c, Library_Item__r.Name,
                       Library_Item_Owner_s_First_Name__c, Library_Item_Name__c
                FROM Lending_Request__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();
            Id realContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            // Dual-check: caller may be the represented identity OR the real submitter
            Boolean isRequester =
                (actingAsContactId != null && actingAsContactId == lendingRequest.Requested_By__c) ||
                (realContactId != null && realContactId == lendingRequest.Requested_By_Real_Contact__c);
            if (!isRequester) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notRequester',
                    'message' => 'You are not the person who requested to borrow this item.'
                };
            }

            Boolean isAwaitingConfirmation =
                lendingRequest.Status__c == FimbyConstants.LENDING_REQUESTING_CONFIRMATION;
            Boolean isWaitlistedFirst =
                lendingRequest.Status__c == FimbyConstants.LENDING_WAITLISTED
                && lendingRequest.Waitlist_Position__c == 1;

            if (!isAwaitingConfirmation && !isWaitlistedFirst) {
                if (lendingRequest.Status__c == FimbyConstants.LENDING_WAITLISTED) {
                    return new Map<String, Object>{
                        'success' => false,
                        'error' => 'notFirst',
                        'message' => 'Only items at the top of the waitlist need to be confirmed.'
                    };
                }
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notOnWaitlist',
                    'message' => 'The request is no longer on the waitlist and does not require confirmation.'
                };
            }

            // Format created date
            String createdDateStr = lendingRequest.CreatedDate != null
                ? lendingRequest.CreatedDate.format('MMMM d, yyyy')
                : 'Unknown';

            return new Map<String, Object>{
                'success' => true,
                'lendingRequest' => new Map<String, Object>{
                    'id' => lendingRequest.Id,
                    'name' => lendingRequest.Name,
                    'status' => lendingRequest.Status__c,
                    'itemName' => lendingRequest.Library_Item_Name__c != null
                        ? lendingRequest.Library_Item_Name__c
                        : lendingRequest.Library_Item__r?.Name,
                    'ownerFirstName' => lendingRequest.Library_Item_Owner_s_First_Name__c,
                    'createdDate' => createdDateStr,
                    'libraryItemId' => lendingRequest.Library_Item__c
                }
            };

        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error loading lending request: ' + e.getMessage());
            ex.setMessage('Error loading lending request: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get Lending Request details for the pickup / handoff confirmation modal.
     * Validates that the current user is the item owner or the borrower, and the request is Approved.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLendingRequestForHandoff(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'noRecordId',
                    'message' => 'No lending request specified.'
                };
            }

            Lending_Request__c lendingRequest = [
                SELECT Id, Name, Status__c, Requested_Date__c, of_Days_Needed__c,
                       Approved_and_Available_Date__c,
                       Requested_By__c, Requested_By_Real_Contact__c,
                       Requested_By__r.Full_Name__c, Requested_By__r.FirstName,
                       Library_Item__c, Library_Item__r.Id, Library_Item__r.Name,
                       Library_Item__r.Owner_Contact__c,
                       Item_Owner__c, Item_Owner__r.Id, Item_Owner__r.FirstName, Item_Owner__r.LastName,
                       Item_Owner__r.Email, Item_Owner__r.Phone,
                       Item_Owner__r.MailingStreet, Item_Owner__r.MailingCity,
                       Item_Owner__r.MailingState, Item_Owner__r.MailingPostalCode,
                       Item_Owner__r.MailingCountry
                FROM Lending_Request__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id callerContactId = identity.actingAsContactId;
            Id realContactId = identity.currentUser != null ? identity.currentUser.ContactId : null;
            Boolean isOwner = (callerContactId == lendingRequest.Item_Owner__c ||
                callerContactId == lendingRequest.Library_Item__r.Owner_Contact__c);
            // Borrower dual-check: represented identity OR real Contact who submitted
            Boolean isBorrower = (callerContactId == lendingRequest.Requested_By__c) ||
                (realContactId != null && realContactId == lendingRequest.Requested_By_Real_Contact__c);
            if (!isOwner && !isBorrower) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notParticipant',
                    'message' => 'Only the item owner or borrower can confirm pickup.'
                };
            }

            if (lendingRequest.Status__c != FimbyConstants.LENDING_APPROVED) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'wrongStatus',
                    'message' => 'This request is not ready for pickup confirmation.'
                };
            }

            Date startDate = (lendingRequest.Approved_and_Available_Date__c != null)
                ? lendingRequest.Approved_and_Available_Date__c : Date.today();
            Integer daysNeeded = (lendingRequest.of_Days_Needed__c != null)
                ? Integer.valueOf(lendingRequest.of_Days_Needed__c) : 7;
            Date dueDate = startDate.addDays(daysNeeded);

            String requestedDateStr = lendingRequest.Requested_Date__c != null
                ? lendingRequest.Requested_Date__c.format()
                : 'Not specified';

            String ownerDisplayName = '';
            if (lendingRequest.Item_Owner__r != null) {
                String fn = lendingRequest.Item_Owner__r.FirstName != null
                    ? lendingRequest.Item_Owner__r.FirstName : '';
                String ln = lendingRequest.Item_Owner__r.LastName != null
                    ? lendingRequest.Item_Owner__r.LastName : '';
                ownerDisplayName = (fn + ' ' + ln).trim();
            }

            return new Map<String, Object>{
                'success' => true,
                'lendingRequest' => new Map<String, Object>{
                    'id' => lendingRequest.Id,
                    'name' => lendingRequest.Name,
                    'status' => lendingRequest.Status__c,
                    'requestedDate' => requestedDateStr,
                    'dueDate' => String.valueOf(dueDate),
                    'daysNeeded' => lendingRequest.of_Days_Needed__c,
                    'requestedById' => lendingRequest.Requested_By__c
                },
                'libraryItem' => new Map<String, Object>{
                    'id' => lendingRequest.Library_Item__r.Id,
                    'name' => lendingRequest.Library_Item__r.Name,
                    'recordTypeName' => null
                },
                'requesterName' => lendingRequest.Requested_By__r?.Full_Name__c != null
                    ? lendingRequest.Requested_By__r.Full_Name__c
                    : lendingRequest.Requested_By__r?.FirstName,
                'ownerContact' => new Map<String, Object>{
                    'id' => lendingRequest.Item_Owner__r?.Id,
                    'name' => ownerDisplayName,
                    'firstName' => lendingRequest.Item_Owner__r?.FirstName,
                    'lastName' => lendingRequest.Item_Owner__r?.LastName,
                    'email' => lendingRequest.Item_Owner__r?.Email,
                    'phone' => lendingRequest.Item_Owner__r?.Phone,
                    'mailingStreet' => lendingRequest.Item_Owner__r?.MailingStreet,
                    'mailingCity' => lendingRequest.Item_Owner__r?.MailingCity,
                    'mailingState' => lendingRequest.Item_Owner__r?.MailingState,
                    'mailingPostalCode' => lendingRequest.Item_Owner__r?.MailingPostalCode,
                    'mailingCountry' => lendingRequest.Item_Owner__r?.MailingCountry
                }
            };

        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error loading lending request: ' + e.getMessage());
            ex.setMessage('Error loading lending request: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Confirm a waitlisted lending request
     * - Updates status to Pending Approval
     * - Sets requested date to the new borrow date
     */
    @AuraEnabled
    public static Map<String, Object> confirmLendingRequest(String recordId, String borrowDate) {
        try {
            return new LendingHelper().confirmRequestInternal(recordId, borrowDate);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error confirming request: ' + e.getMessage());
            ex.setMessage('Error confirming request: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Cancel a waitlisted lending request
     * - Updates status to Cancelled
     */
    @AuraEnabled
    public static Map<String, Object> cancelLendingRequest(String recordId) {
        try {
            return new LendingHelper().cancelRequestInternal(recordId);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error cancelling request: ' + e.getMessage());
            ex.setMessage('Error cancelling request: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get Loaned Item details for the extension form
     * Validates that current user is the borrower or owner, and no one is on waitlist
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLoanedItemForExtension(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'noRecordId',
                    'message' => 'No loaned item specified.'
                };
            }

            // Get loaned item with related data
            Loaned_Item__c loanedItem = [
                SELECT Id, Name, Loan_Start_Date__c, Loan_Due_Date__c,
                       Loaned_To__c, Loaned_To_Real_Contact__c, Owned_By__c,
                       Loaned_To__r.FirstName, Loaned_To__r.Full_Name__c,
                       Library_Item__c, Library_Item__r.Id, Library_Item__r.Name,
                       Library_Item__r.OwnerId, Library_Item__r.Owner_Contact__c,
                       Requester_s_First_Name__c, Item_Owner_s_First_Name__c
                FROM Loaned_Item__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            User currentUser = FimbyIdentityRepository.getCurrentUser();
            Id callerContactId = FimbyIdentityRepository.getIdentity().actingAsContactId;

            String currentUserId18 = currentUser.User_ID_18_Digits__c != null
                ? currentUser.User_ID_18_Digits__c
                : UserInfo.getUserId();
            String itemOwnerId = String.valueOf(loanedItem.Library_Item__r.OwnerId);
            Boolean isOwnerByUser = (currentUserId18 == itemOwnerId || UserInfo.getUserId() == loanedItem.Library_Item__r.OwnerId);
            Boolean isOwnerByContact = (callerContactId != null && loanedItem.Owned_By__c != null
                && callerContactId == loanedItem.Owned_By__c)
                || (callerContactId != null && loanedItem.Library_Item__r.Owner_Contact__c != null
                    && callerContactId == loanedItem.Library_Item__r.Owner_Contact__c);
            Boolean isOwner = isOwnerByUser || isOwnerByContact;

            // Check if there are others on the waitlist
            List<Lending_Request__c> waitlistRequests = [
                SELECT Id
                FROM Lending_Request__c
                WHERE Library_Item__c = :loanedItem.Library_Item__c
                AND Status__c = 'Waitlisted'
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            Boolean hasWaitlist = !waitlistRequests.isEmpty();

            // Validate: If waitlist exists and user is not owner, block extension
            if (hasWaitlist && !isOwner) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'waitlist',
                    'message' => 'Extension cannot be requested when there are others on the waitlist.'
                };
            }

            // Borrower dual-check: represented identity OR real Contact who confirmed handoff
            Id realContactId_borrower = currentUser != null ? currentUser.ContactId : null;
            Boolean isBorrower = (callerContactId != null && callerContactId == loanedItem.Loaned_To__c) ||
                (realContactId_borrower != null && realContactId_borrower == loanedItem.Loaned_To_Real_Contact__c);

            if (!isOwner && !isBorrower) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notAuthorized',
                    'message' => 'Only the borrower or owner can extend the due date.'
                };
            }

            return new Map<String, Object>{
                'success' => true,
                'loanedItem' => new Map<String, Object>{
                    'id' => loanedItem.Id,
                    'name' => loanedItem.Name,
                    'startDate' => loanedItem.Loan_Start_Date__c,
                    'startDateDisplay' => loanedItem.Loan_Start_Date__c != null
                        ? loanedItem.Loan_Start_Date__c.format()
                        : 'Unknown',
                    'dueDate' => loanedItem.Loan_Due_Date__c,
                    'dueDateDisplay' => loanedItem.Loan_Due_Date__c != null
                        ? loanedItem.Loan_Due_Date__c.format()
                        : 'Not set',
                    'borrowerFirstName' => loanedItem.Requester_s_First_Name__c,
                    'ownerFirstName' => loanedItem.Item_Owner_s_First_Name__c
                },
                'libraryItem' => new Map<String, Object>{
                    'id' => loanedItem.Library_Item__r.Id,
                    'name' => loanedItem.Library_Item__r.Name
                },
                'isOwner' => isOwner
            };

        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error loading loaned item: ' + e.getMessage());
            ex.setMessage('Error loading loaned item: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Request or approve a loan extension
     * - If owner: Updates due date immediately and sends email to borrower
     * - If borrower: Sets requested extension date and sends email to owner
     */
    @AuraEnabled
    public static Map<String, Object> requestLoanExtension(String recordId, String newDueDate) {
        try {
            return new LendingHelper().requestExtensionInternal(recordId, newDueDate);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error requesting extension: ' + e.getMessage());
            ex.setMessage('Error requesting extension: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get Loaned Item details for the extension approval form
     * Validates that current user is the owner and extension is requested
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLoanedItemForExtensionApproval(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'noRecordId',
                    'message' => 'No loaned item specified.'
                };
            }

            // Get loaned item with related data
            List<Loaned_Item__c> loanedItems = [
                SELECT Id, Name, Loan_Due_Date__c, Requested_Due_Date_Extension__c,
                       Loaned_To__c, Loaned_To__r.FirstName, Loaned_To__r.Full_Name__c,
                       Library_Item__c, Library_Item__r.Id, Library_Item__r.Name,
                       Library_Item__r.OwnerId,
                       Requester_s_First_Name__c, Library_Item_Name__c
                FROM Loaned_Item__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Validate: Loaned item must exist
            if (loanedItems.isEmpty()) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notOnLoan',
                    'message' => 'This loan has been completed so there is no extension required.'
                };
            }

            Loaned_Item__c loanedItem = loanedItems[0];

            User currentUser = FimbyIdentityRepository.getCurrentUser();

            String currentUserId18 = currentUser.User_ID_18_Digits__c != null
                ? currentUser.User_ID_18_Digits__c
                : UserInfo.getUserId();
            String itemOwnerId = String.valueOf(loanedItem.Library_Item__r.OwnerId);

            if (currentUserId18 != itemOwnerId && UserInfo.getUserId() != loanedItem.Library_Item__r.OwnerId) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notOwner',
                    'message' => 'You are not the owner of this item.'
                };
            }

            // Validate: Extension must be requested
            if (loanedItem.Requested_Due_Date_Extension__c == null) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'noExtension',
                    'message' => 'The borrower has not requested an extension.'
                };
            }

            return new Map<String, Object>{
                'success' => true,
                'loanedItem' => new Map<String, Object>{
                    'id' => loanedItem.Id,
                    'name' => loanedItem.Name,
                    'itemName' => loanedItem.Library_Item_Name__c != null
                        ? loanedItem.Library_Item_Name__c
                        : loanedItem.Library_Item__r?.Name,
                    'borrowerFirstName' => loanedItem.Requester_s_First_Name__c != null
                        ? loanedItem.Requester_s_First_Name__c
                        : loanedItem.Loaned_To__r?.FirstName,
                    'dueDateDisplay' => loanedItem.Loan_Due_Date__c != null
                        ? loanedItem.Loan_Due_Date__c.format()
                        : 'Not set',
                    'requestedDateDisplay' => loanedItem.Requested_Due_Date_Extension__c != null
                        ? loanedItem.Requested_Due_Date_Extension__c.format()
                        : 'Not set',
                    'libraryItemId' => loanedItem.Library_Item__c
                }
            };

        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error loading extension request: ' + e.getMessage());
            ex.setMessage('Error loading extension request: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Approve a loan extension request
     * - Updates Loan_Due_Date__c to the requested date
     * - Clears Requested_Due_Date_Extension__c
     * - Sends approval email
     */
    @AuraEnabled
    public static Map<String, Object> approveExtension(String recordId) {
        try {
            return new LendingHelper().approveExtensionInternal(recordId);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error approving extension: ' + e.getMessage());
            ex.setMessage('Error approving extension: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Decline a loan extension request
     * - Clears Requested_Due_Date_Extension__c
     * - Sets Extension_Decline_Reason__c
     * - Sends decline email
     */
    @AuraEnabled
    public static Map<String, Object> declineExtension(String recordId, String declineReason) {
        try {
            return new LendingHelper().declineExtensionInternal(recordId, declineReason);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error declining extension: ' + e.getMessage());
            ex.setMessage('Error declining extension: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Record physical handoff — either owner or borrower confirms the item changed hands.
     * Creates Loaned_Item__c, transfers conversation, deletes request.
     * Idempotent: concurrent calls return graceful success.
     */
    @AuraEnabled
    public static Map<String, Object> recordHandoff(String requestId) {
        try {
            return new LendingHelper().recordHandoffInternal(requestId);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error recording handoff: ' + e.getMessage());
            ex.setMessage('Error recording handoff: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Returns lending lifecycle context for a conversation thread.
     * Called by fimbyConversationView when contextType is Library_Lending.
     */
    @AuraEnabled
    public static Map<String, Object> getLendingConversationContext(String conversationId) {
        try {
            return new LendingHelper().getLendingConversationContextInternal(conversationId);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error loading lending context: ' + e.getMessage());
            ex.setMessage('Error loading lending context: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * @description Helper class for DML operations without sharing.
     * Matches flow's SystemModeWithoutSharing behavior.
     */
    private without sharing class LendingHelper {

        /**
         * @description Approves a lending request, updates status, shares contact info, and creates DM conversation.
         * @param recordId Id of the Lending_Request__c record
         * @param pickupDate Approved pickup date (ISO string)
         * @param shareContactData JSON with shareEmail, sharePhone, shareAddress flags and contact details
         * @return Map with success flag and message
         */
        public Map<String, Object> approveRequestInternal(String recordId, String pickupDate, String shareContactData) {
            // Get lending request
            Lending_Request__c lendingRequest = [
                SELECT Id, Status__c, Requested_By__c, Item_Owner__c,
                       Library_Item__c, Library_Item__r.Name, Library_Item__r.RecordType.Name
                FROM Lending_Request__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            // Parse pickup date
            Date approvedDate = Date.valueOf(pickupDate);

            // Update lending request
            lendingRequest.Status__c = FimbyConstants.LENDING_APPROVED;
            lendingRequest.Date_Approved__c = Date.today();
            lendingRequest.Approved_and_Available_Date__c = approvedDate;
            update lendingRequest;

            // Share contact info
            if (String.isNotBlank(shareContactData)) {
                shareContactInfoForLending(lendingRequest.Item_Owner__c, lendingRequest.Requested_By__c, shareContactData, lendingRequest.Id);
            }

            // Send approval email (via workflow/email alert)
            // The Lending_Request_Approved email alert should be triggered by status change

            // Create in-app notification for borrower. Action URL deep-links to the
            // pickup-confirmation modal so tapping (in-app or email) opens the next
            // step immediately. See notification-coverage-matrix + lending plan Phase 1.
            Contact owner = [SELECT Id, FirstName FROM Contact WHERE Id = :lendingRequest.Item_Owner__c LIMIT 1];
            String ownerFirstName = owner.FirstName != null ? owner.FirstName : 'A neighbour';
            if (lendingRequest.Requested_By__c != null) {
                String approvedActionUrl = FimbySettings.getUrl('Library_Item',
                    String.valueOf(lendingRequest.Library_Item__c),
                    '?action=confirmPickup&requestId=' + lendingRequest.Id);
                FimbyNotificationService.createNotification(
                    lendingRequest.Requested_By__c,
                    FimbyConstants.NOTIF_LOAN_APPROVED,
                    'Your borrow request was approved',
                    'Pickup date: ' + String.valueOf(approvedDate) + '.',
                    lendingRequest.Id,
                    'Lending_Request__c',
                    approvedActionUrl,
                    ownerFirstName
                );
            }

            // Auto-create a DM conversation between borrower and lender for coordination
            if (lendingRequest.Requested_By__c != null && lendingRequest.Item_Owner__c != null) {
                try {
                    Id ownerId = lendingRequest.Item_Owner__c;
                    Id borrowerId = lendingRequest.Requested_By__c;

                    List<Conversation__c> existingConv = [
                        SELECT Id FROM Conversation__c
                        WHERE Context_Type__c = 'Library_Lending'
                          AND Related_Record_Id__c = :recordId
                        LIMIT 1
                    ];

                    if (existingConv.isEmpty()) {
                        String itemName = lendingRequest.Library_Item__r?.Name != null
                            ? lendingRequest.Library_Item__r.Name : 'your item';
                        String autoMessage = 'Your borrow request for ' + itemName
                            + ' has been approved! Pickup date: ' + String.valueOf(approvedDate)
                            + '. Feel free to message here to coordinate.';

                        Conversation__c newConv = new Conversation__c(
                            Participant_1__c = ownerId,
                            Participant_2__c = borrowerId,
                            Status__c = FimbyConstants.CONVERSATION_ACTIVE,
                            Context_Type__c = FimbyConstants.CTX_LIBRARY_LENDING,
                            Related_Record_Id__c = recordId,
                            Participant_1_Unread_Count__c = 0,
                            Participant_2_Unread_Count__c = 1,
                            Participant_1_Archived__c = false,
                            Participant_2_Archived__c = false,
                            Last_Message_Preview__c = autoMessage.left(255),
                            Last_Message_Date__c = Datetime.now()
                        );
                        insert newConv;

                        Message__c firstMsg = new Message__c(
                            Conversation__c = newConv.Id,
                            Body__c = autoMessage,
                            Sender__c = ownerId,
                            Sent_By__c = ownerId,
                            Sent_Date__c = Datetime.now(),
                            Status__c = FimbyConstants.MESSAGE_SENT
                        );
                        insert firstMsg;
                    }
                } catch (Exception e) {
                    FimbyLogger.error('FimbyLendingController', 'approveRequestInternal', e);
                }
            }

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Lending request approved successfully'
            };
        }

        /**
         * @description Declines a lending request and updates status and decline reason.
         * @param recordId Id of the Lending_Request__c record
         * @param declineReason Reason entered by the owner for declining
         * @return Map with success flag, libraryItemId, and message
         */
        public Map<String, Object> declineRequestInternal(String recordId, String declineReason) {
            Lending_Request__c lendingRequest = [
                SELECT Id, Status__c, Decline_Reason__c, Library_Item__c,
                       Requested_By__c, Item_Owner__c, Item_Owner__r.FirstName
                FROM Lending_Request__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            lendingRequest.Status__c = FimbyConstants.LENDING_DECLINED;
            lendingRequest.Decline_Reason__c = declineReason;
            update lendingRequest;

            if (lendingRequest.Requested_By__c != null) {
                String ownerFirstName = lendingRequest.Item_Owner__r.FirstName != null
                    ? lendingRequest.Item_Owner__r.FirstName : 'A neighbour';
                String notifBody = String.isNotBlank(declineReason)
                    ? declineReason
                    : 'The owner wasn\'t able to lend this item right now.';
                FimbyNotificationService.createNotification(
                    lendingRequest.Requested_By__c,
                    FimbyConstants.NOTIF_LENDING_REQUEST,
                    'Your borrow request was declined',
                    notifBody,
                    lendingRequest.Library_Item__c,
                    'Library_Item__c',
                    FimbySettings.getUrl('Library_Item', String.valueOf(lendingRequest.Library_Item__c)),
                    ownerFirstName
                );
            }

            return new Map<String, Object>{
                'success' => true,
                'libraryItemId' => lendingRequest.Library_Item__c,
                'message' => 'Lending request declined'
            };
        }

        /**
         * @description Confirms a waitlisted lending request; sets status to Pending Approval and requested date.
         * @param recordId Id of the Lending_Request__c record
         * @param borrowDate New borrow date (ISO string)
         * @return Map with success flag and message
         */
        public Map<String, Object> confirmRequestInternal(String recordId, String borrowDate) {
            Lending_Request__c lendingRequest = [
                SELECT Id, Status__c, Requested_Date__c, Item_Owner__c,
                       Library_Item__c, Library_Item__r.Name,
                       Requested_By__c, Requested_By_Real_Contact__c,
                       Requested_By__r.FirstName, Waitlist_Position__c
                FROM Lending_Request__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            Id actingAsContactId = FimbyIdentityRepository.getActingAsContactId();
            Id realContactId = FimbyIdentityRepository.getCurrentUser().ContactId;
            Boolean isRequester =
                (actingAsContactId != null && actingAsContactId == lendingRequest.Requested_By__c)
                || (realContactId != null && realContactId == lendingRequest.Requested_By_Real_Contact__c);
            if (!isRequester) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notRequester',
                    'message' => 'You are not the person who requested to borrow this item.'
                };
            }

            Boolean canConfirm =
                lendingRequest.Status__c == FimbyConstants.LENDING_REQUESTING_CONFIRMATION
                || (lendingRequest.Status__c == FimbyConstants.LENDING_WAITLISTED
                    && lendingRequest.Waitlist_Position__c == 1);
            if (!canConfirm) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notConfirmable',
                    'message' => 'This request is no longer waiting for your confirmation.'
                };
            }

            lendingRequest.Status__c = FimbyConstants.LENDING_PENDING_APPROVAL;
            if (String.isNotBlank(borrowDate)) {
                lendingRequest.Requested_Date__c = Date.valueOf(borrowDate);
            }
            update lendingRequest;

            if (lendingRequest.Item_Owner__c != null) {
                String borrowerFirstName = lendingRequest.Requested_By__r.FirstName != null
                    ? lendingRequest.Requested_By__r.FirstName : 'A neighbour';
                String itemName = lendingRequest.Library_Item__r.Name;
                String actionUrl = FimbySettings.getUrl('Library_Item',
                    String.valueOf(lendingRequest.Library_Item__c),
                    '?action=reviewRequest&requestId=' + recordId);
                FimbyNotificationService.createNotification(
                    lendingRequest.Item_Owner__c,
                    FimbyConstants.NOTIF_LENDING_REQUEST,
                    borrowerFirstName + ' confirmed, ready to borrow ' + itemName,
                    'Review their request.',
                    lendingRequest.Id,
                    'Lending_Request__c',
                    actionUrl,
                    borrowerFirstName
                );
            }

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Request confirmed and waiting for owner approval'
            };
        }

        /**
         * @description Cancels a waitlisted lending request and removes from waitlist.
         * @param recordId Id of the Lending_Request__c record
         * @return Map with success flag and message
         */
        public Map<String, Object> cancelRequestInternal(String recordId) {
            Lending_Request__c lendingRequest = [
                SELECT Id, Status__c, Neighbourhood__c, Library_Item__c,
                       Item_Owner__c, Requested_By__r.FirstName,
                       Library_Item__r.Name
                FROM Lending_Request__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            lendingRequest.Status__c = FimbyConstants.LENDING_CANCELLED;
            lendingRequest.Neighbourhood__c = null;
            update lendingRequest;

            if (lendingRequest.Item_Owner__c != null) {
                String borrowerFirstName = lendingRequest.Requested_By__r.FirstName != null
                    ? lendingRequest.Requested_By__r.FirstName : 'A neighbour';
                FimbyNotificationService.createNotification(
                    lendingRequest.Item_Owner__c,
                    FimbyConstants.NOTIF_LENDING_REQUEST,
                    borrowerFirstName + ' cancelled their request for ' + lendingRequest.Library_Item__r.Name,
                    '',
                    lendingRequest.Library_Item__c,
                    'Library_Item__c',
                    FimbySettings.getUrl('Library_Item', String.valueOf(lendingRequest.Library_Item__c)),
                    borrowerFirstName,
                    true
                );
            }

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Request cancelled and removed from waitlist'
            };
        }

        /**
         * @description Records physical handoff. Creates Loaned_Item__c, transfers conversation,
         * updates library status, deletes request. Idempotent against concurrent calls.
         */
        public Map<String, Object> recordHandoffInternal(String requestId) {
            // Try to lock the request row; if deleted, fall back to existing loan
            List<Lending_Request__c> requests = [
                SELECT Id, Status__c, Requested_By__c, Requested_By_Real_Contact__c, Item_Owner__c,
                       Library_Item__c, Library_Item__r.Name, Library_Item__r.OwnerId,
                       Approved_and_Available_Date__c, of_Days_Needed__c,
                       Neighbourhood__c, Library_Item__r.Owner_Contact__c
                FROM Lending_Request__c
                WHERE Id = :requestId
                FOR UPDATE
            ];

            if (requests.isEmpty()) {
                // Request already deleted — check if loan was created by the winner
                List<Loaned_Item__c> existingLoan = [
                    SELECT Id FROM Loaned_Item__c
                    WHERE Lending_Request_ID__c = :requestId
                    LIMIT 1
                ];
                if (!existingLoan.isEmpty()) {
                    return new Map<String, Object>{
                        'success' => true,
                        'alreadyCompleted' => true,
                        'loanedItemId' => existingLoan[0].Id
                    };
                }
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'This lending request no longer exists.'
                };
            }

            Lending_Request__c req = requests[0];

            // If status already changed (race condition), return graceful success
            if (req.Status__c != FimbyConstants.LENDING_APPROVED) {
                List<Loaned_Item__c> existingLoan = [
                    SELECT Id FROM Loaned_Item__c
                    WHERE Lending_Request_ID__c = :requestId
                    LIMIT 1
                ];
                if (!existingLoan.isEmpty()) {
                    return new Map<String, Object>{
                        'success' => true,
                        'alreadyCompleted' => true,
                        'loanedItemId' => existingLoan[0].Id
                    };
                }
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'This request is no longer in Approved status.'
                };
            }

            // Validate caller is owner or borrower
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id callerContactId = identity.actingAsContactId;
            Id realContactId = identity.currentUser != null ? identity.currentUser.ContactId : null;
            Boolean isOwner = (callerContactId == req.Item_Owner__c ||
                               callerContactId == req.Library_Item__r.Owner_Contact__c);
            // Borrower dual-check: represented identity OR real Contact who submitted
            Boolean isBorrower = (callerContactId == req.Requested_By__c) ||
                (realContactId != null && realContactId == req.Requested_By_Real_Contact__c);
            if (!isOwner && !isBorrower) {
                return new Map<String, Object>{
                    'success' => false,
                    'message' => 'Only the item owner or borrower can record the handoff.'
                };
            }

            // Belt-and-suspenders: ensure no loan already exists
            List<Loaned_Item__c> dupeCheck = [
                SELECT Id FROM Loaned_Item__c
                WHERE Lending_Request_ID__c = :requestId
                LIMIT 1
            ];
            if (!dupeCheck.isEmpty()) {
                return new Map<String, Object>{
                    'success' => true,
                    'alreadyCompleted' => true,
                    'loanedItemId' => dupeCheck[0].Id
                };
            }

            // Compute due date
            Date startDate = (req.Approved_and_Available_Date__c != null)
                ? req.Approved_and_Available_Date__c : Date.today();
            Integer daysNeeded = (req.of_Days_Needed__c != null)
                ? Integer.valueOf(req.of_Days_Needed__c) : 7;
            Date dueDate = startDate.addDays(daysNeeded);

            // Build loaned item name
            String loanName = req.Requested_By__c != null
                ? String.valueOf(Date.today()) + ' - ' + req.Library_Item__r.Name
                : req.Library_Item__r.Name;
            if (loanName.length() > 80) loanName = loanName.substring(0, 80);

            // Dual-stamp: Loaned_To__c = represented identity, Loaned_To_Real_Contact__c = real submitter
            Loaned_Item__c loan = new Loaned_Item__c(
                Name = loanName,
                Library_Item__c = req.Library_Item__c,
                Loaned_To__c = req.Requested_By__c,
                Loaned_To_Real_Contact__c = req.Requested_By_Real_Contact__c,
                Owned_By__c = req.Item_Owner__c,
                Loan_Start_Date__c = startDate,
                Loan_Due_Date__c = dueDate,
                Neighbourhood__c = req.Neighbourhood__c,
                Lending_Request_ID__c = requestId,
                OwnerId = req.Library_Item__r.OwnerId
            );
            insert loan;

            // Transfer conversation from request to loan
            Id conversationId;
            List<Conversation__c> convs = [
                SELECT Id, Related_Record_Id__c
                FROM Conversation__c
                WHERE Context_Type__c = :FimbyConstants.CTX_LIBRARY_LENDING
                AND Related_Record_Id__c = :requestId
                LIMIT 1
            ];
            if (!convs.isEmpty()) {
                convs[0].Related_Record_Id__c = String.valueOf(loan.Id);
                update convs[0];
                conversationId = convs[0].Id;

                // Post system message server-side
                String sysMsg = 'Handoff recorded \u2014 ' + req.Library_Item__r.Name
                    + ' is now on loan until ' + String.valueOf(dueDate) + '.';
                Message__c systemMessage = new Message__c(
                    Conversation__c = conversationId,
                    Body__c = sysMsg,
                    Sender__c = callerContactId,
                    Sent_By__c = callerContactId,
                    Sent_Date__c = Datetime.now(),
                    Status__c = FimbyConstants.MESSAGE_SENT
                );
                insert systemMessage;

                // Update conversation preview
                Conversation__c convUpdate = new Conversation__c(
                    Id = conversationId,
                    Last_Message_Preview__c = sysMsg.left(255),
                    Last_Message_Date__c = Datetime.now()
                );
                update convUpdate;
            }

            // Update library item status
            Library_Item__c libItem = new Library_Item__c(
                Id = req.Library_Item__c,
                Status__c = FimbyConstants.LIBRARY_LENT_OUT
            );
            update libItem;

            // Notify both parties
            String itemName = req.Library_Item__r.Name;
            String itemUrl = FimbySettings.getUrl('Library_Item', String.valueOf(req.Library_Item__c));

            if (req.Requested_By__c != null && !isBorrower) {
                FimbyNotificationService.createNotification(
                    req.Requested_By__c,
                    FimbyConstants.NOTIF_LOAN_APPROVED,
                    itemName + ' is now on loan to you',
                    'Due back ' + String.valueOf(dueDate) + '.',
                    loan.Id, 'Loaned_Item__c', itemUrl, 'FIMBY'
                );
            }
            if (req.Item_Owner__c != null && !isOwner) {
                FimbyNotificationService.createNotification(
                    req.Item_Owner__c,
                    FimbyConstants.NOTIF_LOAN_APPROVED,
                    'Your item is now on loan',
                    itemName + '. Due back ' + String.valueOf(dueDate) + '.',
                    loan.Id, 'Loaned_Item__c', itemUrl, 'FIMBY'
                );
            }

            // Delete the lending request
            delete req;

            return new Map<String, Object>{
                'success' => true,
                'loanedItemId' => loan.Id,
                'conversationId' => conversationId
            };
        }

        /**
         * @description Returns lending lifecycle context for a conversation thread.
         */
        public Map<String, Object> getLendingConversationContextInternal(String conversationId) {
            Conversation__c conv = [
                SELECT Id, Related_Record_Id__c, Context_Type__c,
                       Participant_1__c, Participant_2__c
                FROM Conversation__c
                WHERE Id = :conversationId
                LIMIT 1
            ];

            if (conv.Context_Type__c != FimbyConstants.CTX_LIBRARY_LENDING ||
                String.isBlank(conv.Related_Record_Id__c)) {
                return new Map<String, Object>{ 'phase' => null };
            }

            String relatedId = conv.Related_Record_Id__c;
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id callerContactId = identity.actingAsContactId;

            // Try Lending_Request__c first (Approved phase, before handoff)
            List<Lending_Request__c> reqs = [
                SELECT Id, Status__c, Library_Item__c, Library_Item__r.Name,
                       Library_Item__r.Owner_Contact__c, Requested_By__c
                FROM Lending_Request__c
                WHERE Id = :relatedId
                LIMIT 1
            ];

            if (!reqs.isEmpty()) {
                Lending_Request__c req = reqs[0];
                Boolean isOwner = (callerContactId == req.Library_Item__r.Owner_Contact__c);
                String otherName = isOwner
                    ? conv.Participant_2__c == callerContactId
                        ? [SELECT Full_Name__c FROM Contact WHERE Id = :conv.Participant_1__c LIMIT 1].Full_Name__c
                        : [SELECT Full_Name__c FROM Contact WHERE Id = :conv.Participant_2__c LIMIT 1].Full_Name__c
                    : '';

                return new Map<String, Object>{
                    'phase' => 'approved',
                    'isOwner' => isOwner,
                    'requestId' => req.Id,
                    'loanId' => null,
                    'libraryItemId' => req.Library_Item__c,
                    'itemName' => req.Library_Item__r.Name,
                    'otherParticipantName' => otherName
                };
            }

            // Try Loaned_Item__c (all loan phases after handoff)
            List<Loaned_Item__c> loans = [
                SELECT Id, Status__c, Library_Item__c, Library_Item__r.Name,
                       Library_Item__r.Owner_Contact__c, Loaned_To__c,
                       Loan_Due_Date__c, Requested_Due_Date_Extension__c,
                       Return_Confirmed_By_Borrower__c
                FROM Loaned_Item__c
                WHERE Id = :relatedId
                LIMIT 1
            ];

            if (!loans.isEmpty()) {
                Loaned_Item__c loan = loans[0];
                Boolean isOwner = (callerContactId == loan.Library_Item__r.Owner_Contact__c);
                String phase = deriveLoanPhase(loan.Status__c);

                String otherName;
                Id otherId = isOwner ? loan.Loaned_To__c : loan.Library_Item__r.Owner_Contact__c;
                if (otherId != null) {
                    List<Contact> others = [SELECT Full_Name__c FROM Contact WHERE Id = :otherId LIMIT 1];
                    otherName = others.isEmpty() ? '' : others[0].Full_Name__c;
                } else {
                    otherName = '';
                }

                return new Map<String, Object>{
                    'phase' => phase,
                    'isOwner' => isOwner,
                    'requestId' => null,
                    'loanId' => loan.Id,
                    'libraryItemId' => loan.Library_Item__c,
                    'itemName' => loan.Library_Item__r.Name,
                    'otherParticipantName' => otherName
                };
            }

            // Try Lending_History__c (returned phase)
            List<Lending_History__c> histories = [
                SELECT Id, Library_Item__c, Library_Item__r.Name
                FROM Lending_History__c
                WHERE Id = :relatedId
                LIMIT 1
            ];

            if (!histories.isEmpty()) {
                return new Map<String, Object>{
                    'phase' => 'returned',
                    'isOwner' => false,
                    'requestId' => null,
                    'loanId' => null,
                    'libraryItemId' => histories[0].Library_Item__c,
                    'itemName' => histories[0].Library_Item__r.Name,
                    'otherParticipantName' => ''
                };
            }

            return new Map<String, Object>{ 'phase' => null };
        }

        /**
         * @description Requests or approves a loan extension; owners approve immediately, borrowers request from owner.
         * @param recordId Id of the Loaned_Item__c record
         * @param newDueDate Requested new due date (ISO string)
         * @return Map with success, approved flag, borrower/owner name, and message
         */
        public Map<String, Object> requestExtensionInternal(String recordId, String newDueDate) {
            // Get loaned item
            Loaned_Item__c loanedItem = [
                SELECT Id, Loan_Due_Date__c, Requested_Due_Date_Extension__c,
                       Loaned_To__c, Loaned_To_Real_Contact__c, Owned_By__c,
                       Library_Item__c, Library_Item__r.OwnerId, Library_Item__r.Owner_Contact__c,
                       Requester_s_First_Name__c, Item_Owner_s_First_Name__c
                FROM Loaned_Item__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            User currentUser = FimbyIdentityRepository.getCurrentUser();
            Id callerContactId = FimbyIdentityRepository.getIdentity().actingAsContactId;

            String currentUserId18 = currentUser.User_ID_18_Digits__c != null
                ? currentUser.User_ID_18_Digits__c
                : UserInfo.getUserId();
            String itemOwnerId = String.valueOf(loanedItem.Library_Item__r.OwnerId);
            Boolean isOwnerByUser = (currentUserId18 == itemOwnerId || UserInfo.getUserId() == loanedItem.Library_Item__r.OwnerId);
            Boolean isOwnerByContact = (callerContactId != null && loanedItem.Owned_By__c != null
                && callerContactId == loanedItem.Owned_By__c)
                || (callerContactId != null && loanedItem.Library_Item__r.Owner_Contact__c != null
                    && callerContactId == loanedItem.Library_Item__r.Owner_Contact__c);
            Boolean isOwner = isOwnerByUser || isOwnerByContact;
            // Borrower dual-check: represented identity OR real Contact who confirmed handoff
            Id realContactId_borrower = currentUser != null ? currentUser.ContactId : null;
            Boolean isBorrower = (callerContactId != null && callerContactId == loanedItem.Loaned_To__c) ||
                (realContactId_borrower != null && realContactId_borrower == loanedItem.Loaned_To_Real_Contact__c);

            if (!isOwner && !isBorrower) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notAuthorized',
                    'message' => 'Only the borrower or owner can change the due date.'
                };
            }

            Date requestedDate = Date.valueOf(newDueDate);

            if (isOwner) {
                loanedItem.Loan_Due_Date__c = requestedDate;
                update loanedItem;

                // Gap 8: Notify borrower when owner unilaterally changes due date
                if (loanedItem.Loaned_To__c != null) {
                    FimbyNotificationService.createNotification(
                        loanedItem.Loaned_To__c,
                        FimbyConstants.NOTIF_EXTENSION_APPROVED,
                        'Due date updated for your borrowed item',
                        'The owner has changed your due date to ' + String.valueOf(requestedDate) + '.',
                        loanedItem.Id,
                        'Loaned_Item__c',
                        FimbySettings.getUrl('Library_Item', String.valueOf(loanedItem.Library_Item__c)),
                        loanedItem.Item_Owner_s_First_Name__c
                    );
                }

                return new Map<String, Object>{
                    'success' => true,
                    'approved' => true,
                    'borrowerName' => loanedItem.Requester_s_First_Name__c,
                    'message' => 'Extension approved'
                };
            } else {
                loanedItem.Requested_Due_Date_Extension__c = requestedDate;
                update loanedItem;

                // Gap 2: Notify lender when borrower requests extension
                if (loanedItem.Library_Item__r.Owner_Contact__c != null) {
                    String actionUrl = FimbySettings.getUrl('Library_Item',
                        String.valueOf(loanedItem.Library_Item__c),
                        '?action=approveExtension&loanId=' + recordId);
                    String borrowerFirstName = String.isNotBlank(loanedItem.Requester_s_First_Name__c)
                        ? loanedItem.Requester_s_First_Name__c : 'A neighbour';
                    FimbyNotificationService.createNotification(
                        loanedItem.Library_Item__r.Owner_Contact__c,
                        FimbyConstants.NOTIF_EXTENSION_REQUEST,
                        borrowerFirstName + ' requested an extension',
                        'New due date: ' + String.valueOf(requestedDate) + '. Review the request.',
                        loanedItem.Id,
                        'Loaned_Item__c',
                        actionUrl,
                        borrowerFirstName
                    );
                }

                return new Map<String, Object>{
                    'success' => true,
                    'approved' => false,
                    'ownerName' => loanedItem.Item_Owner_s_First_Name__c,
                    'message' => 'Extension request sent to owner'
                };
            }
        }

        /**
         * @description Approves a requested loan extension; updates due date and sends notification.
         * @param recordId Id of the Loaned_Item__c record
         * @return Map with success, borrowerName, and message
         */
        public Map<String, Object> approveExtensionInternal(String recordId) {
            Loaned_Item__c loanedItem = [
                SELECT Id, Loan_Due_Date__c, Requested_Due_Date_Extension__c,
                       Requester_s_First_Name__c, Loaned_To__c,
                       Library_Item__r.Owner_Contact__c, Library_Item__r.Owner_Contact__r.FirstName,
                       Library_Item__r.Owner_Contact__r.LastName
                FROM Loaned_Item__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            String borrowerName = loanedItem.Requester_s_First_Name__c;

            // Update due date to the requested date and clear the request
            loanedItem.Loan_Due_Date__c = loanedItem.Requested_Due_Date_Extension__c;
            loanedItem.Requested_Due_Date_Extension__c = null;
            update loanedItem;

            // Email alert Loaned_Item__c.Loan_Extension_Approved will be triggered by workflow

            // Create in-app notification for borrower
            if (loanedItem.Loaned_To__c != null) {
                String ownerFirstName = 'A neighbour';
                if (loanedItem.Library_Item__r?.Owner_Contact__r?.FirstName != null) {
                    ownerFirstName = loanedItem.Library_Item__r.Owner_Contact__r.FirstName;
                }
                FimbyNotificationService.createNotification(
                    loanedItem.Loaned_To__c,
                    FimbyConstants.NOTIF_EXTENSION_APPROVED,
                    'Your extension was approved',
                    'New due date: ' + String.valueOf(loanedItem.Loan_Due_Date__c) + '.',
                    loanedItem.Id,
                    'Loaned_Item__c',
                    FimbySettings.getUrl('Library_Item', String.valueOf(loanedItem.Library_Item__c)),
                    ownerFirstName
                );
            }

            return new Map<String, Object>{
                'success' => true,
                'borrowerName' => borrowerName,
                'message' => 'Extension approved'
            };
        }

        /**
         * @description Declines a requested loan extension; clears request and sets decline reason.
         * @param recordId Id of the Loaned_Item__c record
         * @param declineReason Reason entered by the owner
         * @return Map with success, borrowerName, and message
         */
        public Map<String, Object> declineExtensionInternal(String recordId, String declineReason) {
            Loaned_Item__c loanedItem = [
                SELECT Id, Requested_Due_Date_Extension__c, Extension_Decline_Reason__c,
                       Requester_s_First_Name__c, Loaned_To__c,
                       Library_Item__c, Item_Owner_s_First_Name__c
                FROM Loaned_Item__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            String borrowerName = loanedItem.Requester_s_First_Name__c;

            loanedItem.Requested_Due_Date_Extension__c = null;
            loanedItem.Extension_Decline_Reason__c = declineReason;
            update loanedItem;

            if (loanedItem.Loaned_To__c != null) {
                String notifBody = String.isNotBlank(declineReason)
                    ? declineReason
                    : 'The owner wasn\'t able to extend the loan this time.';
                FimbyNotificationService.createNotification(
                    loanedItem.Loaned_To__c,
                    FimbyConstants.NOTIF_EXTENSION_DECLINED,
                    'Extension request declined',
                    notifBody,
                    loanedItem.Id,
                    'Loaned_Item__c',
                    FimbySettings.getUrl('Library_Item', String.valueOf(loanedItem.Library_Item__c)),
                    loanedItem.Item_Owner_s_First_Name__c
                );
            }

            return new Map<String, Object>{
                'success' => true,
                'borrowerName' => borrowerName,
                'message' => 'Extension declined'
            };
        }

        private String deriveLoanPhase(String formulaStatus) {
            if (String.isBlank(formulaStatus)) return 'onLoan';
            String lower = formulaStatus.toLowerCase();
            if (lower.contains('overdue')) return 'overdue';
            if (lower.contains('extension requested')) return 'extensionRequested';
            if (lower.contains('owner to confirm return') || lower.contains('return')) return 'returnPending';
            return 'onLoan';
        }

        private void shareContactInfoForLending(String sendingContactId, String recipientContactId, String shareDataJson, Id lendingRequestId) {
            Map<String, Object> shareData = (Map<String, Object>) JSON.deserializeUntyped(shareDataJson);

            Boolean shareEmail = shareData.get('shareEmail') == true;
            Boolean sharePhone = shareData.get('sharePhone') == true;
            Boolean shareAddress = shareData.get('shareAddress') == true;

            // Get sender contact details
            Contact sender = [
                SELECT Id, FirstName, LastName, Email
                FROM Contact
                WHERE Id = :sendingContactId
                LIMIT 1
            ];

            // Get recipient contact details
            Contact recipient = [
                SELECT Id, FirstName, LastName, Email
                FROM Contact
                WHERE Id = :recipientContactId
                LIMIT 1
            ];

            // Build shared contact info name
            String sharedContactInfoName = sender.FirstName + ' ' + sender.LastName + ' - ' + String.valueOf(Date.today());

            // Look for existing Shared_Contact_Info__c
            List<Shared_Contact_Info__c> existingSharedInfo = [
                SELECT Id, Email__c, Phone__c, Street__c, City__c, Province_State__c,
                       Postal_Code__c, Country__c, Additional_Info__c
                FROM Shared_Contact_Info__c
                WHERE Contact__c = :sendingContactId
                AND Shared_To__c = :recipientContactId
                LIMIT 1
            ];

            Shared_Contact_Info__c sharedContactInfo;
            Boolean isNew = existingSharedInfo.isEmpty();
            Shared_Contact_Info__c beforeShare = isNew
                ? null
                : existingSharedInfo[0].clone(false, false, false, false);

            Boolean shouldSendEmail = isNew || FimbySharedContactInfoHelper.hasExpandedContactShare(
                beforeShare,
                FimbySharedContactInfoHelper.buildAfterStateReplace(
                    beforeShare,
                    shareEmail,
                    sharePhone,
                    shareAddress,
                    (String) shareData.get('email'),
                    (String) shareData.get('phone'),
                    (String) shareData.get('street'),
                    (String) shareData.get('city'),
                    (String) shareData.get('state'),
                    (String) shareData.get('postalCode'),
                    (String) shareData.get('country'),
                    (String) shareData.get('additionalInfo')
                )
            );

            if (isNew) {
                sharedContactInfo = new Shared_Contact_Info__c(
                    Name = sharedContactInfoName,
                    Contact__c = sendingContactId,
                    Shared_To__c = recipientContactId,
                    Lending_Request__c = lendingRequestId,
                    Origin__c = 'Lending'
                );
            } else {
                sharedContactInfo = existingSharedInfo[0];
                sharedContactInfo.Name = sharedContactInfoName;
                sharedContactInfo.Lending_Request__c = lendingRequestId;
                sharedContactInfo.Origin__c = 'Lending';
            }

            // Set values based on what's being shared
            sharedContactInfo.Email__c = shareEmail ? (String) shareData.get('email') : null;
            sharedContactInfo.Phone__c = sharePhone ? (String) shareData.get('phone') : null;
            sharedContactInfo.Street__c = shareAddress ? (String) shareData.get('street') : null;
            sharedContactInfo.City__c = shareAddress ? (String) shareData.get('city') : null;
            sharedContactInfo.Province_State__c = shareAddress ? (String) shareData.get('state') : null;
            sharedContactInfo.Postal_Code__c = shareAddress ? (String) shareData.get('postalCode') : null;
            sharedContactInfo.Country__c = shareAddress ? (String) shareData.get('country') : null;
            sharedContactInfo.Additional_Info__c = shareAddress ? (String) shareData.get('additionalInfo') : null;

            if (isNew) {
                insert sharedContactInfo;
            } else {
                update sharedContactInfo;
            }

            if (shouldSendEmail) {
                sendShareContactEmail(sender, recipient, shareData);
            }
        }

        private void sendShareContactEmail(Contact sender, Contact recipient, Map<String, Object> shareData) {
            List<User> users = [
                SELECT Id FROM User
                WHERE ContactId = :recipient.Id AND IsActive = true
                LIMIT 1
            ];
            if (users.isEmpty()) return;

            Boolean shareEmail = shareData.get('shareEmail') == true;
            Boolean sharePhone = shareData.get('sharePhone') == true;
            Boolean shareAddress = shareData.get('shareAddress') == true;

            String senderName = sender.FirstName + ' ' + sender.LastName;
            String emailVal = shareEmail ? (String) shareData.get('email') : null;
            String phoneVal = sharePhone ? (String) shareData.get('phone') : null;
            String streetVal = shareAddress ? (String) shareData.get('street') : null;
            String additionalVal = shareAddress ? (String) shareData.get('additionalInfo') : null;

            String cardHtml = FimbyEmailHtmlBuilder.buildContactShareCard(
                senderName, emailVal, phoneVal, streetVal, additionalVal, 'Lending item'
            );

            FimbyTransactionalEmailService.TransactionalEmailRequest req =
                new FimbyTransactionalEmailService.TransactionalEmailRequest();
            req.recipientUserId = users[0].Id;
            req.subject = senderName + ' shared their contact info with you';
            req.cardHtml = cardHtml;
            req.skipSubjectBlock = true;
            req.replyToEmail = sender.Email;

            FimbyTransactionalEmailService.send(req);
        }

        /**
         * @description Submits borrower's return confirmation; updates loaned item and notifies owner.
         * @param recordId Id of the Loaned_Item__c record
         * @param dateReturned Date returned (ISO string)
         * @param isDamaged Whether the item was damaged or lost
         * @param wouldBorrowAgain Would borrow from this owner again (picklist value)
         * @return Map with success flag and message
         */
        public Map<String, Object> submitBorrowerReturnInternal(String recordId, String dateReturned, Boolean isDamaged, String wouldBorrowAgain) {
            Loaned_Item__c loanedItem = [
                SELECT Id, Return_Confirmed_By_Borrower__c, Borrow_From_Again__c, Returned_Date__c,
                       Damaged_Lost__c, Library_Item__c, Library_Item__r.Name, Library_Item__r.Owner_Contact__c,
                       Requester_s_First_Name__c
                FROM Loaned_Item__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            loanedItem.Return_Confirmed_By_Borrower__c = true;
            loanedItem.Returned_Date__c = Date.valueOf(dateReturned);
            loanedItem.Borrow_From_Again__c = wouldBorrowAgain;
            loanedItem.Damaged_Lost__c = isDamaged;
            update loanedItem;

            if (loanedItem.Library_Item__r.Owner_Contact__c != null) {
                String actionUrl = FimbySettings.getUrl('Library_Item',
                    String.valueOf(loanedItem.Library_Item__c),
                    '?action=confirmReturn&loanId=' + recordId);
                String borrowerFirstName = String.isNotBlank(loanedItem.Requester_s_First_Name__c)
                    ? loanedItem.Requester_s_First_Name__c : 'A neighbour';
                FimbyNotificationService.createNotification(
                    loanedItem.Library_Item__r.Owner_Contact__c,
                    FimbyConstants.NOTIF_ITEM_RETURNED,
                    borrowerFirstName + ' says they\'ve returned ' + loanedItem.Library_Item__r.Name,
                    'Confirm the return to close out this loan.',
                    loanedItem.Id,
                    'Loaned_Item__c',
                    actionUrl,
                    borrowerFirstName
                );
            }

            return new Map<String, Object>{
                'success' => true,
                'message' => 'Return submitted successfully'
            };
        }

        /**
         * @description Submits owner's return confirmation; creates lending history, updates library item, deletes loaned item.
         * @param recordId Id of the Loaned_Item__c record
         * @param dateReturned Date returned (ISO string)
         * @param isDamaged Whether the item was damaged
         * @param conditionUponReturn Condition picklist value
         * @param wouldLendAgain Would lend to this borrower again (picklist value)
         * @return Map with success, libraryItemId, and message
         */
        public Map<String, Object> submitOwnerReturnInternal(String recordId, String dateReturned, Boolean isDamaged,
                                                             String conditionUponReturn, String wouldLendAgain) {
            // Get loaned item with all needed fields
            Loaned_Item__c loanedItem = [
                SELECT Id, Loaned_To__c, Loan_Start_Date__c, Days_Overdue__c, Borrow_From_Again__c,
                       Library_Item__c, Library_Item__r.Id, Library_Item__r.Name, Library_Item__r.OwnerId,
                       Library_Item_Name__c, Requester_s_Name__c, Neighbourhood__c, Owned_By__c
                FROM Loaned_Item__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            Library_Item__c libraryItem = [
                SELECT Id, Status__c, OwnerId
                FROM Library_Item__c
                WHERE Id = :loanedItem.Library_Item__c
                LIMIT 1
            ];

            // Create Lending History record
            String lendingHistoryName = String.valueOf(Date.valueOf(dateReturned)) + ' - ' +
                (loanedItem.Requester_s_Name__c != null ? loanedItem.Requester_s_Name__c : 'Unknown') + ' - ' +
                (loanedItem.Library_Item_Name__c != null ? loanedItem.Library_Item_Name__c : libraryItem.Name);
            if (lendingHistoryName.length() > 80) {
                lendingHistoryName = lendingHistoryName.substring(0, 80);
            }

            Lending_History__c lendingHistory = new Lending_History__c(
                Name = lendingHistoryName,
                Borrow_From_Again__c = loanedItem.Borrow_From_Again__c,
                Borrowed_By__c = loanedItem.Loaned_To__c,
                Condition_Upon_Return__c = conditionUponReturn,
                Days_Overdue__c = loanedItem.Days_Overdue__c,
                End_Date__c = Date.valueOf(dateReturned),
                Lend_To_Again__c = wouldLendAgain,
                Lent_By__c = loanedItem.Owned_By__c,
                Library_Item__c = loanedItem.Library_Item__c,
                Neighbourhood__c = loanedItem.Neighbourhood__c,
                Start_Date__c = loanedItem.Loan_Start_Date__c,
                OwnerId = libraryItem.OwnerId
            );
            insert lendingHistory;

            // Transfer conversation from loaned item to lending history
            List<Conversation__c> returnConvs = [
                SELECT Id, Related_Record_Id__c
                FROM Conversation__c
                WHERE Context_Type__c = :FimbyConstants.CTX_LIBRARY_LENDING
                AND Related_Record_Id__c = :String.valueOf(loanedItem.Id)
                LIMIT 1
            ];
            if (!returnConvs.isEmpty()) {
                returnConvs[0].Related_Record_Id__c = String.valueOf(lendingHistory.Id);
                update returnConvs[0];
            }

            // Update Library Item status
            if (isDamaged) {
                libraryItem.Status__c = FimbyConstants.LIBRARY_REMOVED;
            } else {
                libraryItem.Status__c = FimbyConstants.LIBRARY_AVAILABLE;
            }
            update libraryItem;

            Id borrowerContactId = loanedItem.Loaned_To__c;
            String borrowerItemName = loanedItem.Library_Item_Name__c != null
                ? loanedItem.Library_Item_Name__c : libraryItem.Name;

            delete loanedItem;

            if (borrowerContactId != null) {
                FimbyNotificationService.createNotification(
                    borrowerContactId,
                    FimbyConstants.NOTIF_ITEM_RETURNED,
                    'Return confirmed for ' + borrowerItemName,
                    'The owner has confirmed the return. Thanks for sharing.',
                    libraryItem.Id,
                    'Library_Item__c',
                    FimbySettings.getUrl('Library_Item', String.valueOf(libraryItem.Id)),
                    'FIMBY'
                );
            }

            // Waitlist handling depends on damage state
            String itemName = loanedItem.Library_Item_Name__c != null
                ? loanedItem.Library_Item_Name__c : libraryItem.Name;
            if (!isDamaged) {
                // Promote first waitlisted request and notify them
                List<Lending_Request__c> waitlistRequests = [
                    SELECT Id, Status__c, Requested_By__c
                    FROM Lending_Request__c
                    WHERE Library_Item__c = :libraryItem.Id
                    AND Waitlist_Position__c = 1
                    AND Status__c IN ('Waitlisted', 'Pending Approval')
                    LIMIT 1
                ];
                if (!waitlistRequests.isEmpty()) {
                    waitlistRequests[0].Status__c = FimbyConstants.LENDING_REQUESTING_CONFIRMATION;
                    update waitlistRequests[0];

                    if (waitlistRequests[0].Requested_By__c != null) {
                        String confirmUrl = FimbySettings.getUrl('Library_Item',
                            String.valueOf(libraryItem.Id),
                            '?action=confirmWaitlist&requestId=' + waitlistRequests[0].Id);
                        FimbyNotificationService.createNotification(
                            waitlistRequests[0].Requested_By__c,
                            FimbyConstants.NOTIF_LENDING_REQUEST,
                            itemName + ' is now available',
                            'You\'re next on the waitlist. Confirm you still want to borrow it.',
                            waitlistRequests[0].Id, 'Lending_Request__c',
                            confirmUrl,
                            'FIMBY'
                        );
                    }
                }
            } else {
                // Damaged/lost: cancel all active requests and notify waitlisters
                List<Lending_Request__c> activeRequests = [
                    SELECT Id, Status__c, Requested_By__c
                    FROM Lending_Request__c
                    WHERE Library_Item__c = :libraryItem.Id
                    AND Status__c IN ('Waitlisted', 'Requesting Confirmation', 'Pending Approval')
                ];
                if (!activeRequests.isEmpty()) {
                    for (Lending_Request__c req : activeRequests) {
                        req.Status__c = FimbyConstants.LENDING_CANCELLED;
                    }
                    update activeRequests;

                    for (Lending_Request__c req : activeRequests) {
                        if (req.Requested_By__c != null) {
                            FimbyNotificationService.createNotification(
                                req.Requested_By__c,
                                FimbyConstants.NOTIF_LENDING_REQUEST,
                                itemName + ' is no longer available for borrowing',
                                'This item has been removed from the library.',
                                req.Id, 'Lending_Request__c',
                                FimbySettings.getUrl('Library_Item', String.valueOf(libraryItem.Id)),
                                'FIMBY'
                            );
                        }
                    }
                }
            }

            // Email alert will be triggered by workflow
            // Loaned_Item__c.Owner_Confirmed_Item_Returned OR Loaned_Item__c.Owner_Confirmed_Item_Damaged

            return new Map<String, Object>{
                'success' => true,
                'libraryItemId' => libraryItem.Id,
                'message' => 'Return confirmed and lending history created'
            };
        }
    }

    /**
     * Get Loaned Item details for the return form
     * Validates that current user is the owner or borrower
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLoanedItemForReturn(String recordId) {
        try {
            if (String.isBlank(recordId)) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'noRecordId',
                    'message' => 'No loaned item specified.'
                };
            }

            // Get loaned item (Owned_By__c + Owner_Contact__c align with recordHandoff / identity)
            List<Loaned_Item__c> loanedItems = [
                SELECT Id, Name, Loaned_To__c, Loaned_To_Real_Contact__c, Owned_By__c,
                       Library_Item__c, Library_Item__r.Id, Library_Item__r.Name,
                       Library_Item__r.OwnerId, Library_Item__r.Owner_Contact__c,
                       Requester_s_First_Name__c, Item_Owner_s_First_Name__c
                FROM Loaned_Item__c
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Check if already returned
            if (loanedItems.isEmpty()) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'alreadyReturned',
                    'message' => 'This item has already been returned.'
                };
            }

            Loaned_Item__c loanedItem = loanedItems[0];

            User currentUser = FimbyIdentityRepository.getCurrentUser();
            FimbyIdentityRepository.Identity identity = FimbyIdentityRepository.getIdentity();
            Id callerContactId = identity.actingAsContactId;

            String currentUserId18 = currentUser.User_ID_18_Digits__c != null
                ? currentUser.User_ID_18_Digits__c
                : UserInfo.getUserId();
            String itemOwnerId = String.valueOf(loanedItem.Library_Item__r.OwnerId);
            Boolean isOwnerByUser = (currentUserId18 == itemOwnerId || UserInfo.getUserId() == loanedItem.Library_Item__r.OwnerId);
            Boolean isOwnerByContact = (callerContactId != null && loanedItem.Owned_By__c != null
                && callerContactId == loanedItem.Owned_By__c)
                || (callerContactId != null && loanedItem.Library_Item__r.Owner_Contact__c != null
                    && callerContactId == loanedItem.Library_Item__r.Owner_Contact__c);
            Boolean isOwner = isOwnerByUser || isOwnerByContact;

            // Borrower dual-check: represented identity OR real Contact who confirmed handoff
            Id realContactId_borrower = currentUser != null ? currentUser.ContactId : null;
            Boolean isBorrower = (callerContactId != null && callerContactId == loanedItem.Loaned_To__c) ||
                (realContactId_borrower != null && realContactId_borrower == loanedItem.Loaned_To_Real_Contact__c);

            // Validate: User must be owner OR borrower
            if (!isOwner && !isBorrower) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'notAuthorized',
                    'message' => 'You are not the owner or the borrower of this item.'
                };
            }

            return new Map<String, Object>{
                'success' => true,
                'loanedItem' => new Map<String, Object>{
                    'id' => loanedItem.Id,
                    'name' => loanedItem.Name,
                    'Requester_s_First_Name__c' => loanedItem.Requester_s_First_Name__c,
                    'Item_Owner_s_First_Name__c' => loanedItem.Item_Owner_s_First_Name__c
                },
                'libraryItem' => new Map<String, Object>{
                    'Id' => loanedItem.Library_Item__r.Id,
                    'Name' => loanedItem.Library_Item__r.Name
                },
                'isOwner' => isOwner,
                'isBorrower' => isBorrower
            };

        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error loading loaned item: ' + e.getMessage());
            ex.setMessage('Error loading loaned item: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Get picklist values for Condition Upon Return
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getConditionPicklistValues() {
        List<String> picklistValues = new List<String>();
        Schema.DescribeFieldResult fieldResult = Lending_History__c.Condition_Upon_Return__c.getDescribe();
        List<Schema.PicklistEntry> entries = fieldResult.getPicklistValues();
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                picklistValues.add(entry.getValue());
            }
        }
        return picklistValues;
    }

    /**
     * Submit borrower return - updates loaned item and notifies owner
     */
    @AuraEnabled
    public static Map<String, Object> submitBorrowerReturn(String recordId, String dateReturned, Boolean isDamaged, String wouldBorrowAgain) {
        try {
            return new LendingHelper().submitBorrowerReturnInternal(recordId, dateReturned, isDamaged, wouldBorrowAgain);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error submitting return: ' + e.getMessage());
            ex.setMessage('Error submitting return: ' + e.getMessage());
            throw ex;
        }
    }

    /**
     * Submit owner return confirmation - creates lending history, updates library item, deletes loaned item
     */
    @AuraEnabled
    public static Map<String, Object> submitOwnerReturn(String recordId, String dateReturned, Boolean isDamaged,
                                                        String conditionUponReturn, String wouldLendAgain) {
        try {
            return new LendingHelper().submitOwnerReturnInternal(recordId, dateReturned, isDamaged, conditionUponReturn, wouldLendAgain);
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error confirming return: ' + e.getMessage());
            ex.setMessage('Error confirming return: ' + e.getMessage());
            throw ex;
        }
    }
}