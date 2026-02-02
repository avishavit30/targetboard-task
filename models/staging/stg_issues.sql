{{
    config(
        materialized='view'
    )
}}

-- stg_issues: Staging model for Jira issues
-- Filters to Task, Epic, and Story issue types only (configurable via var)
-- Applies title case to summary field
-- Note: Multi-tenant source switching happens at the source YAML level

with source as (
    select
        id,
        key,
        "fields__summary",
        "fields__issuetype__name",
        "fields__status__name",
        "fields__created"
    from {{ source('jira', 'issues') }}
    where
        true
        -- Filter to work items only (excludes Bug, Sub-task, etc.)
        -- Issue types are configurable via var('issue_types')
        and "fields__issuetype__name" in (
            {%- for issue_type in var('issue_types', ['Task', 'Epic', 'Story']) -%}
                '{{ issue_type }}'{% if not loop.last %},{% endif %}
            {%- endfor -%}
        )
),

renamed as (
    select
        id,
        key,
        coalesce(initcap("fields__summary"), '') as issue_summary,
        "fields__issuetype__name" as issue_type,
        coalesce("fields__status__name", 'Unknown') as status,
        "fields__created" as created
    from source
)

select
    id,
    key,
    issue_summary,
    issue_type,
    status,
    created
from renamed
