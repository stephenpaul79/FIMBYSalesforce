trigger PreventCspLitePortalComments on FeedComment (after insert) {
    // Call the helper class method to perform the validation
    FeedCommentHelper.preventCspLitePortalComments(Trigger.new);
}