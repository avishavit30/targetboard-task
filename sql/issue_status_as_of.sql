-- issue_status_as_of: Example query for determining issue status at a specific date
--
-- IMPORTANT: This file is for REFERENCE ONLY.
-- Use the dbt model `issue_status_as_of` in models/marts/ for actual queries.
-- The model uses the generic `get_status_as_of` macro which works with any source system.
--
-- Usage:
--   dbt run --select issue_status_as_of --vars '{"as_of_date": "''2024-03-01''::date"}'
--
-- For a specific issue, you can query the result:
--   SELECT * FROM your_schema.issue_status_as_of WHERE issue_key = 'TB-123';
--   -- Replace 'your_schema' with {{ target.schema }} in actual dbt models
--
-- Logic:
--   1. If a status change exists on or before the date, return the to_status of
--      the most recent change
--   2. If no changes exist before the date but changes exist after, return the
--      from_status of the earliest change (the initial status)
--   3. If no changes exist at all, return the current status from stg_issues

-- Example direct SQL query (equivalent to what the macro generates):
-- Note: Replace 'your_schema' with {{ target.schema }} in actual dbt models
with items_base as (
    select
        key as item_key,
        issue_summary as summary,
        status as current_status
    from your_schema.stg_issues
    where true
),

status_history_base as (
    select
        issue_key as item_key,
        status_changed_at as changed_at,
        from_status,
        to_status,
        row_number() over (
            partition by issue_key
            order by status_changed_at asc nulls first
        ) as change_order
    from your_schema.int_issue_status_history
    where true
),

-- Get the most recent status change on or before the target date
latest_change_before_date as (
    select
        item_key,
        to_status as status_value,
        row_number() over (
            partition by item_key
            order by changed_at desc nulls last
        ) as rn
    from status_history_base
    where true
        and changed_at is not null  -- Always filter NULLs for latest determination
        and changed_at::date <= '2024-03-01'::date  -- Replace with your target date
),

latest_status as (
    select
        item_key,
        status_value
    from latest_change_before_date
    where true
        and rn = 1
),

-- Get the initial status (from_status of the first change ever)
initial_status as (
    select
        item_key,
        from_status as status_value
    from status_history_base
    where true
        and change_order = 1
),

-- Combine: use latest change before date, or initial status, or current status
status_as_of_result as (
    select
        items_base.item_key,
        items_base.summary,
        coalesce(
            latest_status.status_value,
            initial_status.status_value,
            items_base.current_status
        ) as status_as_of
    from items_base
    left join latest_status
        on items_base.item_key = latest_status.item_key
    left join initial_status
        on items_base.item_key = initial_status.item_key
)

select
    item_key as issue_key,
    summary,
    status_as_of
from status_as_of_result;
