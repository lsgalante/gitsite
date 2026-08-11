#!/bin/sh
# Deploy the built site to Cloudflare Pages.
# One-time setup: npx wrangler login
set -e

OUT="$HOME/.cache/gitsite/out"
[ -d "$OUT" ] || { echo "no build output; run ./build.sh first" >&2; exit 1; }

# Pinned: wrangler 4.121.0 ships a dependency on a nonexistent miniflare
# alpha (npm ETARGET); bump when upstream fixes their release.
npx -y wrangler@4.120.0 pages deploy "$OUT" --project-name=git-lucas-co --branch=main --commit-dirty=true
