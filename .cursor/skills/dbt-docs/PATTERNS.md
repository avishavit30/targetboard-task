# dbt Documentation Patterns Reference

This file contains detailed patterns and examples for dbt model documentation.

## Table of Contents

1. [YAML Structure](#yaml-structure)
2. [Description Writing](#description-writing)
3. [Column Categories](#column-categories)
4. [Test Configuration](#test-configuration)
5. [Common Anti-Patterns](#common-anti-patterns)

---

## YAML Structure

### Basic Model Documentation

```yaml
version: 2

models:
  - name: model_name
    description: "Brief description of the model's purpose."
    columns:
      - name: column_name
        description: "What this column represents."
```

### With Owner Metadata

```yaml
version: 2

models:
  - name: stg_issues
    description: "Staged Jira issues with cleaned column names."
    meta:
      owner: analytics@example.com
    columns:
      - name: issue_id
        description: "Unique identifier for the issue."
```

### With Tests

```yaml
version: 2

models:
  - name: int_issue_status_history
    description: "Issue status transitions over time."
    columns:
      - name: issue_id
        description: "Reference to the parent issue."
        data_tests:
          - not_null
      - name: status_key
        description: "Unique key for this status record."
        data_tests:
          - unique
          - not_null
```

---

## Description Writing

### General Guidelines

1. **Be specific**: Describe what the column contains, not just its name
2. **Note transformations**: If data is cleaned or derived, say how
3. **Include business context**: What does this mean to users?
4. **Keep it concise**: 1-2 sentences is usually enough

### Good vs Bad Examples

| Bad | Good |
|-----|------|
| "The ID" | "Unique identifier for the issue (internal database key)." |
| "Status field" | "Current workflow status of the issue (e.g., Open, In Progress, Done)." |
| "Date" | "Timestamp when the issue was created, in UTC." |
| "Name" | "Human-readable issue key (e.g., PROJ-123)." |

### The "In this table:" Pattern

For derived or calculated columns, add context about how the value is computed in this specific model:

```yaml
- name: days_in_status
  description: "Number of days spent in this status. In this table: calculated as the difference between consecutive status transition timestamps."

- name: is_active
  description: "Boolean flag indicating active status. In this table: true when status is not 'Closed' or 'Done'."
```

Use this pattern when:
- The column is calculated from other columns
- The column has model-specific filtering or business logic
- The same column name means something different in this context

---

## Column Categories

### Identifier Columns

```yaml
- name: issue_id
  description: "Unique identifier for the issue (internal database primary key)."
  data_tests:
    - unique
    - not_null

- name: issue_key
  description: "Human-readable issue identifier (e.g., PROJ-123)."
```

### Timestamp Columns

```yaml
- name: created_at
  description: "Timestamp when the record was created, in UTC."

- name: updated_at
  description: "Timestamp when the record was last modified, in UTC."

- name: transition_at
  description: "Timestamp when the status transition occurred."
```

### Status/Enum Columns

```yaml
- name: status
  description: "Current workflow status. Possible values: Open, In Progress, Review, Done, Closed."

- name: priority
  description: "Issue priority level. Values: Critical, High, Medium, Low."
```

### Foreign Key Columns

```yaml
- name: project_id
  description: "Reference to the parent project. Foreign key to stg_projects.project_id."

- name: assignee_id
  description: "User ID of the current assignee. May be null if unassigned."
```

### Calculated Columns

```yaml
- name: duration_days
  description: "Number of days between start and end dates. In this table: calculated as end_date - start_date."

- name: total_story_points
  description: "Sum of story points for all issues. In this table: aggregated by sprint."
```

---

## Test Configuration

See also: `.cursor/rules/dbt-testing-requirements.mdc` for mandatory test requirements.

### Primary Key Test (REQUIRED)

Every model must have `unique` + `not_null` on its primary key:

```yaml
- name: issue_id
  description: "Primary key for this table."
  data_tests:
    - unique
    - not_null
```

### Foreign Key Test (REQUIRED for join columns)

```yaml
- name: project_id
  description: "Reference to parent project."
  data_tests:
    - not_null
    - relationships:
        to: ref('stg_projects')
        field: project_id
```

### Accepted Values Test (REQUIRED for status/enum columns)

```yaml
- name: status
  description: "Issue status."
  data_tests:
    - accepted_values:
        values: ['Open', 'In Progress', 'Done', 'Closed']

- name: priority
  description: "Issue priority level."
  data_tests:
    - accepted_values:
        values: ['Critical', 'High', 'Medium', 'Low']
```

### Minimum Tests by Layer

| Layer | Required Tests |
|-------|----------------|
| Staging | `unique` + `not_null` on primary key |
| Intermediate | Primary key tests + `not_null` on join keys |
| Marts | All above + `accepted_values` for enums |

---

## Common Anti-Patterns

### ❌ Column Mismatch

YAML columns must match SQL output exactly.

```sql
-- SQL has these columns
select issue_id, issue_key, status from issues
```

```yaml
# ❌ Wrong: different columns
columns:
  - name: id           # Should be issue_id
  - name: key          # Should be issue_key
  - name: issue_status # Should be status
```

### ❌ Stale Columns

Remove columns from YAML when removed from SQL.

```yaml
# ❌ Wrong: old_column no longer exists in SQL
columns:
  - name: issue_id
  - name: old_column    # DELETE THIS
  - name: status
```

### ❌ Unquoted Colons

Descriptions with colons must be quoted.

```yaml
# ❌ Wrong: will break YAML parsing
- name: status
  description: Status values: Open, Closed

# ✅ Correct: properly quoted
- name: status
  description: "Status values: Open, Closed"
```

### ❌ Empty or Generic Descriptions

```yaml
# ❌ Wrong: not helpful
- name: created_at
  description: "A timestamp"

# ✅ Correct: specific and useful
- name: created_at
  description: "Timestamp when the issue was created in Jira, stored in UTC."
```

### ❌ Missing Tests on Keys

```yaml
# ❌ Wrong: primary key without tests
- name: issue_id
  description: "Primary key"

# ✅ Correct: has uniqueness and not-null tests
- name: issue_id
  description: "Primary key for this table."
  data_tests:
    - unique
    - not_null
```

---

## Model Type Templates

### Staging Model Template

```yaml
version: 2

models:
  - name: stg_table_name
    description: >
      Staged data from source.schema.table_name with cleaned column names
      and basic type casting. One row per original source record.
    columns:
      - name: primary_key_id
        description: "Primary key from source table."
        data_tests:
          - unique
          - not_null
      # ... other columns matching source
```

### Intermediate Model Template

```yaml
version: 2

models:
  - name: int_model_name
    description: >
      Intermediate transformation that [describe what this does].
      Combines data from [list sources] to produce [output description].
    columns:
      - name: unique_key
        description: "Composite key for this intermediate result."
        data_tests:
          - unique
          - not_null
      # ... other columns
```

### Mart Model Template

```yaml
version: 2

models:
  - name: model_name
    description: >
      Final analytical model for [business purpose].
      Used by [who uses it] for [what purpose].
      Grain: one row per [entity].
    columns:
      - name: primary_key
        description: "Primary key representing [what]."
        data_tests:
          - unique
          - not_null
      # ... other columns with business context
```
