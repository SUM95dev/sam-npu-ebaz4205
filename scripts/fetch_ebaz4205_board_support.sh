#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/third_party/EBAZ4205_BoardSupport"
REPO="https://github.com/DavidJRichards/EBAZ4205_BoardSupport.git"

# Optional: pass an already-downloaded/cloned repository path as argument 1.
if [[ $# -ge 1 ]]; then
  SRC="$(cd "$1" && pwd)"
  rm -rf "$DEST"
  mkdir -p "$(dirname "$DEST")"
  cp -a "$SRC" "$DEST"
else
  if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git is required, or pass a local EBAZ4205_BoardSupport directory as argument 1." >&2
    exit 2
  fi
  mkdir -p "$(dirname "$DEST")"
  if [[ -d "$DEST/.git" ]]; then
    git -C "$DEST" pull --ff-only
  else
    rm -rf "$DEST"
    git clone --depth 1 "$REPO" "$DEST"
  fi
fi

BOARD_DIR="$DEST/board_files/ebaz4205/1.1"
if [[ ! -f "$BOARD_DIR/board.xml" || ! -f "$BOARD_DIR/preset.xml" ]]; then
  echo "ERROR: expected EBAZ4205 board.xml/preset.xml under $BOARD_DIR" >&2
  exit 3
fi

echo "EBAZ4205 board support ready: $BOARD_DIR"
echo "Downloaded EBAZ4205 board support: $BOARD_DIR"
echo "The build will first try this project-local repository via board.repoPaths."
echo "If Vivado 2020.2 does not enumerate it, run:"
echo "  ./scripts/install_ebaz4205_board_support_vivado.sh"
