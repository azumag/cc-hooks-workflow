#!/bin/bash

# JSON入力を読み取り、作業報告ファイルパスを取得
JSON_INPUT=$(cat)
WORK_SUMMARY_FILE_PATH=$(echo "$JSON_INPUT" | jq -r '.work_summary_file_path // empty')

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

# 作業報告の内容を読み込む
WORK_SUMMARY_CONTENT=""
if [ -n "$WORK_SUMMARY_FILE_PATH" ] && [ -f "$WORK_SUMMARY_FILE_PATH" ]; then
    WORK_SUMMARY_CONTENT=$(cat "$WORK_SUMMARY_FILE_PATH")
fi

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

## 作業報告の内容:
$WORK_SUMMARY_CONTENT
EOF
)

jq -n \
    --arg phrase "$NEXT_PHRASE" \
    --arg reason "$REASON" \
    '{decision: "block", reason: $reason}'
