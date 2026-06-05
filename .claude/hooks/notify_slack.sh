#!/bin/bash
# notify_slack.sh
# Slack通知の共通関数
#
# 必須環境変数:
#   SLACK_CHANNEL_ID: 通知先チャンネルの ID (例: C01234ABCDE)

slack_notify() {
  local message="$1"
  local color="${2:-good}"
  local title="${3:-BigQuery Hook}"

  if [[ -z "${SLACK_CHANNEL_ID:-}" ]]; then
    echo "[WARN] SLACK_CHANNEL_ID が設定されていません。Slack通知をスキップします。" >&2
    return 0
  fi

  local emoji
  case "$color" in
    danger)  emoji="🚫" ;;
    warning) emoji="⚠️" ;;
    *)       emoji="✅" ;;
  esac

  local claude_output
  claude_output=$(claude --print \
    "Slack の ${SLACK_CHANNEL_ID} チャンネルに以下のメッセージを送信してください。
メッセージ内容:
${emoji} *${title}*
${message}" \
    --allowedTools "mcp__claude_ai_Slack__slack_send_message" 2>/dev/null)

  local slack_url
  slack_url=$(echo "$claude_output" | grep -oP 'https://[a-z0-9-]+\.slack\.com/archives/[A-Z0-9]+/p[0-9]+' | head -1)
  if [[ -n "$slack_url" ]]; then
    echo "[Slack] ${slack_url}" >&2
  fi

  return $?
}
