#!/usr/bin/env bash
# Scan active MergeTree parts for Map subcolumn read failures (ClickHouse CANNOT_READ_ALL_DATA / code 33).
# Uses the same map-key expressions the Owlpane API reads during home, releases, SLO, and alerts.
#
# Usage:
#   OWLPANE_CLICKHOUSE_URL=http://127.0.0.1:8123 \
#   OWLPANE_CLICKHOUSE_USER=stumpcam \
#   OWLPANE_CLICKHOUSE_PASSWORD=... \
#   OWLPANE_CLICKHOUSE_DATABASE=stumpcam \
#   ./saas/scripts/check-otel-map-parts.sh [table]
#
# table defaults to otel_traces; also try otel_logs if log map reads fail.

set -euo pipefail

TABLE="${1:-otel_traces}"
URL="${OWLPANE_CLICKHOUSE_URL:-http://127.0.0.1:8123}"
URL="${URL%/}"
USER="${OWLPANE_CLICKHOUSE_USER:-default}"
PASS="${OWLPANE_CLICKHOUSE_PASSWORD:-}"
DB="${OWLPANE_CLICKHOUSE_DATABASE:-stumpcam}"

ch() {
  curl -sS "${URL}/?database=${DB}" --user "${USER}:${PASS}" --data-binary @-
}

echo "==> Checking ${DB}.${TABLE} parts at ${URL}"

PARTS=$(ch <<< "SELECT name FROM system.parts WHERE database='${DB}' AND table='${TABLE}' AND active ORDER BY name FORMAT TSV")
if [[ -z "${PARTS// }" ]]; then
  echo "No active parts found."
  exit 0
fi

if [[ "$TABLE" == "otel_logs" ]]; then
  PROBE="ResourceAttributes['owlpane.project_id'] != '' OR LogAttributes['http.response.status_code'] != ''"
else
  PROBE="ResourceAttributes['owlpane.project_id'] != '' OR ResourceAttributes['service.version'] != '' OR SpanAttributes['http.response.status_code'] != ''"
fi

FAIL=0
while IFS= read -r part; do
  [[ -z "$part" ]] && continue
  err=$(ch <<< "
SELECT count()
FROM ${TABLE}
WHERE _part = '${part}'
  AND (${PROBE})
" 2>&1) || true
  if echo "$err" | grep -qE 'CANNOT_READ_ALL_DATA|Code: 33'; then
    echo "FAIL  ${part}"
    echo "      ${err}" | head -1
    echo "      -- detach: ALTER TABLE ${DB}.${TABLE} DETACH PART '${part}';"
    echo "      -- then inspect detached/ and DROP DETACHED or re-attach after repair"
    FAIL=$((FAIL + 1))
  fi
done <<< "$PARTS"

COUNT=$(echo "$PARTS" | grep -c . || true)
if [[ "$FAIL" -eq 0 ]]; then
  echo "OK    scanned ${COUNT} part(s), no map subcolumn read errors."
  exit 0
fi

echo "==> ${FAIL} part(s) failed. Run CHECK TABLE ${DB}.${TABLE}; consider OPTIMIZE on affected partitions."
exit 1
