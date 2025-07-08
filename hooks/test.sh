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

REASON=$(cat <<EOF
test_workflow.sh を実行し、テスト完了を確認してください。
テストが正常終了した時のみ、 $NEXT_PHRASE と発言してください。
EOF
)

jq -n \
    --arg phrase "$NEXT_PHRASE" \
    --arg reason "$REASON" \
    '{decision: "block", reason: $reason}'
