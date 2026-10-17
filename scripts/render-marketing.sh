#!/bin/zsh
# Renders docs/marketing/banner.html to PNGs with headless Chrome:
#   docs/banner.png          1280x640  GitHub social preview and README header
#   docs/marketing/insta.png 1080x1350 Instagram portrait post
set -euo pipefail
cd "$(dirname "$0")/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PAGE="file://$PWD/docs/marketing/banner.html"
PROFILE=$(mktemp -d)
render() { # url width height out
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$PROFILE" \
    --force-device-scale-factor=1 --window-size="$2,$3" --screenshot="$4" "$1" >/dev/null 2>&1
}
render "$PAGE?w=1280&h=640" 1280 640 "$PWD/docs/banner.png"
render "$PAGE?w=1080&h=1350&tall=1" 1080 1350 "$PWD/docs/marketing/insta.png"
rm -rf "$PROFILE"
echo "docs/banner.png  docs/marketing/insta.png"
