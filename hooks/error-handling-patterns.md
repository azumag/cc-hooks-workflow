# Hooks エラーハンドリング標準パターン

## 設計原則

レビューで指摘された4つの重要な観点：

1. **一貫性**: プロジェクト全体で一貫したエラーハンドリングパターン
2. **明確性**: 何が起こったか、どう解決するかを明確に伝える
3. **回復性**: 可能であればエラーから回復するメカニズム
4. **テスト**: エラーハンドリングもテストでカバー

## 標準エラーハンドリングパターン

### 1. JSON入力処理パターン

```bash
# パターン: JSON入力からwork_summary_file_pathを抽出
read_work_summary_file_path() {
    local json_input
    json_input=$(cat) || {
        output_error "Failed to read JSON input from stdin"
        return 1
    }
    
    if [ -z "$json_input" ]; then
        output_error "JSON input is empty"
        return 1
    fi
    
    local work_summary_file_path
    work_summary_file_path=$(echo "$json_input" | jq -r '.work_summary_file_path // empty' 2>/dev/null) || {
        output_error "Invalid JSON format" "Check input format: {\"work_summary_file_path\": \"/path/to/file\"}"
        return 1
    }
    
    if [ -z "$work_summary_file_path" ] || [ "$work_summary_file_path" = "null" ]; then
        output_error "Missing work_summary_file_path field" "Ensure JSON contains work_summary_file_path field"
        return 1
    fi
    
    echo "$work_summary_file_path"
}
```

### 2. ファイル操作エラーパターン

```bash
# パターン: 作業報告ファイル読み取り
read_work_summary_safe() {
    local file_path="$1"
    
    if [ -z "$file_path" ]; then
        output_error "File path is required" "Provide valid file path as argument"
        return 1
    fi
    
    if [ ! -f "$file_path" ]; then
        output_error "Work summary file not found: $file_path" "Check if file exists and path is correct"
        return 1
    fi
    
    if [ ! -r "$file_path" ]; then
        output_error "Cannot read work summary file: $file_path" "Check file permissions"
        return 1
    fi
    
    if [ ! -s "$file_path" ]; then
        output_error "Work summary file is empty: $file_path" "Ensure file contains valid content"
        return 1
    fi
    
    cat "$file_path" || {
        output_error "Failed to read work summary file: $file_path" "Check file integrity and permissions"
        return 1
    }
}
```

### 3. 依存関係チェックパターン

```bash
# パターン: 依存関係チェック
check_dependencies() {
    local missing_deps=()
    local required_deps=("jq")
    
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        local install_instructions=""
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                jq)
                    install_instructions="${install_instructions}Install jq: apt-get install jq (Ubuntu) or brew install jq (macOS)\n"
                    ;;
                *)
                    install_instructions="${install_instructions}Install $dep\n"
                    ;;
            esac
        done
        
        output_error "Missing required dependencies: ${missing_deps[*]}" "$install_instructions"
        return 1
    fi
}
```

### 4. JSON出力パターン

```bash
# パターン: 成功時のJSON出力
output_success() {
    local reason="${1:-Hook executed successfully}"
    jq -n --arg reason "$reason" '{decision: "approve", reason: $reason}'
    exit 0
}

# パターン: エラー時のJSON出力
output_error() {
    local error_message="${1:-Unknown error occurred}"
    local solution_hint="${2:-""}"
    
    local full_message="$error_message"
    if [ -n "$solution_hint" ]; then
        full_message="$error_message. $solution_hint"
    fi
    
    jq -n --arg reason "$full_message" '{decision: "block", reason: $reason}'
    exit 1
}

# パターン: カスタム判定のJSON出力
output_decision() {
    local decision="$1"  # "approve" or "block"
    local reason="$2"
    
    if [ "$decision" != "approve" ] && [ "$decision" != "block" ]; then
        output_error "Invalid decision value: $decision" "Use 'approve' or 'block'"
    fi
    
    jq -n --arg decision "$decision" --arg reason "$reason" \
        '{decision: $decision, reason: $reason}'
    
    [ "$decision" = "block" ] && exit 1 || exit 0
}
```

### 5. 初期化パターン

```bash
# パターン: hooks共通初期化
init_hook() {
    # 依存関係チェック
    check_dependencies || return 1
    
    # デバッグモード設定
    if [ "${HOOK_DEBUG:-false}" = "true" ]; then
        echo "DEBUG: Hook debug mode enabled" >&2
        set -x
    fi
    
    return 0
}
```

## エラーメッセージ設計ガイドライン

### 1. エラーメッセージの構造

```
[問題の説明] + [解決方法のヒント]
```

### 2. 良いエラーメッセージの例

```bash
# ❌ 悪い例
"Error"
"File not found"
"Invalid input"

# ✅ 良い例  
"Work summary file not found: /path/to/file. Check if file exists and path is correct"
"Invalid JSON format. Check input format: {\"work_summary_file_path\": \"/path/to/file\"}"
"Missing required dependencies: jq. Install jq: apt-get install jq (Ubuntu) or brew install jq (macOS)"
```

### 3. JSON出力での統一フォーマット

```json
{
  "decision": "block",
  "reason": "具体的な問題の説明. 解決方法のヒント"
}
```

## テスト戦略

### エラーハンドリングのテストパターン

```bash
# 各エラーシナリオのテスト
@test "handles missing work_summary_file gracefully" {
    # エラー条件を作成
    # 適切なエラーメッセージが返されることを確認
    # exit code 1であることを確認
    # JSON形式が正しいことを確認
}
```

## 使用方法

各hooksスクリプトで以下のパターンを使用：

```bash
#!/bin/bash
set -euo pipefail

# 共通パターンを使用
source "$(dirname "$0")/common-patterns.sh"

# 初期化
init_hook || exit 1

# JSON入力処理
work_summary_file=$(read_work_summary_file_path) || exit 1

# ファイル読み取り
work_summary=$(read_work_summary_safe "$work_summary_file") || exit 1

# 処理実行
# ... hook固有の処理 ...

# 成功時の出力
output_success "Hook completed successfully"
```