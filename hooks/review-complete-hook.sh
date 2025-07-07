#!/bin/bash
# Sample Review Complete Hook
# This hook is triggered when REVIEW_COMPLETED state is detected

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/shared-utils.sh"

# Read input JSON
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
WORK_SUMMARY_FILE=$(echo "$INPUT" | jq -r '.work_summary_file_path // ""')

# Basic validation
if [ -z "$SESSION_ID" ]; then
    safe_exit "No session ID provided" "approve"
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    safe_exit "Transcript file not found or not provided" "approve"
fi

# Read work summary if available
WORK_SUMMARY=""
if [ -n "$WORK_SUMMARY_FILE" ] && [ -f "$WORK_SUMMARY_FILE" ]; then
    WORK_SUMMARY=$(cat "$WORK_SUMMARY_FILE")
fi

# Sample review logic - just approve for now
# In a real implementation, this could:
# - Check if all tests pass
# - Validate code quality
# - Check for security issues
# - Integrate with external review systems

echo "[review-complete-hook] Review complete hook executed for session: $SESSION_ID" >&2

# Return approval
safe_exit "Review completed successfully" "approve"