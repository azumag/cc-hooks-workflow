#!/bin/bash
# Simple test script for workflow.sh

set -euo pipefail

# Test configuration
# Get the absolute path to the project root
if [[ -n "${BATS_TEST_DIRNAME:-}" ]]; then
    # Running under bats
    PROJECT_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
else
    # Running directly
    TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_DIR="$(dirname "$TEST_DIR")"
fi

WORKFLOW_SCRIPT="$PROJECT_DIR/workflow.sh"

@test "workflow.sh exists and is executable" {
    [ -f "$WORKFLOW_SCRIPT" ]
    [ -x "$WORKFLOW_SCRIPT" ]
}

@test "required dependencies are available" {
    command -v jq >/dev/null 2>&1
    command -v grep >/dev/null 2>&1
    command -v tail >/dev/null 2>&1
    command -v mktemp >/dev/null 2>&1
}

@test "workflow functions can be sourced" {
    source "$WORKFLOW_SCRIPT"
}

@test "session ID extraction works correctly" {
    source "$WORKFLOW_SCRIPT"
    
    # Create a temporary test file
    TEST_TRANSCRIPT="/tmp/test-session-id.jsonl"
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"test"}]}}' > "$TEST_TRANSCRIPT"
    
    # Test with valid session ID
    setup_work_summary_paths "$TEST_TRANSCRIPT"
    [ "$work_summary_tmp_dir" = "/tmp/claude/test-session-id" ]
    
    # Clean up
    rm -f "$TEST_TRANSCRIPT"
}

@test "assistant message extraction works correctly" {
    source "$WORKFLOW_SCRIPT"
    
    # Test 1: Single-line message extraction
    TEST_TRANSCRIPT="/tmp/test-assistant-messages.jsonl"
    cat > "$TEST_TRANSCRIPT" << 'EOF'
{"type":"user","message":{"content":[{"type":"text","text":"user message"}]}}
{"type":"assistant","uuid":"msg1","message":{"content":[{"type":"text","text":"first assistant message"}]}}
{"type":"assistant","uuid":"msg2","message":{"content":[{"type":"text","text":"second assistant message"}]}}
EOF
    
    # Test extracting last message
    LAST_MESSAGE=$(extract_assistant_text "$TEST_TRANSCRIPT")
    [ "$LAST_MESSAGE" = "second assistant message" ]
    
    # Test 2: Multi-line message extraction
    TEST_MULTILINE="/tmp/test-multiline-messages.jsonl"
    cat > "$TEST_MULTILINE" << 'EOF'
{"type":"user","message":{"content":[{"type":"text","text":"user message"}]}}
{"type":"assistant","uuid":"msg1","message":{"content":[{"type":"text","text":"first line\nsecond line\nthird line"}]}}
{"type":"assistant","uuid":"msg2","message":{"content":[{"type":"text","text":"final line 1\nfinal line 2\nfinal line 3"}]}}
EOF
    
    MULTILINE_MESSAGE=$(extract_assistant_text "$TEST_MULTILINE")
    EXPECTED_MULTILINE="final line 1
final line 2
final line 3"
    
    [ "$MULTILINE_MESSAGE" = "$EXPECTED_MULTILINE" ]
    
    # Clean up
    rm -f "$TEST_TRANSCRIPT" "$TEST_MULTILINE"
}