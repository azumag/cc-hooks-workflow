#!/bin/bash
# test.sh - テスト実行スクリプト
# このスクリプトは直接実行用で、hook経由では呼ばれません

echo "テストを実行中..."

# 基本的なテストを実行
if [ -f "./tests/test_workflow.sh" ]; then
    echo "workflow基本テストを実行します"
    ./tests/test_workflow.sh
else
    echo "テストファイルが見つかりません"
    exit 1
fi

# batsテストがある場合は実行
if command -v bats >/dev/null 2>&1; then
    echo ""
    echo "統合テストを実行します"
    if [ -f "./tests/test_integration.bats" ]; then
        bats ./tests/test_integration.bats
    fi
    
    echo ""
    echo "hookテストを実行します"
    if [ -f "./tests/test_review_complete_hook.bats" ]; then
        bats ./tests/test_review_complete_hook.bats
    fi
else
    echo "batsがインストールされていないため、統合テストをスキップします"
fi

echo ""
echo "すべてのテストが完了しました"
echo "TEST_COMPLETED"