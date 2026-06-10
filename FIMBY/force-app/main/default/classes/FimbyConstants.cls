/**
 * @description Central constants for FIMBY status values, record types, context types, and notification types.
 * Used across controllers, triggers, and batch jobs for consistent string values.
 */
public class FimbyConstants {

    // Response statuses
    public static final String RESPONSE_NEW = 'New';
    public static final String RESPONSE_ACCEPTED = 'Accepted';
    public static final String RESPONSE_DECLINED = 'Declined';
    public static final String RESPONSE_CANCELLED = 'Cancelled';
    public static final String RESPONSE_COMPLETED = 'Completed';
    public static final String RESPONSE_EXPIRED = 'Expired';

    // Lending request statuses
    public static final String LENDING_PENDING_APPROVAL = 'Pending Approval';
    public static final String LENDING_WAITLISTED = 'Waitlisted';
    public static final String LENDING_APPROVED = 'Approved';
    public static final String LENDING_DECLINED = 'Declined';
    public static final String LENDING_CANCELLED = 'Cancelled';
    public static final String LENDING_REQUESTING_CONFIRMATION = 'Requesting Confirmation';
    public static final String LENDING_SENT = 'Sent';

    // Library item statuses
    public static final String LIBRARY_AVAILABLE = 'Available';
    public static final String LIBRARY_ON_HOLD = 'On Hold';
    public static final String LIBRARY_LENT_OUT = 'Currently Lent Out';
    public static final String LIBRARY_UNAVAILABLE = 'Unavailable';
    public static final String LIBRARY_REMOVED = 'Removed from Library';

    // Library browser viewer states
    public static final String LIB_VIEW_OWNER = 'owner';
    public static final String LIB_VIEW_BORROWED = 'borrowed';
    public static final String LIB_VIEW_WAITLISTED = 'waitlisted';
    public static final String LIB_VIEW_PAST_BORROWER = 'pastBorrower';
    public static final String LIB_VIEW_AVAILABLE = 'available';
    public static final String LIB_VIEW_ON_LOAN = 'onLoan';
    public static final String LIB_VIEW_ON_HOLD = 'onHold';

    // Conversation statuses
    public static final String CONVERSATION_ACTIVE = 'Active';
    public static final String CONVERSATION_BLOCKED = 'Blocked';

    // Message statuses
    public static final String MESSAGE_SENT = 'Sent';

    // Shared contact info statuses
    public static final String SHARED_CONTACT_ACTIVE = 'Active';
    public static final String SHARED_CONTACT_REVOKED = 'Revoked';

    // Needs/Offers statuses
    public static final String NEEDS_OFFERS_POSTED = 'Posted';
    public static final String NEEDS_OFFERS_AVAILABLE = 'Available';

    // Onboarding statuses
    public static final String ONBOARDING_NOT_STARTED = 'Not Started';
    public static final String ONBOARDING_COMPLETED = 'Completed';
    public static final String ONBOARDING_DISMISSED = 'Dismissed';

    // Notification types
    public static final String NOTIF_RESPONSE = 'Response';
    public static final String NOTIF_COMMENT = 'Comment';
    public static final String NOTIF_LENDING_REQUEST = 'Lending_Request';
    public static final String NOTIF_LOAN_APPROVED = 'Loan_Approved';
    public static final String NOTIF_EXTENSION_REQUEST = 'Extension_Request';
    public static final String NOTIF_EXTENSION_APPROVED = 'Extension_Approved';
    public static final String NOTIF_EXTENSION_DECLINED = 'Extension_Declined';
    public static final String NOTIF_OVERDUE_REMINDER = 'Overdue_Reminder';
    public static final String NOTIF_ITEM_RETURNED = 'Item_Returned';
    public static final String NOTIF_THANKS_RECEIVED = 'Thanks_Received';

    // Needs/Offers record types
    public static final String RT_NEED = 'Need';
    public static final String RT_OFFER = 'Offer';
    public static final String RT_BULK_BUY = 'Bulk_Buy';

    // Needs/Offers Bulk Buy statuses
    public static final String NEEDS_OFFERS_PICKUP_READY = 'Pickup_Ready';
    public static final String NEEDS_OFFERS_COMPLETED = 'Completed (Offer Accepted / Need Met)';
    public static final String NEEDS_OFFERS_CANCELLED = 'Cancelled';
    public static final String NEEDS_OFFERS_EXPIRED = 'Expired';

    // Response statuses (Bulk Buy)
    public static final String RESPONSE_RESERVED = 'Reserved';
    public static final String RESPONSE_NO_FOLLOW_THROUGH = 'No_Follow_Through';

    // Bulk Buy Follow-Up statuses
    public static final String FOLLOWUP_PENDING = 'Pending';
    public static final String FOLLOWUP_RESOLVED = 'Resolved';
    public static final String FOLLOWUP_NO_RESPONSE = 'No_Response';
    public static final String FOLLOWUP_ESCALATED = 'Escalated';
    public static final String FOLLOWUP_ADMIN_CLEARED = 'Admin_Cleared';
    public static final String FOLLOWUP_ADMIN_CONFIRMED = 'Admin_Confirmed';
    public static final String FOLLOWUP_PROBATIONARY_RESTORED = 'Probationary_Restored';
    public static final String FOLLOWUP_EXPIRED = 'Expired';

    // Bulk Buy Follow-Up RecordType developer names
    public static final String RT_FOLLOW_UP = 'Follow_Up';
    public static final String RT_RESTORATION = 'Restoration';

    // Context types
    public static final String CTX_DIRECT = 'Direct';
    public static final String CTX_LIBRARY_LENDING = 'Library_Lending';
    public static final String CTX_BULK_BUY = 'Bulk_Buy';
    public static final String CTX_EVENT = 'Event';
    public static final String CTX_MISSED_PICKUP = 'Missed_Pickup';
    public static final String CTX_RESPONSE = 'response';
    public static final String CTX_STORY = 'story';
    public static final String CTX_LIBRARY = 'library';

    // Notification types (Message)
    public static final String NOTIF_MESSAGE = 'Message';

    // Notification types (Event Chat)
    public static final String NOTIF_EVENT_CHAT = 'Event_Chat';

    // Notification types (Event Reminder)
    public static final String NOTIF_EVENT_REMINDER = 'Event_Reminder';

    // Notification types (Recurring event new occurrence re-invite)
    public static final String NOTIF_EVENT_SERIES_NEW_OCCURRENCE = 'Event_Series_New_Occurrence';

    // Notification types (Bulk Buy)
    public static final String NOTIF_BULK_BUY_RESERVATION = 'Bulk_Buy_Reservation';
    public static final String NOTIF_BULK_BUY_STATUS = 'Bulk_Buy_Status';
    public static final String NOTIF_BULK_BUY_PICKUP = 'Bulk_Buy_Pickup';
    public static final String NOTIF_NOT_RESPONDING_FLAG = 'Not_Responding_Flag';
    public static final String NOTIF_NOT_RESPONDING_RESPONSE = 'Not_Responding_Response';
    public static final String NOTIF_NOT_RESPONDING_ESCALATED = 'Not_Responding_Escalated';
    public static final String NOTIF_FOLLOW_UP_RESOLVED = 'Follow_Up_Resolved';

    // Notification types (Moderator)
    public static final String NOTIF_MODERATOR = 'Moderator';

    // Notification types (System)
    public static final String NOTIF_SYSTEM = 'System';
    public static final String NOTIF_SYSTEM_NEIGHBOURHOOD_CHANGE = 'System_Neighbourhood_Change';

    // Notification types (Vouching)
    public static final String NOTIF_VOUCH_REQUEST_RECEIVED = 'Vouch_Request_Received';
    public static final String NOTIF_VOUCH_REQUEST_REMINDER = 'Vouch_Request_Reminder';
    public static final String NOTIF_VOUCH_APPROVED         = 'Vouch_Approved';
    public static final String NOTIF_VOUCH_DECLINED         = 'Vouch_Declined';
    public static final String NOTIF_VOUCH_REVOKED          = 'Vouch_Revoked';
    public static final String NOTIF_VOUCHER_PAUSED         = 'Voucher_Paused';

    // Vouch context
    public static final String CTX_VOUCH_REQUEST = 'Vouch_Request';

    // Vouch system message types
    public static final String SYS_MSG_VOUCH_REQUESTED = 'Vouch_Requested';
    public static final String SYS_MSG_VOUCH_APPROVED  = 'Vouch_Approved';
    public static final String SYS_MSG_VOUCH_DECLINED  = 'Vouch_Declined';
    public static final String SYS_MSG_VOUCH_WITHDRAWN = 'Vouch_Withdrawn';
    public static final String SYS_MSG_VOUCH_REVOKED   = 'Vouch_Revoked';

    // Conversation Member roles
    public static final String MEMBER_ROLE_OWNER = 'Owner';
    public static final String MEMBER_ROLE_MEMBER = 'Member';

    // Conversation Member statuses
    public static final String MEMBER_ACTIVE = 'Active';
    public static final String MEMBER_REMOVED = 'Removed';
    public static final String MEMBER_LEFT = 'Left';

    // System message types
    public static final String SYS_MSG_RESERVATION_CREATED = 'Reservation_Created';
    public static final String SYS_MSG_RESERVATION_CANCELLED = 'Reservation_Cancelled';
    public static final String SYS_MSG_STATUS_CHANGE = 'Status_Change';
    public static final String SYS_MSG_PICKUP_READY = 'Pickup_Ready';
    public static final String SYS_MSG_NOT_RESPONDING_FLAG = 'Not_Responding_Flag';

    // Visibility
    public static final String VIS_SELF = 'Self';
}
