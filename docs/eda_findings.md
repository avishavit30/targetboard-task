# Jira Data EDA Findings

**Date:** 2026-02-02 (Updated)  
**Original Date:** 2026-01-29  
**Database:** targetboard_production_data_0001  
**Schema:** targetboard_source_jira

---

## Executive Summary

The dbt models are **correctly implemented** and producing accurate results:
- ✅ All 1,601 filtered issues have correct `status_as_of` values
- ✅ As-of date logic works correctly for historical queries
- ✅ Edge cases handled properly (issues without history, initial status fallback)
- ✅ 100% coverage of filtered issues in the mart

---

## Source Data Overview

Three key tables for the "status as of" function:

| Table | Rows | Columns | Description |
|-------|------|---------|-------------|
| `issues` | 2,296 | 202 | Main issue data with current state |
| `changelogs` | 18,620 | 18 | Change records linked to issues |
| `changelogs__items` | 20,547 | 13 | Individual field changes per changelog |

**Data range:** 2024-09-01 to 2026-01-26

---

## Pipeline Flow Analysis

### Data Flow Through DAG

```
SOURCE LAYER (raw data)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
issues (2,296) ──────────────────────┐
changelogs (18,620) ─────────────────┼──→ source()
changelogs__items (20,547) ──────────┘

STAGING LAYER (cleaned, typed)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
stg_issues (1,601)          ← Filtered to Task/Epic/Story
stg_changelogs (12,811)     ← Filtered to valid issues
stg_changelog_items (8,109) ← Status changes only (unfiltered by issue type)

INTERMEDIATE LAYER (business logic)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
int_issue_status_history (5,444) ← Joined and filtered
  • 1,285 issues have status history
  • 316 issues (19.7%) have no status changes

MART LAYER (consumer-ready)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
issue_status_as_of (1,601)  ← 100% coverage
  • All issues have status_as_of populated
  • Uses fallback logic for issues without history
```

### Row Count Reconciliation

| Layer | Model | Rows | Notes |
|-------|-------|------|-------|
| Source | issues | 2,296 | All issue types |
| Source | changelogs | 18,620 | All change events |
| Source | changelogs__items | 8,109 | Status changes only |
| Staging | stg_issues | 1,601 | Task/Epic/Story only (-695) |
| Staging | stg_changelogs | 12,811 | For filtered issues (-5,809) |
| Staging | stg_changelog_items | 8,109 | All status changes* |
| Intermediate | int_issue_status_history | 5,444 | After joins |
| Mart | issue_status_as_of | 1,601 | 100% issue coverage |

*Note: `stg_changelog_items` includes ALL status changes (8,109), but only 5,444 are used after joining with `stg_changelogs`. This is correct behavior - filtering by issue type happens at the intermediate layer.

---

## Table: issues (Source)

### Key Columns

| Column | Type | Distinct | Nulls | Notes |
|--------|------|----------|-------|-------|
| `id` | text | 2,296 | 0 | Primary key |
| `key` | text | 2,296 | 0 | Issue key (e.g., TB-152) |
| `fields__summary` | text | 2,188 | 0 | Issue title |
| `fields__issuetype__name` | text | 7 | 0 | Issue type |
| `fields__status__name` | text | 18 | 0 | Current status |
| `fields__created` | timestamp | - | 0 | Creation date |

### Issue Type Distribution

| Type | Count | Include in Cleaned Model? |
|------|-------|---------------------------|
| Task | 1,371 | ✅ Yes |
| Bug | 511 | ❌ No |
| Story | 136 | ✅ Yes |
| Subtask | 113 | ❌ No |
| Epic | 94 | ✅ Yes |
| Sub-task | 65 | ❌ No |
| Idea | 6 | ❌ No |

**Cleaned model has:** 1,601 issues (Task + Story + Epic)

### Status Distribution (Top 10)

| Status | Count |
|--------|-------|
| Done | 1,532 |
| To Do | 407 |
| Won't do | 147 |
| DEPLOYED | 43 |
| Ready for Dev | 39 |
| In Product Review | 30 |
| Pending Dev | 22 |
| In Progress | 19 |
| In Design | 17 |
| BLOCKED | 14 |

---

## Table: changelogs (Source)

### Schema

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | text | NO | Primary key |
| `issueId` | text | YES | FK to issues.id |
| `created` | timestamp | YES | When change occurred |
| `author__displayName` | text | YES | Who made the change |
| `author__emailAddress` | text | YES | Author email |
| `_sdc_*` | various | YES | Stitch metadata columns |

### Statistics

- **Distinct changelog IDs:** 18,620
- **Distinct issues with changelogs:** 2,142
- **Changes per issue:** min=1, avg=9, max=43

### Data Quality

- **Join to issues:** 18,601/18,620 matched (99%)
- **19 orphaned changelogs** (issues may have been deleted)

---

## Table: changelogs__items (Source)

### Schema

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `_sdc_source_key_id` | text | NO | FK to changelogs.id |
| `_sdc_level_0_id` | bigint | NO | Array index |
| `field` | text | YES | Field that changed |
| `fieldId` | text | YES | Field ID |
| `fieldtype` | text | YES | Field type |
| `from` | text | YES | Previous value (ID) |
| `fromString` | text | YES | Previous value (display) |
| `to` | text | YES | New value (ID) |
| `toString` | text | YES | New value (display) |

### Field Change Distribution (Top 15)

| Field | Count | Relevant? |
|-------|-------|-----------|
| status | 8,109 | ✅ **Primary focus** |
| Rank | 3,162 | ❌ |
| IssueParentAssociation | 1,768 | ❌ |
| resolution | 1,734 | ❌ |
| description | 1,124 | ❌ |
| assignee | 1,067 | ❌ |
| Sprint | 999 | ❌ |
| priority | 525 | ❌ |
| Link | 403 | ❌ |
| Client | 352 | ❌ |
| summary | 298 | ❌ |
| duedate | 177 | ❌ |
| labels | 168 | ❌ |
| Account Status | 159 | ❌ |
| issuetype | 116 | ❌ |

### Status Transition Targets (Top 10)

| New Status (toString) | Count |
|-----------------------|-------|
| Done | 1,576 |
| In Progress | 1,443 |
| DEPLOYED | 1,128 |
| IN REVIEW | 1,123 |
| Ready for Dev | 1,050 |
| In Product Review | 663 |
| READY TO DEPLOY | 558 |
| Won't do | 155 |
| To Do | 134 |
| BLOCKED | 58 |

### Data Quality

- **Join to changelogs:** 20,547/20,547 matched (100%)
- **NULL fromString:** 0 (all status changes have from_status)

---

## Relationships

```
issues (id)
    │
    └──< changelogs (issueId)
              │
              └──< changelogs__items (_sdc_source_key_id)
```

**Join keys:**
- `issues.id` = `changelogs.issueId`
- `changelogs.id` = `changelogs__items._sdc_source_key_id`

---

## Model Validation Results

### stg_issues ✅

| Metric | Value |
|--------|-------|
| Total rows | 1,601 |
| Distinct IDs | 1,601 |
| Distinct keys | 1,601 |
| NULL IDs | 0 |
| NULL keys | 0 |
| NULL status | 0 |

**Issue Type Distribution:**
- Task: 1,371
- Story: 136
- Epic: 94

### stg_changelogs ✅

| Metric | Value |
|--------|-------|
| Total rows | 12,811 |
| Distinct changelog IDs | 12,811 |
| Distinct issue IDs | 1,452 |
| NULL changelog IDs | 0 |
| NULL issue IDs | 0 |
| NULL created | 0 |

### stg_changelog_items ✅

| Metric | Value |
|--------|-------|
| Total rows | 8,109 |
| Distinct changelog IDs | 8,109 |
| NULL changelog IDs | 0 |
| NULL to_status | 0 |
| NULL from_status | 0 |

### int_issue_status_history ✅ (ephemeral)

| Metric | Value |
|--------|-------|
| Total rows | 5,444 |
| Distinct issue IDs | 1,285 |
| Issues with history | 1,285 (80.3%) |
| Issues without history | 316 (19.7%) |
| Status changes per issue | min=1, max=17, avg=4.2, median=4.0 |
| Date range | 2024-09-01 to 2026-01-26 |

### issue_status_as_of (Mart) ✅

| Metric | Value |
|--------|-------|
| Total rows | 1,601 |
| Distinct keys | 1,601 |
| NULL status_as_of | 0 |
| Coverage | 100% |
| Matches current status | 1,601/1,601 (100%) |

**Status Distribution:**
- Done: 1,002
- To Do: 358
- Won't do: 98
- Ready for Dev: 34
- DEPLOYED: 32
- Pending Dev: 18
- In Design: 17
- In Progress: 14
- BLOCKED: 8
- Others: 20

---

## Edge Case Validation

### 1. Issues Without Status History ✅

316 issues (19.7%) have no recorded status changes. The model correctly falls back to `current_status` from `stg_issues`:

| Issue Key | Current Status | status_as_of | Result |
|-----------|---------------|--------------|--------|
| TB-567 | To Do | To Do | ✅ Correct |
| CS-122 | To Do | To Do | ✅ Correct |
| CS-123 | To Do | To Do | ✅ Correct |

### 2. As-Of Date Logic ✅

Tested with TB-240 (8 status changes from 2024-11-28 to 2025-06-26):

| As-Of Date | Expected Status | Result |
|------------|-----------------|--------|
| 2024-11-01 | To Do (initial) | ✅ |
| 2024-11-28 | Ready for Dev | ✅ |
| 2024-12-15 | To Do | ✅ |
| 2025-05-17 | In Progress | ✅ |
| 2025-06-26 | Done | ✅ |
| 2026-02-02 | Done | ✅ |

### 3. Initial Status Fallback ✅

All 1,285 issues with history have `To Do` as their initial from_status. The fallback logic correctly uses `initial_status.from_status` when querying dates before any changes.

---

## Conclusions

### What's Working Well

1. **Accurate Status Tracking**: The `get_status_as_of` macro correctly determines status at any historical date
2. **Complete Coverage**: 100% of filtered issues have a `status_as_of` value
3. **Proper Filtering**: Issue type filtering via `var('issue_types')` works correctly
4. **DAG Compliance**: Models follow the staging → intermediate → mart pattern
5. **Defensive SQL**: NULL handling, coalesce fallbacks, and type casting are implemented

### Potential Improvements

1. **stg_changelog_items optimization**: Currently includes all 8,109 status changes, but only 5,444 are used. Could add an inner join to `stg_changelogs` to reduce unused rows (trade-off: would reference another staging model)

2. **Add dbt tests**: Consider adding tests for:
   - `unique` + `not_null` on primary keys
   - `relationships` between staging models
   - `accepted_values` for status columns

3. **Documentation**: Add column-level descriptions in YAML files for all models

---

## Appendix: Original Analysis Notes

### Implications for dbt Models

#### stg_issues
- Filter: `fields__issuetype__name IN ('Task', 'Epic', 'Story')`
- Transform: Title Case on `fields__summary`
- Select: `id`, `key`, `summary`, `issue_type`, `status`, `created`

#### stg_changelogs
- Select: `id`, `issue_id`, `created`
- Join will filter to only issues in stg_issues

#### stg_changelog_items
- Filter: `field = 'status'`
- Select: `changelog_id`, `from_status`, `to_status`

#### Status "As Of" Function Logic
1. Given `issue_key` and `date`:
2. Find the issue by key
3. Get all status changes from changelog where `created <= date`
4. Return the `toString` of the most recent change
5. If no changes before date, return the `fromString` of the earliest change (initial status)
6. If no changes at all, return the current status from stg_issues
