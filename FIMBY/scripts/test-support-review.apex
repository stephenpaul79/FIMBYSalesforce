Map<String, Object> data = FimbyModeratorQueryService.getSupportReviewData('a1YOL000005Wuyf2AC');
System.debug('relationshipType=' + data.get('relationshipType'));
System.debug('orgVerified=' + data.get('orgVerified'));
System.debug('orgVerificationStatus=' + data.get('orgVerificationStatus'));
