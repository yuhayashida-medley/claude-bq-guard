#!/bin/bash
# Usage: bq-run.sh "SELECT ..."
#        echo "SELECT ..." | bq-run.sh
set -euo pipefail

if [[ $# -ge 1 ]]; then
  SQL="$1"
else
  SQL=$(cat)
fi

exec bq query --nouse_legacy_sql "$SQL"
