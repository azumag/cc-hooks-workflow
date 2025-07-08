#!/bin/bash
set -euo pipefail

# Test array declaration - different approach
declare -A STATE_MAPPING
STATE_MAPPING["REVIEW_COMPLETED"]="review-complete-hook.sh"
STATE_MAPPING["PUSH_COMPLETED"]="push-complete-hook.sh"
STATE_MAPPING["COMMIT_COMPLETED"]="commit-complete-hook.sh"
STATE_MAPPING["TEST_COMPLETED"]="test-complete-hook.sh"
STATE_MAPPING["BUILD_COMPLETED"]="build-complete-hook.sh"
STATE_MAPPING["IMPLEMENTATION_COMPLETED"]="implementation-complete-hook.sh"
STATE_MAPPING["STOP"]="stop-hook.sh"
STATE_MAPPING["NONE"]="initial-hook.sh"

echo "Array declared successfully"
echo "STOP maps to: ${STATE_MAPPING[STOP]}"