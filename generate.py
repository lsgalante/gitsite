#!/usr/bin/env python3
# Static git repository browser generator for git.lucas.co.
# Reads bare mirrors from ~/.cache/gitsite/mirrors (created by build.sh)
# and writes a browsable HTML site to ~/.cache/gitsite/out.

import html
import os
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

BASE = Path(__file__).resolve().parent
CACHE = Path.home() / ".cache" / "gitsite"
MIRRORS = CACHE / "mirrors"
OUT = CACHE / "out"

SITE_TITLE = "git.lucas.co"
HOME_URL = "https://lucas.co"
CLONE_BASE = "https://git.lucas.co"

MAX_DIFF_BYTES = 500_000   # truncate commit patches beyond this
MAX_BLOB_BYTES = 300_000   # don't render file contents beyond this


def read_repos():
    repos = []
    for line in (BASE / "repos.conf").read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, path, desc, mode = line.split("|")
        repos.append({"name": name, "path": path, "desc": desc,
                      "clone": mode == "clone"})
    return repos


def git(mirror, *args, binary=False):
    r = subprocess.run(["git", "-C", str(mirror), *args], capture_output=True)
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed in {mirror}: "
                           f"{r.stderr.decode('utf-8', 'replace')}")
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def esc(s):
    return html.escape(s, quote=True)


def human_size(n):
    if n == "-":  # e.g. submodule entries
        return "-"
    n = int(n)
    if n < 1024:
        return f"{n}B"
    for unit in ("K", "M", "G"):
        n /= 1024
        if n < 1024 or unit == "G":
            return f"{n:.1f}".removesuffix(".0") + unit


def write_page(path, title, body, site_root):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"""<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{esc(title)}</title>
<link rel="stylesheet" href="{site_root}style.css">
</head>
<body>
{body}
</body>
</html>
""")


def rel(from_dir, to_dir):
    # relative prefix ("", "../", "../../", ...) from a page dir to another dir
    r = os.path.relpath(to_dir, from_dir)
    return "" if r == "." else r + "/"


def repo_header(repo, page_dir, repo_dir, active):
    site_root = rel(page_dir, OUT)
    repo_root = rel(page_dir, repo_dir)
    nav = " | ".join(
        f'<a href="{repo_root}{href}">{label}</a>' if label != active
        else f'<span class="active">{label}</span>'
        for label, href in (("Log", "index.html"), ("Files", "files.html"),
                            ("Refs", "refs.html")))
    desc = f'\n<div class="desc">{esc(repo["desc"])}</div>' if repo["desc"] else ""
    clone = (f'\n<div class="clone">git clone {CLONE_BASE}/{repo["name"]}.git</div>'
             if repo["clone"] else "")
    return (f'<div class="crumbs"><a href="{site_root}index.html">{SITE_TITLE}</a>'
            f' / <a href="{repo_root}index.html">{esc(repo["name"])}</a></div>{desc}{clone}\n'
            f'<div class="nav">{nav}</div>\n<hr>\n')


def fmt_diff(patch):
    out = []
    for line in patch.split("\n"):
        e = esc(line)
        if line.startswith("diff --git"):
            out.append(f'<span class="df">{e}</span>')
        elif line.startswith("@@"):
            out.append(f'<span class="dh">{e}</span>')
        elif line.startswith("+") and not line.startswith("+++"):
            out.append(f'<span class="di">{e}</span>')
        elif line.startswith("-") and not line.startswith("---"):
            out.append(f'<span class="dd">{e}</span>')
        else:
            out.append(e)
    return "\n".join(out)


def gen_commit_pages(repo, mirror, repo_dir, commits):
    page_dir = repo_dir / "commit"
    for h, at, author, subject in commits:
        meta = git(mirror, "show", "--no-patch",
                   "--format=%H%x1f%P%x1f%an <%ae>%x1f%ad%x1f%B",
                   "--date=format:%Y-%m-%d %H:%M", h)
        full, parents, who, date, msg = meta.split("\x1f", 4)
        patch_b = git(mirror, "show", "--format=", "--stat", "--patch",
                      "--no-color", h, binary=True)
        truncated = len(patch_b) > MAX_DIFF_BYTES
        patch = patch_b[:MAX_DIFF_BYTES].decode("utf-8", "replace")
        parent_html = " ".join(
            f'<a href="{p}.html">{p[:10]}</a>' for p in parents.split() if p)
        body = repo_header(repo, page_dir, repo_dir, None)
        body += '<table class="meta">\n'
        body += f'<tr><td>commit</td><td>{full}</td></tr>\n'
        if parent_html:
            body += f'<tr><td>parent</td><td>{parent_html}</td></tr>\n'
        body += f'<tr><td>author</td><td>{esc(who)}</td></tr>\n'
        body += f'<tr><td>date</td><td>{date}</td></tr>\n'
        body += '</table>\n'
        body += f'<pre class="msg">{esc(msg.strip())}</pre>\n<hr>\n'
        body += f'<pre class="diff">{fmt_diff(patch)}</pre>\n'
        if truncated:
            body += '<div class="notice">diff truncated</div>\n'
        write_page(page_dir / f"{full}.html",
                   f'{repo["name"]}: {subject}', body, rel(page_dir, OUT))


def gen_log(repo, mirror, repo_dir, commits):
    body = repo_header(repo, repo_dir, repo_dir, "Log")
    body += '<table class="list">\n<tr><td>Date</td><td>Message</td><td>Author</td></tr>\n'
    for h, at, author, subject in commits:
        body += (f'<tr><td>{at}</td>'
                 f'<td><a href="commit/{h}.html">{esc(subject)}</a></td>'
                 f'<td>{esc(author)}</td></tr>\n')
    body += '</table>\n'
    if not commits:
        body += '<div class="notice">no commits yet</div>\n'
    write_page(repo_dir / "index.html", repo["name"], body, rel(repo_dir, OUT))


def gen_files(repo, mirror, repo_dir):
    body = repo_header(repo, repo_dir, repo_dir, "Files")
    body += '<table class="list">\n<tr><td>Mode</td><td>Name</td><td>Size</td></tr>\n'
    entries = []
    try:
        tree = git(mirror, "ls-tree", "-r", "-l", "HEAD").splitlines()
    except RuntimeError:  # empty repository
        tree = []
    for line in tree:
        info, path = line.split("\t", 1)
        mode, otype, _h, size = info.split()
        entries.append((mode, otype, size, path))
        href = quote(f"file/{path}.html")
        body += (f'<tr><td class="mode">{mode}</td>'
                 f'<td><a href="{href}">{esc(path)}</a></td>'
                 f'<td class="size">{human_size(size)}</td></tr>\n')
    body += '</table>\n'
    write_page(repo_dir / "files.html", f'{repo["name"]} files', body,
               rel(repo_dir, OUT))
    return entries


def gen_blob_pages(repo, mirror, repo_dir, entries):
    for mode, otype, size, path in entries:
        out_path = repo_dir / "file" / (path + ".html")
        page_dir = out_path.parent
        body = repo_header(repo, page_dir, repo_dir, None)
        body += f'<div class="path">{esc(path)} ({human_size(size)})</div>\n<hr>\n'
        if otype != "blob":
            body += '<div class="notice">not a regular file</div>\n'
        else:
            content = git(mirror, "cat-file", "blob", f"HEAD:{path}", binary=True)
            if b"\0" in content[:8000]:
                body += '<div class="notice">binary file</div>\n'
            elif len(content) > MAX_BLOB_BYTES:
                body += '<div class="notice">file too large to display</div>\n'
            else:
                text = content.decode("utf-8", "replace")
                lines = text.split("\n")
                if lines and lines[-1] == "":
                    lines.pop()
                w = len(str(len(lines)))
                rows = "\n".join(
                    f'<a class="ln" id="l{i}" href="#l{i}">{i:>{w}}</a> {esc(l)}'
                    for i, l in enumerate(lines, 1))
                body += f'<pre class="blob">{rows}</pre>\n'
        write_page(out_path, f'{repo["name"]}: {path}', body, rel(page_dir, OUT))


def gen_refs(repo, mirror, repo_dir):
    body = repo_header(repo, repo_dir, repo_dir, "Refs")
    for title, pattern in (("Branches", "refs/heads"), ("Tags", "refs/tags")):
        refs = git(mirror, "for-each-ref", "--sort=-creatordate",
                   "--format=%(refname:short)%1f%(objectname:short)%1f%(creatordate:short)",
                   pattern).splitlines()
        if not refs and pattern == "refs/tags":
            continue
        body += f'<div class="section">{title}</div>\n<table class="list">\n'
        for r in refs:
            name, obj, date = r.split("\x1f")
            body += f'<tr><td>{esc(name)}</td><td>{obj}</td><td>{date}</td></tr>\n'
        body += '</table>\n'
    write_page(repo_dir / "refs.html", f'{repo["name"]} refs', body,
               rel(repo_dir, OUT))


def gen_404():
    # a real 404.html switches Pages out of SPA-fallback mode; without it,
    # unknown paths (e.g. git probing loose objects) get index.html with a 200
    body = (f'<div class="crumbs"><a href="index.html">{SITE_TITLE}</a></div>\n'
            '<hr>\n<div class="notice">not found</div>\n')
    write_page(OUT / "404.html", f"{SITE_TITLE}: not found", body, "")


def gen_headers(repos):
    # keep Cloudflare from recompressing/transforming git transport files
    rules = ""
    for repo in repos:
        if repo["clone"]:
            rules += (f'/{repo["name"]}.git/*\n'
                      "  Cache-Control: no-transform\n"
                      "  Content-Type: application/octet-stream\n")
    (OUT / "_headers").write_text(rules)


def gen_index(repos):
    body = (f'<div class="crumbs">{SITE_TITLE}</div>\n'
            f'<div class="desc"><a href="{HOME_URL}">Lucas Galante</a>\'s projects</div>\n<hr>\n')
    body += '<table class="list">\n<tr><td>Name</td><td>Description</td><td>Last commit</td></tr>\n'
    for repo in repos:
        mirror = MIRRORS / f'{repo["name"]}.git'
        try:
            last = git(mirror, "log", "-1", "--format=%as", "HEAD").strip()
        except RuntimeError:  # empty repository
            last = "-"
        body += (f'<tr><td><a href="{quote(repo["name"])}/index.html">{esc(repo["name"])}</a></td>'
                 f'<td>{esc(repo["desc"])}</td><td>{last}</td></tr>\n')
    body += '</table>\n'
    write_page(OUT / "index.html", SITE_TITLE, body, "")


def main():
    repos = read_repos()
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    shutil.copy(BASE / "style.css", OUT / "style.css")
    font = BASE / "font"
    if font.is_dir():
        shutil.copytree(font, OUT / "font")

    for repo in repos:
        mirror = MIRRORS / f'{repo["name"]}.git'
        if not mirror.is_dir():
            sys.exit(f"missing mirror {mirror}; run build.sh")
        repo_dir = OUT / repo["name"]
        commits = []
        try:
            log = git(mirror, "log", "--format=%H%x1f%as%x1f%an%x1f%s", "HEAD")
        except RuntimeError:  # empty repository
            log = ""
        for line in log.splitlines():
            h, at, author, subject = line.split("\x1f")
            commits.append((h, at, author, subject))
        gen_log(repo, mirror, repo_dir, commits)
        gen_commit_pages(repo, mirror, repo_dir, commits)
        entries = gen_files(repo, mirror, repo_dir)
        gen_blob_pages(repo, mirror, repo_dir, entries)
        gen_refs(repo, mirror, repo_dir)
        print(f'{repo["name"]}: {len(commits)} commits, {len(entries)} files')

    gen_404()
    gen_headers(repos)
    gen_index(repos)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
