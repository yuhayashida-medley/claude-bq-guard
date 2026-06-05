#!/bin/bash
# bq_pre_hook.sh
# PreToolUse フック: bq query 実行前に dry_run でスキャン量をチェックし、
# 閾値超えの場合は自動ブロック、Slack & ターミナルログへ通知する。
# --maximum_bytes_billed を自動注入して Hook すり抜け時の保険とする。
#
# 必須環境変数:
#   SLACK_CHANNEL_ID               : 通知先SlackチャンネルID
#
# オプション環境変数:
#   BQ_WARN_GB  (default: 1)       : 警告閾値 (GB)
#   BQ_BLOCK_GB (default: 10)      : ブロック閾値 (GB)
#   BQ_MAX_BYTES_BILLED            : --maximum_bytes_billed に渡す値 (bytes)
#                                    省略時は BQ_BLOCK_GB をバイト換算した値を使用
#   BQ_LOG_FILE                    : ログ出力先ファイル (省略時: ~/.claude/logs/bq_hook.log)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/notify_slack.sh"

WARN_GB="${BQ_WARN_GB:-1}"
BLOCK_GB="${BQ_BLOCK_GB:-2}"
LOG_FILE="${BQ_LOG_FILE:-${HOME}/.claude/logs/bq_hook.log}"
mkdir -p "$(dirname "$LOG_FILE")"

DEFAULT_MAX_BYTES=$(echo "$BLOCK_GB * 1024 * 1024 * 1024" | bc | cut -d. -f1)
MAX_BYTES_BILLED="${BQ_MAX_BYTES_BILLED:-${DEFAULT_MAX_BYTES}}"

log() {
  local level="$1"; shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" | tee -a "$LOG_FILE" >&2
}

bytes_to_gb() {
  printf "%.2f" "$(echo "scale=4; $1 / 1024 / 1024 / 1024" | bc)"
}

inject_max_bytes() {
  local cmd="$1"
  if echo "$cmd" | grep -q '\-\-maximum_bytes_billed'; then
    echo "$cmd"
  else
    echo "$cmd" | sed "s/bq query/bq query --maximum_bytes_billed=${MAX_BYTES_BILLED}/"
  fi
}

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if ! echo "$COMMAND" | grep -qE '^\s*bq\s+(query|mk|load)'; then
  exit 0
fi
if ! echo "$COMMAND" | grep -qE '^\s*bq\s+query'; then
  exit 0
fi

log "INFO" "bq query 検知: ${COMMAND}"

DRY_CMD=$(echo "$COMMAND" | sed 's/bq query/bq query --dry_run/')
log "INFO" "dry_run 実行中..."
DRY_OUTPUT=$(eval "$DRY_CMD" 2>&1 || true)

BYTES=$(echo "$DRY_OUTPUT" | grep -oP '(?<=process )\d+(?= bytes)' || echo "0")

if [[ -z "$BYTES" || "$BYTES" == "0" ]]; then
  log "WARN" "スキャン量の取得に失敗しました。dry_run 出力: ${DRY_OUTPUT}"
  INJECTED_CMD=$(inject_max_bytes "$COMMAND")
  log "INFO" "--maximum_bytes_billed=${MAX_BYTES_BILLED} を注入して続行します"
  jq -n \
    --arg cmd "$INJECTED_CMD" \
    --arg reason "dry_run によるスキャン量取得に失敗しましたが、--maximum_bytes_billed=${MAX_BYTES_BILLED} bytes を注入して実行します。" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "approve",
        permissionDecisionReason: $reason
      },
      modifiedToolInput: { command: $cmd }
    }'
  exit 0
fi

SCAN_GB=$(bytes_to_gb "$BYTES")
log "INFO" "予測スキャン量: ${SCAN_GB} GB (${BYTES} bytes)"

IS_OVER_BLOCK=$(echo "$SCAN_GB > $BLOCK_GB" | bc -l)
IS_OVER_WARN=$(echo "$SCAN_GB > $WARN_GB" | bc -l)

if [[ "$IS_OVER_BLOCK" == "1" ]]; then
  MSG="スキャン量: *${SCAN_GB} GB* (閾値: ${BLOCK_GB} GB)
コマンド: \`${COMMAND}\`"
  log "ERROR" "ブロック: スキャン量 ${SCAN_GB} GB が閾値 ${BLOCK_GB} GB を超えました"
  slack_notify "$MSG" "danger" "BigQuery ブロック 🚫"
  jq -n \
    --arg reason "スキャン量 ${SCAN_GB} GB が上限 ${BLOCK_GB} GB を超えているため、クエリをブロックしました。クエリを最適化するか、管理者に相談してください。" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
  exit 0

elif [[ "$IS_OVER_WARN" == "1" ]]; then
  INJECTED_CMD=$(inject_max_bytes "$COMMAND")
  MSG="スキャン量: *${SCAN_GB} GB* (警告閾値: ${WARN_GB} GB)
--maximum_bytes_billed: ${MAX_BYTES_BILLED} bytes を設定
コマンド: \`${COMMAND}\`"
  log "WARN" "警告: スキャン量 ${SCAN_GB} GB（--maximum_bytes_billed=${MAX_BYTES_BILLED} を注入して実行）"
  slack_notify "$MSG" "warning" "BigQuery 警告（要確認）⚠️"
  jq -n \
    --arg cmd "$INJECTED_CMD" \
    --arg msg "⚠️ スキャン量 ${SCAN_GB} GB は警告閾値 ${WARN_GB} GB を超えています。このまま実行しますか？（--maximum_bytes_billed=${MAX_BYTES_BILLED} bytes を自動設定します）" \
    '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: $msg
      },
      modifiedToolInput: { command: $cmd }
    }'
  exit 0

else
  INJECTED_CMD=$(inject_max_bytes "$COMMAND")
  MSG="スキャン量: *${SCAN_GB} GB*
--maximum_bytes_billed: ${MAX_BYTES_BILLED} bytes を設定
コマンド: \`${COMMAND}\`"
  log "INFO" "OK: スキャン量 ${SCAN_GB} GB（--maximum_bytes_billed=${MAX_BYTES_BILLED} を注入）"
  slack_notify "$MSG" "good" "BigQuery 実行（スキャンOK）✅"
  jq -n \
    --arg cmd "$INJECTED_CMD" \
    '{
      modifiedToolInput: { command: $cmd }
    }'
  exit 0
fi
