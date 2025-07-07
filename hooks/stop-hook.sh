#!/bin/bash
# stop-hook.sh - STOP状態のhooks (作業完了時の自動コミット・プッシュ)
# JSON入力: {"work_summary_file_path": "/path/to/file"}
# JSON出力: {"decision": "approve|block", "reason": "理由"}

set -euo pipefail

# ====================
# エラーハンドリング標準パターン
# ====================

# JSON出力パターン
output_success() {
    local reason="${1:-Hook executed successfully}"
    jq -n --arg reason "$reason" '{decision: "approve", reason: $reason}'
    exit 0
}

output_error() {
    local error_message="${1:-Unknown error occurred}"
    local solution_hint="${2:-""}"
    
    local full_message="$error_message"
    if [ -n "$solution_hint" ]; then
        full_message="$error_message. $solution_hint"
    fi
    
    jq -n --arg reason "$full_message" '{decision: "block", reason: $reason}'
    exit 1
}

# 依存関係チェック
check_dependencies() {
    local missing_deps=()
    local required_deps=("jq" "git")
    
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        local install_instructions=""
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                jq)
                    install_instructions="${install_instructions}Install jq: apt-get install jq (Ubuntu) or brew install jq (macOS)\n"
                    ;;
                git)
                    install_instructions="${install_instructions}Install git: apt-get install git (Ubuntu) or brew install git (macOS)\n"
                    ;;
                *)
                    install_instructions="${install_instructions}Install $dep\n"
                    ;;
            esac
        done
        
        output_error "Missing required dependencies: ${missing_deps[*]}" "$install_instructions"
    fi
}

# JSON入力処理パターン
read_work_summary_file_path() {
    local json_input
    json_input=$(cat) || {
        output_error "Failed to read JSON input from stdin"
    }
    
    if [ -z "$json_input" ]; then
        output_error "JSON input is empty"
    fi
    
    local work_summary_file_path
    work_summary_file_path=$(echo "$json_input" | jq -r '.work_summary_file_path // empty' 2>/dev/null) || {
        output_error "Invalid JSON format" "Check input format: {\"work_summary_file_path\": \"/path/to/file\"}"
    }
    
    if [ -z "$work_summary_file_path" ] || [ "$work_summary_file_path" = "null" ]; then
        output_error "Missing work_summary_file_path field" "Ensure JSON contains work_summary_file_path field"
    fi
    
    echo "$work_summary_file_path"
}

# ファイル操作エラーパターン
read_work_summary_safe() {
    local file_path="$1"
    
    if [ -z "$file_path" ]; then
        output_error "File path is required" "Provide valid file path as argument"
    fi
    
    if [ ! -f "$file_path" ]; then
        output_error "Work summary file not found: $file_path" "Check if file exists and path is correct"
    fi
    
    if [ ! -r "$file_path" ]; then
        output_error "Cannot read work summary file: $file_path" "Check file permissions"
    fi
    
    if [ ! -s "$file_path" ]; then
        output_error "Work summary file is empty: $file_path" "Ensure file contains valid content"
    fi
    
    cat "$file_path" || {
        output_error "Failed to read work summary file: $file_path" "Check file integrity and permissions"
    }
}

# ====================
# Git操作関数
# ====================

# 未コミットファイルの検出
detect_uncommitted_files() {
    local git_status
    git_status=$(git status --porcelain 2>/dev/null) || {
        output_error "Failed to check git status" "Ensure current directory is a git repository"
    }
    
    if [ -n "$git_status" ]; then
        return 0  # 未コミットファイルあり
    else
        return 1  # 未コミットファイルなし
    fi
}

# 自動コミット処理
auto_commit() {
    local work_summary_file="$1"
    local commit_message="Auto-commit: Work completed"
    
    # 作業報告からコミットメッセージのヒントを取得
    if [ -f "$work_summary_file" ] && [ -r "$work_summary_file" ]; then
        local summary_content
        summary_content=$(head -n 3 "$work_summary_file" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
        if [ -n "$summary_content" ]; then
            commit_message="Auto-commit: $summary_content"
        fi
    fi
    
    # すべてのファイルをステージング
    git add -A 2>/dev/null || {
        output_error "Failed to stage files for commit" "Check git repository state and file permissions"
    }
    
    # コミット実行
    git commit -m "$commit_message" 2>/dev/null || {
        output_error "Failed to commit changes" "Check git configuration (user.name, user.email) and repository state"
    }
}

# プッシュ処理
auto_push() {
    # リモートリポジトリの確認
    local remote_url
    remote_url=$(git config --get remote.origin.url 2>/dev/null) || {
        # リモートがない場合は警告して続行
        return 0
    }
    
    # 現在のブランチ名を取得
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || {
        output_error "Failed to get current branch name" "Check git repository state"
    }
    
    # プッシュ実行（失敗しても続行）
    git push origin "$current_branch" 2>/dev/null || {
        # プッシュに失敗した場合は警告して続行
        return 0
    }
}

# ====================
# 初期化とメイン処理
# ====================

# 初期化
init_hook() {
    # 依存関係チェック
    check_dependencies
    
    # デバッグモード設定
    if [ "${HOOK_DEBUG:-false}" = "true" ]; then
        echo "DEBUG: Hook debug mode enabled" >&2
        set -x
    fi
    
    # Gitリポジトリの確認
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        output_error "Current directory is not a git repository" "Initialize git repository with 'git init' or change to a git directory"
    fi
}

# メイン処理
main() {
    # 初期化
    init_hook
    
    # JSON入力処理
    local work_summary_file
    work_summary_file=$(read_work_summary_file_path)
    
    # 作業報告ファイルの検証
    read_work_summary_safe "$work_summary_file" >/dev/null
    
    # 未コミットファイルの検出
    if detect_uncommitted_files; then
        # 自動コミット
        auto_commit "$work_summary_file"
        
        # 自動プッシュ（失敗しても続行）
        auto_push
        
        # 成功メッセージ
        output_success "Auto-commit completed successfully. REVIEW_COMPLETED && PUSH_COMPLETED"
    else
        # 既にすべてコミット済み
        output_success "All files are already committed. REVIEW_COMPLETED && PUSH_COMPLETED"
    fi
}

# スクリプトが直接実行された場合のみmainを実行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi