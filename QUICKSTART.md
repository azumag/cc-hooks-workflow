# クイックスタートガイド

Claude Code Hooks Workflow を5分で開始できるガイドです。

## 前提条件

- [Claude Code](https://claude.ai/code) がインストールされている
- bash, jq, grep, tail, mktemp コマンドが利用可能

### 依存関係のインストール（macOS）

```bash
# Homebrewを使用
brew install jq

# または、各種パッケージマネージャで
# Ubuntu/Debian: sudo apt-get install jq
# CentOS/RHEL: sudo yum install jq
```

## 手順1: プロジェクトの設定

### 1.1 ワークフローファイルの配置

```bash
# このリポジトリをクローンするか、workflow.shをダウンロード
git clone https://github.com/your-repo/cc-hooks-workflow.git
cd cc-hooks-workflow

# または、workflow.shを直接プロジェクトに配置
curl -O https://raw.githubusercontent.com/your-repo/cc-hooks-workflow/main/workflow.sh
chmod +x workflow.sh
```

### 1.2 hooksディレクトリの作成

```bash
mkdir -p hooks
```

### 1.3 基本的なフックスクリプトの作成

```bash
# stop.shを作成（最低限必要）
cat > hooks/stop.sh << 'EOF'
#!/bin/bash
exit 0
EOF
chmod +x hooks/stop.sh
```

## 手順2: 設定ファイルの作成

### 2.1 .claudeディレクトリの作成

```bash
mkdir -p .claude
```

### 2.2 最小限の設定ファイルを作成

```bash
cat > .claude/workflow.json << 'EOF'
{
  "hooks": [
    {
      "launch": null,
      "prompt": "作業内容を確認し、必要に応じて修正を行ってください。完了したら WORK_COMPLETED と表示してください。"
    },
    {
      "launch": "WORK_COMPLETED",
      "path": "stop.sh",
      "next": null,
      "handling": "pass"
    }
  ]
}
EOF
```

## 手順3: 初回テスト実行

### 3.1 動作確認

```bash
# 依存関係チェック
./workflow.sh

# 期待される出力例：
# INFO: Workflow開始
# INFO: トランスクリプトファイル: /path/to/transcript.jsonl
# INFO: 検出された状態: 何らかのメッセージ
# INFO: 実行するhook設定: {"launch":null,"prompt":"..."}
# INFO: プロンプトフックを実行中
# 作業内容を確認し、必要に応じて修正を行ってください。完了したら WORK_COMPLETED と表示してください。
```

### 3.2 Claude Code での Stop Hooks 設定

Claude Code で以下のコマンドを実行し、Stop Hooks を設定します：

```bash
# プロジェクトルートディレクトリで実行
claude config set stop_hooks "./workflow.sh"

# 確認
claude config get stop_hooks
```

## 手順4: 実際の使用

### 4.1 Claude Code でのセッション開始

```bash
# プロジェクトディレクトリで Claude Code を起動
claude

# 何らかの作業を行う
# 例: ファイルの編集、コードの修正など
```

### 4.2 セッション終了

Claude Code セッションを終了すると、自動的に workflow.sh が実行されます。

## 手順5: カスタマイズ

### 5.1 より高度な設定例

```bash
# サンプル設定をコピー
cp .claude/workflow.json.example .claude/workflow.json

# 必要に応じて編集
vi .claude/workflow.json
```

### 5.2 追加フックの作成

```bash
# self-review.shの作成例
cat > hooks/self-review.sh << 'EOF'
#!/bin/bash

# JSON入力を読み取り
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

REASON="作業内容をレビューしてください。問題がなければ $NEXT_PHRASE と表示してください。

作業報告:
$WORK_SUMMARY_CONTENT"

jq -n \
    --arg phrase "$NEXT_PHRASE" \
    --arg reason "$REASON" \
    '{decision: "block", reason: $reason}'
EOF
chmod +x hooks/self-review.sh
```

### 5.3 テスト専用設定

```bash
# テスト専用の設定
cat > .claude/workflow.json << 'EOF'
{
  "hooks": [
    {
      "launch": null,
      "prompt": "npm test を実行してください。完了したら TEST_COMPLETED と表示してください。"
    },
    {
      "launch": "TEST_COMPLETED",
      "path": "stop.sh",
      "next": null,
      "handling": "pass"
    }
  ]
}
EOF
```

## トラブルシューティング

### 一般的な問題

1. **jqが見つからない**
   ```bash
   brew install jq  # macOS
   sudo apt-get install jq  # Ubuntu
   ```

2. **実行権限がない**
   ```bash
   chmod +x workflow.sh
   chmod +x hooks/*.sh
   ```

3. **設定ファイルが無効**
   ```bash
   # JSON形式を確認
   jq '.' .claude/workflow.json
   ```

4. **Claude Code のStop Hooks設定**
   ```bash
   # 絶対パスで設定
   claude config set stop_hooks "$(pwd)/workflow.sh"
   ```

### デバッグ

```bash
# ログを確認
./workflow.sh 2>&1 | tee workflow.log

# 設定ファイルの構文チェック
jq empty .claude/workflow.json
```

## 次のステップ

- README.md で詳細な機能を確認
- .claude/workflow.json.example で高度な設定例を参照
- 独自のフックスクリプトを作成してワークフローをカスタマイズ

## サポート

問題が発生した場合は：
1. この「トラブルシューティング」セクションを確認
2. README.md の「基本的なトラブルシューティング」を参照
3. GitHub Issues で報告（リポジトリがある場合）

## 完了

これで Claude Code Hooks Workflow の基本的な使用準備が完了しました。Claude Code でのセッション終了時に自動的にワークフローが実行されるはずです。