#!/usr/bin/env bats
# Tests for stop-hook.sh (STOP state handler)

setup() {
    # Create test fixtures
    export TEST_WORK_SUMMARY_FILE="$(mktemp)"
    echo "Test work summary content" > "$TEST_WORK_SUMMARY_FILE"
    
    export VALID_JSON_INPUT='{"work_summary_file_path": "'$TEST_WORK_SUMMARY_FILE'"}'
    export INVALID_JSON_INPUT='{"invalid": "json"}'
    export EMPTY_JSON_INPUT='{}'
    
    # Setup a temporary git repo for testing
    export TEST_GIT_DIR="$(mktemp -d)"
    cd "$TEST_GIT_DIR"
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"
    
    # Create initial commit
    echo "initial" > initial.txt
    git add initial.txt
    git commit -m "Initial commit"
}

teardown() {
    [ -f "$TEST_WORK_SUMMARY_FILE" ] && rm -f "$TEST_WORK_SUMMARY_FILE"
    [ -d "$TEST_GIT_DIR" ] && rm -rf "$TEST_GIT_DIR"
}

@test "stop-hook.sh exists and is executable" {
    [ -f "$OLDPWD/hooks/stop-hook.sh" ]
    [ -x "$OLDPWD/hooks/stop-hook.sh" ]
}

@test "accepts valid JSON input and returns JSON output" {
    cd "$TEST_GIT_DIR"
    run bash -c "echo '$VALID_JSON_INPUT' | $OLDPWD/hooks/stop-hook.sh"
    [ "$status" -eq 0 ]
    
    # Verify JSON output
    echo "$output" | jq . >/dev/null
    
    # Check required fields exist
    echo "$output" | jq -e '.decision' >/dev/null
    echo "$output" | jq -e '.reason' >/dev/null
}

@test "detects uncommitted files and commits them" {
    cd "$TEST_GIT_DIR"
    
    # Create uncommitted files
    echo "new content" > new_file.txt
    echo "modified content" > initial.txt
    
    run bash -c "echo '$VALID_JSON_INPUT' | $OLDPWD/hooks/stop-hook.sh"
    [ "$status" -eq 0 ]
    
    # Verify files were committed
    git_status=$(git status --porcelain)
    [ -z "$git_status" ]
    
    # Check that reason contains success message
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "REVIEW_COMPLETED && PUSH_COMPLETED" ]]
}

@test "handles no uncommitted files gracefully" {
    cd "$TEST_GIT_DIR"
    
    # No uncommitted files
    run bash -c "echo '$VALID_JSON_INPUT' | $OLDPWD/hooks/stop-hook.sh"
    [ "$status" -eq 0 ]
    
    # Check decision is approve
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "approve" ]
    
    # Check that reason contains success message
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "REVIEW_COMPLETED && PUSH_COMPLETED" ]]
}

@test "handles git commit failure gracefully" {
    cd "$TEST_GIT_DIR"
    
    # Create uncommitted files
    echo "new content" > new_file.txt
    
    # Make git commit fail by setting invalid user.name
    git config user.name ""
    git config user.email ""
    
    run bash -c "echo '$VALID_JSON_INPUT' | $OLDPWD/hooks/stop-hook.sh"
    [ "$status" -eq 1 ]
    
    # Should return valid JSON with block decision
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
    
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "Failed to commit changes" ]]
}

@test "handles invalid JSON input" {
    cd "$TEST_GIT_DIR"
    
    run bash -c "echo 'invalid json' | $OLDPWD/hooks/stop-hook.sh"
    [ "$status" -eq 1 ]
    
    # Should return valid JSON with block decision
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
    
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "Invalid JSON" ]]
}

@test "handles empty JSON input" {
    cd "$TEST_GIT_DIR"
    
    run bash -c "echo '$EMPTY_JSON_INPUT' | $OLDPWD/hooks/stop-hook.sh"
    [ "$status" -eq 1 ]
    
    # Should return valid JSON with block decision
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
    
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "Missing work_summary_file_path" ]]
}

@test "handles missing work_summary_file gracefully" {
    cd "$TEST_GIT_DIR"
    
    local non_existent_file="/tmp/non_existent_$(date +%s).txt"
    local invalid_input='{"work_summary_file_path": "'$non_existent_file'"}'
    
    run bash -c "echo '$invalid_input' | $OLDPWD/hooks/stop-hook.sh"
    [ "$status" -eq 1 ]
    
    # Should still return valid JSON
    echo "$output" | jq . >/dev/null
    
    decision=$(echo "$output" | jq -r '.decision')
    [ "$decision" = "block" ]
    
    reason=$(echo "$output" | jq -r '.reason')
    [[ "$reason" =~ "Work summary file not found" ]]
}

@test "requires jq dependency" {
    # Test that jq is available
    command -v jq >/dev/null
}

@test "requires git dependency" {
    # Test that git is available
    command -v git >/dev/null
}

@test "creates appropriate commit message" {
    cd "$TEST_GIT_DIR"
    
    # Create uncommitted files
    echo "new feature" > feature.txt
    echo "bug fix" > bugfix.txt
    
    run bash -c "echo '$VALID_JSON_INPUT' | $OLDPWD/hooks/stop-hook.sh"
    [ "$status" -eq 0 ]
    
    # Check the commit message
    commit_msg=$(git log -1 --pretty=format:"%s")
    [[ "$commit_msg" =~ "Auto-commit" ]]
}