#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/docs/references/ucla-source/Edukit_Rotary_Inverted_Pendulum_Project"
URL="https://github.com/wjkaiser/Edukit_Rotary_Inverted_Pendulum_Project.git"

mkdir -p "$(dirname "$DEST")"

if [ -d "$DEST/.git" ]; then
  echo "UCLA reference already cloned: $DEST"
  git -C "$DEST" fetch --all --prune
  git -C "$DEST" status --short
else
  git clone "$URL" "$DEST"
fi

echo
echo "UCLA reference ready at:"
echo "$DEST"
