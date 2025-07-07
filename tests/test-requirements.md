# Hooks テスト要件定義 (TDD)

## 実装対象のhooks（使用頻度調査結果）

使用頻度調査に基づき、以下3つのhooksを優先実装：

1. **initial-hook.sh** (NONE状態) - 必須
2. **review-complete-hook.sh** (R_EVIEW_COMPLETED状態) - 高頻度
3. **stop-hook.sh** (STOP状態) - 既存機能

## initial-hook.sh テストケース

### 基本機能テスト
- ✅ 有効なJSON入力で"approve"を返す
- ✅ work_summary_fileが存在する場合の処理
- ✅ 適切なJSON出力フォーマット

### エラーハンドリングテスト
- ✅ work_summary_fileが存在しない場合のエラー処理
- ✅ 無効なJSON入力でのエラー処理
- ✅ 空のJSON入力でのエラー処理

### 出力検証テスト
- ✅ exit code 0 (approve時)
- ✅ JSON形式の正確性
- ✅ decision/reasonフィールドの存在

## review-complete-hook.sh テストケース

### 基本機能テスト
- ✅ レビュー完了時の適切な処理
- ✅ 作業報告ファイルの読み取り
- ✅ 適切な承認/ブロック判定

### エラーハンドリングテスト
- ✅ 作業報告ファイルが空の場合
- ✅ ファイルアクセスエラー
- ✅ JSON形式エラー

### 出力検証テスト
- ✅ 理由メッセージの適切性
- ✅ decision値の正確性
- ✅ JSON形式の妥当性

## stop-hook.sh テストケース

### 基本機能テスト
- ✅ 未コミットファイルの検出
- ✅ 自動コミット処理
- ✅ プッシュ処理

### エラーハンドリングテスト
- ✅ Git操作失敗時の処理
- ✅ ネットワークエラー処理
- ✅ 権限エラー処理

### 出力検証テスト
- ✅ 成功時の適切なメッセージ
- ✅ 失敗時のエラーメッセージ
- ✅ JSON出力の正確性

## 共通テストパターン

### JSON入出力パターン
```bash
# 入力形式
{
  "work_summary_file_path": "/path/to/summary.txt"
}

# 出力形式
{
  "decision": "approve|block",
  "reason": "説明メッセージ"
}
```

### 依存関係テスト
- ✅ jq コマンドの存在確認
- ✅ 基本シェルコマンドの動作確認

## テストファイル構成

```
tests/
├── test-requirements.md (このファイル)
├── test_initial_hook.bats
├── test_review_complete_hook.bats
├── test_stop_hook.bats
└── fixtures/
    ├── valid_summary.txt
    ├── empty_summary.txt
    └── test_input.json
```