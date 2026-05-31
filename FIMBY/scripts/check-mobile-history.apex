Map<String,Object> h = FimbyFollowUpController.getBulkBuyHistory('003OL00000bwBSSYA2');
System.debug('slots=' + h.get('slots') + ' blocked=' + h.get('isBlocked'));
