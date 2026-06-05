# BigQuery Hook プロジェクト

## BQ クエリの実行方法

SQL を実行するときは必ず以下の形式を使うこと：

```bash
bq query --nouse_legacy_sql 'SQL文'
```

または：

```bash
/workspace/bq-run.sh "SQL文"
```

**ラッパースクリプトの使い方：**
```bash
# 引数で渡す
/workspace/bq-run.sh "SELECT * FROM project.dataset.table LIMIT 10"

# パイプで渡す
echo "SELECT 1" | /workspace/bq-run.sh
```

## フックの動作

`bq query` を実行すると自動的にフックが介入する：

| スキャン量 | 動作 |
|-----------|------|
| 1 GB 未満 | そのまま実行（`--maximum_bytes_billed` 自動注入） |
| 1 GB 〜 2 GB | 確認プロンプト → 承認後に実行 |
| 2 GB 超 | ブロック（実行されない） |

閾値は環境変数 `BQ_WARN_GB` / `BQ_BLOCK_GB` で上書き可能。

## ログ

```bash
cat ~/.claude/logs/bq_hook.log
```
