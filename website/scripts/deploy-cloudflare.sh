#!/usr/bin/env bash
set -euo pipefail

project_name="${CF_PAGES_PROJECT:-contactsdeduper-site}"
branch_name="${CF_PAGES_BRANCH:-main}"

if [[ -n "${CLOUDFLARE_API_TOKEN:-}" && -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  echo "CLOUDFLARE_ACCOUNT_ID is required when using CLOUDFLARE_API_TOKEN." >&2
  exit 1
fi

echo "Building and checking the static site..."
npm run build
npm run check

echo "Deploying dist/ to Cloudflare Pages project: ${project_name}"
npx wrangler pages deploy dist \
  --project-name "${project_name}" \
  --branch "${branch_name}"
