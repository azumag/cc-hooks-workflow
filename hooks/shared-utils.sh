#!/bin/bash
# Minimal shared utilities for hooks scripts
# YAGNI/KISS原則に従い、必要最小限の機能のみ提供

set -euo pipefail

# Basic logging
log_info() {
    echo "INFO: $*" >&2
}

log_error() {
    echo "ERROR: $*" >&2
}

# Read work summary file path from JSON input
read_work_summary_file_path() {
    jq -r '.work_summary_file_path // empty'
}

# Read work summary file content
read_work_summary() {
    local file_path="$1"
    [ -f "$file_path" ] || { log_error "File not found: $file_path"; return 1; }
    cat "$file_path"
}

# Safe exit with JSON output and appropriate exit code
safe_exit() {
    local reason="${1:-Hook executed successfully}"
    local decision="${2:-approve}"
    
    jq -n --arg reason "$reason" --arg decision "$decision" \
        '{decision: $decision, reason: $reason}'
    
    [ "$decision" = "block" ] && exit 1 || exit 0
}

# Check jq dependency (only dependency needed)
check_jq() {
    command -v jq >/dev/null || { 
        log_error "jq is required but not installed"
        safe_exit "Missing dependency: jq" "block"
    }
}