#!/bin/bash
# bq_post_hook.sh
# PostToolUse フック: bq query 実行後に実際のスキャン量・実行時間を
# Slack & ターミナルログへ通知する。
#
# 必須環境変数:
#   SLACK_CHANNEL_ID          : 通知先SlackチャンネルID
#
# オプション環境変数:
#   BQ_LOG_FILE               : ログ出力先ファイル (省略時: ~/.claude/logs/bq_hook.log)
#   BQ_LOCATION               : BigQuery ロケーション (省略時: us)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${CLAUDE_PROJECT_DIR:-${SCRIPT_DIR}/../..}/.env"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
fi
source "${SCRIPT_DIR}/notify_slack.sh"

LOG_FILE="${BQ_LOG_FILE:-${HOME}/.claude/logs/bq_hook.log}"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  local level="$1"; shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" | tee -a "$LOG_FILE" >&2
}

bytes_to_gb() {
  printf "%.2f" "$(echo "scale=4; $1 / 1024 / 1024 / 1024" | bc)"
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
TOOL_OUTPUT=$(echo "$INPUT" | jq -r '.tool_response.output // empty')

if ! echo "$COMMAND" | grep -qE '^\s*bq\s+query'; then
  exit 0
fi

log "INFO" "PostToolUse: bq query 完了"

BYTES_PROCESSED=$(echo "$TOOL_OUTPUT" | grep -oP '(?<=Bytes processed: )\d+' || echo "")
BYTES_BILLED=$(echo "$TOOL_OUTPUT" | grep -oP '(?<=Bytes billed: )\d+' || echo "")
SLOT_TIME=$(echo "$TOOL_OUTPUT" | grep -oP '(?<=Slot time consumed: )[\d.]+ \w+' || echo "不明")

PROCESSED_GB=$( [[ -n "$BYTES_PROCESSED" ]] && bytes_to_gb "$BYTES_PROCESSED" || echo "不明" )
BILLED_GB=$( [[ -n "$BYTES_BILLED" ]] && bytes_to_gb "$BYTES_BILLED" || echo "不明" )

JOB_ID=$(echo "$TOOL_OUTPUT" | grep -oP '(?<=Waiting on )\S+' || echo "")
GCP_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
BQ_LOCATION="${BQ_LOCATION:-us}"

if [[ -n "$JOB_ID" && -n "$GCP_PROJECT" ]]; then
  JOB_URL="https://console.cloud.google.com/bigquery?project=${GCP_PROJECT}&j=bq:${BQ_LOCATION}:${JOB_ID}&page=queryresults"
  JOB_LINK="<${JOB_URL}|ジョブ詳細を確認 🔗>"
else
  JOB_LINK=""
fi

log "INFO" "実際のスキャン量: processed=${PROCESSED_GB} GB, billed=${BILLED_GB} GB, slot=${SLOT_TIME}, job=${JOB_ID}"

MSG="処理バイト数: *${PROCESSED_GB} GB*
課金対象バイト数: *${BILLED_GB} GB*
スロット使用時間: ${SLOT_TIME}
コマンド: \`${COMMAND}\`${JOB_LINK:+
${JOB_LINK}}"
slack_notify "$MSG" "good" "BigQuery 完了 📊"

exit 0
