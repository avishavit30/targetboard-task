# TargetBoard dbt Project

A dbt project for tracking Jira issue status history with point-in-time querying capabilities.

## Overview

This project implements a "status as of" function that determines what status a Jira issue had on any given historical date. It's built with a multi-tenant architecture supporting different source systems.

## Key Features

- **Point-in-time status queries**: Query what status any issue had on a specific date
- **Multi-tenant ready**: Configurable via `vars` for different clients/source systems
- **PostgreSQL optimized**: Native PostgreSQL syntax with proper indexing
- **Defensive SQL**: Handles NULLs, edge cases, and missing history gracefully

## Project Structure

```
models/
├── staging/           # Cleaned source data
│   ├── stg_issues.sql
│   ├── stg_changelogs.sql
│   └── stg_changelog_items.sql
├── intermediate/      # Business logic
│   └── int_issue_status_history.sql
└── marts/             # Consumer-ready outputs
    └── issue_status_as_of.sql

macros/
└── get_status_as_of.sql   # Generic, reusable macro
```

## Data Flow

```
SOURCE: issues → changelogs → changelogs__items
           ↓           ↓              ↓
STAGING: stg_issues  stg_changelogs  stg_changelog_items
                  ↘      ↓      ↙
INTERMEDIATE:    int_issue_status_history
                         ↓
MART:           issue_status_as_of
```

## Usage

### Run all models (current date)

```bash
dbt run
```

### Query status as of a specific date

```bash
dbt run --select issue_status_as_of --vars '{"as_of_date": "2024-03-01"}'
```

This creates a table named `issue_status_as_of_2024_03_01` with the status each issue had on March 1, 2024.

### Configuration

Edit `dbt_project.yml` to configure:

```yaml
vars:
  source_system: 'jira'
  source_schema: 'targetboard_source_jira'
  issue_types: ['Task', 'Epic', 'Story']
```

## Requirements

- PostgreSQL database
- dbt Core 1.11+
- Python 3.10+

## Setup

1. Clone the repository
2. Create a virtual environment: `python -m venv venv`
3. Activate: `source venv/bin/activate`
4. Install dependencies: `pip install dbt-postgres`
5. Configure `~/.dbt/profiles.yml` with your database connection
6. Run: `dbt run`

## Status Logic

The `get_status_as_of` macro determines status using this priority:

1. **Latest change before date**: The `to_status` of the most recent status change on or before the target date
2. **Initial status**: If no changes before the date, use the `from_status` of the first-ever change
3. **Current status**: If no change history exists, fall back to the current status from the source

## Documentation

- `docs/eda_findings.md` - Detailed EDA and validation results
- Model YAML files contain column descriptions and tests
