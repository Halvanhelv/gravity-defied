#!/usr/bin/env bash
# Builds the web version and publishes GitHub Pages: the landing page (site/) at the root,
# the game under play/. Run from anywhere; DragonRuby must be unpacked one level above mygame.
#
#   tools/deploy_pages.sh             # build and push to gh-pages
#   tools/deploy_pages.sh --preview   # build into a temp dir and print it, push nothing
set -euo pipefail

game_dir=$(cd "$(dirname "$0")/.." && pwd)
engine_dir=$(dirname "$game_dir")
meta="$game_dir/metadata/game_metadata.txt"
gameid=$(sed -n 's/^gameid=//p' "$meta")
version=$(sed -n 's/^version=//p' "$meta")
build="$engine_dir/builds/$gameid-html5-$version"

(cd "$engine_dir" && ./dragonruby-publish --package --platforms=html5 "$(basename "$game_dir")" >/dev/null)
[ -f "$build/index.html" ] || { echo "No web build at $build" >&2; exit 1; }

out=$(mktemp -d)
if [ "${1:-}" != "--preview" ]; then
  git clone --quiet --branch gh-pages --single-branch "$(git -C "$game_dir" remote get-url origin)" "$out"
  find "$out" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
fi

cp -R "$game_dir/site/." "$out/"
cp "$game_dir/sprites/sprites.png" "$out/media/sprites.png"
mkdir -p "$out/play"
cp -R "$build/." "$out/play/"
touch "$out/.nojekyll"

if [ "${1:-}" = "--preview" ]; then
  echo "$out"
  exit 0
fi

git -C "$out" add -A
if git -C "$out" diff --cached --quiet; then
  echo "Nothing to publish"
else
  git -C "$out" commit --quiet -m "Publish $(git -C "$game_dir" rev-parse --short HEAD)"
  git -C "$out" push --quiet origin gh-pages
  echo "Published to gh-pages"
fi
