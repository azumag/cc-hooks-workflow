#!/bin/bash
# Hooks Workflow Tool - Main orchestration script
# Claude Code のStop Hooksの起点スクリプト
# 全ての状態を管理し、各hooksスクリプトを呼び出す

set -euo pipefail

# ====================
# 設定とマッピング
# ====================

# 作業報告ファイルパス（セッションID取得後に設定）
work_summary_tmp_dir=""
work_summary_file=""


# 状態フレーズからhooksスクリプトへのマッピング
# hookスクリプト名と次の状態フレーズオプションを直接返す
get_hook_script() {
    local state="$1"
    case "$state" in
        "TEST_COMPLETED") echo "self-review.sh --phrase=SELF_REVIEWED" ;;
        "SELF_REVIEWED") echo "commit.sh --phrase=STOP" ;;
        "STOP") echo "stop.sh" ;; # stop.shは実際には何もせずに終了する
        *) echo "test.sh --phrase=TEST_COMPLETED" ;; # 何も指定されていない状態では起点フックをよぶ
    esac
}

# 依存関係一覧
REQUIRED_DEPS=("jq" "grep" "tail" "mktemp")

# 共通のユーティリティ関数を直接実装（shared-utils.shに依存しない）

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


# 最新のトランスクリプトファイルを探す（self-contained implementation）
find_latest_transcript() {
    local transcript_dir="$HOME/.claude/projects"
    
    # ディレクトリが存在するかチェック
    if [ ! -d "$transcript_dir" ]; then
        log_error "Claude transcriptsディレクトリが見つかりません: $transcript_dir"
        return 1
    fi
    
    # .jsonlファイルが存在するかチェック
    if ! find "$transcript_dir" -name "*.jsonl" -type f -print -quit | grep -q .; then
        log_error "Claude transcriptsディレクトリに.jsonlファイルが見つかりません: $transcript_dir"
        return 2
    fi
    
    # 最新のファイルを取得（クロスプラットフォーム対応）
    local latest_file
    if stat -f "%m %N" /dev/null >/dev/null 2>&1; then
        # macOS/BSD stat
        latest_file=$(find "$transcript_dir" -name "*.jsonl" -type f -exec stat -f "%m %N" {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    else
        # GNU stat (Linux)
        latest_file=$(find "$transcript_dir" -name "*.jsonl" -type f -exec stat -c "%Y %n" {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    fi
    
    if [ -n "$latest_file" ] && [ -f "$latest_file" ]; then
        echo "$latest_file"
        return 0
    else
        log_error "Claude transcriptsファイルへのアクセス中にエラーが発生しました: $transcript_dir"
        return 3
    fi
}

# セッションIDを取得してwork_summary_file_pathを設定
setup_work_summary_paths() {
    local transcript_path="$1"
    
    # セッションIDをファイル名から抽出（シンプル化）
    local session_id
    session_id=$(basename "$transcript_path" .jsonl)
    
    # 簡単な検証とフォールバック
    if [[ ! "$session_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        session_id="unknown"
    fi
    
    # グローバル変数に設定（/tmp/claude/の下にセッションIDディレクトリを作成）
    work_summary_tmp_dir="/tmp/claude/$session_id"
    work_summary_file="$work_summary_tmp_dir/work_summary.txt"
}

# 共通のアシスタントメッセージ抽出関数
extract_assistant_text() {
    local transcript_path="$1"
    
    if [ ! -f "$transcript_path" ]; then
        return 1
    fi
    
    # 最新のアシスタントメッセージの完全なテキストを取得（改行を含む）
    # JSONL形式なので、最後のアシスタントメッセージを正しく抽出
    local last_assistant_line=$(grep '"type":"assistant"' "$transcript_path" | tail -n 1)
    if [ -n "$last_assistant_line" ]; then
        echo "$last_assistant_line" | jq -r '.message.content[]? | select(.type == "text") | .text'
    fi
}

# 最新のアシスタントメッセージから状態フレーズを抽出
extract_state_phrase() {
    local transcript_path="$1"
    
    # 共通関数を使用して最新メッセージを取得
    extract_assistant_text "$transcript_path"
}

# 作業報告をセッション固有のパスに保存
save_work_summary() {
    local transcript_path="$1"
   
    # セッション固有のディレクトリを作成
    mkdir -p "$work_summary_tmp_dir"
    
    # 共通関数を使用して最後のアシスタントメッセージを取得
    if ! extract_assistant_text "$transcript_path" > "$work_summary_file"; then
        log_error "アシスタントメッセージの抽出に失敗しました"
        return 1
    fi
    
    # 作業報告ファイルが空でないことを確認
    if [ ! -s "$work_summary_file" ]; then
        log_error "作業報告が空です"
        return 1
    fi

    echo "$work_summary_file"
}


# hooksスクリプトの実行
execute_hook() {
    local hook_command="$1"  # "hook.sh --phrase=XXX" 形式のコマンド
    local work_summary_file="$2"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # コマンドからスクリプト名を抽出
    local hook_script="${hook_command%% *}"
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
    
    log_info "Hookコマンドを実行中: $hook_command"
    
    # hookを実行し、終了コードで判定（標準的なUnix方式）
    # パイプラインの終了コードを確実に取得するため、変数に保存
    local hook_exit_code
    # コマンドを安全に実行
    # hook_commandからオプションを抽出
    local hook_options="${hook_command#* }"
    if [ "$hook_options" = "$hook_command" ]; then
        # オプションがない場合
        echo "$json_input" | "$hook_path"
    else
        # オプションがある場合
        echo "$json_input" | "$hook_path" $hook_options
    fi
    hook_exit_code=${PIPESTATUS[1]}
    
    # hookの終了コードを明示的に返す
    return $hook_exit_code
}

# ====================
# メイン処理
# ====================

main() {
    log_info "Workflow開始"
    
    # 依存関係チェック
    check_dependencies
    
    # 最新のトランスクリプトファイルを探す
    local transcript_path
    if ! transcript_path=$(find_latest_transcript); then
        log_error "トランスクリプトファイルが見つかりません"
        exit 1
    fi
    
    log_info "トランスクリプトファイル: $transcript_path"
    
    # セッションIDを取得してwork_summary_file_pathを設定
    setup_work_summary_paths "$transcript_path"
    
    # 状態フレーズを抽出
    local state_phrase
    if ! state_phrase=$(extract_state_phrase "$transcript_path"); then
        log_error "状態フレーズの抽出に失敗しました"
        exit 1
    fi
    
    log_info "検出された状態: $state_phrase"
    
    # 状態に対応するhooksコマンドを決定
    local hook_command
    hook_command=$(get_hook_script "$state_phrase")
    
    if [ -z "$hook_command" ]; then
        # 定義していない状態フレーズの場合は、エラーではない。
        # 純粋にフックを設定していないだけなので、正常終了する。
        exit 0
    fi
    
    log_info "実行するhookコマンド: $hook_command"
    
    # 状態フレーズが指定されていない場合（デフォルトケース）を判定
    # get_hook_scriptのデフォルトケース（test.sh）と一致するかで判定
    local default_hook_command
    default_hook_command=$(get_hook_script "")
    
    if [ "$hook_command" = "$default_hook_command" ]; then
        # 状態フレーズが指定されていない場合のみ作業報告を保存
        if ! work_summary_file=$(save_work_summary "$transcript_path"); then
            log_error "作業報告の保存に失敗しました"
            exit 1
        fi
        log_info "新しい作業報告ファイルを作成: $work_summary_file"
    fi
   
    # hooksスクリプトを実行
    if execute_hook "$hook_command" "$work_summary_file"; then
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