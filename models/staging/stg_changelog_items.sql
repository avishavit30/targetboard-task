{{
    config(
        materialized='view'
    )
}}

-- stg_changelog_items: Staging model for Jira changelog items
-- Filters to status changes only (field = 'status')
-- Used to track issue status transitions over time
-- Note: Multi-tenant source switching happens at the source YAML level
-- Note: NULL values in from_status are expected for initial status transitions

with source as (
    select
        "_sdc_source_key_id",
        field,
        "fromString",
        "toString"
    from {{ source('jira', 'changelogs__items') }}
),

-- Filter to status field changes only
-- _sdc_source_key_id is a Stitch-specific column linking to changelogs.id
filtered as (
    select
        "_sdc_source_key_id" as changelog_id,
        -- NULL from_status is expected when an issue is first created/transitioned
        "fromString" as from_status,
        coalesce("toString", 'Unknown') as to_status
    from source
    where
        true
        and field = 'status'
)

select
    changelog_id,
    from_status,
    to_status
from filtered
