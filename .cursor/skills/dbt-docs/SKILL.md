---
name: dbt-documentation
description: Generate and maintain YAML documentation for dbt models. Use when documenting models, creating YAML files, or updating column descriptions.
---

# dbt Model Documentation Skill

## Overview

This skill helps you create and maintain YAML documentation for dbt models. It focuses on:
- Creating new YAML files for undocumented models
- Keeping YAML columns in sync with SQL outputs
- Ensuring consistent, quality descriptions

## Quick Start

### Document a New Model

1. Read the model SQL file
2. Extract all output columns from final SELECT
3. Create YAML with matching columns
4. Add meaningful descriptions

### Update Existing Documentation

1. Compare YAML columns to current SQL output
2. Add new columns, remove stale ones
3. Preserve existing descriptions
4. Validate YAML structure

## Documentation Workflow

```
┌─────────────────┐
│ 1. Analyze SQL  │ ← Read model, extract columns, owner, config
└────────┬────────┘
         │
┌────────▼────────┐
│ 2. Check YAML   │ ← Does YAML exist? Is it current?
└────────┬────────┘
         │
┌────────▼────────┐
│ 3. Create/Update│ ← Match columns 1:1 with SQL
└────────┬────────┘
         │
┌────────▼────────┐
│ 4. Validate     │ ← Check structure, quoting, completeness
└─────────────────┘
```

## Detailed Steps

### Step 1: Model Analysis

Read the SQL file and extract:

- **Output columns**: All columns in the final SELECT statement
- **Owner**: From `config(meta={ owner: ... })` if present
- **Materialization**: table, view, incremental
- **Transformations**: Which columns are calculated vs direct

Example analysis output:
```
Model: stg_issues
Columns: issue_id, issue_key, status, created_at, updated_at
Owner: analytics@example.com
Materialization: view
Calculated: (none - all direct from source)
```

### Step 2: YAML Creation/Update

Create or update the YAML file to match the SQL exactly.

**CRITICAL RULES:**
- YAML columns must match SQL output 1:1
- Delete columns from YAML that no longer exist in SQL
- Maintain column order from SQL
- Quote descriptions containing colons

**Template for new YAML:**

```yaml
version: 2

models:
  - name: model_name
    description: "Brief description of what this model does."
    columns:
      - name: column_name
        description: "What this column represents."
```

**Example:**

```yaml
version: 2

models:
  - name: stg_issues
    description: "Staged Jira issues with cleaned column names and basic type casting."
    columns:
      - name: issue_id
        description: "Unique identifier for the issue (internal database ID)."
      - name: issue_key
        description: "Human-readable issue key (e.g., PROJ-123)."
      - name: status
        description: "Current status of the issue (e.g., Open, In Progress, Done)."
      - name: created_at
        description: "Timestamp when the issue was created."
      - name: updated_at
        description: "Timestamp when the issue was last updated."
```

### Step 3: Writing Good Descriptions

**For columns propagated from sources:**
- Describe what the column represents
- Note any transformations applied

**For calculated/derived columns:**
- Explain the calculation
- Use the "In this table:" pattern for context

```yaml
- name: days_in_status
  description: "Number of days the issue spent in this status. In this table: calculated as the difference between transition timestamps."
```

### Step 4: Validation Checklist

Before completing documentation:

```
[ ] YAML syntax is valid (version: 2 format)
[ ] Model name matches SQL file name
[ ] All SQL columns are documented
[ ] No stale columns (removed from SQL but still in YAML)
[ ] Column order matches SQL SELECT
[ ] Every column has a non-empty description
[ ] Descriptions with colons are quoted
[ ] Primary key has unique + not_null tests (per dbt-testing-requirements.mdc)
[ ] Foreign keys have relationships tests
[ ] Status/enum columns have accepted_values tests
```

## YAML Formatting Rules

### Quoting Descriptions

Descriptions containing colons MUST be quoted:

```yaml
# ✅ Correct
- name: status
  description: "Status code: active, inactive, or pending"

# ❌ Wrong - will break YAML parsing
- name: status
  description: Status code: active, inactive, or pending
```

### Test Configuration

For unique key columns, add a uniqueness test:

```yaml
- name: issue_id
  description: "Unique identifier for the issue."
  data_tests:
    - unique
    - not_null
```

### Multi-line Descriptions

For longer descriptions, use proper YAML multi-line:

```yaml
- name: complex_field
  description: >
    This is a longer description that explains
    a complex field. It continues on multiple lines
    but renders as a single paragraph.
```

## Common Patterns

### Staging Models

Focus on:
- What the source table contains
- Any renaming/cleaning applied
- Type casting notes

### Intermediate Models

Focus on:
- Business logic being applied
- How data is being combined/transformed
- Grain of the table

### Mart Models

Focus on:
- Business purpose
- Who uses this data
- Key metrics calculated

## Anti-Patterns to Avoid

❌ **Column mismatch** - YAML columns don't match SQL output
❌ **Stale columns** - YAML has columns removed from SQL
❌ **Empty descriptions** - Missing or placeholder descriptions
❌ **Unquoted colons** - Will break YAML parsing
❌ **Generic descriptions** - "This is a column" (not helpful)
❌ **Wrong column order** - Should match SQL SELECT order

## Additional Resources

### Scripts

Optional helper scripts are available in `.cursor/skills/dbt-docs/scripts/`:

| Script | Purpose |
|--------|---------|
| `generate_columns_catalog.py` | Build catalog of all column descriptions across models |
| `validate_yaml.py` | Validate YAML structure and column matching |

**Usage examples:**

```bash
# Generate a catalog of all columns across models
python .cursor/skills/dbt-docs/scripts/generate_columns_catalog.py

# Validate a YAML file
python .cursor/skills/dbt-docs/scripts/validate_yaml.py models/staging/_staging.yml

# Validate with SQL column matching
python .cursor/skills/dbt-docs/scripts/validate_yaml.py models/staging/_staging.yml --sql models/staging/stg_issues.sql
```

### Patterns Reference

For detailed patterns, templates, and examples, see:
- [PATTERNS.md](.cursor/skills/dbt-docs/PATTERNS.md) - Comprehensive documentation patterns

## Related Rules

This skill aligns with the following Cursor rules in `.cursor/rules/quality/`:

| Rule | Alignment |
|------|-----------|
| `quality/dbt-documentation.mdc` | Documentation standards enforced by this skill |
| `quality/dbt-testing-requirements.mdc` | Required tests (this skill includes test patterns) |
| `quality/dbt-naming-contracts.mdc` | YAML file naming conventions |

When documenting models, ensure compliance with these rules.

---

## Integration with Existing Models

When documenting existing models in this project:

1. Check `models/*/_*.yml` files for existing patterns
2. Follow the same naming conventions
3. Reuse descriptions for common columns (e.g., `created_at`, `updated_at`)
4. Maintain consistency with existing documentation style

### Existing Documentation in This Project

```
models/
├── staging/
│   ├── __sources.yml    # Source definitions
│   └── _staging.yml     # Staging model docs
├── intermediate/
│   └── _intermediate.yml
└── marts/
    └── _marts.yml
```

Review these files before creating new documentation to maintain consistency.
