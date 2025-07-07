#!/bin/bash
# CI Monitor Hook - Monitors CI status after review and push completion
# Enhanced version with timeout handling and user feedback

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/shared-utils.sh"

# Configuration - can be overridden by environment variables
readonly MAX_WAIT_TIME="${CI_MONITOR_TIMEOUT:-600}"  # Default 10 minutes (increased from 300s)
readonly INITIAL_DELAY="${CI_MONITOR_INITIAL_DELAY:-10}"
readonly MAX_DELAY="${CI_MONITOR_MAX_DELAY:-30}"
readonly CHECK_INTERVAL="${CI_MONITOR_CHECK_INTERVAL:-15}"

# Version identification for debugging
readonly CI_HOOK_VERSION="2.0-enhanced-timeout"

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

echo "[ci-monitor-hook] Starting CI monitoring for session: $SESSION_ID (v$CI_HOOK_VERSION)" >&2
echo "[ci-monitor-hook] Configuration: timeout=${MAX_WAIT_TIME}s, check_interval=${CHECK_INTERVAL}s" >&2

# Check if we're in a git repository
if ! git rev-parse --git-dir &>/dev/null; then
    safe_exit "Not in a git repository, CI monitoring skipped" "approve"
fi

# Check if gh CLI is available
if ! command -v gh &>/dev/null; then
    safe_exit "GitHub CLI (gh) not found, CI monitoring skipped. Please install gh CLI for CI monitoring." "approve"
fi

# Check if authenticated with gh
if ! gh auth status &>/dev/null; then
    safe_exit "Not authenticated with GitHub CLI, CI monitoring skipped. Run 'gh auth login' to enable CI monitoring." "approve"
fi

# Function to get current branch
get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main"
}

# Function to get active workflow runs for current branch and commit
get_active_workflow_runs() {
    local branch="$1"
    local current_sha
    current_sha=$(git rev-parse HEAD)

    # Get all workflow runs for the current branch and filter by current commit
    if ! gh run list --branch "$branch" --limit 20 --json status,conclusion,databaseId,name,headSha,url 2>/dev/null |
        jq --arg sha "$current_sha" '[.[] | select(.headSha == $sha)]'; then
        return 1
    fi
}

# Function to format timeout message with helpful information
format_timeout_message() {
    local elapsed_time="$1"
    local branch="$2"
    
    cat <<EOF
## CI Monitoring Timeout

**Branch:** $branch
**Timeout Duration:** ${elapsed_time}s (max: ${MAX_WAIT_TIME}s)
**Status:** CI checks are still running

### Possible Actions:
1. **Continue waiting**: The CI may still complete successfully
2. **Check manually**: Visit GitHub Actions page to check CI status
3. **Increase timeout**: Set CI_MONITOR_TIMEOUT environment variable (e.g., export CI_MONITOR_TIMEOUT=900)
4. **Skip CI monitoring**: The code has been pushed successfully regardless of CI status

### Commands to check CI status manually:
\`\`\`bash
gh run list --branch $branch --limit 5
gh run watch  # Watch the latest run
\`\`\`

Would you like me to continue with the next steps while CI runs in the background?
EOF
}

# Main monitoring logic with enhanced timeout handling
monitor_ci() {
    local branch
    branch=$(get_current_branch)
    local start_time
    start_time=$(date +%s)
    local delay=$INITIAL_DELAY

    echo "[ci-monitor-hook] Monitoring CI status for branch: $branch (timeout: ${MAX_WAIT_TIME}s)" >&2

    # Initial delay to allow CI to start
    echo "[ci-monitor-hook] Waiting ${INITIAL_DELAY}s for CI to start..." >&2
    sleep $INITIAL_DELAY

    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Check if we've exceeded max wait time
        if [ $elapsed -ge $MAX_WAIT_TIME ]; then
            echo "[ci-monitor-hook] CI monitoring timeout reached after ${elapsed}s" >&2
            
            # Format helpful timeout message
            local timeout_message
            timeout_message=$(format_timeout_message "$elapsed" "$branch")
            local escaped_message
            escaped_message=$(echo "$timeout_message" | jq -Rs .)

            cat <<EOF
{
  "decision": "approve",
  "reason": $escaped_message
}
EOF
            return 0
        fi

        # Get workflow runs with error handling
        local run_data
        if ! run_data=$(get_active_workflow_runs "$branch" 2>/dev/null); then
            echo "[ci-monitor-hook] Warning: Failed to fetch workflow runs (network error), continuing..." >&2
            sleep $CHECK_INTERVAL
            continue
        fi

        # Check if there are any runs
        local run_count
        run_count=$(echo "$run_data" | jq '. | length')
        
        if [ "$run_count" -eq 0 ]; then
            echo "[ci-monitor-hook] No CI workflows found for branch $branch, assuming no CI required" >&2
            safe_exit "No CI workflows configured for this branch" "approve"
        fi

        # Check all workflow runs status
        local all_completed=true
        local any_failed=false
        local in_progress_count=0

        while IFS= read -r run; do
            local run_id status conclusion run_name
            run_id=$(echo "$run" | jq -r '.databaseId')
            status=$(echo "$run" | jq -r '.status')
            conclusion=$(echo "$run" | jq -r '.conclusion // "null"')
            run_name=$(echo "$run" | jq -r '.name')

            case "$status" in
            "completed")
                case "$conclusion" in
                "success")
                    echo "[ci-monitor-hook] ✓ $run_name completed successfully" >&2
                    ;;
                "failure" | "cancelled" | "timed_out")
                    echo "[ci-monitor-hook] ✗ $run_name failed ($conclusion)" >&2
                    any_failed=true
                    ;;
                *)
                    echo "[ci-monitor-hook] ? $run_name completed with status: $conclusion" >&2
                    all_completed=false
                    ;;
                esac
                ;;
            "in_progress" | "queued" | "requested" | "waiting" | "pending")
                echo "[ci-monitor-hook] ⏳ $run_name is $status" >&2
                all_completed=false
                ((in_progress_count++))
                ;;
            *)
                echo "[ci-monitor-hook] Unknown status '$status' for $run_name" >&2
                all_completed=false
                ;;
            esac
        done < <(echo "$run_data" | jq -c '.[]')

        # If any runs failed, report failure
        if [ "$any_failed" = true ]; then
            echo "[ci-monitor-hook] CI checks failed" >&2
            safe_exit "CI checks failed. Please review the failed workflows and fix any issues." "block"
        fi

        # If all runs are completed and none failed, success
        if [ "$all_completed" = true ]; then
            echo "[ci-monitor-hook] All CI workflows passed successfully!" >&2
            safe_exit "All CI workflows passed successfully!" "approve"
        fi

        # Some runs are still in progress, continue monitoring
        echo "[ci-monitor-hook] $in_progress_count workflow(s) still running, elapsed: ${elapsed}s" >&2

        # Wait before next check
        sleep $CHECK_INTERVAL
    done
}

# Start monitoring
monitor_ci