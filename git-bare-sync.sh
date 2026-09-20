#!/bin/sh
# Create and maintain the local bare-repo layer under ~/git.
#
#   ~/git/<name>.git          bare, pushable -- the canonical copy
#         ^ git push
#   working tree              gitsite mirrors from the bare repo -> git.lucas.co
#
# Why this exists: nothing in the setup could be pushed to. The cce repos'
# origin was https://git.lucas.co/<name>.git, which is static dumb-http -- you
# can clone from it, you cannot push to it, because there is no receive-pack
# behind static hosting. So "published" meant "a timer happened to run", with
# no signal either way. gitsite's own readme names the hazard: if the timer
# stops, local commits look published but aren't.
#
# With a bare remote, `git push` succeeds or fails now, and the bare repo is a
# second real copy on disk -- independent of the working tree, so an rm -rf no
# longer costs everything since the last nightly restic run.
#
# Safe to re-run. Existing bare repos are fetched into, not recreated, and an
# existing origin is preserved under a descriptive name rather than dropped.
#
# Which repos: every line of repos.conf, by NAME (field 1). Field 2 is the BARE
# path -- what gitsite reads HEAD from -- not a work tree, so work trees are
# resolved by name under $WORK_ROOTS. A name that resolves to nothing is
# reported and fails the run; it is never silently skipped.
#
# Run it only on the machine that owns the bare layer. The bare repos are
# canonical and live on exactly one host; on any other machine a work tree's
# origin is a URL pointing back at that host over the network, and this script
# -- which computes bare="$BARE_ROOT/$name.git" and rewrites origin to that
# local path -- would hand the second machine its own divergent bare repos and
# file the real remote away under "previous". It would then look like it was
# publishing while pushing to its own disk, which is the failure this whole
# arrangement exists to prevent. A remote-looking origin is therefore refused.
# On a second machine just use git: `git push origin <branch>`.
#
# GIT_BARE_HOST=1 overrides the refusal. That is the migration case this script
# was written for, where an old fetch-only origin (git.lucas.co, github) is
# deliberately replaced by a local bare repo.
#
# Usage:  git-bare-sync.sh [--dry-run]
#   env:  GIT_BARE_ROOT (default ~/git), GIT_WORK_ROOTS, REPOS_CONF,
#         GIT_BARE_HOST

set -eu

BARE_ROOT="${GIT_BARE_ROOT:-$HOME/git}"
REPOS_CONF="${REPOS_CONF:-$HOME/Dropbox/src/gitsite/repos.conf}"
DRY=""
[ "${1:-}" = "--dry-run" ] && DRY=1

# Where work trees live. repos.conf does NOT record them -- its field 2 is the
# BARE path, because that is what gitsite reads HEAD from -- so a repo's work
# tree is found by NAME under these roots, first match winning.
WORK_ROOTS="${GIT_WORK_ROOTS:-$HOME/projects/cce $HOME/projects $HOME/Dropbox/src}"

# Repos that are not published through gitsite and so are absent from
# repos.conf. Add a line here (a work-tree path), or add them to repos.conf to
# publish them too. Empty now that hou-control and gitsite are both listed
# there -- they were carried here with a path that had since gone stale.
EXTRA_REPOS=""

# The work tree for a repo name, or nothing if it is not under WORK_ROOTS.
find_worktree() {
    _name=$1
    for _root in $WORK_ROOTS; do
        if [ -d "$_root/$_name/.git" ]; then
            printf '%s\n' "$_root/$_name"
            return 0
        fi
    done
    return 1
}

say() { printf '%s\n' "$*"; }
run() {
    if [ -n "$DRY" ]; then
        printf '    would: %s\n' "$*"
    else
        "$@"
    fi
}

# Does this origin point at a bare layer on another machine? A local bare repo
# is an absolute path; a URL scheme or an scp-style host:path is somewhere
# else. file:// is a URL but still local, so it is not remote.
is_remote_url() {
    case "$1" in
        ''|/*|./*|../*|~*) return 1 ;;
        file://*)          return 1 ;;
        *://*)             return 0 ;;
        *:*)               return 0 ;;
        *)                 return 1 ;;
    esac
}

# A name for an existing origin, so replacing it loses no information.
preserved_name() {
    case "$1" in
        *git.lucas.co*) echo "published" ;;   # static mirror: fetch-only
        *codeberg.org*) echo "codeberg"  ;;   # no longer used
        *github.com*)   echo "github"    ;;
        *)              echo "previous"  ;;
    esac
}

# Runs in a subshell so a failure inside it is returnable rather than fatal
# under `set -e`. fail() records the first error and keeps going, so a repo
# that cannot be cloned still gets reported rather than silently skipped.
sync_one() (
    set +e
    rc=0
    fail() { rc=1; }
    path=$1
    [ -d "$path/.git" ] || { say "  skip $path (not a git work tree)"; exit 0; }
    name=$(basename "$path")
    bare="$BARE_ROOT/$name.git"
    current=$(git -C "$path" remote get-url origin 2>/dev/null || true)

    # Client-mode guard, before anything is written: creating the bare repo is
    # itself a mutation, so the origin has to be inspected first.
    if [ -z "${GIT_BARE_HOST:-}" ] && is_remote_url "$current"; then
        say "  !! $name: origin is $current"
        say "     That is a bare layer on another machine. Running here would"
        say "     replace it with $bare, giving this machine its own divergent"
        say "     bare repos while the real remote is filed away as 'previous'."
        say "     Push from here with git directly: git push origin <branch>."
        say "     Run this only on the host that owns $BARE_ROOT."
        say "     GIT_BARE_HOST=1 overrides, for replacing a legacy origin."
        fail
        exit $rc
    fi

    if [ -d "$bare" ]; then
        say "  $name: bare exists"
    else
        say "  $name: creating $bare"
        run git clone --bare --quiet "$path" "$bare" || { fail; exit $rc; }
        # clone --bare leaves a back-reference to the work tree; the bare repo
        # is the upstream, so it should not point anywhere.
        run git -C "$bare" remote remove origin 2>/dev/null || true
        run git -C "$bare" config gc.auto 6700
    fi

    if [ -n "$current" ]; then
        case "$current" in
            "$bare") : ;;   # already pointed at the bare repo
            *)
                keep=$(preserved_name "$current")
                if git -C "$path" remote get-url "$keep" >/dev/null 2>&1; then
                    run git -C "$path" remote remove origin
                else
                    say "    keeping old origin as '$keep' ($current)"
                    run git -C "$path" remote rename origin "$keep"
                fi
                run git -C "$path" remote add origin "$bare"
                ;;
        esac
    else
        run git -C "$path" remote add origin "$bare"
    fi

    # A repo with no commits yet has nothing to push and is not a failure.
    if ! git -C "$path" rev-parse --quiet --verify HEAD >/dev/null 2>&1; then
        say "    no commits yet -- bare repo created, nothing to push"
        exit 0
    fi

    # Push every branch and tag. --all covers main/master without caring which.
    run git -C "$path" push --quiet origin --all || fail
    run git -C "$path" push --quiet origin --tags || fail

    branch=$(git -C "$path" symbolic-ref --short HEAD 2>/dev/null || true)
    if [ -n "$branch" ]; then
        run git -C "$path" branch --quiet --set-upstream-to="origin/$branch" "$branch" 2>/dev/null || true
        # Point the bare repo's HEAD at the same branch, so cloning it checks
        # out the right thing and gitsite shows the right default.
        run git -C "$bare" symbolic-ref HEAD "refs/heads/$branch" || fail
    fi
    exit $rc
)

[ -n "$DRY" ] && say "DRY RUN -- nothing will be written"
run mkdir -p "$BARE_ROOT"

FAILED=""

# One damaged repo must not abort the other thirty-three. A repo whose refs
# Dropbox has mangled makes git exit non-zero here; record it and carry on.
attempt() {
    if sync_one "$1"; then
        :
    else
        say "  !! $(basename "$1") FAILED -- see above"
        FAILED="$FAILED $(basename "$1")"
    fi
}

say "from $REPOS_CONF:"
# Read the whole list first: the loop body runs in this shell, not a subshell,
# so a failure is visible to the caller rather than swallowed by a pipeline.
# Fields 1|2 are name|bare-path (no spaces around the separators, per the file's
# own header). This used to iterate field 2 and hand it to sync_one as though it
# were a work tree; every repo then reported "not a git work tree" and was
# skipped, so nothing was pushed for weeks while commits piled up looking
# published. Hence: resolve by NAME, and treat an unresolvable one as a failure
# rather than a skip.
list=$(grep -v '^#' "$REPOS_CONF" | grep -v '^[[:space:]]*$' | cut -d'|' -f1,2)
for entry in $list; do
    name=${entry%%|*}
    conf_bare=${entry#*|}
    if ! path=$(find_worktree "$name"); then
        say "  !! $name: no work tree under $WORK_ROOTS -- NOT synced"
        FAILED="$FAILED $name"
        continue
    fi
    # gitsite publishes whatever field 2 points at, while this script maintains
    # $BARE_ROOT/<name>.git. If the two ever diverge, pushes land in a repo the
    # site never reads -- silent non-publishing again, from the other end.
    if [ "$BARE_ROOT" = "$HOME/git" ] && [ "$conf_bare" != "$BARE_ROOT/$name.git" ]; then
        say "  !! $name: repos.conf publishes $conf_bare, but this syncs"
        say "     $BARE_ROOT/$name.git -- pushes would not reach the site"
        FAILED="$FAILED $name"
        continue
    fi
    attempt "$path"
done

if [ -n "$EXTRA_REPOS" ]; then
    say "extras:"
    for path in $EXTRA_REPOS; do
        attempt "$path"
    done
fi

say ""
if [ -n "$FAILED" ]; then
    say "done, with failures:$FAILED"
    say "bare repos in $BARE_ROOT"
    exit 1
fi
say "done. bare repos in $BARE_ROOT"
