#!/bin/bash
# Push Complete Hook
# PUSH_COMPLETED状態で呼び出されるhookスクリプト

set -euo pipefail

# JSON入力を読み取る
input=$(cat)

# JSON検証
if [ -z "$input" ] || ! echo "$input" | jq . >/dev/null 2>&1; then
    echo '{"decision": "block", "reason": "Invalid JSON input"}'
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

# Push complete処理（プッシュ後の処理をここに実装）
echo '{"decision": "approve", "reason": "Push completed successfully"}'
exit 0