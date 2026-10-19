-- Stumpcam 0003: per-tenant retention (C5).
--
-- 0001 set table-level TTLs (traces 15d, logs 30d, metrics 90d). ClickHouse forbids dictGet() in a TTL
-- expression, so per-tenant retention is done with a row-level expiry column instead:
--   ExpireAt = event time + tenant's retention days   (MATERIALIZED: computed by ClickHouse at insert;
--   a sender can't set it), and TTL ExpireAt.
-- The per-tenant days come from stumpcam_meta.tenant_retention, a Join-engine table (in memory, persisted
-- on disk, no credentials needed, read via joinGet). A tenant with no row gets the plan DEFAULTS below.
--
--   Set/change a tenant (takes effect for data ingested from now on; existing rows keep the expiry they were
--   written with until you run the UPDATE below):
--     INSERT INTO stumpcam_meta.tenant_retention VALUES ('acme', 30, 60, 180);
--   Re-stamp existing rows (heavy mutation: run off-peak, one table at a time, per tenant):
--     ALTER TABLE stumpcam.otel_traces UPDATE ExpireAt = toDateTime(Timestamp) + INTERVAL 30 DAY WHERE TenantId = 'acme';
--
-- Join tables are per node: on a multi-replica cell insert into each replica (scripts/deploy.sh retention-set
-- does). Defaults: traces 15, logs 30, metrics 90 days.
--
-- ALTER ... MODIFY TTL is issued with materialize_ttl_after_modify = 0 so that applying this migration on a
-- large table does not rewrite every part ("at 4 TB, not on my laptop"). Old parts keep their previous TTL
-- (the table-level one from 0001) until they merge; new parts use ExpireAt.

CREATE DATABASE IF NOT EXISTS stumpcam_meta;

CREATE TABLE IF NOT EXISTS stumpcam_meta.tenant_retention
(
    tenant        String,
    traces_days   UInt16,
    logs_days     UInt16,
    metrics_days  UInt16
) ENGINE = Join(ANY, LEFT, tenant);

-- traces
ALTER TABLE stumpcam.otel_traces
    ADD COLUMN IF NOT EXISTS `ExpireAt` DateTime MATERIALIZED
        toDateTime(Timestamp) + toIntervalDay(if(joinGet('stumpcam_meta.tenant_retention', 'traces_days', TenantId) = 0, 15, joinGet('stumpcam_meta.tenant_retention', 'traces_days', TenantId)));
ALTER TABLE stumpcam.otel_traces MODIFY TTL ExpireAt SETTINGS materialize_ttl_after_modify = 0;

-- trace_id -> start lookup follows traces
ALTER TABLE stumpcam.otel_traces_trace_id_ts
    ADD COLUMN IF NOT EXISTS `ExpireAt` DateTime MATERIALIZED
        toDateTime(Start) + toIntervalDay(if(joinGet('stumpcam_meta.tenant_retention', 'traces_days', TenantId) = 0, 15, joinGet('stumpcam_meta.tenant_retention', 'traces_days', TenantId)));
ALTER TABLE stumpcam.otel_traces_trace_id_ts MODIFY TTL ExpireAt SETTINGS materialize_ttl_after_modify = 0;

-- logs
ALTER TABLE stumpcam.otel_logs
    ADD COLUMN IF NOT EXISTS `ExpireAt` DateTime MATERIALIZED
        TimestampTime + toIntervalDay(if(joinGet('stumpcam_meta.tenant_retention', 'logs_days', TenantId) = 0, 30, joinGet('stumpcam_meta.tenant_retention', 'logs_days', TenantId)));
ALTER TABLE stumpcam.otel_logs MODIFY TTL ExpireAt SETTINGS materialize_ttl_after_modify = 0;

-- metrics (five tables)
ALTER TABLE stumpcam.otel_metrics_gauge
    ADD COLUMN IF NOT EXISTS `ExpireAt` DateTime MATERIALIZED
        toDateTime(TimeUnix) + toIntervalDay(if(joinGet('stumpcam_meta.tenant_retention', 'metrics_days', TenantId) = 0, 90, joinGet('stumpcam_meta.tenant_retention', 'metrics_days', TenantId)));
ALTER TABLE stumpcam.otel_metrics_gauge MODIFY TTL ExpireAt SETTINGS materialize_ttl_after_modify = 0;

ALTER TABLE stumpcam.otel_metrics_sum
    ADD COLUMN IF NOT EXISTS `ExpireAt` DateTime MATERIALIZED
        toDateTime(TimeUnix) + toIntervalDay(if(joinGet('stumpcam_meta.tenant_retention', 'metrics_days', TenantId) = 0, 90, joinGet('stumpcam_meta.tenant_retention', 'metrics_days', TenantId)));
ALTER TABLE stumpcam.otel_metrics_sum MODIFY TTL ExpireAt SETTINGS materialize_ttl_after_modify = 0;

ALTER TABLE stumpcam.otel_metrics_histogram
    ADD COLUMN IF NOT EXISTS `ExpireAt` DateTime MATERIALIZED
        toDateTime(TimeUnix) + toIntervalDay(if(joinGet('stumpcam_meta.tenant_retention', 'metrics_days', TenantId) = 0, 90, joinGet('stumpcam_meta.tenant_retention', 'metrics_days', TenantId)));
ALTER TABLE stumpcam.otel_metrics_histogram MODIFY TTL ExpireAt SETTINGS materialize_ttl_after_modify = 0;

ALTER TABLE stumpcam.otel_metrics_exponential_histogram
    ADD COLUMN IF NOT EXISTS `ExpireAt` DateTime MATERIALIZED
        toDateTime(TimeUnix) + toIntervalDay(if(joinGet('stumpcam_meta.tenant_retention', 'metrics_days', TenantId) = 0, 90, joinGet('stumpcam_meta.tenant_retention', 'metrics_days', TenantId)));
ALTER TABLE stumpcam.otel_metrics_exponential_histogram MODIFY TTL ExpireAt SETTINGS materialize_ttl_after_modify = 0;

ALTER TABLE stumpcam.otel_metrics_summary
    ADD COLUMN IF NOT EXISTS `ExpireAt` DateTime MATERIALIZED
        toDateTime(TimeUnix) + toIntervalDay(if(joinGet('stumpcam_meta.tenant_retention', 'metrics_days', TenantId) = 0, 90, joinGet('stumpcam_meta.tenant_retention', 'metrics_days', TenantId)));
ALTER TABLE stumpcam.otel_metrics_summary MODIFY TTL ExpireAt SETTINGS materialize_ttl_after_modify = 0;

-- Row-level expiry must apply inside mixed-tenant parts: with ttl_only_drop_parts = 1 a short-retention
-- tenant's rows could linger until the longest-retention tenant in the same part expired.
ALTER TABLE stumpcam.otel_traces MODIFY SETTING ttl_only_drop_parts = 0;
ALTER TABLE stumpcam.otel_traces_trace_id_ts MODIFY SETTING ttl_only_drop_parts = 0;
ALTER TABLE stumpcam.otel_logs MODIFY SETTING ttl_only_drop_parts = 0;
ALTER TABLE stumpcam.otel_metrics_gauge MODIFY SETTING ttl_only_drop_parts = 0;
ALTER TABLE stumpcam.otel_metrics_sum MODIFY SETTING ttl_only_drop_parts = 0;
ALTER TABLE stumpcam.otel_metrics_histogram MODIFY SETTING ttl_only_drop_parts = 0;
ALTER TABLE stumpcam.otel_metrics_exponential_histogram MODIFY SETTING ttl_only_drop_parts = 0;
ALTER TABLE stumpcam.otel_metrics_summary MODIFY SETTING ttl_only_drop_parts = 0;
