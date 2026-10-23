#!/bin/zsh
# Publishes web/ to the "carriage" project on Cloudflare Pages (carriage.pages.dev). Needs `wrangler login` once.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
npx --yes wrangler@4 pages deploy "$ROOT/web" --project-name carriage --branch main --commit-dirty=true
