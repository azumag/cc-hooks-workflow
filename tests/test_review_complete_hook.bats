#!/usr/bin/env bats
# Tests for review-complete-hook.sh (R_EVIEW_COMPLETED state handler)

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
    run bash -c "echo '$VALID_JSON_INPUT' | ./hooks/review-complete-hook.sh 2>/dev/null"
    [ "$status" -eq 0 ]
    
    # Verify JSON output
    echo "$output" | jq . >/dev/null
    
    # Check decision field
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "approve" ]
}

@test "returns valid JSON format with required fields" {
    run bash -c "echo '$VALID_JSON_INPUT' | ./hooks/review-complete-hook.sh 2>/dev/null"
    [ "$status" -eq 0 ]
    
    # Verify required fields exist
    echo "$output" | jq -e '.decision' >/dev/null
    echo "$output" | jq -e '.reason' >/dev/null
    
    # Verify decision is either approve or block
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "approve" ] || [ "$decision" = "block" ]
}

@test "handles missing work_summary_file gracefully" {
    local non_existent_file="/tmp/non_existent_$(date +%s).txt"
    local invalid_input='{"work_summary_file_path": "'$non_existent_file'"}'
    
    run bash -c "echo '$invalid_input' | ./hooks/review-complete-hook.sh 2>/dev/null"
    [ "$status" -eq 1 ]
    
    # Should still return valid JSON
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
    
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "Work summary file not found" ]]
}

@test "handles empty work summary file" {
    run bash -c "echo '$EMPTY_FILE_JSON_INPUT' | ./hooks/review-complete-hook.sh 2>/dev/null"
    [ "$status" -eq 1 ]
    
    # Should return valid JSON with block decision
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
    
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "Work summary file is empty" ]]
}

@test "handles invalid JSON input" {
    run bash -c "echo 'invalid json' | ./hooks/review-complete-hook.sh 2>/dev/null"
    [ "$status" -eq 1 ]
    
    # Should return valid JSON with block decision
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
    
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "Invalid JSON" ]]
}

@test "handles empty JSON input" {
    run bash -c "echo '$EMPTY_JSON_INPUT' | ./hooks/review-complete-hook.sh 2>/dev/null"
    [ "$status" -eq 1 ]
    
    # Should return valid JSON with block decision
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
    
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "Missing work_summary_file_path" ]]
}

@test "approves well-documented review work" {
    run bash -c "echo '$GOOD_REVIEW_JSON_INPUT' | ./hooks/review-complete-hook.sh 2>/dev/null"
    [ "$status" -eq 0 ]
    
    # Should return valid JSON with approve decision
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "approve" ]
    
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "Review completed successfully" ]]
}

@test "validates work summary content quality" {
    # Test with minimal content
    local minimal_content_file="$(mktemp)"
    echo "Brief summary" > "$minimal_content_file"
    local minimal_input='{"work_summary_file_path": "'$minimal_content_file'"}'
    
    run bash -c "echo '$minimal_input' | ./hooks/review-complete-hook.sh 2>/dev/null"
    
    # Should still approve but with appropriate reasoning
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "approve" ]
    
    rm -f "$minimal_content_file"
}

@test "requires jq dependency" {
    # Test that jq is available
    command -v jq >/dev/null
}

@test "handles file permission errors gracefully" {
    # Create a file without read permissions
    local unreadable_file="$(mktemp)"
    echo "test content" > "$unreadable_file"
    chmod 000 "$unreadable_file"
    
    local permission_input='{"work_summary_file_path": "'$unreadable_file'"}'
    
    run bash -c "echo '$permission_input' | ./hooks/review-complete-hook.sh 2>/dev/null"
    [ "$status" -eq 1 ]
    
    # Should return valid JSON with block decision
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
    
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "Cannot read work summary file" ]]
    
    # Cleanup
    chmod 644 "$unreadable_file"
    rm -f "$unreadable_file"
}