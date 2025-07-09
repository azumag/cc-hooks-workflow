#!/usr/bin/env bats
# Integration tests for workflow.sh system
# Tests complete JSON communication flow from workflow.sh to hooks

# Test environment setup
setup() {
    # Create temporary test directory structure
    export TEST_DIR="$(mktemp -d)"
    export TEST_PROJECT_DIR="$TEST_DIR/project"
    export TEST_CLAUDE_DIR="$TEST_PROJECT_DIR/.claude"
    export TEST_TRANSCRIPTS_DIR="$TEST_CLAUDE_DIR/transcripts"
    
    # Create directory structure
    mkdir -p "$TEST_TRANSCRIPTS_DIR"
    
    # Create session.json to identify as Claude Code project
    cat > "$TEST_CLAUDE_DIR/session.json" << 'EOF'
{
    "session_id": "test-session",
    "created_at": "2025-01-08T00:00:00Z"
}
EOF
    
    # Save original working directory
    export ORIGINAL_DIR="$PWD"
    
    # Create transcript timestamp for consistent ordering
    export TRANSCRIPT_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
}

teardown() {
    # Return to original directory
    cd "$ORIGINAL_DIR"
    
    # Clean up test directory
    [ -d "$TEST_DIR" ] && rm -rf "$TEST_DIR"
}

# Helper function to create mock transcript with state phrase
create_mock_transcript() {
    local state_phrase="$1"
    local work_summary="${2:-Test work summary content}"
    local filename="${3:-transcript_${TRANSCRIPT_TIMESTAMP}.jsonl}"
    local transcript_path="$TEST_TRANSCRIPTS_DIR/$filename"
    
    # Create transcript with assistant message containing state phrase
    cat > "$transcript_path" << EOF
{"type": "user", "message": {"content": [{"type": "text", "text": "Test user message"}]}}
{"type": "assistant", "message": {"content": [{"type": "text", "text": "$work_summary"}]}}
{"type": "assistant", "message": {"content": [{"type": "text", "text": "$state_phrase"}]}}
EOF
    
    echo "$transcript_path"
}

# Helper function to create transcript with only work summary (no state)
create_work_summary_transcript() {
    local work_summary="$1"
    local filename="${2:-transcript_${TRANSCRIPT_TIMESTAMP}.jsonl}"
    local transcript_path="$TEST_TRANSCRIPTS_DIR/$filename"
    
    cat > "$transcript_path" << EOF
{"type": "user", "message": {"content": [{"type": "text", "text": "Please complete the task"}]}}
{"type": "assistant", "message": {"content": [{"type": "text", "text": "$work_summary"}]}}
EOF
    
    echo "$transcript_path"
}

# Test: workflow.sh exists and is executable
@test "workflow.sh exists and is executable" {
    [ -f "$ORIGINAL_DIR/workflow.sh" ]
    [ -x "$ORIGINAL_DIR/workflow.sh" ]
}

# Test: workflow.sh detects REVIEW_COMPLETED state
@test "workflow extracts REVIEW_COMPLETED state and calls correct hook" {
    create_mock_transcript "REVIEW_COMPLETED" "Review has been completed successfully"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    # Should fail because hook doesn't exist yet, but log should show correct detection
    [ "$status" -eq 1 ]
    [[ "$output" =~ "検出された状態: REVIEW_COMPLETED" ]]
    [[ "$output" =~ "実行するhook設定:" ]]
}

# Test: workflow.sh detects STOP state
@test "workflow extracts STOP state and calls stop hook" {
    create_mock_transcript "STOP" "Stopping work for now"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "検出された状態: STOP" ]]
    [[ "$output" =~ "実行するhook設定:" ]]
}

# Test: workflow.sh detects NONE state when no state phrase
@test "workflow extracts NONE state when no state phrase present" {
    create_work_summary_transcript "Just finished implementing the feature"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "検出された状態: NONE" ]]
    [[ "$output" =~ "実行するhook設定:" ]]
}

# Test: complete JSON flow with mock hook
@test "complete JSON communication flow through system" {
    # Create transcript
    create_mock_transcript "REVIEW_COMPLETED" "Comprehensive review completed"
    
    # Create mock hook that returns JSON
    mkdir -p "$ORIGINAL_DIR/hooks"
    cat > "$ORIGINAL_DIR/hooks/review-complete-hook.sh" << 'EOF'
#!/bin/bash
# Read JSON input
input=$(cat)
work_summary_file=$(echo "$input" | jq -r '.work_summary_file_path')

# Verify file exists and has content
if [ -f "$work_summary_file" ] && [ -s "$work_summary_file" ]; then
    echo '{"decision": "approve", "reason": "Review completed successfully"}'
else
    echo '{"decision": "block", "reason": "Work summary file not found or empty"}'
fi
EOF
    chmod +x "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hook決定: approve" ]]
    [[ "$output" =~ "理由: Review completed successfully" ]]
    [[ "$output" =~ "Workflow完了 (承認)" ]]
    
    # Cleanup
    rm -f "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
}

# Test: workflow handles missing Claude project
@test "workflow handles missing Claude Code project directory" {
    # Run from a directory without .claude
    cd "$TEST_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Claude Codeプロジェクトディレクトリが見つかりません" ]]
}

# Test: workflow handles missing transcripts directory
@test "workflow handles missing transcripts directory" {
    # Remove transcripts directory
    rm -rf "$TEST_TRANSCRIPTS_DIR"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "トランスクリプトファイルが見つかりません" ]]
}

# Test: workflow handles empty transcripts directory
@test "workflow handles empty transcripts directory" {
    # Ensure directory is empty
    rm -f "$TEST_TRANSCRIPTS_DIR"/*
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "トランスクリプトファイルが見つかりません" ]]
}

# Test: workflow handles invalid JSON in transcript
@test "workflow handles invalid JSON in transcript file" {
    cat > "$TEST_TRANSCRIPTS_DIR/invalid.jsonl" << 'EOF'
This is not valid JSON
{"invalid": json without quotes}
EOF
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    # Should still work - jq will skip invalid lines
    [ "$status" -eq 1 ]
    [[ "$output" =~ "検出された状態: NONE" ]]
}

# Test: workflow handles hook returning invalid JSON
@test "workflow handles hook returning invalid JSON" {
    create_mock_transcript "REVIEW_COMPLETED"
    
    # Create hook that returns invalid JSON
    mkdir -p "$ORIGINAL_DIR/hooks"
    cat > "$ORIGINAL_DIR/hooks/review-complete-hook.sh" << 'EOF'
#!/bin/bash
echo "This is not JSON"
EOF
    chmod +x "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Hookスクリプトから無効なJSON出力" ]]
    
    # Cleanup
    rm -f "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
}

# Test: workflow handles hook with no output
@test "workflow handles hook with no output" {
    create_mock_transcript "REVIEW_COMPLETED"
    
    # Create hook that produces no output
    mkdir -p "$ORIGINAL_DIR/hooks"
    cat > "$ORIGINAL_DIR/hooks/review-complete-hook.sh" << 'EOF'
#!/bin/bash
# Silent hook - no output
exit 0
EOF
    chmod +x "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Hookスクリプトから出力がありません" ]]
    
    # Cleanup
    rm -f "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
}

# Test: workflow handles hook returning block decision
@test "workflow handles hook returning block decision" {
    create_mock_transcript "REVIEW_COMPLETED"
    
    # Create hook that blocks
    mkdir -p "$ORIGINAL_DIR/hooks"
    cat > "$ORIGINAL_DIR/hooks/review-complete-hook.sh" << 'EOF'
#!/bin/bash
echo '{"decision": "block", "reason": "Review found critical issues"}'
EOF
    chmod +x "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Hook決定: block" ]]
    [[ "$output" =~ "理由: Review found critical issues" ]]
    [[ "$output" =~ "Workflow完了 (ブロック)" ]]
    
    # Cleanup
    rm -f "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
}

# Test: workflow handles multiple transcript files (selects latest)
@test "workflow selects latest transcript when multiple exist" {
    # Create older transcript with different state
    sleep 1  # Ensure different timestamp
    create_mock_transcript "PUSH_COMPLETED" "Old push" "transcript_01_old.jsonl"
    
    # Create newer transcript
    sleep 1
    TRANSCRIPT_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    create_mock_transcript "REVIEW_COMPLETED" "New review" "transcript_02_new.jsonl"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "検出された状態: REVIEW_COMPLETED" ]]
}

# Test: workflow creates and cleans up temporary work summary file
@test "workflow creates and cleans up temporary work summary file" {
    create_mock_transcript "REVIEW_COMPLETED" "Test work summary for cleanup test"
    
    # Create hook that saves the temp file path
    mkdir -p "$ORIGINAL_DIR/hooks"
    cat > "$ORIGINAL_DIR/hooks/review-complete-hook.sh" << 'EOF'
#!/bin/bash
input=$(cat)
work_summary_file=$(echo "$input" | jq -r '.work_summary_file_path')
# Save path for later verification
echo "$work_summary_file" > /tmp/test_work_summary_path.txt
echo '{"decision": "approve", "reason": "OK"}'
EOF
    chmod +x "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 0 ]
    
    # Verify temp file was created and then cleaned up
    if [ -f /tmp/test_work_summary_path.txt ]; then
        temp_file_path=$(cat /tmp/test_work_summary_path.txt)
        # File should not exist after workflow completes
        [ ! -f "$temp_file_path" ]
        rm -f /tmp/test_work_summary_path.txt
    fi
    
    # Cleanup
    rm -f "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
}

# Test: workflow handles all defined state phrases
@test "workflow maps all state phrases to correct hooks" {
    # Test each state mapping
    local -A expected_mappings=(
        ["REVIEW_COMPLETED"]="review-complete-hook.sh"
        ["PUSH_COMPLETED"]="push-complete-hook.sh"
        ["COMMIT_COMPLETED"]="commit-complete-hook.sh"
        ["TEST_COMPLETED"]="test-complete-hook.sh"
        ["BUILD_COMPLETED"]="build-complete-hook.sh"
        ["IMPLEMENTATION_COMPLETED"]="implementation-complete-hook.sh"
        ["STOP"]="stop-hook.sh"
        ["NONE"]="initial-hook.sh"
    )
    
    for state in "${!expected_mappings[@]}"; do
        # Create transcript for this state
        if [ "$state" = "NONE" ]; then
            create_work_summary_transcript "Work without state"
        else
            create_mock_transcript "$state" "Work for $state"
        fi
        
        cd "$TEST_PROJECT_DIR"
        run "$ORIGINAL_DIR/workflow.sh"
        
        [ "$status" -eq 1 ]  # Will fail because hooks don't exist
        [[ "$output" =~ "検出された状態: $state" ]]
        [[ "$output" =~ "実行するhook設定:" ]]
        
        # Clean up for next iteration
        rm -f "$TEST_TRANSCRIPTS_DIR"/*
    done
}

# Test: workflow handles unknown state phrase
@test "workflow handles unknown state phrase gracefully" {
    create_mock_transcript "UNKNOWN_STATE" "Work with unknown state"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "検出された状態: NONE" ]]
    [[ "$output" =~ "実行するhook設定:" ]]
}

# Test: workflow handles missing hook script file
@test "workflow handles missing hook script file" {
    create_mock_transcript "REVIEW_COMPLETED"
    
    # Ensure hook doesn't exist
    rm -f "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Hookスクリプトが見つかりません" ]]
}

# Test: workflow handles non-executable hook script
@test "workflow handles non-executable hook script" {
    create_mock_transcript "REVIEW_COMPLETED"
    
    # Create non-executable hook
    mkdir -p "$ORIGINAL_DIR/hooks"
    cat > "$ORIGINAL_DIR/hooks/review-complete-hook.sh" << 'EOF'
#!/bin/bash
echo '{"decision": "approve", "reason": "OK"}'
EOF
    # Don't make it executable
    chmod 644 "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Hookスクリプトに実行権限がありません" ]]
    
    # Cleanup
    rm -f "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
}

# Test: workflow processes complex work summary correctly
@test "workflow extracts and passes complex work summary to hooks" {
    local complex_summary="## Work Summary

### Changes Made
- Implemented feature X with proper error handling
- Added comprehensive test coverage (95%)
- Updated documentation with examples
- Fixed memory leak in module Y

### Technical Details
\`\`\`bash
# Code changes
git diff --stat
 src/feature.js | 150 ++++
 tests/feature.test.js | 200 ++++
\`\`\`

### Next Steps
1. Deploy to staging
2. Monitor performance metrics
3. Gather user feedback"
    
    create_mock_transcript "REVIEW_COMPLETED" "$complex_summary"
    
    # Create hook that verifies work summary content
    mkdir -p "$ORIGINAL_DIR/hooks"
    cat > "$ORIGINAL_DIR/hooks/review-complete-hook.sh" << 'EOF'
#!/bin/bash
input=$(cat)
work_summary_file=$(echo "$input" | jq -r '.work_summary_file_path')

if [ -f "$work_summary_file" ]; then
    content=$(cat "$work_summary_file")
    # Check for expected content patterns
    if [[ "$content" =~ "Changes Made" ]] && \
       [[ "$content" =~ "Technical Details" ]] && \
       [[ "$content" =~ "Next Steps" ]]; then
        echo '{"decision": "approve", "reason": "Complex work summary processed correctly"}'
    else
        echo '{"decision": "block", "reason": "Work summary content missing expected sections"}'
    fi
else
    echo '{"decision": "block", "reason": "Work summary file not found"}'
fi
EOF
    chmod +x "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hook決定: approve" ]]
    [[ "$output" =~ "Complex work summary processed correctly" ]]
    
    # Cleanup
    rm -f "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
}

# Test: workflow handles transcript with only user messages
@test "workflow handles transcript with only user messages" {
    cat > "$TEST_TRANSCRIPTS_DIR/user_only.jsonl" << 'EOF'
{"type": "user", "message": {"content": [{"type": "text", "text": "First user message"}]}}
{"type": "user", "message": {"content": [{"type": "text", "text": "Second user message"}]}}
EOF
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "検出された状態: NONE" ]]
}

# Test: verify dependency checks work
@test "workflow checks for required dependencies" {
    # This test just verifies the checks exist - actual missing deps would break the test
    cd "$TEST_PROJECT_DIR"
    
    # Run workflow and check that it starts (dependencies are present)
    create_mock_transcript "NONE"
    run "$ORIGINAL_DIR/workflow.sh"
    
    # Should get past dependency check
    [[ ! "$output" =~ "以下の依存関係が見つかりません" ]]
}

# Test: workflow handles concurrent execution (file safety)
@test "workflow handles concurrent execution safely" {
    create_mock_transcript "REVIEW_COMPLETED" "Concurrent test"
    
    # Create hook that sleeps to simulate long processing
    mkdir -p "$ORIGINAL_DIR/hooks"
    cat > "$ORIGINAL_DIR/hooks/review-complete-hook.sh" << 'EOF'
#!/bin/bash
input=$(cat)
work_summary_file=$(echo "$input" | jq -r '.work_summary_file_path')
# Verify each instance gets unique temp file
echo "$work_summary_file" >> /tmp/concurrent_test_files.txt
sleep 0.1
echo '{"decision": "approve", "reason": "OK"}'
EOF
    chmod +x "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
    
    # Clean up any previous test file
    rm -f /tmp/concurrent_test_files.txt
    
    cd "$TEST_PROJECT_DIR"
    
    # Run multiple instances in background
    "$ORIGINAL_DIR/workflow.sh" &
    "$ORIGINAL_DIR/workflow.sh" &
    "$ORIGINAL_DIR/workflow.sh" &
    
    # Wait for all to complete
    wait
    
    # Verify each got a unique temp file
    if [ -f /tmp/concurrent_test_files.txt ]; then
        local file_count=$(wc -l < /tmp/concurrent_test_files.txt)
        local unique_count=$(sort -u /tmp/concurrent_test_files.txt | wc -l)
        [ "$file_count" -eq "$unique_count" ]
        rm -f /tmp/concurrent_test_files.txt
    fi
    
    # Cleanup
    rm -f "$ORIGINAL_DIR/hooks/review-complete-hook.sh"
}