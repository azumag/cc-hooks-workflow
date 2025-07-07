#!/bin/bash
# initial-hook.sh - NONE状態のhooks (最初の実行時)
# JSON入力: {"work_summary_file_path": "/path/to/file"}
# JSON出力: {"decision": "approve|block", "reason": "理由"}

# 依存関係チェック
if ! command -v jq >/dev/null 2>&1; then
    echo '{"decision": "block", "reason": "Missing required dependency: jq."}'
    exit 1
fi

# JSON入力を読み取り
json_input=$(cat)

# work_summary_file_pathを抽出
work_summary_file_path=$(echo "$json_input" | jq -r '.work_summary_file_path // ""' 2>/dev/null)

# jqのパースエラーをチェック
if [ $? -ne 0 ]; then
    echo '{"decision": "block", "reason": "Invalid JSON input. Ensure input is valid JSON"}'
    exit 1
fi

# 基本的な検証
if [ -z "$work_summary_file_path" ]; then
    echo '{"decision": "block", "reason": "Missing work_summary_file_path field. Ensure JSON contains work_summary_file_path field"}'
    exit 1
fi

# ファイルの存在確認
if [ ! -f "$work_summary_file_path" ]; then
    echo '{"decision": "block", "reason": "Work summary file not found: '"$work_summary_file_path"'. Check if file exists and path is correct"}'
    exit 1
fi

# ファイルが読み取り可能かチェック
if [ ! -r "$work_summary_file_path" ]; then
    echo '{"decision": "block", "reason": "Cannot read work summary file: '"$work_summary_file_path"'. Check file permissions"}'
    exit 1
fi

# ファイルが空でないことを確認
if [ ! -s "$work_summary_file_path" ]; then
    echo '{"decision": "block", "reason": "Work summary file is empty: '"$work_summary_file_path"'. Ensure file contains valid content"}'
    exit 1
fi

# 成功時の出力
echo '{"decision": "approve", "reason": "Initial hook executed successfully"}'
exit 0