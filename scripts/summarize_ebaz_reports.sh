#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "=== Sam NPU EBAZ4205 report summary ==="
for f in "$ROOT"/reports_ebaz/utilization_synth.rpt "$ROOT"/reports_ebaz/utilization_impl.rpt; do
  [[ -f "$f" ]] || continue
  echo "-- $(basename "$f") --"
  grep -E "Slice LUTs|Slice Registers|Block RAM Tile|DSPs" "$f" || true
done
for f in "$ROOT"/reports_ebaz/timing_synth.rpt "$ROOT"/reports_ebaz/timing_impl.rpt; do
  [[ -f "$f" ]] || continue
  echo "-- $(basename "$f") --"
  grep -A8 -B2 "Design Timing Summary" "$f" | head -14 || true
done
[[ -f "$ROOT/reports_ebaz/route_status.rpt" ]] && { echo "-- route_status --"; grep -E "ROUT|unrouted|routing" "$ROOT/reports_ebaz/route_status.rpt" | head -20 || true; }
[[ -f "$ROOT/ebaz_final_build.log" ]] && { echo "-- build status --"; grep -E "STATUS=|ERROR:|CRITICAL WARNING|BUILD FLOW COMPLETE|Board preset applied" "$ROOT/ebaz_final_build.log" | tail -30 || true; }
