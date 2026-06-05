# BigQuery Hook UAT 手順書

## 前提確認

新しい Claude Code セッションを `/workspace` で起動していること。

```bash
# ツールが揃っているか確認
bq version    # → "This is BigQuery CLI 2.1.32"（実 CLI）
jq --version
bc --version

# GCP 認証・プロジェクト設定
gcloud auth list
gcloud config get-value project
```

GCP 未認証の場合：
```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project <your-project-id>
```

---

## テスト共通設定

閾値はデフォルト値（変更不要）：

| 閾値 | 値 | 環境変数 |
|------|-----|---------|
| 警告 | 1 GB | `BQ_WARN_GB` |
| ブロック | 2 GB | `BQ_BLOCK_GB` |

閾値を一時的に変えたい場合は環境変数で上書きできる（後述）。

---

## テストケース一覧

### TC-1: OK（1GB 未満のクエリ）

**Claude への指示**
```
bq query --nouse_legacy_sql '<1GB未満でスキャンされるクエリ>' を実行して
```

**期待結果**
- クエリが実行される（ブロックされない）
- 実行されたコマンドに `--maximum_bytes_billed=2147483648` が自動注入されている
- ターミナルにエラーや警告は表示されない

**確認ポイント**
- [ ] クエリが実行完了する
- [ ] Claude の発言か Bash ツールの引数に `--maximum_bytes_billed` が含まれている

---

### TC-2: 警告（1GB〜2GB のクエリ）

**Claude への指示**
```
bq query --nouse_legacy_sql '<1GB〜2GB をスキャンするクエリ>' を実行して
```

**期待結果**
- 確認プロンプトが表示される（ブロックはされない）
- `--maximum_bytes_billed` が自動注入される
- Claude が「スキャン量が警告閾値を超えている」旨を伝えてくる

**確認ポイント**
- [ ] クエリが実行完了する
- [ ] Claude が「スキャン量が警告閾値を超えている」旨を伝えてくる（または `--maximum_bytes_billed` 注入を言及する）

---

### TC-3: ブロック（2GB 超のクエリ）

**Claude への指示**
```
bq query --nouse_legacy_sql '<2GB超をスキャンするクエリ>' を実行して
```

**期待結果**
- クエリが**実行されない**
- ターミナルにエラーメッセージが表示される：
  ```
  スキャン量 X.XX GB が上限 2 GB を超えているため、クエリをブロックしました。クエリを最適化するか、管理者に相談してください。
  ```

**確認ポイント**
- [ ] クエリが実行されない
- [ ] 上記エラーメッセージが表示される

---

### TC-4: bq query 以外はフック対象外

**Claude への指示**
```
bq version を実行して
```

**期待結果**
- フックが発火せず、そのまま実行される
- ブロックされない

**確認ポイント**
- [ ] `bq version` の結果が返ってくる
- [ ] エラーなし

---

### TC-5: Slack 通知（SLACK_CHANNEL_ID 設定済みの場合のみ）

**事前準備**
```bash
export SLACK_CHANNEL_ID="C0XXXXXXXXX"  # 実際のチャンネルID
```

**Claude への指示**（TC-1〜3 を再実行）

**期待結果**
- 各シナリオに応じて Slack に通知が届く
  - OK → ✅ BigQuery 実行
  - 警告 → ⚠️ BigQuery 警告
  - ブロック → 🚫 BigQuery ブロック

> ✅ **再テスト合格**（2026-06-04）
> スキャン量の表記・タイトル文言ともに修正済みを確認。

---

## 要望・改善事項

### REQ-1: Slack 通知にジョブリンクを含める

**内容**: Slack 通知メッセージに BigQuery ジョブへのリンクを追加してほしい。
通知から直接ジョブ詳細を確認できると便利。

---

## ログ確認

各テスト後にログで実行履歴を確認できる。

```bash
cat ~/.claude/logs/bq_hook.log
```

---

## 閾値変更テスト（オプション）

環境変数で閾値を変えて動作が変わることを確認する。

```bash
export BQ_WARN_GB=0.1   # 100MB 超で警告
export BQ_BLOCK_GB=1    # 1GB 超でブロック
```
