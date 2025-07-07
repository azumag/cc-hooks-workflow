#!/bin/bash
# CI Monitor Hook - Monitors CI status after review and push completion
# This is a simplified version of the original ci-monitor-hook.sh

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

# Check if we're in a git repository
if ! git rev-parse --git-dir &>/dev/null; then
    safe_exit "Not in a git repository, CI monitoring skipped" "approve"
fi

# Check if gh CLI is available
if ! command -v gh &>/dev/null; then
    safe_exit "GitHub CLI (gh) not found, CI monitoring skipped" "approve"
fi

# Check if authenticated with gh
if ! gh auth status &>/dev/null; then
    safe_exit "Not authenticated with GitHub CLI, CI monitoring skipped" "approve"
fi

echo "CI monitor hook executed for session: $SESSION_ID" >&2
echo "This is a simplified version - full CI monitoring logic would go here" >&2

# For now, just approve
safe_exit "CI monitoring completed (simplified implementation)" "approve"