#!/bin/sh
# Deploy the built site to Cloudflare Pages.
# One-time setup: npx wrangler login
set -e

OUT="$HOME/.cache/gitsite/out"
[ -d "$OUT" ] || { echo "no build output; run ./build.sh first" >&2; exit 1; }

npx wrangler pages deploy "$OUT" --project-name=git-lucas-co --branch=main --commit-dirty=true
