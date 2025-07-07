#!/bin/bash
# Shared utilities for Claude Code hooks scripts
# DRY原則に従い、全hooksで共通利用可能な機能を提供

set -euo pipefail

# ====================
# ログ機能
# ====================

# 基本ログ関数（hooks_oldから移植）
log_info() {
    echo "INFO: $*" >&2
}

log_warning() {
    echo "WARNING: $*" >&2
}

log_error() {
    echo "ERROR: $*" >&2
}

# ====================
# JSON入出力機能
# ====================

# JSON入力からwork_summary_file_pathを抽出
# Usage: work_summary_file=$(read_work_summary_file_path)
read_work_summary_file_path() {
    local json_input
    json_input=$(cat)
    
    if [ -z "$json_input" ]; then
        log_error "JSON入力が空です"
        return 1
    fi
    
    local work_summary_file_path
    if ! work_summary_file_path=$(echo "$json_input" | jq -r '.work_summary_file_path // empty'); then
        log_error "JSON入力の解析に失敗しました"
        return 1
    fi
    
    if [ -z "$work_summary_file_path" ] || [ "$work_summary_file_path" = "null" ]; then
        log_error "work_summary_file_pathが見つかりません"
        return 1
    fi
    
    echo "$work_summary_file_path"
}

# 作業報告ファイルの内容を読み取り
# Usage: work_summary=$(read_work_summary "$work_summary_file_path")
read_work_summary() {
    local work_summary_file_path="$1"
    
    if [ ! -f "$work_summary_file_path" ]; then
        log_error "作業報告ファイルが見つかりません: $work_summary_file_path"
        return 1
    fi
    
    if [ ! -s "$work_summary_file_path" ]; then
        log_error "作業報告ファイルが空です: $work_summary_file_path"
        return 1
    fi
    
    cat "$work_summary_file_path"
}

# JSON形式で結果を出力し、適切なexit codeで終了
# Usage: safe_exit "理由" "decision"
# hooks_oldから移植・改良
safe_exit() {
    local reason="${1:-Hook executed successfully}"
    local decision="${2:-approve}"
    
    # Safely escape the reason for JSON
    local escaped_reason
    escaped_reason=$(echo "$reason" | jq -Rs .)
    
    # JSON出力（workflow.shの期待する形式）
    cat <<EOF
{
  "decision": "$decision",
  "reason": $escaped_reason
}
EOF

    # Return appropriate exit code based on decision
    # - "block" decisions return exit 1 (failure)
    # - "approve" decisions return exit 0 (success)
    if [ "$decision" = "block" ]; then
        exit 1
    else
        exit 0
    fi
}

# ====================
# エラーハンドリング
# ====================

# 予期しないエラーでの安全な終了
safe_error_exit() {
    local error_message="${1:-Unexpected error occurred}"
    log_error "$error_message"
    safe_exit "$error_message" "block"
}

# 依存関係チェック
check_hook_dependencies() {
    local missing_deps=()
    local required_deps=("jq")
    
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        safe_error_exit "必要な依存関係が見つかりません: ${missing_deps[*]}"
    fi
}

# ====================
# Claude Code プロジェクト探索 (hooks_oldから移植・簡素化)
# ====================

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

# 最新のトランスクリプトファイルを探す（簡素化版）
find_latest_transcript() {
    local project_dir="$1"
    local transcript_dir="$project_dir/.claude/transcripts"
    
    if [ ! -d "$transcript_dir" ]; then
        return 1
    fi
    
    # 最新の.jsonlファイルを探す
    local latest_file
    latest_file=$(find "$transcript_dir" -name "*.jsonl" -type f -print0 | 
                  xargs -0 ls -t 2>/dev/null | head -1)
    
    if [ -n "$latest_file" ]; then
        echo "$latest_file"
        return 0
    fi
    
    return 1
}

# ====================
# 初期化とクリーンアップ
# ====================

# hooks共通の初期化処理
# Usage: init_hook (hooksスクリプトの冒頭で呼び出し)
init_hook() {
    # 依存関係チェック
    check_hook_dependencies
    
    # デバッグモード設定
    if [ "${HOOK_DEBUG:-false}" = "true" ]; then
        log_info "デバッグモードが有効です"
        set -x
    fi
}

# ====================
# よく使用されるヘルパー関数
# ====================

# 文字列が空でないかチェック
is_not_empty() {
    [ -n "${1:-}" ]
}

# ファイルが存在し読み取り可能かチェック
is_readable_file() {
    [ -f "${1:-}" ] && [ -r "${1:-}" ]
}

# ディレクトリが存在するかチェック
is_directory() {
    [ -d "${1:-}" ]
}