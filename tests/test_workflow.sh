#!/bin/bash
# Test script for workflow.sh

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TEST_DIR")"
WORKFLOW_SCRIPT="$PROJECT_DIR/workflow.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Utility functions
log_test() {
    echo -e "${YELLOW}[TEST]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    ((TESTS_FAILED++))
}

# Test: Check if workflow.sh exists and is executable
test_workflow_exists() {
    ((TESTS_TOTAL++))
    log_test "workflow.sh の存在と実行権限の確認"
    
    if [ -f "$WORKFLOW_SCRIPT" ] && [ -x "$WORKFLOW_SCRIPT" ]; then
        log_pass "workflow.sh exists and is executable"
    else
        log_fail "workflow.sh does not exist or is not executable"
    fi
}

# Test: Check dependency checking function
test_dependency_check() {
    ((TESTS_TOTAL++))
    log_test "依存関係チェック機能のテスト"
    
    # Source the workflow script to test its functions
    source "$WORKFLOW_SCRIPT"
    
    # Test check_dependencies function
    if check_dependencies 2>/dev/null; then
        log_pass "依存関係チェック機能は正常に動作します"
    else
        log_fail "依存関係チェック機能にエラーがあります"
    fi
}

# Test: Create mock hook script for testing execute_hook
test_execute_hook_stderr_separation() {
    ((TESTS_TOTAL++))
    log_test "execute_hook のstdout/stderr分離テスト"
    
    # Create mock hook script
    local mock_hook_dir="$PROJECT_DIR/hooks"
    mkdir -p "$mock_hook_dir"
    
    local mock_hook="$mock_hook_dir/test-hook.sh"
    cat > "$mock_hook" << 'EOF'
#!/bin/bash
# Mock hook script for testing

# Read JSON input
json_input=$(cat)

# Output to stderr (should not interfere with JSON parsing)
echo "Debug: Processing hook with input: $json_input" >&2

# Output valid JSON to stdout
echo '{"decision": "approve", "reason": "Test hook executed successfully"}'
EOF
    
    chmod +x "$mock_hook"
    
    # Source the workflow script to test its functions
    source "$WORKFLOW_SCRIPT"
    
    # Create temporary work summary file
    local temp_summary
    temp_summary=$(mktemp /tmp/test_summary_XXXXXX.txt)
    echo "Test work summary" > "$temp_summary"
    
    # Test execute_hook function
    if execute_hook "test-hook.sh" "$temp_summary" 2>/dev/null; then
        log_pass "execute_hook のstdout/stderr分離は正常に動作します"
    else
        log_fail "execute_hook のstdout/stderr分離にエラーがあります"
    fi
    
    # Cleanup
    rm -f "$mock_hook" "$temp_summary"
}

# Test: Test JSON input format
test_json_input_format() {
    ((TESTS_TOTAL++))
    log_test "JSON入力フォーマットのテスト"
    
    # Create mock hook script that validates JSON input
    local mock_hook_dir="$PROJECT_DIR/hooks"
    mkdir -p "$mock_hook_dir"
    
    local mock_hook="$mock_hook_dir/json-test-hook.sh"
    cat > "$mock_hook" << 'EOF'
#!/bin/bash
# Mock hook script for JSON input testing

# Read JSON input
json_input=$(cat)

# Validate JSON input has required field
if echo "$json_input" | jq -e '.work_summary_file_path' >/dev/null 2>&1; then
    echo '{"decision": "approve", "reason": "JSON input format is valid"}'
else
    echo '{"decision": "block", "reason": "JSON input format is invalid"}'
fi
EOF
    
    chmod +x "$mock_hook"
    
    # Source the workflow script to test its functions
    source "$WORKFLOW_SCRIPT"
    
    # Create temporary work summary file
    local temp_summary
    temp_summary=$(mktemp /tmp/test_summary_XXXXXX.txt)
    echo "Test work summary" > "$temp_summary"
    
    # Test execute_hook function
    if execute_hook "json-test-hook.sh" "$temp_summary" 2>/dev/null; then
        log_pass "JSON入力フォーマットは正常に動作します"
    else
        log_fail "JSON入力フォーマットにエラーがあります"
    fi
    
    # Cleanup
    rm -f "$mock_hook" "$temp_summary"
}

# Test: Test invalid JSON output handling
test_invalid_json_handling() {
    ((TESTS_TOTAL++))
    log_test "不正なJSON出力の処理テスト"
    
    # Create mock hook script that outputs invalid JSON
    local mock_hook_dir="$PROJECT_DIR/hooks"
    mkdir -p "$mock_hook_dir"
    
    local mock_hook="$mock_hook_dir/invalid-json-hook.sh"
    cat > "$mock_hook" << 'EOF'
#!/bin/bash
# Mock hook script that outputs invalid JSON

# Read JSON input
json_input=$(cat)

# Output invalid JSON
echo "This is not valid JSON"
EOF
    
    chmod +x "$mock_hook"
    
    # Source the workflow script to test its functions
    source "$WORKFLOW_SCRIPT"
    
    # Create temporary work summary file
    local temp_summary
    temp_summary=$(mktemp /tmp/test_summary_XXXXXX.txt)
    echo "Test work summary" > "$temp_summary"
    
    # Test execute_hook function (should fail)
    if ! execute_hook "invalid-json-hook.sh" "$temp_summary" 2>/dev/null; then
        log_pass "不正なJSON出力の処理は正常に動作します"
    else
        log_fail "不正なJSON出力の処理にエラーがあります"
    fi
    
    # Cleanup
    rm -f "$mock_hook" "$temp_summary"
}

# Run all tests
run_all_tests() {
    echo "=== workflow.sh テストスイート ==="
    echo
    
    test_workflow_exists
    test_dependency_check
    test_execute_hook_stderr_separation
    test_json_input_format
    test_invalid_json_handling
    
    echo
    echo "=== テスト結果 ==="
    echo "Total: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    run_all_tests
fi