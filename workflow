#!/bin/bash
# Claude Code Hooks Workflow Tool
# Main workflow script for state-based hook execution

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/hooks/shared-utils.sh"

# Configuration
readonly CLAUDE_TRANSCRIPTS_DIR="${CLAUDE_TRANSCRIPTS_DIR:-$HOME/.claude-code/transcripts}"
readonly WORKFLOW_DEBUG="${WORKFLOW_DEBUG:-false}"
readonly WORK_REPORT_MAX_LENGTH="${WORK_REPORT_MAX_LENGTH:-2000}"

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in jq grep tail; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        echo "Please install the missing dependencies and try again." >&2
        exit 1
    fi
}

# State phrase extraction from transcript
extract_state_phrase() {
    local transcript_path="$1"
    
    if [ ! -f "$transcript_path" ]; then
        echo "NONE"
        return
    fi
    
    # Extract last assistant message
    local last_message
    last_message=$(extract_last_assistant_message "$transcript_path" 50 true)
    
    if [ -z "$last_message" ]; then
        echo "NONE"
        return
    fi
    
    # Check for state phrases in priority order
    if echo "$last_message" | grep -q "REVIEW_COMPLETED && PUSH_COMPLETED"; then
        echo "REVIEW_COMPLETED_AND_PUSH_COMPLETED"
    elif echo "$last_message" | grep -q "PUSH_COMPLETED"; then
        echo "PUSH_COMPLETED"
    elif echo "$last_message" | grep -q "REVIEW_COMPLETED"; then
        echo "REVIEW_COMPLETED"
    elif echo "$last_message" | grep -q "COMMIT_COMPLETED"; then
        echo "COMMIT_COMPLETED"
    elif echo "$last_message" | grep -q "TESTING_COMPLETED"; then
        echo "TESTING_COMPLETED"
    elif echo "$last_message" | grep -q "BUILD_COMPLETED"; then
        echo "BUILD_COMPLETED"
    elif echo "$last_message" | grep -q "IMPLEMENTATION_COMPLETED"; then
        echo "IMPLEMENTATION_COMPLETED"
    elif echo "$last_message" | grep -q "STOP"; then
        echo "STOP"
    else
        echo "NONE"
    fi
}

# Normalize state phrase
normalize_state_phrase() {
    local state="$1"
    # Remove any extra whitespace and convert to uppercase
    echo "$state" | tr '[:lower:]' '[:upper:]' | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//'
}

# Hard-coded state mapping
map_state_to_hook() {
    local state="$1"
    local normalized_state
    normalized_state=$(normalize_state_phrase "$state")
    
    case "$normalized_state" in
        "REVIEW_COMPLETED_AND_PUSH_COMPLETED"|"REVIEW_COMPLETED && PUSH_COMPLETED")
            echo "ci-monitor-hook.sh"
            ;;
        "PUSH_COMPLETED")
            echo "push-complete-hook.sh"
            ;;
        "REVIEW_COMPLETED")
            echo "review-complete-hook.sh"
            ;;
        "COMMIT_COMPLETED")
            echo "commit-complete-hook.sh"
            ;;
        "TESTING_COMPLETED")
            echo "test-complete-hook.sh"
            ;;
        "BUILD_COMPLETED")
            echo "build-complete-hook.sh"
            ;;
        "IMPLEMENTATION_COMPLETED")
            echo "implementation-complete-hook.sh"
            ;;
        "STOP")
            echo "stop-hook.sh"
            ;;
        "NONE"|"")
            echo ""
            ;;
        *)
            echo "unknown-state-hook.sh"
            ;;
    esac
}

# Save work report to temporary file
save_work_report() {
    local transcript_path="$1"
    local work_report_file
    work_report_file=$(mktemp)
    
    if [ ! -f "$transcript_path" ]; then
        echo "Error: Transcript file not found: $transcript_path" > "$work_report_file"
        echo "$work_report_file"
        return
    fi
    
    # Extract work report (last assistant message)
    local work_summary
    work_summary=$(extract_last_assistant_message "$transcript_path" 0 true)
    
    if [ -z "$work_summary" ]; then
        echo "No work summary available" > "$work_report_file"
    else
        # Limit work report length
        if [ ${#work_summary} -gt $WORK_REPORT_MAX_LENGTH ]; then
            local first_part="${work_summary:0:800}"
            local last_part="${work_summary: -800}"
            echo "${first_part}...(truncated)...${last_part}" > "$work_report_file"
        else
            echo "$work_summary" > "$work_report_file"
        fi
    fi
    
    echo "$work_report_file"
}

# Execute hook script
execute_hook() {
    local hook_script="$1"
    local session_id="$2"
    local transcript_path="$3"
    local work_report_file="$4"
    
    local hook_path="$SCRIPT_DIR/hooks/$hook_script"
    
    if [ ! -f "$hook_path" ]; then
        echo "Error: Hook script not found: $hook_path" >&2
        return 1
    fi
    
    if [ ! -x "$hook_path" ]; then
        echo "Error: Hook script not executable: $hook_path" >&2
        return 1
    fi
    
    # Prepare input JSON for hook
    local hook_input
    hook_input=$(jq -n \
        --arg session_id "$session_id" \
        --arg transcript_path "$transcript_path" \
        --arg work_summary_file_path "$work_report_file" \
        '{
            session_id: $session_id,
            transcript_path: $transcript_path,
            work_summary_file_path: $work_summary_file_path
        }')
    
    # Execute hook and capture output (separating stdout and stderr)
    local hook_output
    local hook_exit_code
    local temp_stderr
    temp_stderr=$(mktemp)
    hook_output=$(echo "$hook_input" | "$hook_path" 2>"$temp_stderr") || hook_exit_code=$?
    
    # Show stderr messages
    if [ -s "$temp_stderr" ]; then
        cat "$temp_stderr" >&2
    fi
    rm -f "$temp_stderr"
    
    if [ "${hook_exit_code:-0}" -ne 0 ]; then
        echo "Warning: Hook '$hook_script' failed with exit code ${hook_exit_code:-0}" >&2
        echo "Hook stdout: $hook_output" >&2
        return 1
    fi
    
    # Parse JSON response
    local decision reason
    if ! decision=$(echo "$hook_output" | jq -r '.decision // "approve"' 2>/dev/null); then
        echo "Error: Invalid JSON response from hook '$hook_script'" >&2
        echo "Hook stdout: $hook_output" >&2
        return 1
    fi
    
    if ! reason=$(echo "$hook_output" | jq -r '.reason // "No reason provided"' 2>/dev/null); then
        reason="No reason provided"
    fi
    
    echo "Hook '$hook_script' returned: decision=$decision, reason=$reason" >&2
    
    # Return hook result
    echo "$hook_output"
    
    # Return exit code based on decision
    if [ "$decision" = "block" ]; then
        return 1
    else
        return 0
    fi
}

# Main workflow function
main() {
    local session_id="${1:-}"
    local transcript_path="${2:-}"
    
    # Handle help option
    if [ "$session_id" = "--help" ] || [ "$session_id" = "-h" ]; then
        echo "Claude Code Hooks Workflow Tool"
        echo "Usage: $0 [session_id] [transcript_path]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo ""
        echo "If no arguments provided, will auto-detect latest session"
        echo "from $CLAUDE_TRANSCRIPTS_DIR"
        exit 0
    fi
    
    # Check dependencies
    check_dependencies
    
    # Handle input arguments
    if [ -z "$session_id" ] && [ -z "$transcript_path" ]; then
        echo "Usage: $0 [session_id] [transcript_path]" >&2
        echo "If no arguments provided, will auto-detect latest session" >&2
        
        # Auto-detect latest transcript
        if [ -d "$CLAUDE_TRANSCRIPTS_DIR" ]; then
            transcript_path=$(find_latest_transcript_in_dir "$CLAUDE_TRANSCRIPTS_DIR")
            local find_exit=$?
            
            if [ $find_exit -eq 0 ] && [ -n "$transcript_path" ]; then
                session_id=$(basename "$transcript_path" .jsonl)
                echo "Auto-detected session: $session_id" >&2
                echo "Using transcript: $transcript_path" >&2
            else
                echo "Error: Could not find any transcript files in $CLAUDE_TRANSCRIPTS_DIR" >&2
                exit 1
            fi
        else
            echo "Error: Claude transcripts directory not found: $CLAUDE_TRANSCRIPTS_DIR" >&2
            exit 1
        fi
    fi
    
    # Derive session_id from transcript_path if not provided
    if [ -z "$session_id" ] && [ -n "$transcript_path" ]; then
        session_id=$(basename "$transcript_path" .jsonl)
    fi
    
    # Derive transcript_path from session_id if not provided
    if [ -n "$session_id" ] && [ -z "$transcript_path" ]; then
        transcript_path="$CLAUDE_TRANSCRIPTS_DIR/$session_id.jsonl"
    fi
    
    echo "Processing session: $session_id" >&2
    echo "Transcript file: $transcript_path" >&2
    
    # Extract state phrase
    local state_phrase
    state_phrase=$(extract_state_phrase "$transcript_path")
    echo "Detected state: $state_phrase" >&2
    
    # Map state to hook
    local hook_script
    hook_script=$(map_state_to_hook "$state_phrase")
    
    if [ -z "$hook_script" ]; then
        echo "No hook mapped for state: $state_phrase" >&2
        exit 0
    fi
    
    echo "Executing hook: $hook_script" >&2
    
    # Save work report
    local work_report_file
    work_report_file=$(save_work_report "$transcript_path")
    
    # Execute hook
    local hook_result
    local hook_exit_code=0
    hook_result=$(execute_hook "$hook_script" "$session_id" "$transcript_path" "$work_report_file") || hook_exit_code=$?
    
    # Clean up work report file
    rm -f "$work_report_file"
    
    # Output final result
    if [ $hook_exit_code -eq 0 ]; then
        echo "Workflow completed successfully" >&2
        echo "$hook_result"
    else
        echo "Workflow failed" >&2
        echo "$hook_result"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"