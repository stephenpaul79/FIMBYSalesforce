/**
 * @description Stamps humane-push doorbell timestamps on User after confirmed delivery.
 * Separate class so FimbyPushQueueable can invoke @future (not allowed from Queueable directly).
 */
public without sharing class FimbyPushGateStampAction {

    @Future
    public static void stampGates(Map<String, String> gateUpdatesByUserId) {
        stampGatesSync(gateUpdatesByUserId);
    }

    public static void stampGatesSync(Map<String, String> gateUpdatesByUserId) {
        if (gateUpdatesByUserId == null || gateUpdatesByUserId.isEmpty()) {
            return;
        }
        Datetime now = Datetime.now();
        List<User> usersToUpdate = new List<User>();
        for (String userIdStr : gateUpdatesByUserId.keySet()) {
            String gateType = gateUpdatesByUserId.get(userIdStr);
            User u = new User(Id = userIdStr);
            if (gateType == 'QUIET') {
                // QUIET is mutually exclusive with the doorbell gates: a passive
                // refresh must NEVER move Last_DM/Activity_Push_At__c (that would
                // close the gate and silence the next legitimate audible buzz).
                // The else-branch is the ONLY writer of the doorbell timestamps;
                // this guard enforces the exclusion at the writer rather than
                // trusting the caller.
                u.Last_Quiet_Refresh_At__c = now;   // observability only
            } else {
                if (gateType == 'DM' || gateType == 'BOTH') {
                    u.Last_DM_Push_At__c = now;
                }
                if (gateType == 'ACTIVITY' || gateType == 'BOTH') {
                    u.Last_Activity_Push_At__c = now;
                }
            }
            usersToUpdate.add(u);
        }
        try {
            Database.update(usersToUpdate, false);
        } catch (Exception e) {
            FimbyLogger.error('FimbyPushGateStampAction', 'stampGatesSync', e);
        }
    }
}
