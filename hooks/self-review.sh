#!/bin/bash

set -euo pipefail

# JSON入力を読み取る
input=$(cat)

# JSON検証
if [ -z "$input" ] || ! echo "$input" | jq . >/dev/null 2>&1; then
    echo "Invalid JSON input" >&2
    exit 1
fi

# 作業報告ファイルパスを取得
work_summary_file_path=$(echo "$input" | jq -r '.work_summary_file_path')

if [ "$work_summary_file_path" = "null" ] || [ -z "$work_summary_file_path" ]; then
    echo '{"decision": "block", "reason": "Missing work_summary_file_path"}'
    exit 1
fi

# ファイルが存在し、空でないことを確認
if [ ! -f "$work_summary_file_path" ] || [ ! -s "$work_summary_file_path" ]; then
    echo '{"decision": "block", "reason": "Work summary file not found or empty"}'
    exit 1
fi

# Self-review complete処理
echo '{"decision": "approve", "reason": "Self-review completed successfully"}'
exit 0