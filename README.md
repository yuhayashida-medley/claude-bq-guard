# BigQuery Hook for Claude Code

Claude Code の Hooks 機能を使って、BigQuery クエリのスキャン量を事前チェックし、コスト超過を防ぐプロジェクトです。

## 概要

`bq query` を実行しようとすると、自動的に以下のフローが動きます。

```
bq query 実行
    ↓
[PreToolUse Hook] dry_run でスキャン量を取得
    ↓
┌─────────────────────────────────────────┐
│ スキャン量 < 1 GB  → そのまま実行       │
│ 1 GB 〜 2 GB       → 確認プロンプト表示 │
│ 2 GB 超            → 実行ブロック       │
└─────────────────────────────────────────┘
    ↓
[PostToolUse Hook] 実際のスキャン量・課金量をログ
```

`--maximum_bytes_billed` はブロック閾値と同じ値で自動注入されるため、フックが万が一すり抜けても過剰課金を防ぎます。

## ファイル構成

```
.
├── .claude/
│   ├── settings.json          # フック設定
│   └── hooks/
│       ├── bq_pre_hook.sh     # スキャン量チェック・ブロック（本体）
│       ├── bq_post_hook.sh    # 実行後ログ・Slack通知
│       ├── notify_slack.sh    # Slack通知共通関数
│       └── mock_bq.sh         # ローカルテスト用モック
├── bq-run.sh                  # SQL を引数で渡せる薄いラッパー
├── .env.example               # 環境変数のテンプレート
└── UAT.md                     # テスト手順書
```

## セットアップ

### 1. 前提ツール

```bash
gcloud --version   # Google Cloud SDK
bq version         # BigQuery CLI（Cloud SDK に含まれる）
jq --version
bc --version
```

### 2. GCP 認証

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project <your-project-id>
```

### 3. bq CLI の配置

```bash
sudo ln -sf /usr/lib/google-cloud-sdk/bin/bq /usr/local/bin/bq
```

### 4. 環境変数（任意）

```bash
# .env.example を参考に設定
export SLACK_CHANNEL_ID="C0XXXXXXXXX"   # Slack通知を使う場合
export BQ_WARN_GB=1                     # 警告閾値（デフォルト: 1）
export BQ_BLOCK_GB=2                    # ブロック閾値（デフォルト: 2）
```

## 使い方

Claude に SQL を渡すか、ラッパースクリプトを使います。

```bash
# Claude への指示
"SELECT * FROM project.dataset.table LIMIT 10 を実行して"

# ラッパースクリプト
./bq-run.sh "SELECT * FROM project.dataset.table LIMIT 10"

# パイプ
echo "SELECT 1" | ./bq-run.sh
```

## 閾値の変更

環境変数で動的に変更できます。

```bash
export BQ_WARN_GB=0.5
export BQ_BLOCK_GB=1
```

## ログ確認

```bash
cat ~/.claude/logs/bq_hook.log
```

## Slack 通知

`SLACK_CHANNEL_ID` を設定すると、実行のたびに結果が通知されます。

| 状態 | 通知 |
|------|------|
| 正常実行 | ✅ BigQuery 実行（スキャンOK） |
| 警告（確認後実行） | ⚠️ BigQuery 警告（要確認） |
| ブロック | 🚫 BigQuery ブロック |
| 実行完了 | 📊 BigQuery 完了（実スキャン量・課金量） |

通知には実スキャン量、課金対象バイト数、スロット使用時間、BigQuery ジョブへのリンクが含まれます。

---

## テスト結果

実データによる動作確認の結果を記録します。

### TC-1: 正常実行（1 GB 未満）

- **確認内容**: 1 GB 未満のスキャンが発生するクエリを実行
- **結果**: ブロックなしで実行完了。`--maximum_bytes_billed` が自動注入される
- **ポイント**: dry_run → スキャン量取得 → 承認 → 実行 の一連フローが動作

### TC-2: 警告（1 GB 〜 2 GB）

- **確認内容**: 1 GB〜2 GB のスキャンが発生するクエリを実行
- **結果**: 確認プロンプトが表示され、承認後に実行完了。Slack に ⚠️ 通知
- **ポイント**: `permissionDecision: "ask"` による確認フローが機能する

### TC-3: ブロック（2 GB 超）

- **確認内容**: 2 GB を超えるスキャンが発生するクエリを実行
- **結果**: クエリが実行されず、エラーメッセージが表示される。Slack に 🚫 通知
- **ポイント**: `permissionDecision: "deny"` によりクエリが完全にブロックされる

### TC-4: bq query 以外はフック対象外

- **確認内容**: `bq version` を実行
- **結果**: フックが発火せず、そのまま実行される
- **ポイント**: フックの `if` 条件で `bq query` のみを対象にしているため、他のサブコマンドには影響しない

### TC-5: Slack 通知

- **確認内容**: `SLACK_CHANNEL_ID` を設定した状態で TC-1〜3 を実行
- **結果**: 各シナリオに応じた通知（✅ / ⚠️ / 🚫）が届く。PostHook による 📊 完了通知も届く
- **ポイント**: Slack MCP を Claude 自身が呼び出す構成のため、Bot トークンの管理が不要

### dry_run 失敗時のフォールバック

- **確認内容**: dry_run がスキャン量を返せないケース（権限エラーなど）
- **結果**: ブロックではなく `--maximum_bytes_billed` を注入した上で実行を承認。ログに WARN が記録される
- **ポイント**: フォールバックがあるため、dry_run 失敗でクエリが一切実行できなくなる事態を避けられる
