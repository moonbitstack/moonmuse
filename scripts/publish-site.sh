#!/usr/bin/env bash
# Publish the site to the gh-pages branch, without touching the working tree.
#
# The branch holds the page, the converter the page imports, the share card, the 404 and a
# `.nojekyll` marker, and nothing else — so what is published cannot drift from what the
# repository builds. The converter is compiled here, from `src/examples/07-convert`, which is
# the same source the tests run against.
#
# The commit is written with plumbing (hash-object / mktree / commit-tree) rather than by
# checking the branch out, so switching branches by hand is not part of publishing.
#
#     bash scripts/publish-site.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

[ -f "site/index.html" ] || { echo "no site/index.html"; exit 1; }

echo "building the converter"
moon build src/examples/07-convert --target js --release
cp "_build/js/release/build/examples/07-convert/07-convert.js" "site/convert.js"

# Every published file, by the name it takes on the branch.
files=("index.html" "convert.js" "og.png" "404.html")
tree_file="$(mktemp)"
trap 'rm -f "$tree_file"' EXIT

printf '100644 blob %s\t.nojekyll\n' "$(printf '' | git hash-object -w --stdin)" > "$tree_file"
for name in "${files[@]}"; do
  [ -f "site/$name" ] || { echo "no site/$name"; exit 1; }
  printf '100644 blob %s\t%s\n' "$(git hash-object -w "site/$name")" "$name" >> "$tree_file"
done

tree="$(git mktree < "$tree_file")"
commit="$(git commit-tree "$tree" -m "site: publish the page

Pushed by scripts/publish-site.sh from $(git rev-parse --short HEAD), with the converter built
from src/examples/07-convert: ${files[*]}.")"

git branch -f gh-pages "$commit"
# Every publish is an orphan commit built from an empty tree, so it shares no history with the
# last one: the branch is a build artifact, and replacing it is the point.
git push --force origin gh-pages
echo "published $(git rev-parse --short HEAD) as $(git rev-parse --short "$commit")"
