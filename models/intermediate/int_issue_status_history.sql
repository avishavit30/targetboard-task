{{
    config(
        materialized='ephemeral'
    )
}}

-- int_issue_status_history: Intermediate model for tracking issue status transitions
-- Grain: one row per status change event per issue
-- Combines stg_issues, stg_changelogs, and stg_changelog_items to create
-- a complete status history for each issue. Used by the get_status_as_of macro to
-- determine issue status "as of" a specific date.

-- Import issue data (already filtered to Task/Epic/Story in stg_issues)
with issues as (
    select
        id,
        key
    from {{ ref('stg_issues') }}
    where key is not null  -- Defensive filter for issue key
),

-- Import changelog entries (filtered to valid issues)
changelogs as (
    select
        changelog_id,
        issue_id,
        created
    from {{ ref('stg_changelogs') }}
    -- Defense-in-depth: stg_changelogs already filters created is not null,
    -- but we keep this check here for robustness against upstream changes
    where created is not null
),

-- Import status changes only
-- Note: from_status may be NULL for initial status transitions
changelog_items as (
    select
        changelog_id,
        from_status,
        to_status
    from {{ ref('stg_changelog_items') }}
)

select
    issues.id as issue_id,
    issues.key as issue_key,
    changelogs.created as status_changed_at,
    changelog_items.from_status,
    changelog_items.to_status
from issues
inner join changelogs
    on issues.id = changelogs.issue_id
inner join changelog_items
    on changelogs.changelog_id = changelog_items.changelog_id
