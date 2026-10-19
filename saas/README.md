# OwlPane ClickHouse Fork (`saas/`)

This directory holds OwlPane's SaaS telemetry cell configuration, schema migrations, upstream sync automation, and engine patch backlog on top of upstream ClickHouse **26.8 LTS**.

## Container Images (GHCR)

Published by [`.github/workflows/owlpane-ghcr-release.yml`](../.github/workflows/owlpane-ghcr-release.yml):

- **Server:** `ghcr.io/owlpane/clickhouse-server:26.8.7-owlpane.1` (and rolling `latest-26.8` for dev)
- **Keeper:** `ghcr.io/owlpane/clickhouse-keeper:26.8.7-owlpane.1` (and rolling `latest-26.8` for dev)

Helm deployment lives in the first-party chart repository **[OwlPane/owlpane-clickhouse-helm](https://github.com/OwlPane/owlpane-clickhouse-helm)** (mirrored in `seo-infra` for Argo CD).

## Upstream Sync Workflow (`owlpane/26.8`)

1. Fetch the latest 26.8 LTS tag from `https://github.com/ClickHouse/ClickHouse.git`:
   ```bash
   ./saas/scripts/sync-upstream.sh v26.8.7.19-lts
   ```
2. Open a pull request from `owlpane/dev` into `owlpane/26.8`.
3. Tag the release as `v26.8.x-owlpane.N` (for example `v26.8.7-owlpane.1`) and push the tag to trigger the GHCR image build for both `clickhouse-server` and `clickhouse-keeper`.
4. Update the pinned image tags in `owlpane-clickhouse-helm` / `seo-infra` and run the API real-ClickHouse integration suite (`owlpane/api/test/clickhouse-integration.test.ts`).

## SaaS Architecture & Engine Patch Backlog

### Current SQL & Config Invariants (`saas/config.d/` & `saas/migrations/`)

- `config.d/custom-settings.xml`: registers `custom_settings_prefixes = "custom_"` so the API can pass `custom_tenant_id` per query.
- `config.d/keeper-client.xml`: configures Keeper quorum and `{shard}/{replica}` macros for `ReplicatedMergeTree`.
- `migrations/0001_otel_tenant_first.sql`: tenant-first (`ORDER BY (TenantId, ...)`) OTel traces, logs, and metrics tables.
- `migrations/0002_tenant_isolation.sql`: read-only `owlpane_api` user, `AS RESTRICTIVE` row policies (`TenantId = getSetting('custom_tenant_id')`), and noisy-neighbor quotas.
- `migrations/0003_retention.sql`: TTL retention policies.
- `migrations/0004_erase_user.sql`: scoped `owlpane_erase` user (`SELECT, ALTER DELETE`) for GDPR/privacy subject erasure.
- `migrations/0005_otel_profiles.sql`: continuous profiling schema.
- `migrations/0006_carbon_input_rollup.sql`: carbon footprint rollup tables.

### Phase 2+ Engine Patches (Tracked in `owlpane/dev` → `owlpane/26.8`)

1. **Hard Read-Only & Execution Bounds for `owlpane_api` Role:** Enforce server-side defaults (`readonly=1`, `max_execution_time`, `max_rows_to_read`) at profile initialization so misconfigured grants fail closed.
2. **Server-Side `custom_tenant_id` Enforcement:** Optional defense-in-depth check rejecting `SELECT` queries against `otel_*` tables from non-admin roles when `custom_tenant_id` is empty.
3. **OTel MergeTree & Projection Defaults:** Tuned compression codecs and ZSTD levels for high-cardinality OTel `Map(LowCardinality(String), String)` attributes.
