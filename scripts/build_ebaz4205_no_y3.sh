#!/usr/bin/env bash
# Canonical REVIEW50 build profile for EBAZ4205 boards with Y3 absent.
# The hardware must have R1485 bridged so FPGA U18 reaches IP101GA pin 47.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${CONFIRM_R1485_BRIDGED:-0}" != "1" ]]; then
  cat >&2 <<'MSG'
ERROR: no-Y3 Ethernet clock profile not enabled.
Before building, verify that R1485 is bridged (0-ohm link) on this board.
This connects FPGA U18 to IP101GA pin 47 (25 MHz reference input).
If you have verified the link, run:
  CONFIRM_R1485_BRIDGED=1 ./scripts/build_ebaz4205_no_y3.sh
MSG
  exit 2
fi

export EBAZ_PHY_CLOCK_FROM_PL=1
exec "$ROOT/scripts/build_ebaz4205_final.sh" "$@"
