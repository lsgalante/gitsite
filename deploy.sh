#!/bin/sh
# Deploy the built site to Cloudflare Pages.
# One-time setup: npx wrangler login
set -e

OUT="$HOME/.cache/gitsite/out"
[ -d "$OUT" ] || { echo "no build output; run ./build.sh first" >&2; exit 1; }

# Token auth when available: wrangler refuses OAuth in non-interactive
# environments (e.g. the gitsite.timer systemd unit).
TOKEN_FILE="$HOME/.config/gitsite-cf-token"
if [ -f "$TOKEN_FILE" ]; then
    CLOUDFLARE_API_TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
    export CLOUDFLARE_API_TOKEN
    export CLOUDFLARE_ACCOUNT_ID=16cc27b259a59a98845182903fee02e4
fi

# Pinned: wrangler 4.121.0 ships a dependency on a nonexistent miniflare
# alpha (npm ETARGET); bump when upstream fixes their release.
npx -y wrangler@4.120.0 pages deploy "$OUT" --project-name=git-lucas-co --branch=main --commit-dirty=true
