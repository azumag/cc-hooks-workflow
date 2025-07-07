#!/bin/bash
# Hooks Workflow Tool - Main orchestration script
# Claude Code のStop Hooksの起点スクリプト
# 全ての状態を管理し、各hooksスクリプトを呼び出す

set -euo pipefail

# ====================
# 設定とマッピング
# ====================

# 状態フレーズからhooksスクリプトへのマッピング
declare -A STATE_MAPPING=(
    ["REVIEW_COMPLETED"]="review-complete-hook.sh"
    ["PUSH_COMPLETED"]="push-complete-hook.sh"
    ["COMMIT_COMPLETED"]="commit-complete-hook.sh"
    ["TEST_COMPLETED"]="test-complete-hook.sh"
    ["BUILD_COMPLETED"]="build-complete-hook.sh"
    ["IMPLEMENTATION_COMPLETED"]="implementation-complete-hook.sh"
    ["STOP"]="stop-hook.sh"
    ["NONE"]="initial-hook.sh"
)

# 依存関係一覧
REQUIRED_DEPS=("jq" "grep" "tail" "mktemp")

# ====================
# ユーティリティ関数
# ====================

# ログ関数
log_info() {
    echo "INFO: $*" >&2
}

log_warning() {
    echo "WARNING: $*" >&2
}

log_error() {
    echo "ERROR: $*" >&2
}

# 依存関係チェック
check_dependencies() {
    local missing_deps=()
    
    for dep in "${REQUIRED_DEPS[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "以下の依存関係が見つかりません: ${missing_deps[*]}"
        log_error "インストールしてから再実行してください"
        exit 1
    fi
}

# Claude Code のプロジェクトディレクトリを探す
find_claude_project_dir() {
    local current_dir="$PWD"
    while [ "$current_dir" != "/" ]; do
        if [ -f "$current_dir/.claude/session.json" ]; then
            echo "$current_dir"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    return 1
}

# 最新のトランスクリプトファイルを探す
find_latest_transcript() {
    local project_dir="$1"
    local transcript_dir="$project_dir/.claude/transcripts"
    
    if [ ! -d "$transcript_dir" ]; then
        return 1
    fi
    
    # 最新の.jsonlファイルを探す
    local latest_file
    latest_file=$(find "$transcript_dir" -name "*.jsonl" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$latest_file" ]; then
        echo "$latest_file"
        return 0
    fi
    
    return 1
}

# 最新のアシスタントメッセージから状態フレーズを抽出
extract_state_phrase() {
    local transcript_path="$1"
    
    if [ ! -f "$transcript_path" ]; then
        return 1
    fi
    
    # 最新のアシスタントメッセージの最後の行を取得
    local last_message
    last_message=$(jq -r 'select(.type == "assistant" and (.message.content[]? | select(.type == "text"))) | .message.content[] | select(.type == "text") | .text' < "$transcript_path" | tail -n 1)
    
    if [ -z "$last_message" ]; then
        return 1
    fi
    
    # 状態フレーズをチェック
    for state in "${!STATE_MAPPING[@]}"; do
        if echo "$last_message" | grep -q "^$state$"; then
            echo "$state"
            return 0
        fi
    done
    
    # 状態フレーズが見つからない場合
    echo "NONE"
    return 0
}

# 作業報告を一時ファイルに保存
save_work_summary() {
    local transcript_path="$1"
    local temp_file
    temp_file=$(mktemp /tmp/work_summary_XXXXXX.txt)
    
    if [ ! -f "$transcript_path" ]; then
        log_error "トランスクリプトファイルが見つかりません: $transcript_path"
        rm -f "$temp_file"
        return 1
    fi
    
    # 最新のアシスタントメッセージの全内容を取得
    local last_text_uuid
    last_text_uuid=$(jq -r 'select(.type == "assistant" and (.message.content[]? | select(.type == "text"))) | .uuid' < "$transcript_path" | tail -1)
    
    if [ -n "$last_text_uuid" ]; then
        if ! jq -r --arg uuid "$last_text_uuid" 'select(.type == "assistant" and .uuid == $uuid) | .message.content[] | select(.type == "text") | .text' < "$transcript_path" > "$temp_file"; then
            log_error "アシスタントメッセージの抽出に失敗しました"
            rm -f "$temp_file"
            return 1
        fi
    else
        log_error "アシスタントメッセージが見つかりません"
        rm -f "$temp_file"
        return 1
    fi
    
    # 作業報告ファイルが空でないことを確認
    if [ ! -s "$temp_file" ]; then
        log_error "作業報告が空です"
        rm -f "$temp_file"
        return 1
    fi
    
    echo "$temp_file"
}

# hooksスクリプトの実行
execute_hook() {
    local hook_script="$1"
    local work_summary_file="$2"
    local hook_path="./hooks/$hook_script"
    
    # スクリプトの存在確認
    if [ ! -f "$hook_path" ]; then
        log_error "Hookスクリプトが見つかりません: $hook_path"
        return 1
    fi
    
    # 実行権限の確認
    if [ ! -x "$hook_path" ]; then
        log_error "Hookスクリプトに実行権限がありません: $hook_path"
        return 1
    fi
    
    # JSON入力の準備
    local json_input
    json_input=$(jq -n --arg work_summary_file_path "$work_summary_file" '{work_summary_file_path: $work_summary_file_path}')
    
    log_info "Hookスクリプトを実行中: $hook_script"
    
    local hook_output
    local hook_exit_code
    local temp_stderr_file
    
    # stderrを一時ファイルにリダイレクトし、stdoutのみをキャプチャ
    temp_stderr_file=$(mktemp /tmp/hook_stderr_XXXXXX.log)
    hook_output=$(echo "$json_input" | "$hook_path" 2>"$temp_stderr_file")
    hook_exit_code=$?
    
    local hook_stderr
    hook_stderr=$(cat "$temp_stderr_file")
    rm -f "$temp_stderr_file"
    
    if [ -n "$hook_stderr" ]; then
        log_warning "HookスクリプトからのSTDERR出力: $hook_script"
        echo "$hook_stderr" >&2
    fi
    
    # JSON出力の検証
    if ! echo "$hook_output" | jq . >/dev/null 2>&1; then
        log_error "Hookスクリプトから無効なJSON出力: $hook_script"
        log_error "出力: $hook_output"
        if [ -n "$hook_stderr" ]; then
            log_error "STDERR: $hook_stderr"
        fi
        return 1
    fi
    
    # decision フィールドの処理
    local decision
    decision=$(echo "$hook_output" | jq -r '.decision // "approve"')
    
    local reason
    reason=$(echo "$hook_output" | jq -r '.reason // "処理完了"')
    
    log_info "Hook決定: $decision"
    log_info "理由: $reason"
    
    # blockの場合は1で終了、approveの場合は0で終了
    if [ "$decision" = "block" ]; then
        echo "$reason"
        return 1
    fi
    
    return 0
}

# ====================
# メイン処理
# ====================

main() {
    log_info "Workflow開始"
    
    # 依存関係チェック
    check_dependencies
    
    # Claude Codeプロジェクトディレクトリを探す
    local project_dir
    if ! project_dir=$(find_claude_project_dir); then
        log_error "Claude Codeプロジェクトディレクトリが見つかりません"
        exit 1
    fi
    
    log_info "プロジェクトディレクトリ: $project_dir"
    
    # 最新のトランスクリプトファイルを探す
    local transcript_path
    if ! transcript_path=$(find_latest_transcript "$project_dir"); then
        log_error "トランスクリプトファイルが見つかりません"
        exit 1
    fi
    
    log_info "トランスクリプトファイル: $transcript_path"
    
    # 状態フレーズを抽出
    local state_phrase
    if ! state_phrase=$(extract_state_phrase "$transcript_path"); then
        log_error "状態フレーズの抽出に失敗しました"
        exit 1
    fi
    
    log_info "検出された状態: $state_phrase"
    
    # 状態に対応するhooksスクリプトを決定
    local hook_script="${STATE_MAPPING[$state_phrase]:-}"
    
    if [ -z "$hook_script" ]; then
        log_error "未知の状態フレーズ: $state_phrase"
        exit 1
    fi
    
    log_info "実行するhook: $hook_script"
    
    # 作業報告を一時ファイルに保存
    local work_summary_file
    if ! work_summary_file=$(save_work_summary "$transcript_path"); then
        log_error "作業報告の保存に失敗しました"
        exit 1
    fi
    
    # cleanup function
    cleanup() {
        if [ -f "$work_summary_file" ]; then
            rm -f "$work_summary_file"
        fi
    }
    trap cleanup EXIT
    
    # hooksスクリプトを実行
    if execute_hook "$hook_script" "$work_summary_file"; then
        log_info "Workflow完了 (承認)"
        exit 0
    else
        log_info "Workflow完了 (ブロック)"
        exit 1
    fi
}

# スクリプトが直接実行された場合のみmainを実行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi