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
- SubAgent に Task として作業内容の厳正なレビューを行わせ,
  その結果をもとに、必要な修正を行え
- 自ら git diff やコミット確認を行なって把握せよ
- 作業完了したら $NEXT_PHRASE とは発言せず、作業報告を行うこと
- SubAgent のレビューの結果、問題がないと判断されたときのみ、 $NEXT_PHRASE とだけ発言せよ

## レビュー観点:
- YAGNI：今必要じゃない機能は作らない
- DRY：同じコードを繰り返さない
- KISS：シンプルに保つ
- t-wada TDD：テスト駆動開発
EOF
)

jq -n \
    --arg phrase "$NEXT_PHRASE" \
    --arg reason "$REASON" \
    '{decision: "block", reason: $reason}'
