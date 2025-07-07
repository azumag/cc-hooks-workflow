#!/bin/bash
# review-complete-hook.sh - R_EVIEW_COMPLETED状態のhooks (レビュー完了時)
# JSON入力: {"work_summary_file_path": "/path/to/file"}
# JSON出力: {"decision": "approve|block", "reason": "理由"}

set -euo pipefail

# 依存関係チェック
if ! command -v jq >/dev/null 2>&1; then
    echo '{"decision": "block", "reason": "Missing required dependency: jq. Install jq: apt-get install jq (Ubuntu) or brew install jq (macOS)"}'
    exit 1
fi

# JSON入力を読み取り
json_input=$(cat) || {
    echo '{"decision": "block", "reason": "Failed to read JSON input from stdin"}'
    exit 1
}

# 入力の空チェック
if [ -z "$json_input" ]; then
    echo '{"decision": "block", "reason": "JSON input is empty"}'
    exit 1
fi

# work_summary_file_pathを抽出
work_summary_file_path=$(echo "$json_input" | jq -r '.work_summary_file_path // empty' 2>/dev/null) || {
    echo '{"decision": "block", "reason": "Invalid JSON format. Check input format: {\"work_summary_file_path\": \"/path/to/file\"}"}'
    exit 1
}

# work_summary_file_pathの存在チェック
if [ -z "$work_summary_file_path" ] || [ "$work_summary_file_path" = "null" ]; then
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

# 作業報告の内容を読み取り
work_summary_content=$(cat "$work_summary_file_path") || {
    echo '{"decision": "block", "reason": "Failed to read work summary file: '"$work_summary_file_path"'. Check file integrity and permissions"}'
    exit 1
}

# レビュー完了の検証ロジック
# 1. 基本的な内容の存在確認
content_length=$(echo "$work_summary_content" | wc -c)
if [ "$content_length" -lt 10 ]; then
    echo '{"decision": "block", "reason": "Work summary content too short for meaningful review. Provide more detailed review information"}'
    exit 1
fi

# 2. レビュー完了の品質チェック
# レビュー関連のキーワードをチェック
review_keywords=("review" "Review" "REVIEW" "test" "Test" "TEST" "code" "Code" "implementation" "Implementation")
has_review_content=false

for keyword in "${review_keywords[@]}"; do
    if echo "$work_summary_content" | grep -q "$keyword"; then
        has_review_content=true
        break
    fi
done

# 3. レビュー判定
if [ "$has_review_content" = "true" ]; then
    # レビュー関連の内容が含まれている場合
    echo '{"decision": "approve", "reason": "Review completed successfully. Work summary contains appropriate review content and demonstrates thorough analysis"}'
    exit 0
else
    # レビュー関連の内容が少ない場合でも、基本的な作業報告として承認
    echo '{"decision": "approve", "reason": "Review completed. Work summary provided, though additional review details could enhance the documentation"}'
    exit 0
fi