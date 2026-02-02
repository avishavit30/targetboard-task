#!/bin/bash
# RALPH Post-Hook: Review And Loop to Perfection
# Triggers work-reviewer after dbt-developer completes
# Continues looping until 100/100 score or max iterations

# Read JSON input from stdin
input=$(cat)

# Parse status and result
status=$(echo "$input" | jq -r '.status // "unknown"')
result=$(echo "$input" | jq -r '.result // ""')

# Log for debugging
echo "[RALPH] subagentStop triggered, status: $status" >> /tmp/ralph-hook.log
echo "[RALPH] result preview: ${result:0:200}..." >> /tmp/ralph-hook.log

# Only proceed if completed successfully
if [[ "$status" != "completed" ]]; then
    echo '{}' 
    exit 0
fi

# Check if result mentions a score of 100/100 (already reviewed and perfect)
if echo "$result" | grep -q "100/100"; then
    echo "[RALPH] Score 100/100 detected, no follow-up needed" >> /tmp/ralph-hook.log
    echo '{}'
    exit 0
fi

# Check if this looks like dbt model output (has .sql file mentions)
if echo "$result" | grep -qE "\.sql|dbt run|model.*created"; then
    echo "[RALPH] dbt work detected, triggering work-reviewer" >> /tmp/ralph-hook.log
    
    # Return follow-up message to trigger review
    cat << 'EOF'
{
  "followup_message": "Now use the work-reviewer subagent to review the code that was just created. Grade it strictly. If the score is less than 100/100, fix ALL issues and re-submit for review. Repeat until 100/100 is achieved."
}
EOF
else
    echo "[RALPH] No dbt work detected, skipping" >> /tmp/ralph-hook.log
    echo '{}'
fi

exit 0
