{% macro get_status_as_of(
    items_relation,
    status_history_relation,
    item_key_column='item_key',
    item_summary_column='item_summary',
    current_status_column='status',
    history_key_column='item_key',
    history_changed_at_column='status_changed_at',
    history_from_status_column='from_status',
    history_to_status_column='to_status',
    filter_key=none,
    filter_date=none,
    output_cte_name='status_as_of_result'
) %}
{#
    Generic macro to determine the status of an item as of a specific date.
    
    This macro can be used with any source system (Jira, ServiceNow, Salesforce, etc.)
    as long as you have:
    1. An items table with current status
    2. A status history table with timestamps and from/to values
    
    Parameters:
    - items_relation: The relation containing items (e.g., ref('stg_issues'))
    - status_history_relation: The relation containing status history (e.g., ref('int_issue_status_history'))
    - item_key_column: Column name for the item identifier (default: 'item_key')
    - item_summary_column: Column name for the item summary/title (default: 'item_summary')
    - current_status_column: Column name for current status in items (default: 'status')
    - history_key_column: Column name for item key in history (default: 'item_key')
    - history_changed_at_column: Column name for change timestamp (default: 'status_changed_at')
    - history_from_status_column: Column name for previous status (default: 'from_status')
    - history_to_status_column: Column name for new status (default: 'to_status')
    - filter_key: Optional - filter to a specific item key
    - filter_date: Optional - the "as of" date to query. If not provided, returns
      the latest status change overall. To get current status, pass 'current_date'.
    - output_cte_name: Name of the final CTE (default: 'status_as_of_result')
    
    Returns CTE SQL that produces columns:
    - item_key
    - summary  
    - status_as_of (may be NULL if all status values are NULL)
    
    IMPORTANT: Caller must provide the 'with' keyword before calling this macro.
    The macro outputs a series of CTEs that should follow the 'with' keyword.
    
    Usage Examples:
    
    -- Jira
    {{ get_status_as_of(
        items_relation=ref('stg_issues'),
        status_history_relation=ref('int_issue_status_history'),
        item_key_column='key',
        item_summary_column='issue_summary',
        current_status_column='status',
        history_key_column='issue_key',
        filter_key="'TB-123'",
        filter_date="'2024-03-01'::date"
    ) }}
    
    -- ServiceNow
    {{ get_status_as_of(
        items_relation=ref('stg_incidents'),
        status_history_relation=ref('int_incident_history'),
        item_key_column='incident_id',
        item_summary_column='short_description',
        current_status_column='state',
        history_key_column='incident_id'
    ) }}
    
    -- Salesforce
    {{ get_status_as_of(
        items_relation=ref('stg_cases'),
        status_history_relation=ref('int_case_history'),
        item_key_column='case_number',
        item_summary_column='subject',
        current_status_column='status',
        history_key_column='case_number'
    ) }}
    
    select * from status_as_of_result
#}

items_base as (
    select
        {{ item_key_column }} as item_key,
        {{ item_summary_column }} as summary,
        {{ current_status_column }} as current_status
    from {{ items_relation }}
    where true
        {% if filter_key is not none %}
        and {{ item_key_column }} = {{ filter_key }}
        {% endif %}
),

status_history_base as (
    select
        {{ history_key_column }} as item_key,
        {{ history_changed_at_column }} as changed_at,
        {{ history_from_status_column }} as from_status,
        {{ history_to_status_column }} as to_status,
        row_number() over (
            partition by {{ history_key_column }}
            order by {{ history_changed_at_column }} asc nulls first
        ) as change_order
    from {{ status_history_relation }}
    where true
        {% if filter_key is not none %}
        and {{ history_key_column }} = {{ filter_key }}
        {% endif %}
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
        {% if filter_date is not none %}
        and changed_at::date <= {{ filter_date }}
        {% endif %}
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
{{ output_cte_name }} as (
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

{% endmacro %}
