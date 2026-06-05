#!/bin/bash
# mock_bq.sh
# 動作確認用モック bq コマンド
#
# 環境変数でシナリオを切り替える:
#   MOCK_BQ_BYTES (default: 5あ00000000)  : dry_run 時に返すスキャン量 (bytes)
#   MOCK_BQ_FAIL  (default: 0)          : 1 にすると dry_run 失敗をシミュレート
#
# 使い方:
#   PATH="/workspace/.claude/hooks:$PATH" bq query ...

MOCK_BYTES="${MOCK_BQ_BYTES:-500000000}"  # デフォルト 500MB（OKゾーン）
MOCK_FAIL="${MOCK_BQ_FAIL:-0}"

# 引数を全部受け取る
ARGS="$*"

if echo "$ARGS" | grep -q "\-\-dry_run"; then
  if [[ "$MOCK_FAIL" == "1" ]]; then
    echo "Error: BigQuery error: access denied" >&2
    exit 1
  fi
  GB=$(echo "scale=2; $MOCK_BYTES / 1024 / 1024 / 1024" | bc)
  echo "Query successfully validated. Assuming the tables are not modified, running this query will process ${MOCK_BYTES} bytes (${GB} GB)." >&2
  exit 0
fi

# 通常実行
echo "Waiting on bqjob_mock_$(date +%s) ... (0s) Current status: DONE"
echo "+---------+"
echo "| mock    |"
echo "+---------+"
echo "| result  |"
echo "+---------+"
echo ""
echo "Bytes processed: ${MOCK_BYTES}"
echo "Bytes billed: ${MOCK_BYTES}"
echo "Slot time consumed: 1.23 sec"
exit 0
