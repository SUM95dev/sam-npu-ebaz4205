#!/usr/bin/env bash
# Install the already-fetched EBAZ4205 board definition into Vivado 2020.2's
# always-scanned board_files directory. This is the most robust fallback when
# a project-local board.repoPaths entry is not enumerated by a particular
# Vivado 2020.2 installation/session.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIVADO_ROOT="${VIVADO_ROOT:-/home/sum/Xilinx/Vivado/2020.2}"
SRC="$ROOT/third_party/EBAZ4205_BoardSupport/board_files/ebaz4205/1.1"
DST="$VIVADO_ROOT/data/boards/board_files/ebaz4205/1.1"

if [[ ! -f "$SRC/board.xml" || ! -f "$SRC/preset.xml" ]]; then
  echo "ERROR: board support is not fetched. Run ./scripts/fetch_ebaz4205_board_support.sh first." >&2
  exit 2
fi
if [[ ! -d "$VIVADO_ROOT/data/boards/board_files" ]]; then
  echo "ERROR: Vivado board directory not found under $VIVADO_ROOT" >&2
  echo "Set VIVADO_ROOT=/path/to/Xilinx/Vivado/2020.2" >&2
  exit 3
fi

copy_files() {
  mkdir -p "$DST"
  cp -a "$SRC/." "$DST/"
}
if [[ -w "$VIVADO_ROOT/data/boards/board_files" ]]; then
  copy_files
else
  sudo mkdir -p "$DST"
  sudo cp -a "$SRC/." "$DST/"
fi

echo "Installed EBAZ4205 board files to: $DST"
echo "Verify with:"
echo "$VIVADO_ROOT/bin/vivado -mode tcl <<'TCL'"
echo 'puts [get_board_parts -nocase *ebaz*]'
echo 'exit'
echo 'TCL'
