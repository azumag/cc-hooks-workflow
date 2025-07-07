#!/bin/bash
# Simple test script for workflow.sh

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TEST_DIR")"
WORKFLOW_SCRIPT="$PROJECT_DIR/workflow.sh"

# Test: Check if workflow.sh exists and is executable
echo "Testing workflow.sh existence and permissions..."
if [ -f "$WORKFLOW_SCRIPT" ] && [ -x "$WORKFLOW_SCRIPT" ]; then
    echo "✅ workflow.sh exists and is executable"
else
    echo "❌ workflow.sh does not exist or is not executable"
    exit 1
fi

# Test: Check dependencies
echo "Testing dependencies..."
MISSING_DEPS=""
for dep in jq grep tail mktemp; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        MISSING_DEPS="$MISSING_DEPS $dep"
    fi
done

if [ -z "$MISSING_DEPS" ]; then
    echo "✅ All dependencies are available"
else
    echo "⚠️  Missing dependencies:$MISSING_DEPS"
fi

# Test: Source workflow functions
echo "Testing workflow functions sourcing..."
if source "$WORKFLOW_SCRIPT" 2>/dev/null; then
    echo "✅ workflow.sh functions can be sourced"
else
    echo "❌ Failed to source workflow.sh functions"
    exit 1
fi

echo ""
echo "🎉 All basic tests passed!"