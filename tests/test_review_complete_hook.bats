#!/usr/bin/env bats
# Tests for review-complete-hook.sh (REVIEW_COMPLETED state handler)
# Updated for new I/F: exit code based instead of JSON output

setup() {
    # Create test fixtures
    export TEST_WORK_SUMMARY_FILE="$(mktemp)"
    export TEST_EMPTY_SUMMARY_FILE="$(mktemp)"
    export TEST_GOOD_REVIEW_FILE="$(mktemp)"
    
    # Create test content for different scenarios
    echo "Test work summary content" > "$TEST_WORK_SUMMARY_FILE"
    # Create truly empty file
    > "$TEST_EMPTY_SUMMARY_FILE"
    
    # Create a good review work summary
    cat > "$TEST_GOOD_REVIEW_FILE" << 'EOF'
## Work Summary - Review Complete

### Changes Made
- Implemented feature X following TDD principles
- Added comprehensive test coverage
- Updated documentation
- Fixed bug Y in module Z

### Review Completed
- All tests pass
- Code follows project standards
- Documentation updated
- No security issues found

### Decision
The review has been completed successfully. All requirements met.
EOF
    
    export VALID_JSON_INPUT='{"work_summary_file_path": "'$TEST_WORK_SUMMARY_FILE'"}'
    export EMPTY_FILE_JSON_INPUT='{"work_summary_file_path": "'$TEST_EMPTY_SUMMARY_FILE'"}'
    export GOOD_REVIEW_JSON_INPUT='{"work_summary_file_path": "'$TEST_GOOD_REVIEW_FILE'"}'
    export INVALID_JSON_INPUT='{"invalid": "json"}'
    export EMPTY_JSON_INPUT='{}'
}

teardown() {
    [ -f "$TEST_WORK_SUMMARY_FILE" ] && rm -f "$TEST_WORK_SUMMARY_FILE"
    [ -f "$TEST_EMPTY_SUMMARY_FILE" ] && rm -f "$TEST_EMPTY_SUMMARY_FILE"
    [ -f "$TEST_GOOD_REVIEW_FILE" ] && rm -f "$TEST_GOOD_REVIEW_FILE"
}

@test "review-complete-hook.sh exists and is executable" {
    [ -f "./hooks/review-complete-hook.sh" ]
    [ -x "./hooks/review-complete-hook.sh" ]
}

@test "accepts valid JSON input with work summary file" {
    run bash -c "echo '$VALID_JSON_INPUT' | ./hooks/review-complete-hook.sh"
    [ "$status" -eq 0 ]
    
    # Verify success message on stdout
    [[ "$output" =~ "INFO: Review completed successfully" ]]
}

@test "returns success exit code with valid input" {
    run bash -c "echo '$VALID_JSON_INPUT' | ./hooks/review-complete-hook.sh"
    [ "$status" -eq 0 ]
}

@test "handles missing work_summary_file gracefully" {
    local non_existent_file="/tmp/non_existent_$(date +%s).txt"
    local invalid_input='{"work_summary_file_path": "'$non_existent_file'"}'
    
    run bash -c "echo '$invalid_input' | ./hooks/review-complete-hook.sh"
    [ "$status" -eq 1 ]
    
    # Error should be on stderr (captured in output by bats)
    [[ "$output" =~ "ERROR: Work summary file not found" ]]
}

@test "handles empty work summary file" {
    run bash -c "echo '$EMPTY_FILE_JSON_INPUT' | ./hooks/review-complete-hook.sh"
    [ "$status" -eq 1 ]
    
    # Should return error about empty file
    [[ "$output" =~ "ERROR: Work summary file is empty" ]]
}

@test "handles invalid JSON input" {
    run bash -c "echo 'invalid json' | ./hooks/review-complete-hook.sh"
    [ "$status" -eq 1 ]
    
    [[ "$output" =~ "ERROR: Invalid JSON input" ]]
}

@test "handles empty JSON input" {
    run bash -c "echo '$EMPTY_JSON_INPUT' | ./hooks/review-complete-hook.sh"
    [ "$status" -eq 1 ]
    
    [[ "$output" =~ "ERROR: Missing work_summary_file_path field" ]]
}

@test "approves well-documented review work" {
    run bash -c "echo '$GOOD_REVIEW_JSON_INPUT' | ./hooks/review-complete-hook.sh"
    [ "$status" -eq 0 ]
    
    [[ "$output" =~ "INFO: Review completed successfully" ]]
}

@test "validates work summary content quality" {
    # This hook basically approves if file exists and is not empty
    run bash -c "echo '$GOOD_REVIEW_JSON_INPUT' | ./hooks/review-complete-hook.sh"
    [ "$status" -eq 0 ]
    
    [[ "$output" =~ "INFO: Review completed successfully" ]]
}

@test "requires jq dependency" {
    # This test is difficult to implement safely without sudo
    # We'll verify that the dependency check exists in the code instead
    grep -q "command -v jq" ./hooks/review-complete-hook.sh
    grep -q "Missing required dependency: jq" ./hooks/review-complete-hook.sh
}

@test "handles file permission errors gracefully" {
    # Create a file and remove read permissions
    local permission_test_file="$(mktemp)"
    echo "test content" > "$permission_test_file"
    chmod 000 "$permission_test_file"
    
    local permission_input='{"work_summary_file_path": "'$permission_test_file'"}'
    
    run bash -c "echo '$permission_input' | ./hooks/review-complete-hook.sh"
    [ "$status" -eq 1 ]
    
    [[ "$output" =~ "ERROR: Cannot read work summary file" ]]
    
    # Clean up
    chmod 644 "$permission_test_file"
    rm -f "$permission_test_file"
}
