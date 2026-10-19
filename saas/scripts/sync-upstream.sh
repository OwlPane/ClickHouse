#!/usr/bin/env bash
set -euo pipefail

# Sync OwlPane/ClickHouse with an upstream ClickHouse 26.8 LTS tag.
# Usage: ./saas/scripts/sync-upstream.sh [upstream-tag]
UPSTREAM_TAG="${1:-v26.8.7.19-lts}"
UPSTREAM_URL="https://github.com/ClickHouse/ClickHouse.git"

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$UPSTREAM_URL"
fi

echo "==> Fetching upstream tag ${UPSTREAM_TAG}..."
git fetch --depth 1 upstream tag "${UPSTREAM_TAG}"

echo "==> Merging ${UPSTREAM_TAG} into current branch ($(git branch --show-current))..."
git merge --no-edit "${UPSTREAM_TAG}"

echo "==> Sync complete. Open a PR from owlpane/dev -> owlpane/26.8 and tag v26.8.x-owlpane.N after merge."
