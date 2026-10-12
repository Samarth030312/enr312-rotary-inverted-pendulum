#!/usr/bin/env bash
# Render an SVG to PNG at its own size with headless Chrome (no other converter needed).
#   scripts/render_svg.sh in.svg [out.png]
set -euo pipefail
in="$(readlink -f "$1")"; out="${2:-${in%.svg}.png}"
read -r W H < <(grep -o 'viewBox="0 0 [0-9]* [0-9]*"' "$in" | head -1 | awk '{print $3, $4}' | tr -d '"')
tmp="$(mktemp --suffix=.png)"
google-chrome --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
  --window-size="$W,$((H + 200))" --screenshot="$tmp" "file://$in" >/dev/null 2>&1
ffmpeg -hide_banner -loglevel error -y -i "$tmp" -vf "crop=$W:$H:0:0" "$out"
rm -f "$tmp"; echo "$out (${W}x${H})"
