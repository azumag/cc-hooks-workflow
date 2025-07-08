#!/bin/bash
# review-complete-hook.sh - REVIEW_COMPLETED状態のhooks (レビュー完了時)
# JSON入力: {"work_summary_file_path": "/path/to/file"}
# 終了コード: 0=成功, 1=失敗

# エラーハンドリング関数
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# 依存関係チェック
if ! command -v jq >/dev/null 2>&1; then
    error_exit "Missing required dependency: jq."
fi

# JSON入力を読み取り
json_input=$(cat)

# work_summary_file_pathを抽出
work_summary_file_path=$(echo "$json_input" | jq -r '.work_summary_file_path // ""' 2>/dev/null)

# jqのパースエラーをチェック
if [ $? -ne 0 ]; then
    error_exit "Invalid JSON input. Ensure input is valid JSON"
fi

# 基本的な検証
if [ -z "$work_summary_file_path" ]; then
    error_exit "Missing work_summary_file_path field. Ensure JSON contains work_summary_file_path field"
fi

# ファイルの存在確認
if [ ! -f "$work_summary_file_path" ]; then
    error_exit "Work summary file not found: $work_summary_file_path. Check if file exists and path is correct"
fi

# ファイルが読み取り可能かチェック
if [ ! -r "$work_summary_file_path" ]; then
    error_exit "Cannot read work summary file: $work_summary_file_path. Check file permissions"
fi

# ファイルが空でないことを確認
if [ ! -s "$work_summary_file_path" ]; then
    error_exit "Work summary file is empty: $work_summary_file_path. Ensure file contains valid content"
fi

# レビュー完了フックは基本的に承認
# ファイルが存在し、読み取り可能で、空でないことは既に確認済み
echo "INFO: Review completed successfully"
exit 0
