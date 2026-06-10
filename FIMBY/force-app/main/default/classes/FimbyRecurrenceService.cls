/**
 * @description Recurrence engine — find-due series, spawn occurrences, end gates, series lifecycle.
 */
public with sharing class FimbyRecurrenceService {

    public static final String END_MODE_NEVER = 'Never';
    public static final String END_MODE_ON_DATE = 'On_Date';
    public static final String END_MODE_AFTER_N = 'After_N';

    public static final String DELETE_THIS_EVENT = 'THIS_EVENT';
    public static final String DELETE_THIS_AND_FOLLOWING = 'THIS_AND_FOLLOWING';
    public static final String DELETE_ALL_EVENTS = 'ALL_EVENTS';

    public static final String SCOPE_THIS_ONLY = 'thisOnly';
    public static final String SCOPE_THIS_AND_FUTURE = 'thisAndFuture';

    private static final Set<String> ALLOWED_RECURRENCE_FREQUENCIES = new Set<String>{
        'Week', 'Month', 'Year'
    };

    private static List<FimbyRecurrenceSpawnStrategy> strategies;

    @TestVisible
    private static List<FimbyRecurrenceSpawnStrategy> getStrategies() {
        if (strategies == null) {
            strategies = new List<FimbyRecurrenceSpawnStrategy>{
                new FimbyEventRecurrenceSpawnStrategy()
            };
        }
        return strategies;
    }

    /**
     * @description Apply recurrence fields from composer/edit payload onto a new series parent.
     */
    public static void applyRecurrenceOnCreate(Needs_Offers__c post, Map<String, Object> data) {
        if (data == null || data.get('recurrenceEnabled') != true) {
            return;
        }
        applyRecurrenceFields(post, data);
        post.Current_Occurrence__c = null;
        post.Series_Ended__c = false;
        post.Next_Occurrence_Date__c = computeNextSpawnDate(
            post.Start_Date__c != null ? post.Start_Date__c : Date.today(),
            post.Recurrence_Frequency__c,
            post.Recurrence_Interval__c
        );
    }

    /**
     * @description After insert, leave Current_Occurrence__c null — the parent row is the live occurrence until spawn.
     * Self-referencing Current_Occurrence__c causes a hierarchy circular-dependency error.
     */
    public static void finalizeSeriesParentAfterInsert(Needs_Offers__c post) {
        // no-op; feed treats null Current_Occurrence__c on series parent as live
    }

    public static Date computeNextSpawnDate(Date fromDate, String frequency, Decimal interval) {
        return FimbyRecurrenceDateMath.advanceDate(fromDate, frequency, interval);
    }

    /**
     * @description Process all series due for spawn. Called by FimbyRecurrenceJob.
     */
    public static Integer processDueSeries(Integer maxRows) {
        Integer limitSize = maxRows != null && maxRows > 0 ? maxRows : 100;
        Date today = Date.today();

        List<Needs_Offers__c> parents = [
            SELECT Id, Name, RecordTypeId, Type__c, Event_Type__c,
                   Contact__c, Posted_By__c, Neighbourhood__c, Giver_Recipient_Type__c,
                   Visibility_Scope__c, Details__c, Full_Details__c,
                   Total_Quantity__c, Per_Response_Limit__c,
                   Start_Date__c, End_Date__c, Start_Time__c, Start_Time_Text__c,
                   End_Time__c, End_Time_Text__c, Location__c, Event_Link__c, Event_Notes__c,
                   Expected_Attendance__c, Auto_Accept_Responses__c, Auto_Share_Contact_Info__c,
                   Image_1_URL__c, Image_1_Ratio__c, Image_1_Dimensions__c,
                   Image_2_URL__c, Image_2_Ratio__c, Image_3_URL__c, Image_3_Ratio__c,
                   Image_4_URL__c, Image_4_Ratio__c,
                   Recurrence_Frequency__c, Recurrence_Interval__c,
                   Recurrence_End_Mode__c, Recurrence_End_Date__c, Recurrence_Max_Occurrences__c,
                   Next_Occurrence_Date__c, Current_Occurrence__c, Reinvite_Prior_Attendees__c,
                   Series_Ended__c
            FROM Needs_Offers__c
            WHERE Recurrence_Frequency__c != null
              AND Series_Parent__c = null
              AND Series_Ended__c = false
              AND Next_Occurrence_Date__c != null
              AND Next_Occurrence_Date__c <= :today
            ORDER BY Next_Occurrence_Date__c ASC
            LIMIT :limitSize
        ];

        Integer spawned = 0;
        for (Needs_Offers__c parent : parents) {
            if (spawnNextOccurrence(parent)) {
                spawned++;
            }
        }
        return spawned;
    }

    @TestVisible
    private static Boolean spawnNextOccurrence(Needs_Offers__c parent) {
        FimbyRecurrenceSpawnStrategy strategy = resolveStrategy(parent);
        if (strategy == null) {
            return false;
        }

        Needs_Offers__c prior = resolvePriorOccurrence(parent);
        Date nextStart = parent.Next_Occurrence_Date__c;
        Integer spanDays = FimbyRecurrenceDateMath.daysBetweenInclusive(
            prior.Start_Date__c != null ? prior.Start_Date__c : nextStart,
            prior.End_Date__c != null ? prior.End_Date__c : nextStart
        );
        Date nextEnd = nextStart.addDays(spanDays);

        Integer existingChildren = countChildren(parent.Id);
        if (isSeriesAfterNComplete(parent, existingChildren)) {
            endSeries(parent);
            return false;
        }
        if (shouldEndBeforeSpawn(parent, nextStart, existingChildren)) {
            endSeries(parent);
            return false;
        }

        Needs_Offers__c child = strategy.buildOccurrence(parent, prior, nextStart, nextEnd);
        insert as user child;

        parent.Current_Occurrence__c = child.Id;
        parent.Next_Occurrence_Date__c = computeNextSpawnDate(
            nextStart,
            parent.Recurrence_Frequency__c,
            parent.Recurrence_Interval__c
        );

        if (shouldEndAfterSpawn(parent, nextStart, existingChildren + 1)) {
            update as user new Needs_Offers__c(
                Id = parent.Id,
                Current_Occurrence__c = child.Id
            );
            parent.Current_Occurrence__c = child.Id;
            endSeries(parent);
        } else {
            update as user new Needs_Offers__c(
                Id = parent.Id,
                Current_Occurrence__c = child.Id,
                Next_Occurrence_Date__c = parent.Next_Occurrence_Date__c
            );
        }

        if (parent.Reinvite_Prior_Attendees__c == true && prior != null) {
            FimbyRecurrenceReinviteService.sendReinvites(parent, prior, child);
        }

        return true;
    }

    private static Needs_Offers__c resolvePriorOccurrence(Needs_Offers__c parent) {
        if (parent.Current_Occurrence__c == null) {
            return parent;
        }
        List<Needs_Offers__c> rows = [
            SELECT Id, Start_Date__c, End_Date__c
            FROM Needs_Offers__c
            WHERE Id = :parent.Current_Occurrence__c
            LIMIT 1
        ];
        return rows.isEmpty() ? parent : rows[0];
    }

    @TestVisible
    private static Integer countChildren(Id parentId) {
        return [
            SELECT COUNT()
            FROM Needs_Offers__c
            WHERE Series_Parent__c = :parentId
        ];
    }

    @TestVisible
    private static Boolean isSeriesAfterNComplete(Needs_Offers__c parent, Integer existingChildren) {
        if (parent.Recurrence_End_Mode__c != END_MODE_AFTER_N) {
            return false;
        }
        Decimal maxN = parent.Recurrence_Max_Occurrences__c;
        if (maxN == null) {
            return false;
        }
        return (1 + existingChildren) >= maxN.intValue();
    }

    @TestVisible
    private static Boolean shouldEndBeforeSpawn(Needs_Offers__c parent, Date nextStart, Integer existingChildren) {
        String mode = parent.Recurrence_End_Mode__c != null ? parent.Recurrence_End_Mode__c : END_MODE_NEVER;
        if (mode == END_MODE_ON_DATE) {
            return parent.Recurrence_End_Date__c != null && nextStart > parent.Recurrence_End_Date__c;
        }
        if (mode == END_MODE_AFTER_N) {
            Decimal maxN = parent.Recurrence_Max_Occurrences__c;
            Integer totalIfSpawned = 1 + existingChildren + 1;
            return maxN != null && totalIfSpawned > maxN.intValue();
        }
        return false;
    }

    @TestVisible
    private static Boolean shouldEndAfterSpawn(Needs_Offers__c parent, Date spawnedStart, Integer childCountAfterSpawn) {
        String mode = parent.Recurrence_End_Mode__c != null ? parent.Recurrence_End_Mode__c : END_MODE_NEVER;
        if (mode == END_MODE_ON_DATE) {
            return parent.Recurrence_End_Date__c != null && spawnedStart > parent.Recurrence_End_Date__c;
        }
        if (mode == END_MODE_AFTER_N) {
            Decimal maxN = parent.Recurrence_Max_Occurrences__c;
            Integer totalOccurrences = 1 + childCountAfterSpawn;
            return maxN != null && totalOccurrences >= maxN.intValue();
        }
        return false;
    }

    public static void endSeries(Needs_Offers__c parent) {
        update as user new Needs_Offers__c(
            Id = parent.Id,
            Series_Ended__c = true,
            Next_Occurrence_Date__c = null,
            Recurrence_Frequency__c = null,
            Recurrence_Interval__c = null,
            Recurrence_End_Mode__c = null,
            Recurrence_End_Date__c = null,
            Recurrence_Max_Occurrences__c = null
        );
        parent.Series_Ended__c = true;
        parent.Next_Occurrence_Date__c = null;
        parent.Recurrence_Frequency__c = null;
        parent.Recurrence_Interval__c = null;
        parent.Recurrence_End_Mode__c = null;
        parent.Recurrence_End_Date__c = null;
        parent.Recurrence_Max_Occurrences__c = null;
    }

    public static Id resolveSeriesParentId(Needs_Offers__c post) {
        if (post == null) {
            return null;
        }
        return post.Series_Parent__c != null ? post.Series_Parent__c : post.Id;
    }

    public static Boolean isSeriesMember(Needs_Offers__c post) {
        return post != null && (
            String.isNotBlank(post.Recurrence_Frequency__c) || post.Series_Parent__c != null
        );
    }

    /**
     * @description Copy recurrence template fields from payload onto parent and/or occurrence.
     */
    public static void applyRecurrenceOnUpdate(
        Needs_Offers__c occurrence,
        Needs_Offers__c parent,
        Map<String, Object> data,
        String scope
    ) {
        if (data == null || data.get('recurrenceEnabled') != true) {
            if (data != null && data.containsKey('recurrenceEnabled') && data.get('recurrenceEnabled') == false) {
                if (parent != null && parent.Id == occurrence.Id) {
                    endSeries(parent);
                }
            }
            return;
        }

        Boolean thisAndFuture = scope == SCOPE_THIS_AND_FUTURE;
        Needs_Offers__c target = thisAndFuture && parent != null ? parent : occurrence;
        applyRecurrenceFields(target, data);

        if (thisAndFuture && parent != null && parent.Id != occurrence.Id) {
            copyTemplateFieldsToOccurrence(parent, occurrence);
            occurrence.Next_Occurrence_Date__c = null;
            occurrence.Recurrence_Frequency__c = null;
            occurrence.Recurrence_Interval__c = null;
            occurrence.Recurrence_End_Mode__c = null;
            occurrence.Recurrence_End_Date__c = null;
            occurrence.Recurrence_Max_Occurrences__c = null;
            occurrence.Reinvite_Prior_Attendees__c = false;
            occurrence.Series_Ended__c = false;
            parent.Next_Occurrence_Date__c = computeNextSpawnDate(
                occurrence.Start_Date__c != null ? occurrence.Start_Date__c : Date.today(),
                parent.Recurrence_Frequency__c,
                parent.Recurrence_Interval__c
            );
            parent.Series_Ended__c = false;
            parent.Current_Occurrence__c = occurrence.Id;
        }
    }

    public static void copyTemplateFieldsToOccurrence(Needs_Offers__c parent, Needs_Offers__c occurrence) {
        if (parent == null || occurrence == null) {
            return;
        }
        occurrence.Name = parent.Name;
        occurrence.Details__c = parent.Details__c;
        occurrence.Full_Details__c = parent.Full_Details__c;
        occurrence.Location__c = parent.Location__c;
        occurrence.Event_Link__c = parent.Event_Link__c;
        occurrence.Event_Notes__c = parent.Event_Notes__c;
        occurrence.Total_Quantity__c = parent.Total_Quantity__c;
        occurrence.Per_Response_Limit__c = parent.Per_Response_Limit__c;
        occurrence.Expected_Attendance__c = parent.Expected_Attendance__c;
        occurrence.Auto_Accept_Responses__c = parent.Auto_Accept_Responses__c;
        occurrence.Auto_Share_Contact_Info__c = parent.Auto_Share_Contact_Info__c;
        occurrence.Image_1_URL__c = parent.Image_1_URL__c;
        occurrence.Image_1_Ratio__c = parent.Image_1_Ratio__c;
        occurrence.Image_2_URL__c = parent.Image_2_URL__c;
        occurrence.Image_2_Ratio__c = parent.Image_2_Ratio__c;
        occurrence.Image_3_URL__c = parent.Image_3_URL__c;
        occurrence.Image_3_Ratio__c = parent.Image_3_Ratio__c;
        occurrence.Image_4_URL__c = parent.Image_4_URL__c;
        occurrence.Image_4_Ratio__c = parent.Image_4_Ratio__c;
    }

    private static void applyRecurrenceFields(Needs_Offers__c post, Map<String, Object> data) {
        String frequency = (String) data.get('recurrenceFrequency');
        if (String.isNotBlank(frequency) && !ALLOWED_RECURRENCE_FREQUENCIES.contains(frequency)) {
            throw new AuraHandledException(
                'Recurring events can repeat every week, month, or year at the soonest.'
            );
        }
        post.Recurrence_Frequency__c = frequency;
        post.Recurrence_Interval__c = data.get('recurrenceInterval') != null
            ? Decimal.valueOf(String.valueOf(data.get('recurrenceInterval'))) : 1;
        post.Recurrence_End_Mode__c = (String) data.get('recurrenceEndMode');
        String endDateStr = (String) data.get('recurrenceEndDate');
        post.Recurrence_End_Date__c = String.isNotBlank(endDateStr) ? Date.valueOf(endDateStr) : null;
        post.Recurrence_Max_Occurrences__c = data.get('recurrenceMaxOccurrences') != null
            ? Decimal.valueOf(String.valueOf(data.get('recurrenceMaxOccurrences'))) : null;
        post.Reinvite_Prior_Attendees__c = data.get('reinvitePriorAttendees') == true;
        if (String.isBlank(post.Recurrence_End_Mode__c)) {
            post.Recurrence_End_Mode__c = END_MODE_NEVER;
        }
    }

    /**
     * @description Delete a series member with calendar-app semantics.
     */
    public static void deleteSeriesMember(Id recordId, String deleteScope) {
        Needs_Offers__c post = [
            SELECT Id, Series_Parent__c, Recurrence_Frequency__c, Current_Occurrence__c
            FROM Needs_Offers__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        Id parentId = post.Series_Parent__c != null ? post.Series_Parent__c : post.Id;
        Boolean isParent = post.Series_Parent__c == null && String.isNotBlank(post.Recurrence_Frequency__c);
        String scope = String.isNotBlank(deleteScope) ? deleteScope : DELETE_THIS_EVENT;

        if (scope == DELETE_THIS_EVENT) {
            deleteSingleOccurrence(post, parentId);
            return;
        }

        if (scope == DELETE_THIS_AND_FOLLOWING) {
            if (isParent) {
                deleteAllSeries(parentId);
            } else {
                stopSeriesAndDeleteCurrent(post, parentId);
            }
            return;
        }

        if (scope == DELETE_ALL_EVENTS) {
            deleteAllSeries(parentId);
        }
    }

    private static void deleteSingleOccurrence(Needs_Offers__c post, Id parentId) {
        Boolean isSeriesParent = post.Series_Parent__c == null
            && String.isNotBlank(post.Recurrence_Frequency__c);
        Integer childCount = isSeriesParent ? countChildren(parentId) : 0;

        if (isSeriesParent && childCount == 0) {
            delete as user post;
            return;
        }

        if (isSeriesParent) {
            Needs_Offers__c parent = [
                SELECT Id, Current_Occurrence__c, Recurrence_Frequency__c, Recurrence_Interval__c
                FROM Needs_Offers__c
                WHERE Id = :parentId
                LIMIT 1
            ];
            if (parent.Current_Occurrence__c != null && parent.Current_Occurrence__c != parent.Id) {
                delete as user new Needs_Offers__c(Id = parent.Current_Occurrence__c);
                parent.Current_Occurrence__c = null;
                parent.Next_Occurrence_Date__c = computeNextSpawnDate(
                    Date.today(),
                    parent.Recurrence_Frequency__c,
                    parent.Recurrence_Interval__c
                );
                update as user parent;
            } else {
                delete as user post;
            }
            return;
        }

        Needs_Offers__c parent = [
            SELECT Id, Current_Occurrence__c, Next_Occurrence_Date__c,
                   Recurrence_Frequency__c, Recurrence_Interval__c, Start_Date__c
            FROM Needs_Offers__c
            WHERE Id = :parentId
            LIMIT 1
        ];
        delete as user post;
        if (parent.Current_Occurrence__c == post.Id) {
            parent.Current_Occurrence__c = null;
            parent.Next_Occurrence_Date__c = computeNextSpawnDate(
                Date.today(),
                parent.Recurrence_Frequency__c,
                parent.Recurrence_Interval__c
            );
            update as user parent;
        }
    }

    private static void stopSeriesAndDeleteCurrent(Needs_Offers__c post, Id parentId) {
        endSeries(loadParent(parentId));
        delete as user post;
    }

    private static void deleteAllSeries(Id parentId) {
        List<Needs_Offers__c> children = [
            SELECT Id FROM Needs_Offers__c WHERE Series_Parent__c = :parentId
        ];
        if (!children.isEmpty()) {
            delete as user children;
        }
        delete as user new Needs_Offers__c(Id = parentId);
    }

    private static Needs_Offers__c loadParent(Id parentId) {
        List<Needs_Offers__c> rows = [
            SELECT Id, Recurrence_Frequency__c, Recurrence_Interval__c,
                   Recurrence_End_Mode__c, Recurrence_End_Date__c, Recurrence_Max_Occurrences__c,
                   Next_Occurrence_Date__c, Series_Ended__c
            FROM Needs_Offers__c
            WHERE Id = :parentId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static FimbyRecurrenceSpawnStrategy resolveStrategy(Needs_Offers__c parent) {
        for (FimbyRecurrenceSpawnStrategy strategy : getStrategies()) {
            if (strategy.supports(parent)) {
                return strategy;
            }
        }
        return null;
    }
}
