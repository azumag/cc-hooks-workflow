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
