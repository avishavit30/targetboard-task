{{
    config(
        materialized='view'
    )
}}

-- stg_changelogs: Staging model for Jira changelog entries
-- Filters to only include changelogs for Task, Epic, and Story issues
-- by joining to the source issues table directly (DAG: staging uses source() only)
-- Note: Multi-tenant source switching happens at the source YAML level

with source as (
    select
        id,
        "issueId",
        created
    from {{ source('jira', 'changelogs') }}
    where
        true
        and created is not null  -- Filter out invalid changelogs with NULL timestamps
),

-- Get valid issue IDs directly from source issues table (filtered to configured issue types)
-- This avoids using ref('stg_issues') which would violate DAG rules for staging models
valid_issues as (
    select id
    from {{ source('jira', 'issues') }}
    where
        true
        and "fields__issuetype__name" in (
            {%- for issue_type in var('issue_types', ['Task', 'Epic', 'Story']) -%}
                '{{ issue_type }}'{% if not loop.last %}, {% endif %}
            {%- endfor -%}
        )
),

-- Filter to only changelogs for valid issues using inner join
filtered as (
    select
        source.id,
        source."issueId",
        source.created
    from source
    inner join valid_issues
        on source."issueId" = valid_issues.id
),

renamed as (
    select
        id as changelog_id,
        "issueId" as issue_id,
        created
    from filtered
)

select
    changelog_id,
    issue_id,
    created
from renamed
