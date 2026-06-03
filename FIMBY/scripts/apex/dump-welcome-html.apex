List<EmailTemplate> templates = [
    SELECT Id, Name, DeveloperName, Subject, IsActive,
           HtmlValue, Body
    FROM EmailTemplate
    WHERE DeveloperName LIKE '%Welcome%'
       OR Name LIKE '%Welcome%'
    ORDER BY DeveloperName
];
for (EmailTemplate t : templates) {
    String html = t.HtmlValue != null ? t.HtmlValue : '';
    String snippet = html.length() > 120 ? html.substring(0, 120) : html;
    System.debug('--- ' + t.DeveloperName + ' | ' + t.Name + ' | subject=' + t.Subject);
    System.debug('snippet=' + snippet.replace('\n', ' '));
    System.debug('has founder letter=' + html.contains('Stephen Rathjen'));
    System.debug('has You are in=' + html.contains('You are in'));
    System.debug('has Open FIMBY=' + html.contains('Open FIMBY'));
}
