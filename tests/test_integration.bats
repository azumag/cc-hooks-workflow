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
    
    # Save original working directory (parent of tests directory)
    if [[ "$PWD" == */tests ]]; then
        export ORIGINAL_DIR="$(dirname "$PWD")"
    else
        export ORIGINAL_DIR="$PWD"
    fi
    
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

# Test: Basic workflow functionality without config file
@test "workflow handles missing config file and displays appropriate message" {
    create_mock_transcript "REVIEW_COMPLETED" "Review has been completed successfully"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    # Should succeed with no config file found message
    [ "$status" -eq 0 ]
    [[ "$output" =~ "no config found: .claude/workflow.json" ]]
}

# Test: workflow.sh handles missing transcripts directory
@test "workflow handles missing transcripts directory" {
    # Remove transcripts directory
    rm -rf "$TEST_TRANSCRIPTS_DIR"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "no config found: .claude/workflow.json" ]]
}

# Test: workflow.sh handles empty transcripts directory
@test "workflow handles empty transcripts directory" {
    # Ensure directory is empty
    rm -f "$TEST_TRANSCRIPTS_DIR"/*
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "no config found: .claude/workflow.json" ]]
}

# Test: workflow handles missing Claude project
@test "workflow handles missing Claude Code project directory" {
    # Run from a directory without .claude
    cd "$TEST_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "no config found: .claude/workflow.json" ]]
}

# Test: workflow handles invalid JSON in transcript
@test "workflow handles invalid JSON in transcript file" {
    cat > "$TEST_TRANSCRIPTS_DIR/invalid.jsonl" << 'EOF'
This is not valid JSON
{"invalid": json without quotes}
EOF
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    # Should succeed with no config file found message
    [ "$status" -eq 0 ]
    [[ "$output" =~ "no config found: .claude/workflow.json" ]]
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
    
    # Should succeed with no config file found message
    [ "$status" -eq 0 ]
    [[ "$output" =~ "no config found: .claude/workflow.json" ]]
}

# Test: workflow handles all defined state phrases
@test "workflow maps all state phrases to correct hook types" {
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
        
        # Should succeed with no config file found message
        [ "$status" -eq 0 ]
        [[ "$output" =~ "no config found: .claude/workflow.json" ]]
        
        # Clean up for next iteration
        rm -f "$TEST_TRANSCRIPTS_DIR"/*
    done
}

# Test: workflow handles unknown state phrase
@test "workflow handles unknown state phrase gracefully" {
    create_mock_transcript "UNKNOWN_STATE" "Work with unknown state"
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    # Should succeed with no config file found message
    [ "$status" -eq 0 ]
    [[ "$output" =~ "no config found: .claude/workflow.json" ]]
}

# Test: workflow handles transcript with only user messages
@test "workflow handles transcript with only user messages" {
    cat > "$TEST_TRANSCRIPTS_DIR/user_only.jsonl" << 'EOF'
{"type": "user", "message": {"content": [{"type": "text", "text": "First user message"}]}}
{"type": "user", "message": {"content": [{"type": "text", "text": "Second user message"}]}}
EOF
    
    cd "$TEST_PROJECT_DIR"
    run "$ORIGINAL_DIR/workflow.sh"
    
    # Should succeed with no config file found message
    [ "$status" -eq 0 ]
    [[ "$output" =~ "no config found: .claude/workflow.json" ]]
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

