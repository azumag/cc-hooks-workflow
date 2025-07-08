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

REASON="コミットを行う前に、作業内容を確認してください。作業内容を確認し、必要な変更を行った後、コミットを実行してください。コミットメッセージには、作業内容の要約を含めてください。コミットが完了したら、 $NEXT_PHRASE と発言してください。"

jq -n \
    --arg phrase "$NEXT_PHRASE" \
    --arg reason "$REASON" \
    '{decision: "block", reason: $reason}'
