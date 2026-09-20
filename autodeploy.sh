#!/bin/sh
# Publish git.lucas.co only if any listed repo has new commits.
# Run by the gitsite.timer systemd user unit; log: ~/.cache/gitsite/autodeploy.log
set -e

BASE=$(dirname "$(readlink -f "$0")")
STATE="$HOME/.cache/gitsite/last-publish-heads"

current=$(grep -v '^#' "$BASE/repos.conf" | grep -v '^$' | \
    while IFS='|' read -r name path desc mode; do
        # path is a URL (GitHub); ls-remote is one round trip per repo. A
        # repo with no commits yet answers nothing, hence "empty".
        echo "$name $(git ls-remote "$path" HEAD 2>/dev/null | cut -f1 | grep . || echo empty)"
    done | sha256sum | cut -d' ' -f1)

if [ -f "$STATE" ] && [ "$(cat "$STATE")" = "$current" ]; then
    echo "$(date -Is) no changes, skipping"
    exit 0
fi

"$BASE/build.sh"
"$BASE/deploy.sh"
printf '%s' "$current" > "$STATE"
echo "$(date -Is) published"
