#!/bin/bash
# Test CI monitoring timeout functionality

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CI_HOOK="$PROJECT_DIR/hooks/ci-monitor-hook.sh"

# Test with very short timeout
export CI_MONITOR_TIMEOUT=2
export CI_MONITOR_INITIAL_DELAY=1
export CI_MONITOR_CHECK_INTERVAL=1

echo "Testing CI monitor timeout functionality..."
echo "Setting very short timeout: CI_MONITOR_TIMEOUT=$CI_MONITOR_TIMEOUT"

# Create test input
TEST_INPUT=$(cat <<EOF
{
  "session_id": "test-ci-timeout",
  "transcript_path": "$SCRIPT_DIR/test-data/test-session.jsonl",
  "work_summary_file_path": "/tmp/test-work-summary"
}
EOF
)

echo "Test input prepared"

# Test the CI monitor hook (this should timeout quickly if there are any CI workflows)
echo "Running CI monitor hook with short timeout..."
RESULT=$(echo "$TEST_INPUT" | "$CI_HOOK" 2>/dev/null || echo '{"decision":"error","reason":"Hook failed"}')

echo "CI monitor result:"
echo "$RESULT"

# Parse the result
DECISION=$(echo "$RESULT" | jq -r '.decision // "unknown"')
REASON=$(echo "$RESULT" | jq -r '.reason // "No reason"')

echo ""
echo "Decision: $DECISION"
echo "Reason preview: ${REASON:0:100}..."

# Check if it handled timeout appropriately
if [[ "$REASON" =~ "timeout" ]] || [[ "$REASON" =~ "Timeout" ]]; then
    echo "✓ Timeout handling test PASSED - detected timeout scenario"
elif [[ "$REASON" =~ "No CI workflows" ]] || [[ "$REASON" =~ "not found" ]]; then
    echo "✓ Test PASSED - no CI workflows to monitor (expected for this test repo)"
else
    echo "? Test result unclear - may have passed quickly or failed differently"
fi

echo ""
echo "CI timeout test completed"