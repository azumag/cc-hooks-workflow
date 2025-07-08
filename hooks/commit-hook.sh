#!/bin/bash
# commit-hook.sh - TEST_COMPLETED後のコミット処理フック

# --phraseオプションの処理
NEXT_PHRASE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --phrase=*)
            NEXT_PHRASE="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# エラーハンドリング関数
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# 依存関係チェック
if ! command -v jq >/dev/null 2>&1; then
    error_exit "Missing required dependency: jq."
fi

if ! command -v git >/dev/null 2>&1; then
    error_exit "Missing required dependency: git."
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

# Claudeに指示を送る
if [ -n "$NEXT_PHRASE" ]; then
    echo "変更をコミットしてください。コミットが完了したら、${NEXT_PHRASE}と発言してください。" >&2
else
    echo "変更をコミットしてください。" >&2
fi

# 終了コード1で失敗を示す（Claudeに行動を促すため）
exit 1