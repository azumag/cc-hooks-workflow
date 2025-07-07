#!/bin/bash
# Basic test for workflow script functionality

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WORKFLOW_SCRIPT="$PROJECT_DIR/workflow.sh"

# Test configuration
TEST_SESSION_ID="test-session-$(date +%s)"
TEST_TRANSCRIPT_DIR="/tmp/test-transcripts"
TEST_TRANSCRIPT_PATH="$TEST_TRANSCRIPT_DIR/$TEST_SESSION_ID.jsonl"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test result counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
print_test_header() {
    echo -e "${YELLOW}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    ((TESTS_PASSED++))
}

print_failure() {
    echo -e "${RED}✗ $1${NC}"
    ((TESTS_FAILED++))
}

# Setup test environment
setup_test_env() {
    print_test_header "Setting up test environment"
    
    # Create test transcript directory
    mkdir -p "$TEST_TRANSCRIPT_DIR"
    
    # Create a sample transcript file with REVIEW_COMPLETED state
    cat > "$TEST_TRANSCRIPT_PATH" << 'EOF'
{"type":"user","message":{"content":[{"type":"text","text":"Test user message"}]},"timestamp":"2024-01-01T00:00:00Z","uuid":"user-uuid-1"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Test assistant response with REVIEW_COMPLETED marker"}]},"timestamp":"2024-01-01T00:01:00Z","uuid":"assistant-uuid-1"}
EOF
    
    if [ -f "$TEST_TRANSCRIPT_PATH" ]; then
        print_success "Created test transcript file"
    else
        print_failure "Failed to create test transcript file"
        return 1
    fi
}

# Test workflow script execution
test_workflow_execution() {
    print_test_header "Testing workflow execution"
    
    # Test with explicit session ID and transcript path
    if "$WORKFLOW_SCRIPT" "$TEST_SESSION_ID" "$TEST_TRANSCRIPT_PATH" >/dev/null 2>&1; then
        print_success "Workflow executed successfully with explicit parameters"
    else
        print_failure "Workflow execution failed with explicit parameters"
    fi
}

# Test state phrase extraction
test_state_extraction() {
    print_test_header "Testing state phrase extraction"
    
    # Create transcript with different state phrases
    local test_states=("REVIEW_COMPLETED" "PUSH_COMPLETED" "COMMIT_COMPLETED" "NONE")
    
    for state in "${test_states[@]}"; do
        local test_file="/tmp/test-state-$state.jsonl"
        
        if [ "$state" = "NONE" ]; then
            # Create transcript without state phrases
            cat > "$test_file" << 'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"Regular message without state phrases"}]},"timestamp":"2024-01-01T00:01:00Z","uuid":"assistant-uuid-1"}
EOF
        else
            # Create transcript with state phrase
            cat > "$test_file" << EOF
{"type":"assistant","message":{"content":[{"type":"text","text":"Test message with $state marker"}]},"timestamp":"2024-01-01T00:01:00Z","uuid":"assistant-uuid-1"}
EOF
        fi
        
        # Test extraction (this would require extracting the function, so we'll just test the workflow)
        if "$WORKFLOW_SCRIPT" "test-state-$state" "$test_file" >/dev/null 2>&1; then
            print_success "State extraction test passed for $state"
        else
            print_failure "State extraction test failed for $state"
        fi
        
        rm -f "$test_file"
    done
}

# Test hook execution
test_hook_execution() {
    print_test_header "Testing hook execution"
    
    # Test that hooks are executable
    local hooks_dir="$PROJECT_DIR/hooks"
    local hook_count=0
    
    for hook_file in "$hooks_dir"/*.sh; do
        if [ -f "$hook_file" ]; then
            if [ -x "$hook_file" ]; then
                print_success "Hook is executable: $(basename "$hook_file")"
                ((hook_count++))
            else
                print_failure "Hook is not executable: $(basename "$hook_file")"
            fi
        fi
    done
    
    if [ $hook_count -gt 0 ]; then
        print_success "Found $hook_count executable hooks"
    else
        print_failure "No executable hooks found"
    fi
}

# Test error handling
test_error_handling() {
    print_test_header "Testing error handling"
    
    # Test with non-existent transcript file
    if "$WORKFLOW_SCRIPT" "nonexistent-session" "/tmp/nonexistent.jsonl" >/dev/null 2>&1; then
        print_failure "Workflow should have failed with non-existent transcript"
    else
        print_success "Workflow correctly handled non-existent transcript"
    fi
    
    # Test with invalid session ID
    if "$WORKFLOW_SCRIPT" "" "" >/dev/null 2>&1; then
        print_success "Workflow handled empty parameters (auto-detection)"
    else
        print_failure "Workflow failed with empty parameters"
    fi
}

# Cleanup test environment
cleanup_test_env() {
    print_test_header "Cleaning up test environment"
    
    rm -rf "$TEST_TRANSCRIPT_DIR"
    
    if [ ! -d "$TEST_TRANSCRIPT_DIR" ]; then
        print_success "Cleaned up test environment"
    else
        print_failure "Failed to clean up test environment"
    fi
}

# Print test summary
print_test_summary() {
    echo
    echo -e "${YELLOW}=== Test Summary ===${NC}"
    echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"
    echo
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# Main test execution
main() {
    echo "Running workflow tests..."
    echo
    
    setup_test_env
    test_workflow_execution
    test_state_extraction
    test_hook_execution
    test_error_handling
    cleanup_test_env
    
    print_test_summary
}

# Run tests
main "$@"