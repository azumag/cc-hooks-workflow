#!/bin/bash
# Simple test script for workflow.sh

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TEST_DIR")"
WORKFLOW_SCRIPT="$PROJECT_DIR/workflow.sh"

# Test: Check if workflow.sh exists and is executable
echo "Testing workflow.sh existence and permissions..."
if [ -f "$WORKFLOW_SCRIPT" ] && [ -x "$WORKFLOW_SCRIPT" ]; then
    echo "✅ workflow.sh exists and is executable"
else
    echo "❌ workflow.sh does not exist or is not executable"
    exit 1
fi

# Test: Check dependencies
echo "Testing dependencies..."
MISSING_DEPS=""
for dep in jq grep tail mktemp; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        MISSING_DEPS="$MISSING_DEPS $dep"
    fi
done

if [ -z "$MISSING_DEPS" ]; then
    echo "✅ All dependencies are available"
else
    echo "⚠️  Missing dependencies:$MISSING_DEPS"
fi

# Test: Source workflow functions
echo "Testing workflow functions sourcing..."
if source "$WORKFLOW_SCRIPT" 2>/dev/null; then
    echo "✅ workflow.sh functions can be sourced"
else
    echo "❌ Failed to source workflow.sh functions"
    exit 1
fi

# Test: Session ID extraction
echo "Testing session ID extraction..."
if type setup_work_summary_paths >/dev/null 2>&1; then
    # Create a temporary test file
    TEST_TRANSCRIPT="/tmp/test-session-id.jsonl"
    echo '{"type":"assistant","message":{"content":[{"type":"text","text":"test"}]}}' > "$TEST_TRANSCRIPT"
    
    # Test with valid session ID
    setup_work_summary_paths "$TEST_TRANSCRIPT"
    if [[ "$work_summary_tmp_dir" == "/tmp/claude/test-session-id" ]]; then
        echo "✅ Session ID extraction works correctly"
    else
        echo "❌ Session ID extraction failed: got '$work_summary_tmp_dir'"
        exit 1
    fi
    
    # Clean up
    rm -f "$TEST_TRANSCRIPT"
else
    echo "⚠️  setup_work_summary_paths function not available"
fi

# Test: Assistant message extraction (using extract_assistant_text)
echo "Testing assistant message extraction..."
if type extract_assistant_text >/dev/null 2>&1; then
    # Create a temporary test file with assistant messages
    TEST_TRANSCRIPT="/tmp/test-assistant-messages.jsonl"
    cat > "$TEST_TRANSCRIPT" << 'EOF'
{"type":"user","message":{"content":[{"type":"text","text":"user message"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"first assistant message"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"second assistant message"}]}}
EOF
    
    # Test extracting last message
    LAST_MESSAGE=$(extract_assistant_text "$TEST_TRANSCRIPT" "last")
    if [[ "$LAST_MESSAGE" == "second assistant message" ]]; then
        echo "✅ Assistant message extraction works correctly"
    else
        echo "❌ Assistant message extraction failed: got '$LAST_MESSAGE'"
        exit 1
    fi
    
    # Clean up
    rm -f "$TEST_TRANSCRIPT"
else
    echo "⚠️  extract_assistant_text function not available"
fi

echo ""
echo "🎉 All basic tests passed!"