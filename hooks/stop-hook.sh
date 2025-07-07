#!/bin/bash
# Stop Hook - Implements stop feedback principles
# Commits and pushes uncommitted files, or indicates completion if everything is pushed

set -euo pipefail

# Source shared utilities
source "$(dirname "$0")/shared-utils.sh"

# Read input JSON
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
WORK_SUMMARY_FILE=$(echo "$INPUT" | jq -r '.work_summary_file_path // ""')

# Basic validation
if [ -z "$SESSION_ID" ]; then
    safe_exit "No session ID provided" "approve"
fi

echo "[stop-hook] Executing stop hook for session: $SESSION_ID" >&2

# Check if we're in a git repository
if ! git rev-parse --git-dir &>/dev/null; then
    safe_exit "Not in a git repository" "approve"
fi

# Get git status
GIT_STATUS=$(git status --porcelain 2>/dev/null || echo "")

# Check for uncommitted changes
if [ -n "$GIT_STATUS" ]; then
    echo "[stop-hook] Found uncommitted files, proceeding to commit and push" >&2
    
    # Show what will be committed
    echo "[stop-hook] Files to be committed:" >&2
    echo "$GIT_STATUS" >&2
    
    # Add all changes
    if ! git add -A >&2; then
        safe_exit "Failed to add files to git" "block"
    fi
    
    # Create commit message
    COMMIT_MSG="Auto-commit: Update project files

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>"
    
    # Commit changes
    if ! git commit -m "$COMMIT_MSG" >&2; then
        safe_exit "Failed to commit changes" "block"
    fi
    
    echo "[stop-hook] Changes committed successfully" >&2
    
    # Check if we have a remote to push to
    if git remote &>/dev/null && [ -n "$(git remote)" ]; then
        # Get current branch
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
        
        # Push changes
        if git push origin "$CURRENT_BRANCH" >&2; then
            echo "[stop-hook] Changes pushed successfully to origin/$CURRENT_BRANCH" >&2
            safe_exit "Files committed and pushed successfully. REVIEW_COMPLETED && PUSH_COMPLETED" "approve"
        else
            echo "[stop-hook] Failed to push changes" >&2
            safe_exit "Files committed but push failed. Please push manually." "block"
        fi
    else
        echo "[stop-hook] No remote repository configured" >&2
        safe_exit "Files committed but no remote to push to. REVIEW_COMPLETED" "approve"
    fi
else
    # No uncommitted changes, check if we're ahead of remote
    if git remote &>/dev/null && [ -n "$(git remote)" ]; then
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
        
        # Fetch to get latest remote state
        if git fetch origin "$CURRENT_BRANCH" &>/dev/null; then
            # Check if we're ahead of remote
            LOCAL_COMMIT=$(git rev-parse HEAD)
            REMOTE_COMMIT=$(git rev-parse "origin/$CURRENT_BRANCH" 2>/dev/null || echo "")
            
            if [ -n "$REMOTE_COMMIT" ] && [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
                # We have local commits not yet pushed
                echo "[stop-hook] Local commits found that are not pushed" >&2
                
                if git push origin "$CURRENT_BRANCH" >&2; then
                    echo "[stop-hook] Local commits pushed successfully" >&2
                    safe_exit "Local commits pushed successfully. REVIEW_COMPLETED && PUSH_COMPLETED" "approve"
                else
                    echo "[stop-hook] Failed to push local commits" >&2
                    safe_exit "Failed to push local commits. Please push manually." "block"
                fi
            else
                # Everything is up to date
                echo "[stop-hook] All files are committed and pushed" >&2
                safe_exit "REVIEW_COMPLETED && PUSH_COMPLETED" "approve"
            fi
        else
            echo "[stop-hook] Failed to fetch remote state, assuming everything is up to date" >&2
            safe_exit "REVIEW_COMPLETED && PUSH_COMPLETED" "approve"
        fi
    else
        # No remote, but everything is committed
        echo "[stop-hook] All files are committed (no remote repository)" >&2
        safe_exit "REVIEW_COMPLETED && PUSH_COMPLETED" "approve"
    fi
fi