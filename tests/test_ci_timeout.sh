#!/bin/bash
# Test CI monitoring timeout functionality

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CI_HOOK="$PROJECT_DIR/hooks/ci-monitor-hook.sh"

# Test different timeout scenarios
test_scenarios=(
    "2:1:1:short_timeout"
    "900:10:15:default_timeout"
)

passed_tests=0
total_tests=0

for scenario in "${test_scenarios[@]}"; do
    IFS=':' read -r timeout delay interval test_name <<< "$scenario"
    
    echo "🧪 Testing: $test_name (timeout=${timeout}s)"
    
    # Set test environment
    export CI_MONITOR_TIMEOUT="$timeout"
    export CI_MONITOR_INITIAL_DELAY="$delay"
    export CI_MONITOR_CHECK_INTERVAL="$interval"
    
    # Create test input
    TEST_INPUT=$(cat <<EOF
{
  "session_id": "test-$test_name",
  "transcript_path": "$SCRIPT_DIR/test-data/test-session.jsonl",
  "work_summary_file_path": "/tmp/test-work-summary-$test_name"
}
EOF
    )
    
    # Run test with timeout to prevent hanging
    timeout 10s bash -c "echo '$TEST_INPUT' | '$CI_HOOK' 2>&1" > "/tmp/test-result-$test_name.log" || true
    
    # Analyze results
    if [ -f "/tmp/test-result-$test_name.log" ]; then
        log_content=$(cat "/tmp/test-result-$test_name.log")
        
        # Check for expected timeout configuration
        if echo "$log_content" | grep -q "timeout=${timeout}s"; then
            echo "   ✓ Timeout configuration correct: ${timeout}s"
            ((passed_tests++))
        else
            echo "   ✗ Timeout configuration incorrect"
        fi
        
        # Check for version identification
        if echo "$log_content" | grep -q "v2.0-enhanced-timeout"; then
            echo "   ✓ Version identification present"
        else
            echo "   ? Version identification missing"
        fi
        
        # Clean up
        rm -f "/tmp/test-result-$test_name.log"
    else
        echo "   ✗ Test failed to produce output"
    fi
    
    ((total_tests++))
    echo ""
done

# Test result summary
echo "📊 Test Summary: $passed_tests/$total_tests tests passed"

if [ "$passed_tests" -eq "$total_tests" ]; then
    echo "✅ All CI timeout tests PASSED"
    exit 0
else
    echo "❌ Some tests FAILED"
    exit 1
fi