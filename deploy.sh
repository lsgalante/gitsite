#!/bin/sh
# Deploy the built site to Cloudflare Pages.
# One-time setup: npx wrangler login
set -e

OUT="$HOME/.cache/gitsite/out"
[ -d "$OUT" ] || { echo "no build output; run ./build.sh first" >&2; exit 1; }

# Token auth when available: wrangler refuses OAuth in non-interactive
# environments (e.g. the gitsite.timer systemd unit).
#
# Credentials and account identifiers live outside the repo, mode 600, the
# way restic-backup.sh keeps its own. They used to be here: the token was
# already read from a file, but the account id was inline -- fine while this
# repo was private, less so now that gitsite publishes itself to
# git.lucas.co. Nothing secret belongs in this file.
ENV_FILE="${GITSITE_ENV_FILE:-$HOME/.config/gitsite/env}"
TOKEN_FILE="$HOME/.config/gitsite-cf-token"   # older layout, token only

if [ -f "$ENV_FILE" ]; then
    . "$ENV_FILE"
    export CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID
elif [ -f "$TOKEN_FILE" ]; then
    # A machine that has not been migrated yet. Without an account id wrangler
    # falls back to the one in its own cache, which is how this used to work.
    CLOUDFLARE_API_TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
    export CLOUDFLARE_API_TOKEN
fi

# Pinned: wrangler 4.121.0 ships a dependency on a nonexistent miniflare
# alpha (npm ETARGET); bump when upstream fixes their release.
npx -y wrangler@4.120.0 pages deploy "$OUT" --project-name=git-lucas-co --branch=main --commit-dirty=true
