-- Stumpcam 0004: narrowly-granted user for telemetry erasure (privacy tools: delete a tenant's or a user's
-- telemetry on request). It can read and ALTER ... DELETE on the otel_* tables and nothing else: no INSERT,
-- no DDL, no access to other databases, no user management.
--
-- The Owlpane API connects as this user via OWLPANE_CLICKHOUSE_ERASE_USER / OWLPANE_CLICKHOUSE_ERASE_PASSWORD.
-- {{OWLPANE_CLICKHOUSE_ERASE_PASSWORD}} is substituted by scripts/cell.sh / scripts/deploy.sh from the secret,
-- never committed. Erasure is a mutation: it rewrites parts, so backups age out on the documented schedule
-- (docs/ops/backups.md) rather than instantly.
CREATE USER IF NOT EXISTS owlpane_erase
    IDENTIFIED WITH sha256_password BY '{{OWLPANE_CLICKHOUSE_ERASE_PASSWORD}}'
    SETTINGS max_execution_time = 300 READONLY, max_memory_usage = 4000000000 READONLY;

GRANT SELECT, ALTER DELETE ON stumpcam.otel_traces TO owlpane_erase;
GRANT SELECT, ALTER DELETE ON stumpcam.otel_logs TO owlpane_erase;
GRANT SELECT, ALTER DELETE ON stumpcam.otel_metrics_gauge TO owlpane_erase;
GRANT SELECT, ALTER DELETE ON stumpcam.otel_metrics_sum TO owlpane_erase;
GRANT SELECT, ALTER DELETE ON stumpcam.otel_metrics_histogram TO owlpane_erase;
GRANT SELECT, ALTER DELETE ON stumpcam.otel_metrics_exponential_histogram TO owlpane_erase;
GRANT SELECT, ALTER DELETE ON stumpcam.otel_metrics_summary TO owlpane_erase;
GRANT SELECT, ALTER DELETE ON stumpcam.otel_traces_trace_id_ts TO owlpane_erase;
