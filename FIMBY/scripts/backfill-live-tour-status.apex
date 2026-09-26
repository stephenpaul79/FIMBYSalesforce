// One-time: backfill blank Live_Tour_Status__c on neighbourhood contacts.
Id jobId = Database.executeBatch(new FimbyLiveTourStatusBackfillBatch(), 200);
System.debug('FimbyLiveTourStatusBackfillBatch job id: ' + jobId);
