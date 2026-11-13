#!/usr/bin/env bash
# Canonical one-command release gate + Vivado build.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIVADO="${VIVADO_BIN:-/home/sum/Xilinx/Vivado/2020.2/bin/vivado}"
RUN_STATIC_CHECKS="${RUN_STATIC_CHECKS:-1}"
RUN_XSIM="${RUN_XSIM:-1}"
if [[ ! -x "$VIVADO" ]]; then
  echo "ERROR: Vivado not found at $VIVADO. Set VIVADO_BIN=/path/to/vivado" >&2
  exit 2
fi
cd "$ROOT"

if [[ ! -f "$ROOT/third_party/EBAZ4205_BoardSupport/board_files/ebaz4205/1.1/board.xml" ]]; then
  echo "Board support is not present. Fetching it now..."
  "$ROOT/scripts/fetch_ebaz4205_board_support.sh"
fi

if [[ "$RUN_STATIC_CHECKS" == "1" ]]; then
  echo "=== RELEASE STATIC VALIDATION ==="
  "$ROOT/scripts/validate_release.sh" | tee release_static_validation.log
fi

if [[ "$RUN_XSIM" == "1" ]]; then
  echo "=== 55-TEST XSIM + CORE SYNTHESIS ==="
  "$VIVADO" -mode batch -source scripts/run_vivado_verification.tcl | tee full_verify.log
  grep -q 'SIM SUMMARY: PASS=55 FAIL=0' full_verify.log || {
    echo "ERROR: strict 55/55 XSim gate not observed" >&2; exit 4;
  }
fi

echo "=== FULL EBAZ4205 SYNTHESIS + IMPLEMENTATION + BITSTREAM ==="
RUN_SYNTH=1 RUN_IMPL=1 "$VIVADO" -mode batch -source scripts/build_ebaz4205_system.tcl | tee ebaz_final_build.log

grep -q '^BUILD FLOW COMPLETE$' ebaz_final_build.log || {
  echo "ERROR: full build did not reach its final completion marker" >&2; exit 5;
}
echo "=== REPORT SUMMARY ==="
"$ROOT/scripts/summarize_ebaz_reports.sh" || true

echo "FINAL BUILD FLOW FINISHED. Review timing/DRC and then perform physical Ethernet/DMA self-test."
