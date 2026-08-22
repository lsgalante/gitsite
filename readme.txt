git.lucas.co
============

Static git repo browser for Cloudflare Pages. Generates HTML pages
(log, commits with diffs, file browser, refs) for the repos listed in
repos.conf, plus dumb-http clone support so
`git clone https://git.lucas.co/<name>.git` works from static hosting.

Files
-----
repos.conf   which repos to publish: name|path|description|mode
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
rebuilds + deploys only when a repo in repos.conf has a new HEAD. That
timer is what makes "committing locally IS publishing" true — the repos
it mirrors have no push remotes, so if it stops running, nothing reaches
git.lucas.co and the local commits look published but aren't.

The units are NOT installed by any script here. On a new machine:

    cp gitsite.service gitsite.timer ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now gitsite.timer

Check:  systemctl --user list-timers gitsite.timer
Log:    ~/.cache/gitsite/autodeploy.log

One-time Cloudflare setup
-------------------------
1. npx wrangler login
2. ./deploy.sh (creates the "git-lucas-co" Pages project on first run)
3. Cloudflare dashboard -> Workers & Pages -> git-lucas-co ->
   Custom domains -> add git.lucas.co

Notes
-----
- website repo is mode "browse" because its history is 452MB of media;
  flip to "clone" in repos.conf if you want it clonable anyway.
- Mirrors live in ~/.cache/gitsite/mirrors, repacked into <=20MB packs
  (Cloudflare rejects files over 25MB). Delete a mirror dir to force a
  fresh re-mirror.
- To add a repo: add a line to repos.conf, run build.sh + deploy.sh.
