# Contributing to OwlPane/ClickHouse

1. Branch from **`owlpane/dev`** (tracking **`owlpane/26.8`**):
   ```bash
   git fetch origin
   git checkout -B owlpane/dev origin/owlpane/26.8
   ```
2. Keep SaaS schema, configs, and upstream sync helpers under **`saas/`**.
3. Open a pull request **`owlpane/dev` → `owlpane/26.8`**.
4. After merging to **`owlpane/26.8`**, tag `v26.8.x-owlpane.N` to publish `ghcr.io/owlpane/clickhouse-server` and `ghcr.io/owlpane/clickhouse-keeper`.
