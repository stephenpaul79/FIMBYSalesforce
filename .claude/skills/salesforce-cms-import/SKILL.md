---
name: salesforce-cms-import
description: Build importable Salesforce CMS content packages — zip structure, content.json / _meta.json format, field rules, UTF-8 no-BOM encoding, and common import errors. Load when creating or fixing CMS content import packages for the FIMBY Experience Cloud site.
---

# Salesforce CMS Content Import

## Zip structure
Each content item = a folder with two files, nested under a CMS folder name:
```
CMS Folder Name/
  UniqueFolder001/
    content.json
    _meta.json
  UniqueFolder002/
    content.json
    _meta.json
```
Zip the top-level folder(s) directly — the zip root contains the CMS folder name directory.

## content.json
```json
{
  "type" : "your_content_type_developer_name",
  "title" : "Human-readable title",
  "contentBody" : {
    "nameField" : "Value for the NAMEFIELD node",
    "richTextField" : "<p>HTML content for RTE nodes</p>",
    "textField" : "Plain text value"
  },
  "urlName" : "url-slug-with-hyphens"
}
```
- `type` must match the `developerName` of a ManagedContentType deployed to the org **and enabled on the CMS workspace**.
- `contentBody` keys must match the `nodeName` values from the content type definition.
- RTE fields use raw HTML (not unicode-escaped). Write files UTF-8 **no-BOM**.
- `urlName` = URL slug, lowercase, hyphens allowed.
- Optional content-type fields can be omitted.

## _meta.json
```json
{
  "apiName" : "unique_api_name",
  "path" : "CMS Folder Name",
  "taxonomyTerms" : [ ]
}
```
- `apiName`: **only** alphanumeric + underscores. Begins with a letter, no trailing underscore, no consecutive underscores. Unique per content type.
- `path`: the CMS folder the item belongs to — must match the zip folder directory name.
- **Do NOT include `contentKey`** — Salesforce auto-generates it.

## Common errors
| Error | Cause | Fix |
|-------|-------|-----|
| "couldn't find a content.json file" | Wrong filename / not inside a folder | Each item needs its own subfolder with `content.json` |
| "Specify value for type property" | Content type not recognized | Deploy the type AND enable it on the CMS workspace |
| "This field can contain only underscores and alphanumeric characters" | `apiName` has hyphens/special chars | Use underscores: `my_api_name` |
| "Invalid value for ContentKey" | Made-up contentKey | Omit `contentKey` entirely |

## Build script (PowerShell, when on Windows)
PowerShell's `ConvertTo-Json` unicode-escapes HTML `<>`. Write with `UTF8Encoding($false)` (no BOM):
```powershell
function Write-JsonFile($path, $jsonString) {
    [System.IO.File]::WriteAllText($path, $jsonString, [System.Text.UTF8Encoding]::new($false))
}
```
Build JSON via here-strings (`@' ... '@`) to preserve raw HTML, then zip with `Compress-Archive`. (Any approach works as long as the output is UTF-8 no-BOM with un-escaped HTML.)

## Post-import
Imported items are in **draft** status. They must be **published** in the CMS workspace before LWC wire adapters (`getContents` from `experience/cmsDeliveryApi`) can read them.
