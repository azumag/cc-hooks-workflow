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

# JSON設定ファイルのパス
CONFIG_FILE=".claude/workflow.json"

# JSON設定を読み込む関数
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        log_warning "設定ファイルが見つかりません: $CONFIG_FILE"
        echo "no config found: $CONFIG_FILE" >&2
        exit 1
    fi
}

# 状態フレーズからhook設定を取得する関数
# JSON設定からhook情報を返す（JSON形式）
get_hook_config() {
    local state="$1"
    local config
    config=$(load_config)
    
    # 状態に対応するhook設定を検索
    # まず指定されたstateに対応するhook設定を探す
    local hook_config
    hook_config=$(echo "$config" | jq -r --arg state "$state" '.hooks[] | select(.launch == $state)' 2>/dev/null)
    
    # 該当するstateが見つからない場合は、launchがnullのエントリ（デフォルト）を探す
    if [ -z "$hook_config" ] || [ "$hook_config" = "{}" ]; then
        hook_config=$(echo "$config" | jq -r '.hooks[] | select(.launch == null)' 2>/dev/null)
    fi
    
    # 結果を出力（何も見つからない場合は空のオブジェクト）
    if [ -n "$hook_config" ] && [ "$hook_config" != "{}" ]; then
        echo "$hook_config"
    else
        echo "{}"
    fi
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


# promptタイプのhookを実行（Claude Codeにプロンプトを渡す）
execute_prompt_hook() {
    local prompt="$1"
    local work_summary_file="$2"
    
    log_info "プロンプトフックを実行中"
    
    # $WORK_SUMMARYを作業報告の内容に置換
    if [[ "$prompt" == *'$WORK_SUMMARY'* ]] && [ -f "$work_summary_file" ]; then
        local work_summary_content
        work_summary_content=$(cat "$work_summary_file")
        prompt="${prompt//\$WORK_SUMMARY/$work_summary_content}"
    fi

    jq -n \
        --arg reason "$prompt" \
        '{decision: "block", reason: $reason}'
}

# pathタイプのhookを実行（従来のスクリプト実行）
execute_path_hook() {
    local hook_path="$1"
    local work_summary_file="$2"
    local next_phrase="$3"
    local handling="$4"
    local hook_config="$5"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 相対パスの場合はスクリプトディレクトリを基準にする
    if [[ ! "$hook_path" = /* ]]; then
        hook_path="$script_dir/$hook_path"
    fi
    
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
    
    # argsの処理
    local args=()
    if [ -n "$hook_config" ]; then
        # JSONの妥当性チェック
        if ! echo "$hook_config" | jq empty 2>/dev/null; then
            log_error "不正なJSON形式のhook_config"
            return 1
        fi
        
        # mapfileの代わりにwhileループを使用（古いbashとの互換性のため）
        while IFS= read -r line; do
            args+=("$line")
        done < <(echo "$hook_config" | jq -r '.args[]? // empty' 2>/dev/null)
        
        # 引数の検証（危険な文字のチェック）
        for arg in ${args[@]+"${args[@]}"}; do
            if [[ "$arg" =~ [\;\|\&\$\`] ]]; then
                log_error "危険な文字が含まれています: $arg"
                return 1
            fi
        done
    fi
    
    log_info "Hookスクリプトを実行中: $hook_path"
    
    local hook_exit_code
    # 標準エラーを一時ファイルにリダイレクトして取得
    local hook_stderr_file
    hook_stderr_file=$(mktemp)
    echo "$json_input" | "$hook_path" ${args[@]+"${args[@]}"} 2> "$hook_stderr_file"
    hook_exit_code=${PIPESTATUS[1]}
    hook_stderr=$(cat "$hook_stderr_file")
    rm -f "$hook_stderr_file"
    
    # handlingに応じた処理
    case "$handling" in
        "block")
            # エラーの場合はdecision block JSONを出力してexit 1
            if [ $hook_exit_code -ne 0 ]; then
                log_error "Hook実行失敗（block設定）: $hook_path"
                # decision block JSONをClaudeに通知
                # TODO: 標準エラーを受け取って、reasonに設定
                # 標準エラー出力を取得してreasonに含める
                jq -n --arg reason $hook_stderr '{decision: "block", reason: $reason}'
                exit 1
                
            fi
            ;;
        "raise")
            # エラーメッセージを標準エラー出力に表示してexit 1
            if [ $hook_exit_code -ne 0 ]; then
                log_error "Hook実行失敗（raise設定）: $hook_path"
                # TODO: 標準エラーを出力して exit1
                echo $hook_stderr >&2
                exit 1
            fi
            ;;
        "pass"|*)
            # エラーでも正常終了（exit 0）
            if [ $hook_exit_code -ne 0 ]; then
                log_warning "Hook実行失敗（pass設定）: $hook_path - エラーを無視します"
            fi
            exit 0
            ;;
    esac
    
    # hookが成功した場合、nextフレーズが指定されていれば、
    # next フレーズを表示することをClaudeに通知するため、
    # decision block JSONを出力
    if [ $hook_exit_code -eq 0 ]; then
        if [ -n "$next_phrase" ]; then
            jq -n --arg reason "$next_phrase と表示せよ" '{decision: "block", reason: $reason}'
        else
            # nextフレーズが指定されていない場合は、何も出力しない
            # そのまま正常終了
            exit 0
        fi
    fi

    return 0
}

# hook設定に基づいてhookを実行
execute_hook() {
    local hook_config="$1"
    local work_summary_file="$2"
    
    # hook設定が空の場合は何もしない
    if [ -z "$hook_config" ] || [ "$hook_config" = "{}" ]; then
        return 0
    fi
    
    # hook設定からタイプを判定
    local prompt
    prompt=$(echo "$hook_config" | jq -r '.prompt // empty')
    local path
    path=$(echo "$hook_config" | jq -r '.path // empty')
    local next
    next=$(echo "$hook_config" | jq -r '.next // empty')
    local handling
    handling=$(echo "$hook_config" | jq -r '.handling // "pass"')
    
    if [ -n "$prompt" ]; then
        # promptタイプのhook
        execute_prompt_hook "$prompt" "$work_summary_file"
    elif [ -n "$path" ]; then
        # pathタイプのhook
        execute_path_hook "$path" "$work_summary_file" "$next" "$handling" "$hook_config"
    else
        log_warning "hook設定にpromptもpathも指定されていません"
        return 0
    fi
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
    
    # 状態に対応するhook設定を取得
    local hook_config
    hook_config=$(get_hook_config "$state_phrase")
    
    if [ -z "$hook_config" ] || [ "$hook_config" = "{}" ]; then
        # 定義していない状態フレーズの場合は、エラーではない。
        # 純粋にフックを設定していないだけなので、正常終了する。
        log_info "状態 '$state_phrase' に対応するフックが設定されていません"
        exit 0
    fi
    
    log_info "実行するhook設定: $(echo "$hook_config" | jq -c '.')"
    
    # launchがnullの場合（初回実行）のみ作業報告を保存
    local launch
    launch=$(echo "$hook_config" | jq -r '.launch // empty')
    
    if [ -z "$launch" ] || [ "$launch" = "null" ]; then
        # 状態フレーズが指定されていない場合のみ作業報告を保存
        if ! work_summary_file=$(save_work_summary "$transcript_path"); then
            log_error "作業報告の保存に失敗しました"
            exit 1
        fi
        log_info "新しい作業報告ファイルを作成: $work_summary_file"
    fi
   
    # hook設定に基づいてhookを実行
    if execute_hook "$hook_config" "$work_summary_file"; then
        log_info "Workflow完了"
        exit 0
    else
        log_info "Workflow失敗"
        exit 1
    fi
}

# --stop オプションが渡された場合は即座に終了
if [ "${1:-}" = "--stop" ]; then
    exit 0
fi

# スクリプトが直接実行された場合のみmainを実行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi