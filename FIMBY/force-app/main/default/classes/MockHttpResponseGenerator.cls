@isTest
public class MockHttpResponseGenerator implements HttpCalloutMock{
    
    public HTTPResponse respond(HTTPRequest req) {
        
        // Creating a fake response
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody('{"kind": "drive#file","id": "15t5z-l9MZMadT0JQv-2szr8ONFXES5JZ","name": "test_image", "mimeType": "image/png"}');
        res.setStatusCode(200);
        return res;
    }
}