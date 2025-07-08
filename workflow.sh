#!/bin/bash
# Hooks Workflow Tool - Main orchestration script
# Claude Code のStop Hooksの起点スクリプト
# 全ての状態を管理し、各hooksスクリプトを呼び出す

set -euo pipefail

# ====================
# 設定とマッピング
# ====================

# 状態フレーズからhooksスクリプトへのマッピング
# Using case statement instead of associative array for portability
get_hook_script() {
    local state="$1"
    case "$state" in
        "NONE") echo "initial-hook.sh" ;;
        "TEST_COMPLETED") echo "test-complete-hook.sh" ;;
        "REVIEW_COMPLETED") echo "review-complete-hook.sh" ;;
        "COMMIT_COMPLETED") echo "commit-complete-hook.sh" ;;
        "PUSH_COMPLETED") echo "push-complete-hook.sh" ;;
        "BUILD_COMPLETED") echo "build-complete-hook.sh" ;;
        "IMPLEMENTATION_COMPLETED") echo "implementation-complete-hook.sh" ;;
        "STOP") echo "stop-hook.sh" ;;
        *) echo "" ;;
    esac
}

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
    
    # 最新の.jsonlファイルを探す (シンプルなls -tを使用)
    local latest_file
    latest_file=$(find "$transcript_dir" -name "*.jsonl" -type f -print0 | 
                  xargs -0 ls -t 2>/dev/null | head -1)
    
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
    
    # アシスタントメッセージのテキストを取得 (簡素化)
    local last_message
    last_message=$(jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' < "$transcript_path" | tail -n 1)
    
    if [ -z "$last_message" ]; then
        echo "NONE"
        return 0
    fi
    
    # 最新メッセージをそのまま状態として返す
    # get_hook_scriptで対応していない状態は自然に無視される
    echo "$last_message"
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
    
    # アシスタントメッセージのテキストを直接取得 (簡素化)
    if ! jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' < "$transcript_path" > "$temp_file"; then
        log_error "アシスタントメッセージの抽出に失敗しました"
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
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local hook_path="$script_dir/hooks/$hook_script"
    
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
    
    # JSON入力の準備（hookがClaude Codeから単体実行可能にするため）
    local json_input
    json_input=$(jq -n --arg work_summary_file_path "$work_summary_file" '{work_summary_file_path: $work_summary_file_path}')
    
    log_info "Hookスクリプトを実行中: $hook_script"
    
    # hookを実行し、終了コードで判定（標準的なUnix方式）
    echo "$json_input" | "$hook_path"
    
    # hookの終了コードをそのまま返す
    return $?
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
    local hook_script
    hook_script=$(get_hook_script "$state_phrase")
    
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
        log_info "Workflow完了"
        exit 0
    else
        log_info "Workflow失敗"
        exit 1
    fi
}

# スクリプトが直接実行された場合のみmainを実行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi