# Claude Code Hooks Workflow

Claude Code の Stop Hooks 機能を使用して、自動化されたワークフローを実行するためのツールです。

## 概要

このツールは、Claude Code のセッション終了時にトリガーされるフックを使用して、テスト実行、コードレビュー、コミット、終了処理などのワークフローを自動化します。

## 基本的な使用方法

### 1. 設定ファイルの作成

プロジェクトルートに `.claude/workflow.json` ファイルを作成します：

```json
{
  "hooks": [
    {
      "launch": null,
      "prompt": "npm test を実行せよ。テストがエラーなく完了したら TEST_COMPLETED とだけ表示せよ。"
    },
    {
      "launch": "TEST_COMPLETED",
      "path": "self-review.sh",
      "next": "SELF_REVIEWED",
      "handling": "pass"
    },
    {
      "launch": "SELF_REVIEWED",
      "path": "commit.sh",
      "next": "STOP",
      "handling": "pass"
    },
    {
      "launch": "STOP",
      "path": "stop.sh",
      "next": null,
      "handling": "pass"
    }
  ]
}
```

### 2. workflow.shの配置

`workflow.sh` を実行可能にして、Claude Code の Stop Hooks として設定します：

```bash
chmod +x workflow.sh
```

### 3. 使用開始

Claude Code でセッションを終了すると、設定されたワークフローが自動的に実行されます。

## 設定ファイルの詳細

### フック設定の構造

各フックは以下の要素で構成されます：

- `launch`: フックをトリガーする状態フレーズ（nullの場合は初回実行）
- `prompt`: Claude Code に渡すプロンプト（promptタイプフック）
- `path`: 実行するスクリプトのパス（pathタイプフック）
- `next`: 次の状態フレーズ（スクリプト成功時に出力）
- `handling`: エラーハンドリングモード（"pass", "block", "raise"）

### フックタイプ

#### 1. promptタイプフック

```json
{
  "launch": null,
  "prompt": "テストを実行してください。完了したら TEST_COMPLETED と表示してください。"
}
```

- Claude Code に直接プロンプトを送信
- $WORK_SUMMARY を使用して作業内容を参照可能

#### 2. pathタイプフック

```json
{
  "launch": "TEST_COMPLETED",
  "path": "self-review.sh",
  "next": "SELF_REVIEWED",
  "handling": "pass"
}
```

- 指定されたスクリプトを実行
- hooks/ ディレクトリ内のスクリプトを参照
- 絶対パスでの指定も可能

## エラーハンドリングモード

### 1. pass（デフォルト）
- スクリプトがエラーで終了してもワークフローを継続
- 警告メッセージを表示

### 2. block
- スクリプトがエラーで終了すると decision_block JSON を出力
- Claude Code に処理を委ねる

### 3. raise
- スクリプトがエラーで終了するとワークフロー全体を停止
- エラーメッセージを表示

## $WORK_SUMMARY機能

作業内容の要約を他のフックで参照できます：

```json
{
  "launch": "REVIEW_NEEDED",
  "prompt": "以下の作業内容をレビューしてください：\n\n$WORK_SUMMARY\n\n問題がなければ REVIEW_PASSED と表示してください。"
}
```

## サンプルフック

### hooks/self-review.sh
- 作業内容の厳正なレビューを実行
- SubAgent を使用してコードレビューを行う

### hooks/commit.sh
- コミット前の確認とコミット実行
- 作業内容の要約をコミットメッセージに含める

### hooks/stop.sh
- ワークフローの終了処理
- 単純に exit 0 を実行

## 基本的なトラブルシューティング

### 1. 設定ファイルが見つからない
```
WARNING: 設定ファイルが見つかりません: .claude/workflow.json
INFO: デフォルト設定を使用します
```
- `.claude/workflow.json` ファイルを作成してください
- またはデフォルト設定で動作させることも可能

### 2. スクリプトが見つからない
```
ERROR: Hookスクリプトが見つかりません: hooks/script.sh
```
- hooks/ ディレクトリにスクリプトファイルが存在するか確認
- ファイルパスのスペルミスがないか確認

### 3. 実行権限がない
```
ERROR: Hookスクリプトに実行権限がありません: hooks/script.sh
```
- `chmod +x hooks/script.sh` で実行権限を付与

### 4. 依存関係が不足
```
ERROR: 以下の依存関係が見つかりません: jq
```
- 必要なコマンドをインストール：`brew install jq`（macOS）

### 5. トランスクリプトファイルが見つからない
```
ERROR: Claude transcriptsディレクトリが見つかりません
```
- Claude Code が正常にインストールされているか確認
- `~/.claude/projects/` ディレクトリが存在するか確認

## 要件

- jq
- grep
- tail
- mktemp
- bash（4.0以上推奨）

## ライセンス

このプロジェクトはMITライセンスの下で公開されています。