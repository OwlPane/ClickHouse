-- Factor-free carbon input rollup (methodology §10). Energy maths stay in the API; this table only
-- stores aggregates needed for long Team windows without scanning raw gauges.

CREATE TABLE IF NOT EXISTS stumpcam.otel_carbon_node_buckets (
  TenantId String,
  Environment LowCardinality(String),
  Cluster LowCardinality(String),
  Node LowCardinality(String),
  Bucket DateTime,
  AvgCpuCores Float64,
  AvgAllocCpu Float64,
  AvgMemGb Float64,
  Provider LowCardinality(String),
  Region LowCardinality(String),
  InstanceType LowCardinality(String),
  ExpireAt DateTime
) ENGINE = AggregatingMergeTree()
PARTITION BY toYYYYMM(Bucket)
ORDER BY (TenantId, Environment, Cluster, Node, Bucket)
TTL ExpireAt;

CREATE MATERIALIZED VIEW IF NOT EXISTS stumpcam.otel_carbon_node_buckets_mv TO stumpcam.otel_carbon_node_buckets AS
SELECT
  TenantId,
  Environment,
  anyIf(ResourceAttributes['k8s.cluster.name'], MetricName = 'k8s.node.cpu.usage') AS Cluster,
  ResourceAttributes['k8s.node.name'] AS Node,
  toStartOfInterval(TimeUnix, INTERVAL 5 MINUTE) AS Bucket,
  avgIf(Value, MetricName = 'k8s.node.cpu.usage') AS AvgCpuCores,
  avgIf(Value, MetricName = 'k8s.node.allocatable_cpu') AS AvgAllocCpu,
  avgIf(Value, MetricName = 'k8s.node.memory.working_set') / 1073741824 AS AvgMemGb,
  anyIf(ResourceAttributes['cloud.provider'], MetricName = 'k8s.node.cpu.usage') AS Provider,
  anyIf(ResourceAttributes['cloud.region'], MetricName = 'k8s.node.cpu.usage') AS Region,
  anyIf(if(ResourceAttributes['host.type'] != '', ResourceAttributes['host.type'], ResourceAttributes['cloud.instance.type']), MetricName = 'k8s.node.cpu.usage') AS InstanceType,
  max(ExpireAt) AS ExpireAt
FROM stumpcam.otel_metrics_gauge
WHERE MetricName IN ('k8s.node.cpu.usage', 'k8s.node.allocatable_cpu', 'k8s.node.memory.working_set')
  AND ResourceAttributes['k8s.node.name'] != ''
GROUP BY TenantId, Environment, Node, Bucket;
