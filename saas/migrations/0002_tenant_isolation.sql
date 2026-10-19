-- Stumpcam 0002: tenant isolation as an enforced database invariant, not just application discipline.
--
-- The Owlpane API already binds `tenant` as a SQL parameter on every scoped query (SCOPE_SQL /
-- METRIC_SCOPE_SQL). This adds a second, independent layer: a dedicated read-only ClickHouse user
-- (`owlpane_api`, not the CLICKHOUSE_USER superuser) whose reads are filtered by ClickHouse itself
-- via a ROW POLICY, keyed off a custom per-query setting the API sends alongside the parameter (see
-- observability-store.ts's `custom_tenant_id`). If application code ever forgets to scope a query,
-- this is what turns that bug into an error instead of a cross-tenant data leak — getSetting() with
-- no default throws when the setting was never sent, so a missing tenant fails closed.
--
-- Requires custom_settings_prefixes = "custom_" (see config.d/custom-settings.xml) so
-- custom_tenant_id is a valid setting name at all; without it this migration's CREATE ROW POLICY
-- statements themselves fail loudly, which is the right failure mode.
--
-- {{OWLPANE_CLICKHOUSE_API_PASSWORD}} is substituted from deploy/.env by scripts/cell.sh before this
-- file reaches clickhouse-client — it is never committed as a real value.

CREATE USER IF NOT EXISTS owlpane_api
    IDENTIFIED WITH sha256_password BY '{{OWLPANE_CLICKHOUSE_API_PASSWORD}}'
    SETTINGS readonly = 1 READONLY,
             -- The one setting a read-only client may change: the API sends the caller's tenant with each
             -- query and the row policies below read it. Without this, readonly=1 makes every query fail
             -- with "Cannot modify 'custom_tenant_id' setting in readonly mode". The default is empty, so
             -- a query that forgets to send a tenant sees no rows rather than another tenant's.
             custom_tenant_id = '' CHANGEABLE_IN_READONLY,
             max_execution_time = 10 READONLY,
             max_result_rows = 200000 READONLY,
             max_rows_to_read = 200000000 READONLY,
             max_memory_usage = 4000000000 READONLY;

GRANT SELECT ON stumpcam.* TO owlpane_api;

-- One row policy per otel_* table (row policies aren't inheritable across a whole database).
-- AS RESTRICTIVE so this composes safely with any future policy on the same table (they AND
-- together) instead of silently OR-ing and widening access.
CREATE ROW POLICY IF NOT EXISTS tenant_scope ON stumpcam.otel_traces
    AS RESTRICTIVE USING TenantId = getSetting('custom_tenant_id') TO owlpane_api;
CREATE ROW POLICY IF NOT EXISTS tenant_scope ON stumpcam.otel_logs
    AS RESTRICTIVE USING TenantId = getSetting('custom_tenant_id') TO owlpane_api;
CREATE ROW POLICY IF NOT EXISTS tenant_scope ON stumpcam.otel_metrics_gauge
    AS RESTRICTIVE USING TenantId = getSetting('custom_tenant_id') TO owlpane_api;
CREATE ROW POLICY IF NOT EXISTS tenant_scope ON stumpcam.otel_metrics_sum
    AS RESTRICTIVE USING TenantId = getSetting('custom_tenant_id') TO owlpane_api;
CREATE ROW POLICY IF NOT EXISTS tenant_scope ON stumpcam.otel_metrics_histogram
    AS RESTRICTIVE USING TenantId = getSetting('custom_tenant_id') TO owlpane_api;
CREATE ROW POLICY IF NOT EXISTS tenant_scope ON stumpcam.otel_metrics_exponential_histogram
    AS RESTRICTIVE USING TenantId = getSetting('custom_tenant_id') TO owlpane_api;
CREATE ROW POLICY IF NOT EXISTS tenant_scope ON stumpcam.otel_metrics_summary
    AS RESTRICTIVE USING TenantId = getSetting('custom_tenant_id') TO owlpane_api;
CREATE ROW POLICY IF NOT EXISTS tenant_scope ON stumpcam.otel_traces_trace_id_ts
    AS RESTRICTIVE USING TenantId = getSetting('custom_tenant_id') TO owlpane_api;

-- Noisy-neighbour guard: caps total resource use across all of owlpane_api's queries per interval,
-- independent of the per-query READONLY settings above (those bound one query; this bounds all of
-- them together). Numbers are a starting point for a single small tenant — revisit once real query
-- volume is observed.
CREATE QUOTA IF NOT EXISTS owlpane_api_quota
    FOR INTERVAL 1 MINUTE
    MAX QUERIES 600,
    MAX READ ROWS 500000000,
    MAX EXECUTION TIME 300
    TO owlpane_api;
