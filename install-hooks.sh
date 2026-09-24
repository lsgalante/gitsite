#!/bin/sh
# Symlink the hooks into every repo listed in repos.conf: post-commit-push as
# its post-commit hook and pre-commit-scan as its pre-commit hook. Safe to
# re-run: an existing symlink is refreshed, and a hook that is a real file
# (someone's own) is left alone and reported.
#
# Work trees are found by NAME under $GIT_WORK_ROOTS, since repos.conf records
# only where a repo is mirrored from. A name that resolves to nothing fails
# the run rather than being skipped.
set -eu

BASE=$(dirname "$(readlink -f "$0")")
# hook-name=file, one pair per word.
HOOKS="pre-commit=pre-commit-scan post-commit=post-commit-push"
WORK_ROOTS="${GIT_WORK_ROOTS:-$HOME/projects/cce $HOME/projects}"
FAILED=""

names=$(grep -v '^#' "$BASE/repos.conf" | grep -v '^[[:space:]]*$' | cut -d'|' -f1)
for name in $names; do
    wt=""
    for root in $WORK_ROOTS; do
        if [ -d "$root/$name/.git" ]; then wt="$root/$name"; break; fi
    done
    if [ -z "$wt" ]; then
        echo "!! $name: no work tree under $WORK_ROOTS"
        FAILED="$FAILED $name"
        continue
    fi
    hooks=$(git -C "$wt" rev-parse --path-format=absolute --git-path hooks)
    mkdir -p "$hooks"
    bad=""
    for pair in $HOOKS; do
        dest="$hooks/${pair%%=*}"
        if [ -e "$dest" ] && [ ! -L "$dest" ]; then
            echo "!! $name: $dest exists and is not a symlink -- left alone"
            bad=1
            continue
        fi
        ln -sfn "$BASE/${pair#*=}" "$dest"
    done
    if [ -n "$bad" ]; then
        FAILED="$FAILED $name"
        continue
    fi
    echo "   $name"
done

echo
if [ -n "$FAILED" ]; then
    echo "done, with failures:$FAILED"
    exit 1
fi
echo "done: pre-commit and post-commit hooks installed in every repo"
