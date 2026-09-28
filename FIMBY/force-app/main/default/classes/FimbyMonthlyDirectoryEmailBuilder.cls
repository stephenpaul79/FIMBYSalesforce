/**
 * @description Builds the body of the monthly Library email: every library item a recipient
 * can see (Items To Borrow) and every active skill offer in their neighbourhood (Skills On
 * Offer), grouped by category and then sorted by name.
 *
 * Rows are compact and image-free so the whole list fits under Gmail's clipping threshold.
 * When it does not fit, the owner initials are dropped first, then rows are trimmed
 * round-robin across categories so every category keeps some rows. Each section ends with
 * one link to the Library tab pre-filtered to that section; when rows were left out, that
 * link says how many.
 *
 * loadDirectory runs once per neighbourhood. render applies one recipient cohort's view:
 * adjacent-neighbourhood visibility (including owners who share contact info with them)
 * and bidirectional blocks against both the owner and the person who listed the record.
 */
public without sharing class FimbyMonthlyDirectoryEmailBuilder {

    @TestVisible
    private static final Integer QUERY_LIMIT = 2000;
    private static final String OTHER_CATEGORY = 'Other';
    private static final String FALLBACK_OWNER = 'A neighbour';
    private static final String ITEMS_FILTER = 'items';
    private static final String SKILLS_FILTER = 'skills';
    private static final Set<String> ADJACENT_SCOPES = new Set<String>{ 'Adjacent', 'Regional' };

    private static final String F = FimbyEmailHtmlBuilder.F;
    private static final String TEXT_BODY = '#4A4A4A';
    private static final String TEXT_SECONDARY = '#6B6B6B';
    private static final String LINK_COLOR = '#3A7D8C';
    private static final String BORDER_LIGHT = '#E8E0D6';
    private static final String ROW_RULE = '#F0EBE3';
    private static final String ON_LOAN_COLOR = '#7D6234';
    private static final String ITEMS_ACCENT = '#6B5E50';
    private static final String SKILLS_ACCENT = '#476B4C';
    private static final List<String> INITIAL_COLORS = new List<String>{
        '#476B4C', '#357280', '#6B5E50', '#7D6234', '#8A5936', '#5E7B92'
    };

    public class DirectoryRow implements Comparable {
        public Id recordId;
        public String name;
        public String category;
        public Id ownerContactId;
        public Id listedById;
        public String ownerName;
        public Boolean isOnLoan = false;
        public Id neighbourhoodId;
        public Boolean isAdjacentScoped = false;
        public String url;

        public Integer compareTo(Object other) {
            DirectoryRow that = (DirectoryRow) other;
            Boolean thisOther = category == OTHER_CATEGORY;
            Boolean thatOther = that.category == OTHER_CATEGORY;
            if (thisOther != thatOther) {
                return thisOther ? 1 : -1;
            }
            Integer byCategory = category.toLowerCase().compareTo(that.category.toLowerCase());
            if (byCategory != 0) {
                return byCategory;
            }
            return name.toLowerCase().compareTo(that.name.toLowerCase());
        }
    }

    public class Directory {
        public Id neighbourhoodId;
        public Set<Id> adjacentNeighbourhoodIds = new Set<Id>();
        public List<DirectoryRow> items = new List<DirectoryRow>();
        public List<DirectoryRow> skills = new List<DirectoryRow>();

        public Boolean isEmpty() {
            return items.isEmpty() && skills.isEmpty();
        }

        public Integer totalCount() {
            return items.size() + skills.size();
        }

        /** Owners of adjacent-neighbourhood items; only their shares can change visibility. */
        public Set<Id> adjacentOwnerIds() {
            Set<Id> ownerIds = new Set<Id>();
            for (DirectoryRow row : items) {
                if (row.neighbourhoodId != neighbourhoodId && row.ownerContactId != null) {
                    ownerIds.add(row.ownerContactId);
                }
            }
            return ownerIds;
        }
    }

    public class DirectoryResult {
        public String html = '';
        public Integer itemsShown = 0;
        public Integer itemsOmitted = 0;
        public Integer skillsShown = 0;
        public Integer skillsOmitted = 0;
        public Boolean droppedInitials = false;
        public Boolean isEmpty = true;
    }

    private class Selection {
        List<DirectoryRow> rows = new List<DirectoryRow>();
        Integer usedBytes = 0;
    }

    /* ---------------------------------------------------------------
     * Data
     * --------------------------------------------------------------- */

    public static Directory loadDirectory(Id neighbourhoodId) {
        Directory directory = new Directory();
        directory.neighbourhoodId = neighbourhoodId;
        if (neighbourhoodId == null) {
            return directory;
        }
        directory.adjacentNeighbourhoodIds = loadAdjacentIds(neighbourhoodId);

        List<String> statuses = new List<String>{
            FimbyConstants.LIBRARY_AVAILABLE, FimbyConstants.LIBRARY_LENT_OUT
        };
        for (Library_Item__c item : [
            SELECT Id, Name, Category__c, Status__c, Neighbourhood__c, Visibility_Scope__c,
                   Owner_Contact__c, Listed_By__c, Owner_Contact__r.Full_Name__c
            FROM Library_Item__c
            WHERE Neighbourhood__c = :neighbourhoodId
              AND Status__c IN :statuses
              AND (Moderation_Status__c = null OR Moderation_Status__c = 'Visible')
            LIMIT :QUERY_LIMIT
        ]) {
            directory.items.add(toItemRow(item));
        }

        Set<Id> adjacentIds = directory.adjacentNeighbourhoodIds;
        if (!adjacentIds.isEmpty()) {
            for (Library_Item__c item : [
                SELECT Id, Name, Category__c, Status__c, Neighbourhood__c, Visibility_Scope__c,
                       Owner_Contact__c, Listed_By__c, Owner_Contact__r.Full_Name__c
                FROM Library_Item__c
                WHERE Neighbourhood__c IN :adjacentIds
                  AND Status__c IN :statuses
                  AND (Moderation_Status__c = null OR Moderation_Status__c = 'Visible')
                LIMIT :QUERY_LIMIT
            ]) {
                directory.items.add(toItemRow(item));
            }
        }

        for (Skill_Offer__c skill : [
            SELECT Id, Name, Skill_Category__c, Neighbourhood__c,
                   Owner_Contact__c, Listed_By__c, Owner_Contact__r.Full_Name__c
            FROM Skill_Offer__c
            WHERE Neighbourhood__c = :neighbourhoodId
              AND Status__c = :FimbyConstants.SKILL_ACTIVE
              AND (Moderation_Status__c = null OR Moderation_Status__c = 'Visible')
            LIMIT :QUERY_LIMIT
        ]) {
            directory.skills.add(toSkillRow(skill));
        }

        directory.items.sort();
        directory.skills.sort();
        return directory;
    }

    private static Set<Id> loadAdjacentIds(Id neighbourhoodId) {
        Set<Id> adjacentIds = new Set<Id>();
        List<Account> accounts = [
            SELECT Adjacent_Neighbourhood_Ids__c FROM Account WHERE Id = :neighbourhoodId LIMIT 1
        ];
        if (accounts.isEmpty() || String.isBlank(accounts[0].Adjacent_Neighbourhood_Ids__c)) {
            return adjacentIds;
        }
        for (String idStr : accounts[0].Adjacent_Neighbourhood_Ids__c.split(',')) {
            String trimmed = idStr.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            try {
                adjacentIds.add(Id.valueOf(trimmed));
            } catch (StringException e) {
                // Skip malformed IDs in the denormalized field.
            }
        }
        adjacentIds.remove(neighbourhoodId);
        return adjacentIds;
    }

    private static DirectoryRow toItemRow(Library_Item__c item) {
        DirectoryRow row = new DirectoryRow();
        row.recordId = item.Id;
        row.name = String.isNotBlank(item.Name) ? item.Name : 'Library item';
        row.category = String.isNotBlank(item.Category__c) ? item.Category__c : OTHER_CATEGORY;
        row.ownerContactId = item.Owner_Contact__c;
        row.listedById = item.Listed_By__c;
        row.ownerName = resolveOwnerName(item.Owner_Contact__r?.Full_Name__c);
        row.isOnLoan = item.Status__c == FimbyConstants.LIBRARY_LENT_OUT;
        row.neighbourhoodId = item.Neighbourhood__c;
        row.isAdjacentScoped = ADJACENT_SCOPES.contains(item.Visibility_Scope__c);
        row.url = FimbySettings.getUrl('Library_Item', item.Id);
        return row;
    }

    private static DirectoryRow toSkillRow(Skill_Offer__c skill) {
        DirectoryRow row = new DirectoryRow();
        row.recordId = skill.Id;
        row.name = String.isNotBlank(skill.Name) ? skill.Name : 'Skill';
        row.category = String.isNotBlank(skill.Skill_Category__c) ? skill.Skill_Category__c : OTHER_CATEGORY;
        row.ownerContactId = skill.Owner_Contact__c;
        row.listedById = skill.Listed_By__c;
        row.ownerName = resolveOwnerName(skill.Owner_Contact__r?.Full_Name__c);
        row.neighbourhoodId = skill.Neighbourhood__c;
        row.url = FimbySettings.getUrl('Skill_Offer', skill.Id);
        return row;
    }

    private static String resolveOwnerName(String fullName) {
        return String.isNotBlank(fullName) ? fullName.trim() : FALLBACK_OWNER;
    }

    /* ---------------------------------------------------------------
     * Rendering
     * --------------------------------------------------------------- */

    /**
     * @param excludedContactIds Contacts blocked by or blocking this cohort.
     * @param adjacentSharerIds Adjacent-neighbourhood owners who currently share contact
     *                          info with this cohort.
     * @param budgetBytes UTF-8 byte budget for the returned inner HTML.
     */
    public static DirectoryResult render(
        Directory directory, Set<Id> excludedContactIds, Set<Id> adjacentSharerIds, Integer budgetBytes
    ) {
        Set<Id> excluded = excludedContactIds != null ? excludedContactIds : new Set<Id>();
        Set<Id> sharers = adjacentSharerIds != null ? adjacentSharerIds : new Set<Id>();

        List<DirectoryRow> items = new List<DirectoryRow>();
        for (DirectoryRow row : directory.items) {
            if (isHidden(row, excluded)) {
                continue;
            }
            Boolean local = row.neighbourhoodId == directory.neighbourhoodId;
            if (local || row.isAdjacentScoped || sharers.contains(row.ownerContactId)) {
                items.add(row);
            }
        }
        List<DirectoryRow> skills = new List<DirectoryRow>();
        for (DirectoryRow row : directory.skills) {
            if (!isHidden(row, excluded)) {
                skills.add(row);
            }
        }

        DirectoryResult result = renderSelection(items, items, skills, skills, true);
        if (byteSize(result.html) <= budgetBytes) {
            return result;
        }

        result = renderSelection(items, items, skills, skills, false);
        result.droppedInitials = true;
        if (byteSize(result.html) <= budgetBytes) {
            return result;
        }

        // Frame cost: both sections with no rows, worst-case closing links.
        Integer frameBytes = byteSize(renderSelection(
            items, new List<DirectoryRow>(), skills, new List<DirectoryRow>(), false
        ).html);
        Integer available = budgetBytes - frameBytes;
        for (Integer attempt = 0; attempt < 4; attempt++) {
            Integer totalRows = items.size() + skills.size();
            Integer itemShare = totalRows == 0 ? 0 : available * items.size() / totalRows;
            Selection itemPick = pickRoundRobin(items, Math.max(itemShare, 0));
            Selection skillPick = pickRoundRobin(skills, Math.max(available - itemPick.usedBytes, 0));

            result = renderSelection(items, itemPick.rows, skills, skillPick.rows, false);
            result.droppedInitials = true;
            Integer overage = byteSize(result.html) - budgetBytes;
            if (overage <= 0) {
                return result;
            }
            available -= overage + 256;
        }
        return result;
    }

    private static Boolean isHidden(DirectoryRow row, Set<Id> excluded) {
        return (row.ownerContactId != null && excluded.contains(row.ownerContactId))
            || (row.listedById != null && excluded.contains(row.listedById));
    }

    /**
     * @description Takes one row per category per round while it fits. A category stops
     * the first time its next row does not fit, so other categories keep their turns.
     */
    private static Selection pickRoundRobin(List<DirectoryRow> rows, Integer budget) {
        Selection pick = new Selection();
        List<String> categories = new List<String>();
        Map<String, List<DirectoryRow>> rowsByCategory = new Map<String, List<DirectoryRow>>();
        for (DirectoryRow row : rows) {
            if (!rowsByCategory.containsKey(row.category)) {
                categories.add(row.category);
                rowsByCategory.put(row.category, new List<DirectoryRow>());
            }
            rowsByCategory.get(row.category).add(row);
        }

        Map<String, Integer> nextIndex = new Map<String, Integer>();
        Set<String> stopped = new Set<String>();
        Set<Id> chosen = new Set<Id>();
        Boolean progressed = true;
        while (progressed) {
            progressed = false;
            for (String category : categories) {
                if (stopped.contains(category)) {
                    continue;
                }
                List<DirectoryRow> categoryRows = rowsByCategory.get(category);
                Integer idx = nextIndex.containsKey(category) ? nextIndex.get(category) : 0;
                if (idx >= categoryRows.size()) {
                    stopped.add(category);
                    continue;
                }
                Integer cost = byteSize(buildRowHtml(categoryRows[idx], false));
                if (idx == 0) {
                    cost += byteSize(buildCategoryHtml(category));
                }
                if (pick.usedBytes + cost > budget) {
                    stopped.add(category);
                    continue;
                }
                pick.usedBytes += cost;
                chosen.add(categoryRows[idx].recordId);
                nextIndex.put(category, idx + 1);
                progressed = true;
            }
        }

        for (DirectoryRow row : rows) {
            if (chosen.contains(row.recordId)) {
                pick.rows.add(row);
            }
        }
        return pick;
    }

    private static DirectoryResult renderSelection(
        List<DirectoryRow> allItems, List<DirectoryRow> shownItems,
        List<DirectoryRow> allSkills, List<DirectoryRow> shownSkills,
        Boolean withInitials
    ) {
        DirectoryResult result = new DirectoryResult();
        result.isEmpty = allItems.isEmpty() && allSkills.isEmpty();
        result.itemsShown = shownItems.size();
        result.itemsOmitted = allItems.size() - shownItems.size();
        result.skillsShown = shownSkills.size();
        result.skillsOmitted = allSkills.size() - shownSkills.size();
        result.html = buildSection('Items To Borrow', ITEMS_ACCENT, 'Item', ITEMS_FILTER,
                allItems.size(), shownItems, withInitials)
            + buildSection('Skills On Offer', SKILLS_ACCENT, 'Skill', SKILLS_FILTER,
                allSkills.size(), shownSkills, withInitials);
        return result;
    }

    private static String buildSection(
        String title, String accent, String noun, String filter,
        Integer totalRows, List<DirectoryRow> shownRows, Boolean withInitials
    ) {
        String listUrl = FimbySettings.getUrl('Library_List') + '?filter=' + filter;
        String html = buildSectionHeader(title, accent);

        if (totalRows == 0) {
            String emptyLine = noun == 'Item'
                ? 'No items listed yet. <a href="' + listUrl + '" style="color:' + LINK_COLOR + ';">Be the first to share one in the Library</a>.'
                : 'No skills listed yet. <a href="' + listUrl + '" style="color:' + LINK_COLOR + ';">Be the first to offer one in the Library</a>.';
            return html + '<p style="' + F + 'margin:0;padding:8px 12px;font-size:14px;color:' + TEXT_SECONDARY + ';">'
                + emptyLine + '</p>';
        }

        if (!shownRows.isEmpty()) {
            html += '<table cellpadding="0" cellspacing="0" border="0" width="600" style="max-width:600px;width:100%;'
                + 'background-color:#FFFFFF;border:1px solid ' + BORDER_LIGHT + ';border-radius:8px;'
                + F + 'font-size:14px;color:' + TEXT_BODY + ';">';
            String currentCategory = null;
            for (DirectoryRow row : shownRows) {
                if (row.category != currentCategory) {
                    currentCategory = row.category;
                    html += buildCategoryHtml(currentCategory);
                }
                html += buildRowHtml(row, withInitials);
            }
            html += '</table>';
        }

        Integer omitted = totalRows - shownRows.size();
        return html + '<p style="' + F + 'margin:0;padding:10px 0 0;text-align:center;font-size:14px;">'
            + '<a href="' + listUrl + '" style="color:' + LINK_COLOR + ';">'
            + closingLinkText(noun, omitted) + '</a></p>';
    }

    @TestVisible
    private static String closingLinkText(String noun, Integer omitted) {
        if (omitted == null || omitted <= 0) {
            return 'Browse all ' + noun + 's in the Library';
        }
        return 'Browse ' + omitted + ' more ' + noun + (omitted == 1 ? '' : 's') + ' in the Library';
    }

    private static String buildSectionHeader(String title, String accent) {
        return '<table cellpadding="0" cellspacing="0" border="0" width="600" style="max-width:600px;width:100%;margin:16px 0 8px;">'
            + '<tr><td style="background-color:' + accent + ';border-radius:8px;padding:8px 12px;">'
            + '<span style="' + F + 'color:#FFFFFF;font-size:15px;font-weight:600;">' + escape(title) + '</span>'
            + '</td></tr></table>';
    }

    private static String buildCategoryHtml(String category) {
        return '<tr><td colspan="2" style="padding:12px 12px 4px;font-size:12px;font-weight:bold;color:'
            + TEXT_SECONDARY + ';text-transform:uppercase;">' + escape(category) + '</td></tr>';
    }

    private static String buildRowHtml(DirectoryRow row, Boolean withInitials) {
        String cell = 'padding:5px 12px;border-top:1px solid ' + ROW_RULE + ';';
        String onLoan = row.isOnLoan
            ? ' <span style="font-size:11px;color:' + ON_LOAN_COLOR + ';">on loan</span>'
            : '';
        return '<tr><td style="' + cell + '"><a href="' + row.url + '" style="color:' + LINK_COLOR + ';">'
            + escape(row.name) + '</a>' + onLoan + '</td>'
            + '<td align="right" style="' + cell + 'font-size:13px;color:' + TEXT_SECONDARY + ';">'
            + (withInitials ? buildInitial(row) : '') + escape(row.ownerName) + '</td></tr>';
    }

    private static String buildInitial(DirectoryRow row) {
        String initial = String.isNotBlank(row.ownerName) ? row.ownerName.left(1).toUpperCase() : '?';
        Integer colorIdx = row.ownerContactId == null ? 0
            : Math.mod(Math.abs(String.valueOf(row.ownerContactId).hashCode()), INITIAL_COLORS.size());
        return '<span style="display:inline-block;width:18px;height:18px;line-height:18px;border-radius:9px;'
            + 'background-color:' + INITIAL_COLORS[colorIdx] + ';color:#FFFFFF;font-size:10px;text-align:center;'
            + 'margin-right:6px;">' + escape(initial) + '</span>';
    }

    private static String escape(String input) {
        return input == null ? '' : input.escapeHtml4();
    }

    public static Integer byteSize(String html) {
        return html == null ? 0 : Blob.valueOf(html).size();
    }
}
