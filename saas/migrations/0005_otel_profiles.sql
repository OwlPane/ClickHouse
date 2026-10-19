-- Stumpcam 0005: OTLP continuous profiling samples (Phase L5).
-- Ingest via OpenTelemetry Collector clickhouse exporter (profiles pipeline) or
-- application writers that populate StackFrame + Samples. TenantId is materialized
-- from resource attributes like otel_traces.

CREATE TABLE IF NOT EXISTS stumpcam.otel_profiles
(
    `TenantId` LowCardinality(String) MATERIALIZED ResourceAttributes['stumpcam.tenant_id'],
    `Environment` LowCardinality(String) MATERIALIZED if(ResourceAttributes['deployment.environment.name'] != '', ResourceAttributes['deployment.environment.name'], ResourceAttributes['deployment.environment']),
    `Timestamp` DateTime64(9) CODEC(Delta(8), ZSTD(1)),
    `ServiceName` LowCardinality(String) CODEC(ZSTD(1)),
    `ResourceAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    `ProfileType` LowCardinality(String) DEFAULT 'cpu' CODEC(ZSTD(1)),
    `StackFrame` String CODEC(ZSTD(1)),
    `Samples` UInt64 CODEC(ZSTD(1)),
    INDEX idx_stack StackFrame TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 8
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/stumpcam/otel_profiles', '{replica}')
PARTITION BY toDate(Timestamp)
ORDER BY (TenantId, Environment, ServiceName, ProfileType, Timestamp)
TTL toDateTime(Timestamp) + INTERVAL 7 DAY
SETTINGS index_granularity = 8192, ttl_only_drop_parts = 1;

CREATE ROW POLICY IF NOT EXISTS tenant_scope ON stumpcam.otel_profiles
    AS RESTRICTIVE USING TenantId = getSetting('custom_tenant_id') TO owlpane_api;
