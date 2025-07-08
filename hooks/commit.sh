#!/bin/bash

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

# 正しいJSON出力
jq -n \
    --arg phrase "$NEXT_PHRASE" \
    --arg reason "コミットを行う前に、作業内容を確認してください。作業内容を確認し、必要な変更を行った後、コミットを実行してください。コミットメッセージには、作業内容の要約を含めてください。コミットが完了したら、\($phrase)と発言してください。" \
    '{decision: "block", reason: $reason}'
