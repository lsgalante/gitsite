git.lucas.co
============

Static git repo browser for Cloudflare Pages. Generates HTML pages
(log, commits with diffs, file browser, refs) for the repos listed in
repos.conf, plus dumb-http clone support so
`git clone https://git.lucas.co/<name>.git` works from static hosting.

Files
-----
repos.conf   which repos to publish: name|path|description|mode
             path is the GitHub URL the repo is mirrored from -- what
             this reads HEAD from, not a work tree
             mode "clone" = browse + clonable, "browse" = browse only
generate.py  the HTML generator
build.sh     syncs mirrors, runs generate.py, adds clone files
deploy.sh    pushes the built site to Cloudflare Pages
autodeploy.sh
             build + deploy, but only when a listed repo's HEAD moved
gitsite.service, gitsite.timer
             systemd user units that run autodeploy.sh hourly — see
             "Automatic publishing" below; nothing here installs them
style.css    matches lucas.co (black, white, blue links, Circe)

Workflow
--------
./build.sh    # output goes to ~/.cache/gitsite/out (not in Dropbox)
./deploy.sh   # needs one-time `npx wrangler login`

Preview locally:
python3 -m http.server -d ~/.cache/gitsite/out 8931

Automatic publishing
--------------------
gitsite.timer runs autodeploy.sh hourly (randomized up to 5m; Persistent
so a run missed while the machine was off catches up), and autodeploy.sh
rebuilds + deploys only when a repo in repos.conf has a new HEAD. If it
stops running, nothing reaches git.lucas.co and pushed commits look
published but aren't.

The units are NOT installed by any script here. On a new machine:

    cp gitsite.service gitsite.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now gitsite.timer

Check:  systemctl --user list-timers gitsite.timer
Log:    ~/.cache/gitsite/autodeploy.log

Publishing model
----------------
Committing is NOT publishing; pushing is. Each repo's origin is
https://github.com/lsgalante/<name>.git, GitHub is canonical, and this
site is a mirror of it: repos.conf lists the GitHub URLs, build.sh keeps a
bare mirror of each in ~/.cache/gitsite/mirrors, and autodeploy.sh asks
GitHub (git ls-remote) whether any HEAD moved. So:

    git commit ...              # local only
    git push                    # the publishing step
                                # gitsite.timer then deploys it

The 27 crates pinned to https://git.lucas.co/<name>.git?rev=... keep
working because the dumb-http clone dirs are built from the same mirrors;
a rev exists here as long as it is reachable on GitHub.

One-time Cloudflare setup
-------------------------
1. npx wrangler login
2. ./deploy.sh (creates the "git-lucas-co" Pages project on first run)
3. Cloudflare dashboard -> Workers & Pages -> git-lucas-co ->
   Custom domains -> add git.lucas.co

Credentials
-----------
deploy.sh reads ~/.config/gitsite/env (mode 600, NOT versioned), the same
shape restic-backup.sh uses:

    CLOUDFLARE_API_TOKEN=...
    CLOUDFLARE_ACCOUNT_ID=...

A token is needed for unattended runs: wrangler refuses OAuth in
non-interactive environments, so the gitsite.timer unit cannot use a login
session. The account id used to be inline in deploy.sh, which stopped being
reasonable once this repo started publishing itself to git.lucas.co. It is
still in this repo's git history; it is an identifier rather than a
credential, and does nothing without the token, which has never been in the
repo.

The older ~/.config/gitsite-cf-token (token only, no account id) is still
honoured as a fallback for a machine that has not been migrated.

Notes
-----
- website repo is mode "browse" because its history is 452MB of media;
  flip to "clone" in repos.conf if you want it clonable anyway.
- Mirrors live in ~/.cache/gitsite/mirrors, repacked into <=20MB packs
  (Cloudflare rejects files over 25MB). Delete a mirror dir to force a
  fresh re-mirror.
- To add a repo: create it on GitHub (gh repo create lsgalante/<name>
  --public), push, add a line to repos.conf, run build.sh + deploy.sh.
