#!/usr/bin/env bash
# Publish the site to the gh-pages branch, without touching the working tree.
#
# The branch holds the page, the converter the page imports, and a `.nojekyll` marker, and
# nothing else — so what is published cannot drift from what the repository builds. The page's
# converter is compiled here, from `src/examples/07-convert`, which is the same source the tests
# run against; a page whose converter was hand-edited cannot be published.
#
# The commit is written with plumbing (hash-object / mktree / commit-tree) rather than by
# checking the branch out, so switching branches by hand is not part of publishing.
#
#     bash scripts/publish-site.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

page="site/index.html"
module="site/convert.js"
[ -f "$page" ] || { echo "no $page"; exit 1; }

echo "building the converter"
moon build src/examples/07-convert --target js --release
cp "_build/js/release/build/examples/07-convert/07-convert.js" "$module"

blob="$(git hash-object -w "$page")"
script="$(git hash-object -w "$module")"
empty="$(printf '' | git hash-object -w --stdin)"
tree="$(printf '100644 blob %s\t.nojekyll\n100644 blob %s\tindex.html\n100644 blob %s\tconvert.js\n' \
  "$empty" "$blob" "$script" | git mktree)"
commit="$(git commit-tree "$tree" -m "site: publish $page

Pushed by scripts/publish-site.sh from $(git rev-parse --short HEAD), with the converter built
from src/examples/07-convert.")"

git branch -f gh-pages "$commit"
# Every publish is an orphan commit built from an empty tree, so it shares no history with the
# last one: the branch is a build artifact, and replacing it is the point.
git push --force origin gh-pages
echo "published $(git rev-parse --short HEAD):$page as $(git rev-parse --short "$commit")"
