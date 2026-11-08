#!/usr/bin/env bash
# Publish site/index.html to the gh-pages branch, without touching the working tree.
#
# The published branch holds one page and a `.nojekyll` marker and nothing else, so a build of
# the site cannot drift from what the repository documents. The commit is written with
# plumbing (hash-object / mktree / commit-tree) rather than by checking the branch out, so
# switching branches by hand is not part of publishing.
#
#     bash scripts/publish-site.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

page="site/index.html"
[ -f "$page" ] || { echo "no $page"; exit 1; }

blob="$(git hash-object -w "$page")"
empty="$(printf '' | git hash-object -w --stdin)"
tree="$(printf '100644 blob %s\t.nojekyll\n100644 blob %s\tindex.html\n' "$empty" "$blob" | git mktree)"
commit="$(git commit-tree "$tree" -m "site: publish $page

Pushed by scripts/publish-site.sh from $(git rev-parse --short HEAD).")"

git branch -f gh-pages "$commit"
# Every publish is an orphan commit built from an empty tree, so it shares no history with the
# last one: the branch is a build artifact, and replacing it is the point.
git push --force origin gh-pages
echo "published $(git rev-parse --short HEAD):$page as $(git rev-parse --short "$commit")"
