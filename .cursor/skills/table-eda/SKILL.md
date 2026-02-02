---
name: table-eda
description: Perform exploratory data analysis on PostgreSQL tables. Analyze schema, statistics, distributions, data quality, and relationships. Use when the user asks to explore a table, understand data, profile columns, or perform EDA.
---

# Table EDA (Exploratory Data Analysis)

Perform comprehensive EDA on PostgreSQL tables. Output results as a markdown summary.

## Workflow

1. **Get table info** from the user (schema.table or just table name)
2. **Run analyses** in order: Schema → Stats → Distribution → Quality → Relationships
3. **Output markdown summary** with findings

## Analysis Steps

### 1. Schema Analysis

```sql
-- Column info
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = '{schema}' AND table_name = '{table}'
ORDER BY ordinal_position;
```

### 2. Basic Statistics

```sql
-- Row count
SELECT count(*) as total_rows FROM {schema}.{table};

-- Per-column stats (run for each column)
SELECT
    count(*) as total,
    count({col}) as non_null,
    count(*) - count({col}) as nulls,
    count(distinct {col}) as distinct_values
FROM {schema}.{table};

-- For numeric columns, add:
SELECT
    min({col}),
    max({col}),
    avg({col}),
    percentile_cont(0.5) WITHIN GROUP (ORDER BY {col}) as median
FROM {schema}.{table};

-- For timestamp columns, add:
SELECT
    min({col}) as earliest,
    max({col}) as latest
FROM {schema}.{table};
```

### 3. Value Distribution

```sql
-- Top values (for categorical/text columns)
SELECT {col}, count(*) as cnt
FROM {schema}.{table}
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;

-- For columns with few distinct values, show all
SELECT {col}, count(*) as cnt
FROM {schema}.{table}
GROUP BY 1
ORDER BY 1;
```

### 4. Data Quality

```sql
-- Null percentage per column
SELECT
    '{col}' as column_name,
    round(100.0 * count(*) FILTER (WHERE {col} IS NULL) / count(*), 2) as null_pct
FROM {schema}.{table};

-- Duplicate check (on potential key columns)
SELECT {col}, count(*) as cnt
FROM {schema}.{table}
GROUP BY 1
HAVING count(*) > 1
LIMIT 10;

-- Empty strings (for text columns)
SELECT count(*) as empty_strings
FROM {schema}.{table}
WHERE {col} = '';
```

### 5. Relationships

```sql
-- Check for foreign key patterns (columns ending in _id or Id)
-- Try to identify related tables

-- Sample join validation
SELECT count(*) as matched
FROM {schema}.{table} t
JOIN {schema}.{related_table} r ON t.{fk_col} = r.id;
```

## Output Template

Format results as:

```markdown
# EDA: {schema}.{table}

## Overview
- **Total rows**: X
- **Columns**: Y
- **Date range**: (if applicable)

## Schema

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| col1   | text | YES      |       |

## Column Statistics

### {column_name}
- **Type**: text
- **Non-null**: X (Y%)
- **Distinct**: Z
- **Top values**: val1 (N), val2 (M), ...

## Data Quality Issues
- Column X has Y% nulls
- Found N duplicate values in column Z

## Relationships
- `{col}` appears to reference `{other_table}`
```

## Tips

- For wide tables (>20 columns), focus on key columns first
- Skip distribution analysis for high-cardinality columns (>1000 distinct)
- For large tables, use `TABLESAMPLE` or `LIMIT` in subqueries
- Note any columns with suspicious patterns (all nulls, single value, etc.)
