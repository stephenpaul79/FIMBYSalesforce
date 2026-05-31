public class FeedCommentHelper {
    public static void preventCspLitePortalComments(List<FeedComment> feedComments) {
        // List of user Ids to check their UserType
        Set<Id> userIds = new Set<Id>();

        // Collect all user Ids from the new FeedComments
        for (FeedComment comment : feedComments) {
            if (comment.InsertedById != null) {
                userIds.add(comment.InsertedById);
            }
        }

        if (!userIds.isEmpty()) {
            // Query user types for the collected user Ids
            Map<Id, User> userMap = new Map<Id, User>([SELECT Id, UserType FROM User WHERE Id IN :userIds]);

            // Iterate through the FeedComments and add an error if the user type is 'CspLitePortal'
            for (FeedComment comment : feedComments) {
                if (comment.InsertedById != null && userMap.containsKey(comment.InsertedById)) {
                    User user = userMap.get(comment.InsertedById);
                    if (user.UserType == 'CspLitePortal') {
                        comment.addError('Please do not place comments directly in the feed.  Instead, use the "Reply" button above and copy your comment into the popup window to correspond.  This will send an email directly to that contact.');
                    }
                }
            }
        }
    }
}