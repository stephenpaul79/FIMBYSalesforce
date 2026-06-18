/**
 * @description Static utility that determines email eligibility at notification creation time.
 * Mirrors the push gate check pattern in FimbyNotificationService but with conservative
 * defaults: only direct-action notification types are instant-email by default.
 *
 * Security/safety messages (password resets, login alerts, account deactivation
 * confirmations, ban notifications, etc.) bypass every gate via SECURITY_BYPASS_TYPES.
 * The Settings UI surfaces an "Account & Safety" read-only line — no toggle — so
 * users know there is no opt-out for these by design. See "No security toggle" in
 * the prelaunch product alignment plan A4 for the rationale.
 */
public without sharing class FimbyEmailAlertService {

    public enum EmailDefault { ALWAYS, OPT_IN, NEVER }

    private static final Map<String, EmailDefault> EMAIL_TYPE_MAP = new Map<String, EmailDefault>{
        FimbyConstants.NOTIF_MESSAGE             => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_RESPONSE            => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_RESPONSE_REPLY      => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_EVENT_CHAT          => EmailDefault.OPT_IN,
        FimbyConstants.NOTIF_COMMENT             => EmailDefault.OPT_IN,
        FimbyConstants.NOTIF_LENDING_REQUEST     => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_LOAN_APPROVED       => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_EXTENSION_REQUEST   => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_EXTENSION_APPROVED  => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_EXTENSION_DECLINED  => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_ITEM_RETURNED       => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_OVERDUE_REMINDER    => EmailDefault.OPT_IN,
        FimbyConstants.NOTIF_EVENT_REMINDER      => EmailDefault.OPT_IN,
        FimbyConstants.NOTIF_BULK_BUY_RESERVATION => EmailDefault.OPT_IN,
        FimbyConstants.NOTIF_BULK_BUY_STATUS     => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_BULK_BUY_PICKUP     => EmailDefault.ALWAYS,
        // Vouching: foundational to library access — no per-category opt-out
        // (intentionally absent from EMAIL_TOGGLE_MAP). Master toggle still applies.
        // NOTIF_VOUCHER_PAUSED is omitted here because FimbyVouchController.sendVoucherPauseEmail
        // sends its own custom transactional email — listing it would cause duplicates.
        FimbyConstants.NOTIF_VOUCH_REQUEST_RECEIVED => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_VOUCH_REQUEST_REMINDER => EmailDefault.OPT_IN,
        FimbyConstants.NOTIF_VOUCH_APPROVED         => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_VOUCH_DECLINED         => EmailDefault.ALWAYS,
        FimbyConstants.NOTIF_VOUCH_REVOKED          => EmailDefault.ALWAYS
    };

    // Event-related notification types now route to the new Email_Alert_Events__c
    // toggle. Migration note: previously NOTIF_EVENT_CHAT/REMINDER routed to
    // Email_Alert_Needs_Offers__c and Email_Alert_Reminders__c respectively, so
    // a user who silenced Asks & Offers also silenced event chat. After this
    // change, those users will start receiving event chat unless they opt out
    // separately via the Events toggle. This is the deliberate decision per
    // prelaunch product alignment plan A4.
    @TestVisible
    private static final Map<String, String> EMAIL_TOGGLE_MAP = new Map<String, String>{
        FimbyConstants.NOTIF_MESSAGE             => 'Email_Alert_Messages__c',
        FimbyConstants.NOTIF_RESPONSE            => 'Email_Alert_Needs_Offers__c',
        // Response replies route push as MESSAGE but the toggle stays legacy
        // Asks & Offers (matching the push override) — a reply email is silenced
        // by the user's Asks & Offers preference, not by Messages.
        FimbyConstants.NOTIF_RESPONSE_REPLY      => 'Email_Alert_Needs_Offers__c',
        FimbyConstants.NOTIF_EVENT_CHAT          => 'Email_Alert_Events__c',
        FimbyConstants.NOTIF_COMMENT             => 'Email_Alert_Stories__c',
        FimbyConstants.NOTIF_LENDING_REQUEST     => 'Email_Alert_Library__c',
        FimbyConstants.NOTIF_LOAN_APPROVED       => 'Email_Alert_Library__c',
        FimbyConstants.NOTIF_EXTENSION_REQUEST   => 'Email_Alert_Library__c',
        FimbyConstants.NOTIF_EXTENSION_APPROVED  => 'Email_Alert_Library__c',
        FimbyConstants.NOTIF_EXTENSION_DECLINED  => 'Email_Alert_Library__c',
        FimbyConstants.NOTIF_ITEM_RETURNED       => 'Email_Alert_Library__c',
        FimbyConstants.NOTIF_OVERDUE_REMINDER    => 'Email_Alert_Reminders__c',
        FimbyConstants.NOTIF_EVENT_REMINDER      => 'Email_Alert_Events__c',
        FimbyConstants.NOTIF_BULK_BUY_RESERVATION => 'Email_Alert_Bulk_Buy__c',
        FimbyConstants.NOTIF_BULK_BUY_STATUS     => 'Email_Alert_Bulk_Buy__c',
        FimbyConstants.NOTIF_BULK_BUY_PICKUP     => 'Email_Alert_Bulk_Buy__c'
    };

    // Security/safety notification types that MUST bypass every gate, including
    // the master Email_Alerts_Enabled__c toggle. The Settings UI shows a static
    // "Account & Safety" line with no toggle so users understand there is no
    // opt-out. As of v1 no in-app notification flow targets a user with a
    // security-only message — password resets go through System.resetPassword
    // (Salesforce internal), and account-deletion emails go through
    // FimbyDeletionEmailService directly. Neither uses this pipeline. The set
    // is intentionally empty until a specific security type is added; new
    // entries must be paired with a test that asserts the bypass.
    //
    // Vouching: every vouch lifecycle type is system/safety. Approval grants
    // library access, decline/revoke/pause changes that access, and reminders
    // are needed so a pending vouch does not strand the requester. None of
    // these can be silenced — they ride out on the safety lane.
    @TestVisible
    private static final Set<String> SECURITY_BYPASS_TYPES = new Set<String>{
        FimbyConstants.NOTIF_VOUCH_REQUEST_RECEIVED,
        FimbyConstants.NOTIF_VOUCH_REQUEST_REMINDER,
        FimbyConstants.NOTIF_VOUCH_APPROVED,
        FimbyConstants.NOTIF_VOUCH_DECLINED,
        FimbyConstants.NOTIF_VOUCH_REVOKED,
        FimbyConstants.NOTIF_VOUCHER_PAUSED
    };

    /**
     * @description Determines whether a notification should be queued for email delivery.
     * @return 'Pending' if eligible, null otherwise
     */
    public static String shouldSendEmail(String notifType, User u) {
        if (u == null) {
            return null;
        }

        // Security bypass: these types ride out regardless of master toggle,
        // category toggle, or email-pilot allowlist. Account safety messages
        // are not opt-out-able by design (see SECURITY_BYPASS_TYPES comment).
        if (SECURITY_BYPASS_TYPES.contains(notifType)) {
            return 'Pending';
        }

        if (!FimbySettings.emailAlertsGlobalEnabled()) {
            return null;
        }
        if (u.Email_Alerts_Enabled__c == false) {
            return null;
        }

        EmailDefault emailDefault = EMAIL_TYPE_MAP.get(notifType);
        if (emailDefault == null) {
            return null;
        }

        String toggleField = EMAIL_TOGGLE_MAP.get(notifType);
        if (toggleField != null) {
            Boolean toggleValue = (Boolean) u.get(toggleField);
            if (toggleValue == false) {
                return null;
            }
        }

        Set<String> pilotIds = FimbySettings.emailPilotUserIds();
        if (!pilotIds.isEmpty() && !pilotIds.contains(String.valueOf(u.Id))) {
            return null;
        }

        return 'Pending';
    }

    /**
     * @description Test-only hook that lets the test harness register a fake
     * security-bypass notification type so the bypass code path can be
     * exercised without committing to a real production NOTIF_* constant.
     * Resets are unnecessary because tests run in a fresh transaction.
     */
    @TestVisible
    private static void addSecurityBypassTypeForTest(String notifType) {
        if (Test.isRunningTest() && String.isNotBlank(notifType)) {
            SECURITY_BYPASS_TYPES.add(notifType);
        }
    }

    /**
     * @description Returns true if the notification type uses the DM gate (direct-action).
     * Direct-action types still send on Sundays.
     */
    public static Boolean isDirectActionType(String notifType) {
        return notifType == FimbyConstants.NOTIF_MESSAGE
            || notifType == FimbyConstants.NOTIF_LENDING_REQUEST
            || notifType == FimbyConstants.NOTIF_LOAN_APPROVED
            || notifType == FimbyConstants.NOTIF_EXTENSION_REQUEST
            || notifType == FimbyConstants.NOTIF_EXTENSION_APPROVED
            || notifType == FimbyConstants.NOTIF_EXTENSION_DECLINED
            || notifType == FimbyConstants.NOTIF_ITEM_RETURNED
            || notifType == FimbyConstants.NOTIF_VOUCH_REQUEST_RECEIVED
            || notifType == FimbyConstants.NOTIF_VOUCH_APPROVED
            || notifType == FimbyConstants.NOTIF_VOUCH_DECLINED;
    }
}
