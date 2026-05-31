({
	init : function(component, event, helper) {
		var action = component.get('c.getLinks');
		action.setCallback(this, function(response) {
			if(response.getState() === 'SUCCESS') {
				var result = response.getReturnValue();
				console.log(JSON.stringify(result));

				/*var links = [];
                for (var key in result) {
                	if (key == 'null') links.push({value:result[key], key:''});
                    else links.push({value:result[key], key:key});
                }*/
                console.log(JSON.stringify(result));

				component.set('v.links', result);
			}
		});
		$A.enqueueAction(action);
	}
})