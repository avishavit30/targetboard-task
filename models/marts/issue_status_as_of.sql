{#
    issue_status_as_of: Mart model for querying Jira issue status at a specific date
    Uses the generic get_status_as_of macro (which supports multiple source systems)

    Configure the target date using dbt vars:
      dbt run --select issue_status_as_of --vars '{"as_of_date": "2024-03-01"}'

    If no date is provided, defaults to current_date.
    Each unique as_of_date creates a separate table (e.g., issue_status_as_of_2024_03_01).
#}

{% set target_date = var('as_of_date', none) %}

{# Generate table alias based on date: issue_status_as_of_YYYY_MM_DD or issue_status_as_of_current #}
{% if target_date is none %}
    {% set table_alias = 'issue_status_as_of_current' %}
    {% set date_expr = 'current_date' %}
{% else %}
    {# Convert date string to underscore format for table name #}
    {% set table_alias = 'issue_status_as_of_' ~ target_date | replace('-', '_') %}
    {% set date_expr = "'" ~ target_date ~ "'::date" %}
{% endif %}

{{
    config(
        materialized='table',
        alias=table_alias,
        indexes=[
            {'columns': ['issue_key'], 'unique': true},
            {'columns': ['status_as_of']}
        ]
    )
}}

with

{{ get_status_as_of(
    items_relation=ref('stg_issues'),
    status_history_relation=ref('int_issue_status_history'),
    item_key_column='key',
    item_summary_column='issue_summary',
    current_status_column='status',
    history_key_column='issue_key',
    history_changed_at_column='status_changed_at',
    history_from_status_column='from_status',
    history_to_status_column='to_status',
    filter_date=date_expr
) }}

select
    item_key as issue_key,
    summary,
    status_as_of,
    {{ date_expr }} as as_of_date
from status_as_of_result
