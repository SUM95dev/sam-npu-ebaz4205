#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "[1/8] Five-pass baseline audit"
python3 scripts/five_pass_source_audit.py

echo "[2/8] Final v2 release audit"
SKIP_BASELINE=1 python3 scripts/final_release_audit.py

echo "[3/8] Second independent five-pass audit"
python3 scripts/five_more_pass_audit.py

echo "[4/8] Third independent five-pass audit"
python3 scripts/third_five_pass_audit.py

echo "[5/8] Python syntax (no pycache writes)"
python3 - <<'PY'
from pathlib import Path
for root in (Path('sw'),Path('scripts')):
    for p in root.rglob('*.py'):
        compile(p.read_text(),str(p),'exec')
print('Python syntax PASS')
PY

echo "[6/8] Required integrated release files"
for f in \
  rtl/npu_bd_top.v rtl/npu_axis_system_top.v rtl/axis_maxpool2x2_engine.v rtl/axis_elementwise_add_engine.v \
  sim/tb_system_done_after_stream.v sim/tb_axi_lite_read_write.v sim/tb_regs_extended.v sim/tb_matmul_multitile_order.v \
  sim/tb_conv_stream_bias.v sim/tb_axis_maxpool.v sim/tb_axis_add.v sim/tb_matmul_bias_feeder.v \
  scripts/build_ebaz4205_system.tcl scripts/create_ebaz4205_full_bd.tcl \
  scripts/run_vivado_verification.tcl scripts/fetch_ebaz4205_board_support.sh scripts/install_ebaz4205_board_support_vivado.sh \
  constraints/ebaz4205_ethernet.xdc \
  sw/linux/npu_dma_proxy.c sw/linux/npu_net_server.c sw/linux/matmul_layout.h sw/linux/matmul_layout_test.c \
  sw/host/npu_net_client.py sw/host/npu_board_selftest.py sw/host/npu_benchmark.py \
  verification/review50/test_conv_client.py verification/review51/test_runtime.py \
  sw/snpu_loader.py sw/host/npu_runtime.py sw/host/npu_emulator.py \
  sw/model_packer.py sw/snpu_inspect.py sw/onnx_to_snpu.py \
  docs/FINAL_MAXED_RELEASE.md docs/SECOND_FIVE_PASS_AUDIT.md docs/THIRD_FIVE_PASS_AUDIT.md docs/REGISTER_STATUS.md \
  scripts/third_five_pass_audit.py; do
  [[ -f "$f" ]] || { echo "MISSING: $f" >&2; exit 3; }
done

echo "[7/8] Tcl/text regressions"
! grep -qE '^[[:space:]]*run all[[:space:]]*$' scripts/run_vivado_verification.tcl
! grep -Rqs 'presets\.xml' scripts
! grep -Rqs 'vivado_system' scripts
if command -v tclsh >/dev/null 2>&1; then
  for f in scripts/*.tcl; do
    tclsh <<TCL
set h [open "$f" r]
set s [read \$h]
close \$h
if {![info complete \$s]} { puts stderr "incomplete Tcl: $f"; exit 1 }
TCL
  done
fi

echo "[8/8] C builds + optional kernel-module compile"
for src in sw/linux/npu_net_server.c sw/linux/npu_dma_proxy_test.c sw/linux/npu_uio.c sw/linux/matmul_layout_test.c; do
  gcc -std=c11 -D_DEFAULT_SOURCE -Wall -Wextra -Werror -O2 "$src" -o "/tmp/$(basename "${src%.c}")_release_check"
done
KDIR="${KDIR:-}"
if [[ -z "$KDIR" ]]; then
  KDIR="$(find /usr/src -maxdepth 1 -type d -name 'linux-headers-*-amd64' 2>/dev/null | sort -V | tail -1 || true)"
fi
if [[ -n "$KDIR" && -f "$KDIR/Makefile" ]]; then
  make -C "$KDIR" M="$ROOT/sw/linux" clean >/dev/null
  make -C "$KDIR" M="$ROOT/sw/linux" modules -j1 >/dev/null
  echo "kernel module compile PASS against $KDIR"
  make -C "$KDIR" M="$ROOT/sw/linux" clean >/dev/null
else
  echo "kernel headers unavailable: module compile skipped"
fi

python3 verification/review20/test_software.py -v
python3 verification/review20/test_baremetal.py

python3 verification/review50/run_50_checks.py
python3 verification/review50/test_conv_client.py -v

echo "FINAL RELEASE STATIC VALIDATION PASS"
python3 -W ignore verification/review51/test_runtime.py
