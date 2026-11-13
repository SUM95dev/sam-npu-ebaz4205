# REVIEW50 — 20-area full-project engineering review

Date: 2026-11-01. Basis: the uploaded `Sam_NPU_EBAZ4205_REVIEW50(1).zip`,
plus the derived `REVIEW50_NO_Y3_READY` tree. This is a structured source review,
not twenty independent hardware runs.

## Twenty review areas

| # | Area | Finding | Disposition |
|---:|---|---|---|
| 1 | Archive integrity | ZIP entries extract without CRC errors | PASS |
| 2 | Manifest consistency | Manifest describes 29 RTL files and 55 benches; source inventory is internally represented | PASS |
| 3 | RTL module uniqueness | Existing static audit finds no duplicate production module definitions | PASS |
| 4 | Production hierarchy | 17 modules reachable; 12 legacy/research modules unreachable | PASS with documented boundary |
| 5 | AXI-Lite write channel | AW/W independently buffered; WSTRB propagated | PASS by static audit; XSim not rerun here |
| 6 | AXI-Lite read channel | Address/data timing regression covered by existing tests | PASS by recorded regression; no fresh HDL simulator here |
| 7 | MatMul arithmetic | INT8 products, INT32 accumulation and widened post-processing | PASS by existing audits/model tests |
| 8 | MatMul tiling | Partial tiles and randomized shapes checked by cycle audit | PASS (1000 randomized shapes in release validation) |
| 9 | MatMul output flow control | Serializer snapshots data and honors backpressure | PASS by static audit and recorded RTL regression |
| 10 | MatMul completion | DONE waits for final AXI-stream drain | PASS by static audit and recorded regression |
| 11 | Conv stream framing | Per-output marker and whole-job TLAST contract validated in server/packer | PASS by source audit |
| 12 | Conv arithmetic bounds | Host/server reject more than 131071 worst-case MACs per output | PASS by source audit and client test |
| 13 | Conv2D hardware scheduler | Legacy memory-address scheduler is not in production hierarchy | LIMITATION documented; not represented as active |
| 14 | Host Conv2D lowering | NHWC/OHWI packer exists; network client lacked a convenient integrated method | FIXED: added `NpuSession.conv_nhwc` and `conv` CLI |
| 15 | MaxPool/Add streams | Framing helpers and server byte-contract checks exist | PASS by existing audits |
| 16 | DMA driver | Coherent-buffer ownership, close safety and abort paths statically audited | PASS by recorded tests; ARM runtime unverified |
| 17 | TCP protocol | Fixed headers, exact reads, request IDs, capability checks and timeouts | PASS: 50/50 checks rerun |
| 18 | Ethernet GEM0/MII | EMIO and pin constraints exist; PHY timing/physical link remain board-dependent | SOURCE PASS; hardware unverified |
| 19 | No-Y3 PHY clock | FCLK1 25 MHz to U18 is guarded by R1485 confirmation | SOURCE PASS; R1485 physical state unknown |
| 20 | Full model runtime / bitstream | SNPU pack/inspect and limited ONNX conversion exist, but no complete arbitrary graph executor; PS7 preset, Vivado timing and board acceptance are open | LIMITATION documented; hardware gate remains open |

## Freshly executed in this review environment

- `verification/review50/run_50_checks.py`: **50/50 PASS**.
- `scripts/validate_release.sh`: **PASS**, including 25/25, 36/36, 30/30, 30/30 static audits, Python syntax, C builds, kernel-module build against the available x86-64 headers, existing 11 software tests and 50 directed checks.
- New host Conv tests: **3/3 PASS**.
- Python syntax and CLI help for the new `conv` command: PASS.

## Not freshly executed / not claimed

No Vivado, XSim, Icarus or Verilator executable is available in this environment.
Therefore the 55 RTL regressions are prior recorded evidence, not a fresh run.
No EBAZ4205 board, PHY link, R1485 continuity, PS7 DDR preset, routed timing,
bitstream, Linux-on-ARM, DMA hardware transfer or real inference was tested.

## Completeness decision

REVIEW50 is a substantial INT8 accelerator subsystem with MatMul/Dense,
streaming Conv MAC, host-lowered grouped/depthwise Conv, MaxPool2x2 and Add.
It is **not yet a complete general-purpose NPU platform**: arbitrary ONNX graphs
are not executed directly, the SNPU file is not consumed by an on-board graph
runtime, the memory-address Conv2D scheduler is not integrated, and physical
board acceptance is open. The new Conv helper closes one practical host API gap;
it does not change those architectural limits.
