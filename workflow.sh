#!/bin/bash
# Hooks Workflow Tool - Main orchestration script
# Entry point script for Claude Code Stop Hooks
# Manages all states and calls individual hook scripts

set -euo pipefail

# ====================
# Configuration and Mapping
# ====================

# Work summary file path (set after obtaining session ID)
work_summary_tmp_dir=""
work_summary_file=""

# JSON configuration file path
CONFIG_FILE=".claude/workflow.json"

# Function to load JSON configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        log_warning "Configuration file not found: $CONFIG_FILE"
        echo "no config found: $CONFIG_FILE" >&2
        exit 1
    fi
}

# Function to get hook configuration from state phrase
# Returns hook information from JSON configuration (JSON format)
get_hook_config() {
    local state="$1"
    local config
    config=$(load_config)
    
    # Search for hook configuration corresponding to the state
    # First look for hook configuration corresponding to the specified state
    local hook_config
    hook_config=$(echo "$config" | jq -r --arg state "$state" '.hooks[] | select(.launch == $state)' 2>/dev/null)
    
    # If no corresponding state is found, look for entries with null launch (default)
    if [ -z "$hook_config" ] || [ "$hook_config" = "{}" ]; then
        hook_config=$(echo "$config" | jq -r '.hooks[] | select(.launch == null)' 2>/dev/null)
    fi
    
    # Output result (empty object if nothing found)
    if [ -n "$hook_config" ] && [ "$hook_config" != "{}" ]; then
        echo "$hook_config"
    else
        echo "{}"
    fi
}

# Dependencies list
REQUIRED_DEPS=("jq" "grep" "tail" "mktemp")

# Direct implementation of common utility functions (no dependency on shared-utils.sh)

# ====================
# Utility Functions
# ====================

# Log functions
log_info() {
    echo "INFO: $*" >&2
}

log_warning() {
    echo "WARNING: $*" >&2
}

log_error() {
    echo "ERROR: $*" >&2
}

# Dependency check
check_dependencies() {
    local missing_deps=()
    
    for dep in "${REQUIRED_DEPS[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "The following dependencies are missing: ${missing_deps[*]}"
        log_error "Please install them and run again"
        exit 1
    fi
}


# Find latest transcript file (self-contained implementation)
find_latest_transcript() {
    local transcript_dir="$HOME/.claude/projects"
    
    # Check if directory exists
    if [ ! -d "$transcript_dir" ]; then
        log_error "Claude transcripts directory not found: $transcript_dir"
        return 1
    fi
    
    # Check if .jsonl files exist
    if ! find "$transcript_dir" -name "*.jsonl" -type f -print -quit | grep -q .; then
        log_error "No .jsonl files found in Claude transcripts directory: $transcript_dir"
        return 2
    fi
    
    # Get latest file (cross-platform compatible)
    local latest_file
    if stat -f "%m %N" /dev/null >/dev/null 2>&1; then
        # macOS/BSD stat
        latest_file=$(find "$transcript_dir" -name "*.jsonl" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    else
        # GNU stat (Linux)
        latest_file=$(find "$transcript_dir" -name "*.jsonl" -type f -exec stat -c "%Y %n" {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    fi
    
    if [ -n "$latest_file" ] && [ -f "$latest_file" ]; then
        echo "$latest_file"
        return 0
    else
        log_error "Error accessing Claude transcripts file: $transcript_dir"
        return 3
    fi
}

# Get session ID and set work_summary_file_path
setup_work_summary_paths() {
    local transcript_path="$1"
    
    # Extract session ID from filename (simplified)
    local session_id
    session_id=$(basename "$transcript_path" .jsonl)
    
    # Simple validation and fallback
    if [[ ! "$session_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        session_id="unknown"
    fi
    
    # Set global variable (create session ID directory under /tmp/claude/)
    work_summary_tmp_dir="/tmp/claude/$session_id"
    work_summary_file="$work_summary_tmp_dir/work_summary.txt"
}

# Common assistant message extraction function
extract_assistant_text() {
    local transcript_path="$1"
    
    if [ ! -f "$transcript_path" ]; then
        return 1
    fi
    
    # Get complete text of latest assistant message (including newlines)
    # Since it's JSONL format, correctly extract the last assistant message
    local last_assistant_line=$(grep '"type":"assistant"' "$transcript_path" | tail -n 1)
    if [ -n "$last_assistant_line" ]; then
        echo "$last_assistant_line" | jq -r '.message.content[]? | select(.type == "text") | .text'
    fi
}

# Extract state phrase from latest assistant message
extract_state_phrase() {
    local transcript_path="$1"
    
    # Use common function to get latest message
    extract_assistant_text "$transcript_path"
}

# Save work summary to session-specific path
save_work_summary() {
    local transcript_path="$1"
   
    # Create session-specific directory
    mkdir -p "$work_summary_tmp_dir"
    
    # Use common function to get last assistant message
    if ! extract_assistant_text "$transcript_path" > "$work_summary_file"; then
        log_error "Failed to extract assistant message"
        return 1
    fi
    
    # Verify work summary file is not empty
    if [ ! -s "$work_summary_file" ]; then
        log_error "Work summary is empty"
        return 1
    fi

    echo "$work_summary_file"
}


# Execute prompt type hook (pass prompt to Claude Code)
execute_prompt_hook() {
    local prompt="$1"
    local work_summary_file="$2"
    
    log_info "Executing prompt hook"
    
    # Replace $WORK_SUMMARY with work summary content
    if [[ "$prompt" == *'$WORK_SUMMARY'* ]] && [ -f "$work_summary_file" ]; then
        local work_summary_content
        work_summary_content=$(cat "$work_summary_file")
        prompt="${prompt//\$WORK_SUMMARY/$work_summary_content}"
    fi

    jq -n \
        --arg reason "$prompt" \
        '{decision: "block", reason: $reason}'
}

# Execute path type hook (traditional script execution)
execute_path_hook() {
    local hook_path="$1"
    local work_summary_file="$2"
    local next_phrase="$3"
    local handling="$4"
    local hook_config="$5"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Use script directory as base for relative paths
    if [[ ! "$hook_path" = /* ]]; then
        hook_path="$script_dir/$hook_path"
    fi
    
    # Check script existence
    if [ ! -f "$hook_path" ]; then
        log_error "Hook script not found: $hook_path"
        return 1
    fi
    
    # Check execution permissions
    if [ ! -x "$hook_path" ]; then
        log_error "Hook script does not have execution permissions: $hook_path"
        return 1
    fi
    
    # Prepare JSON input
    local json_input
    json_input=$(jq -n --arg work_summary_file_path "$work_summary_file" '{work_summary_file_path: $work_summary_file_path}')
    
    # Process args
    local args=()
    if [ -n "$hook_config" ]; then
        # JSON validity check
        if ! echo "$hook_config" | jq empty 2>/dev/null; then
            log_error "Invalid JSON format hook_config"
            return 1
        fi
        
        # Use while loop instead of mapfile (for compatibility with older bash)
        while IFS= read -r line; do
            args+=("$line")
        done < <(echo "$hook_config" | jq -r '.args[]? // empty' 2>/dev/null)
        
        # Validate arguments (check for dangerous characters)
        for arg in ${args[@]+"${args[@]}"}; do
            if [[ "$arg" =~ [\;\|\&\$\`] ]]; then
                log_error "Dangerous characters found in argument: $arg"
                return 1
            fi
        done
    fi
    
    log_info "Executing hook script: $hook_path"
    
    local hook_exit_code
    # Redirect both stdout and stderr to temporary files to suppress output
    local hook_stdout_file hook_stderr_file
    hook_stdout_file=$(mktemp)
    hook_stderr_file=$(mktemp)
    echo "$json_input" | "$hook_path" ${args[@]+"${args[@]}"} > "$hook_stdout_file" 2> "$hook_stderr_file"
    hook_exit_code=${PIPESTATUS[1]}
    hook_stderr=$(cat "$hook_stderr_file")
    rm -f "$hook_stdout_file" "$hook_stderr_file"
    
    # Process based on handling configuration
    case "$handling" in
        "block")
            # On error, output decision block JSON and exit 1
            if [ $hook_exit_code -ne 0 ]; then
                log_error "Hook execution failed (block setting): $hook_path"
                # Notify Claude with decision block JSON
                # TODO: Capture stderr and set as reason
                # Capture stderr output and include in reason
                jq -n --arg reason "$hook_stderr" '{decision: "block", reason: $reason}'
                exit 1
                
            fi
            ;;
        "raise")
            # Display error message to stderr and exit 1
            if [ $hook_exit_code -ne 0 ]; then
                log_error "Hook execution failed (raise setting): $hook_path"
                # TODO: Output stderr and exit 1
                echo "$hook_stderr" >&2
                exit 1
            fi
            ;;
        "pass"|*)
            # Exit normally even on error (exit 0)
            if [ $hook_exit_code -ne 0 ]; then
                log_warning "Hook execution failed (pass setting): $hook_path - ignoring error"
            fi
            exit 0
            ;;
    esac
    
    # If hook succeeds and next phrase is specified,
    # notify Claude to display the next phrase by
    # outputting decision block JSON
    if [ $hook_exit_code -eq 0 ]; then
        if [ -n "$next_phrase" ]; then
            jq -n --arg reason "Display only: $next_phrase" '{decision: "block", reason: $reason}'
        else
            # If no next phrase is specified, output nothing
            # Just exit normally
            exit 0
        fi
    fi

    return 0
}

# Execute hook based on hook configuration
execute_hook() {
    local hook_config="$1"
    local work_summary_file="$2"
    
    # Do nothing if hook configuration is empty
    if [ -z "$hook_config" ] || [ "$hook_config" = "{}" ]; then
        return 0
    fi
    
    # Determine type from hook configuration
    local prompt
    prompt=$(echo "$hook_config" | jq -r '.prompt // empty')
    local path
    path=$(echo "$hook_config" | jq -r '.path // empty')
    local next
    next=$(echo "$hook_config" | jq -r '.next // empty')
    local handling
    handling=$(echo "$hook_config" | jq -r '.handling // "pass"')
    
    if [ -n "$prompt" ]; then
        # Prompt type hook
        execute_prompt_hook "$prompt" "$work_summary_file"
    elif [ -n "$path" ]; then
        # Path type hook
        execute_path_hook "$path" "$work_summary_file" "$next" "$handling" "$hook_config"
    else
        log_warning "Neither prompt nor path specified in hook configuration"
        return 0
    fi
}

# ====================
# Main Processing
# ====================

main() {
    log_info "Starting workflow"
    
    # Dependency check
    check_dependencies
    
    # Find latest transcript file
    local transcript_path
    if ! transcript_path=$(find_latest_transcript); then
        log_error "Transcript file not found"
        exit 1
    fi
    
    log_info "Transcript file: $transcript_path"
    
    # Get session ID and set work_summary_file_path
    setup_work_summary_paths "$transcript_path"
    
    # Extract state phrase
    local state_phrase
    if ! state_phrase=$(extract_state_phrase "$transcript_path"); then
        log_error "Failed to extract state phrase"
        exit 1
    fi
    
    log_info "Detected state: $state_phrase"
    
    # Get hook configuration corresponding to the state
    local hook_config
    hook_config=$(get_hook_config "$state_phrase")
    
    if [ -z "$hook_config" ] || [ "$hook_config" = "{}" ]; then
        # If state phrase is not defined, it's not an error.
        # Simply no hook is configured, so exit normally.
        log_info "No hook configured for state '$state_phrase'"
        exit 0
    fi
    
    log_info "Hook configuration to execute: $(echo "$hook_config" | jq -c '.')"
    
    # Save work summary only when launch is null (initial execution)
    local launch
    launch=$(echo "$hook_config" | jq -r '.launch // empty')
    
    if [ -z "$launch" ] || [ "$launch" = "null" ]; then
        # Save work summary only when no state phrase is specified
        if ! work_summary_file=$(save_work_summary "$transcript_path"); then
            log_error "Failed to save work summary"
            exit 1
        fi
        log_info "Created new work summary file: $work_summary_file"
    fi
   
    # Execute hook based on hook configuration
    if execute_hook "$hook_config" "$work_summary_file"; then
        log_info "Workflow completed"
        exit 0
    else
        log_info "Workflow failed"
        exit 1
    fi
}

# Exit immediately if --stop option is passed
if [ "${1:-}" = "--stop" ]; then
    exit 0
fi

# Execute main only when script is run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi