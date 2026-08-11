#!/bin/sh
# Build git.lucas.co: sync repo mirrors, generate HTML, lay down dumb-http clones.
# Output goes to ~/.cache/gitsite/out (kept out of Dropbox on purpose).
set -e

BASE=$(dirname "$(readlink -f "$0")")
CACHE="$HOME/.cache/gitsite"
mkdir -p "$CACHE/mirrors"

grep -v '^#' "$BASE/repos.conf" | grep -v '^$' | while IFS='|' read -r name path desc mode; do
    m="$CACHE/mirrors/$name.git"
    if [ ! -d "$m" ]; then
        echo "mirroring $name"
        git clone --quiet --mirror "$path" "$m"
        git -C "$m" config gc.auto 0
        # small packfiles: Cloudflare Pages rejects files over 25MB
        git -C "$m" repack -a -d -q --max-pack-size=20m
    else
        git -C "$m" fetch --quiet --prune origin
    fi
done

python3 "$BASE/generate.py"

grep -v '^#' "$BASE/repos.conf" | grep -v '^$' | while IFS='|' read -r name path desc mode; do
    if [ "$mode" = "clone" ]; then
        m="$CACHE/mirrors/$name.git"
        git -C "$m" update-server-info
        cp -al "$m" "$CACHE/out/$name.git"
    fi
done

echo "site built at $CACHE/out"
