#!/usr/bin/env bats
# Tests for initial-hook.sh (NONE state handler)

setup() {
    # Create test fixtures
    export TEST_WORK_SUMMARY_FILE="$(mktemp)"
    echo "Test work summary content" > "$TEST_WORK_SUMMARY_FILE"
    
    export VALID_JSON_INPUT='{"work_summary_file_path": "'$TEST_WORK_SUMMARY_FILE'"}'
    export INVALID_JSON_INPUT='{"invalid": "json"}'
    export EMPTY_JSON_INPUT='{}'
}

teardown() {
    [ -f "$TEST_WORK_SUMMARY_FILE" ] && rm -f "$TEST_WORK_SUMMARY_FILE"
}

@test "initial-hook.sh exists and is executable" {
    [ -f "./hooks/initial-hook.sh" ]
    [ -x "./hooks/initial-hook.sh" ]
}

@test "accepts valid JSON input and returns approve" {
    run bash -c "echo '$VALID_JSON_INPUT' | ./hooks/initial-hook.sh"
    [ "$status" -eq 0 ]
    
    # Verify JSON output
    echo "$output" | jq . >/dev/null
    
    # Check decision field
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "approve" ]
}

@test "returns valid JSON format" {
    run bash -c "echo '$VALID_JSON_INPUT' | ./hooks/initial-hook.sh"
    [ "$status" -eq 0 ]
    
    # Verify required fields exist
    echo "$output" | jq -e '.decision' >/dev/null
    echo "$output" | jq -e '.reason' >/dev/null
}

@test "handles missing work_summary_file gracefully" {
    local non_existent_file="/tmp/non_existent_$(date +%s).txt"
    local invalid_input='{"work_summary_file_path": "'$non_existent_file'"}'
    
    run bash -c "echo '$invalid_input' | ./hooks/initial-hook.sh"
    [ "$status" -eq 1 ]
    
    # Should still return valid JSON
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
}

@test "handles invalid JSON input" {
    run bash -c "echo 'invalid json' | ./hooks/initial-hook.sh"
    [ "$status" -eq 1 ]
    
    # Should return valid JSON with block decision
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
    
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "Invalid JSON input" ]]
}

@test "handles empty JSON input" {
    run bash -c "echo '$EMPTY_JSON_INPUT' | ./hooks/initial-hook.sh"
    [ "$status" -eq 1 ]
    
    # Should return valid JSON with block decision
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
}

@test "requires jq dependency" {
    # Test that jq is available
    command -v jq >/dev/null
}