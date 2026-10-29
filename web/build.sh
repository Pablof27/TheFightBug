#!/usr/bin/env bash
# Builds the browser version of the game into dist/web/ (LÖVE 11.5 compiled to WebAssembly by love.js).
#   web/build.sh           build dist/web/
#   web/build.sh --serve   build, then serve it on http://localhost:8000
# Needs zip and Node.js (npx). GitHub Actions runs this same script to publish to GitHub Pages
# (.github/workflows/pages.yml).
set -euo pipefail
cd "$(dirname "$0")/.."

TITLE="TheFightBug"
OUT="dist/web"
# Initial WebAssembly heap. The engine grows it on demand, but starting big enough for the decoded art
# avoids pauses while assets load.
MEMORY=$((256 * 1024 * 1024))
# Davidobot/love.js master: the first LÖVE 11.5 build (the npm package stops at 11.4). It is pinned to a
# commit so builds are reproducible.
LOVEJS="https://github.com/Davidobot/love.js/archive/c4f04e185033a7c9fbefa9be3bec88c41a90421b.tar.gz"

rm -rf "$OUT" dist/game.love
mkdir -p dist

# Only what the game needs at runtime (no tests/, tools/, design/).
zip -9 -r -q -X dist/game.love main.lua conf.lua src lib resources -x '*.DS_Store'

# --compatibility: the single-threaded build. The threaded one needs SharedArrayBuffer, i.e.
# Cross-Origin-Opener/Embedder-Policy headers that GitHub Pages cannot send.
npx --yes "$LOVEJS" dist/game.love "$OUT" --compatibility --title "$TITLE" --memory "$MEMORY"

# love.js mirrors LÖVE's save directory (the save slots) in IndexedDB, but only copies it there when the page unloads,
# which mobile browsers often skip. Expose its file system as Module.FS so that index.html can store every change
# right away (watchSaves there). The pinned love.js mounts the directory exactly once; the build stops if that changes.
node -e '
const fs = require("fs"), file = process.argv[1];
const mount = "FS.mount(IDBFS,{},\"/home/web_user/love\");";
const js = fs.readFileSync(file, "utf8");
if (js.split(mount).length !== 2) { console.error("web/build.sh: love.js changed, cannot expose its file system"); process.exit(1); }
fs.writeFileSync(file, js.replace(mount, mount + "Module.FS=FS;"));
' "$OUT/love.js"

# Use our page (full-window canvas, loading bar, click to start) instead of the love.js template.
rm -rf "$OUT/theme"
BUILD="$(date -u +%Y%m%d%H%M%S)"
sed -e "s/{{title}}/$TITLE/g" -e "s/{{memory}}/$MEMORY/g" -e "s/{{build}}/$BUILD/g" web/index.html > "$OUT/index.html"
cp resources/art/icon.png "$OUT/favicon.png"

echo "Built $OUT ($(du -sh "$OUT" | cut -f1))"

if [ "${1:-}" = "--serve" ]; then
    echo "Serving on http://localhost:8000  (Ctrl+C to stop)"
    python3 -m http.server 8000 --bind 127.0.0.1 --directory "$OUT"
fi
