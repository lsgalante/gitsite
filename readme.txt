gitsite
=======

The git hooks every repo shares, and the list of repos that get them.

This repo used to also build git.lucas.co, a static mirror of the repos.
That site was retired on 2026-10-14: GitHub (github.com/lsgalante) is the
only place the repos are published. The name stayed because every repo's
hooks are symlinks into this directory.

Files
-----
repos.conf        the repos: name|GitHub URL|description|mode (mode is
                  left over from the mirror and unused)
post-commit-push  git post-commit hook: pushes the committed branch to
                  origin, so committing is publishing
pre-commit-scan   git pre-commit hook: refuses a commit whose staged
                  changes look like a secret (gitleaks), since the push
                  hook would publish it seconds later; warns and lets the
                  commit through where gitleaks is not installed
install-hooks.sh  symlinks both hooks into every repo in repos.conf

Publishing model
----------------
Committing is NOT publishing; pushing is. Each repo's origin is
https://github.com/lsgalante/<name>.git. Every repo in repos.conf has
post-commit-push as its post-commit hook, so in practice the push happens
on commit and a plain commit IS the publishing step. The hook never forces:
a rejected push leaves the commit local and says so, and you resolve it
with git pull / git push as usual. It does nothing on a detached HEAD or
mid-rebase.

pre-commit-scan runs first: with gitleaks installed it scans the staged
diff and refuses a commit that looks like it carries a credential. Without
gitleaks the commit goes through with a warning (pacman -S gitleaks).

Adding a repo
-------------
Create it on GitHub (gh repo create lsgalante/<name> --public), push, add a
line to repos.conf, and run install-hooks.sh. Re-run install-hooks.sh after
cloning a repo fresh, too.
