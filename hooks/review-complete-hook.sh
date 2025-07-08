#!/bin/bash
# Review Complete Hook
# REVIEW_COMPLETED状態で呼び出されるhookスクリプト
# 作業報告を受け取り、レビュー完了の処理を行う

set -euo pipefail

# ====================
# ユーティリティ関数
# ====================

# ログ関数
log_info() {
    echo "INFO [review-complete-hook]: $*" >&2
}

log_error() {
    echo "ERROR [review-complete-hook]: $*" >&2
}

# JSON出力関数
output_json() {
    local decision="$1"
    local reason="$2"
    echo "{\"decision\": \"$decision\", \"reason\": \"$reason\"}"
}

# ====================
# メイン処理
# ====================

main() {
    log_info "Review Complete Hookを開始"
    
    # JSON入力を読み取る
    local input
    input=$(cat)
    
    if [ -z "$input" ]; then
        log_error "入力が空です"
        output_json "block" "Invalid JSON input"
        exit 1
    fi
    
    # JSON検証
    if ! echo "$input" | jq . >/dev/null 2>&1; then
        log_error "無効なJSON入力"
        output_json "block" "Invalid JSON input"
        exit 1
    fi
    
    # 作業報告ファイルパスを取得
    local work_summary_file_path
    work_summary_file_path=$(echo "$input" | jq -r '.work_summary_file_path')
    
    if [ "$work_summary_file_path" = "null" ] || [ -z "$work_summary_file_path" ]; then
        log_error "作業報告ファイルパスが指定されていません"
        output_json "block" "Missing work_summary_file_path"
        exit 1
    fi
    
    log_info "作業報告ファイル: $work_summary_file_path"
    
    # 作業報告ファイルの存在確認
    if [ ! -f "$work_summary_file_path" ]; then
        log_error "作業報告ファイルが見つかりません: $work_summary_file_path"
        output_json "block" "Work summary file not found"
        exit 1
    fi
    
    # 作業報告ファイルが空でないか確認
    if [ ! -s "$work_summary_file_path" ]; then
        log_error "作業報告ファイルが空です: $work_summary_file_path"
        output_json "block" "Work summary file is empty"
        exit 1
    fi
    
    # 作業報告を読み取る
    local work_summary
    if ! work_summary=$(cat "$work_summary_file_path" 2>/dev/null); then
        log_error "作業報告ファイルを読み取れません: $work_summary_file_path"
        output_json "block" "Cannot read work summary file"
        exit 1
    fi
    
    # レビューロジック
    log_info "レビューを実行中..."
    
    # 作業報告の内容をチェック（例）
    if echo "$work_summary" | grep -q "ERROR\|FAILED\|失敗"; then
        log_info "エラーキーワードが検出されました"
        output_json "block" "作業報告にエラーが含まれています"
        exit 0
    fi
    
    # デフォルトは承認
    output_json "approve" "Review completed successfully"
    exit 0
}

# スクリプトが直接実行された場合のみmainを実行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi