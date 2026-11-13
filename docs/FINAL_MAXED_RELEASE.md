# Sam NPU EBAZ4205 — Final Maxed Source Release

This release extends the five-pass audited baseline without increasing the 8x8
MAC array (the previous XC7Z010 synthesis already used 72/80 DSPs). The added
features are deliberately LUT/control-heavy so they should not require another
large DSP allocation, but **new utilization must still be measured in Vivado**.

## Newly integrated hardware features

- four execution modes: MatMul, streaming Conv, MaxPool2x2, elementwise INT8 Add
- per-output INT32 bias for streaming Conv
- streamed INT32 column bias for MatMul/Dense, with backward-compatible no-bias packets
- grouped/depthwise Conv support through stream packing
- sticky completion IRQ with PS fabric-interrupt connection
- hardware ABORT command for stalled jobs
- version/capability discovery registers
- total/busy/job/error/last-job cycle counters
- network INFO opcode and hardware telemetry
- persistent TCP host sessions and latency/GOPS benchmark tool
- strict SNPU package validation and strict ONNX quantized-weight conversion
- network-side Conv framing checks
- board self-test covering MatMul, Add, MaxPool, Conv+bias and depthwise Conv

## Verification state

Source-only validation in the packaging environment:
- legacy 50-point audit: PASS
- five-pass full-source audit: PASS 25/25
- final release audit: PASS 36/36
- second independent five-pass audit: PASS 30/30
- third independent five-pass audit: PASS 30/30
- 28 behavioral testbenches are present and listed by the Vivado verification flow
- Python tools compile
- Linux userspace tools compile warning-free
- grouped/depthwise Conv packet contract randomized against the golden model
- board network self-test packet construction passes in dry-run mode

The packaging environment does **not** contain Vivado/XSim. Therefore the new
28-test suite has not been executed here and no post-change synthesis/timing or
bitstream result is claimed.

## Remaining proof obligations on the user's machine/board

1. Vivado XSim: require `SIM SUMMARY: PASS=28 FAIL=0`.
2. Full-system synthesis with the real `aliexpress:ebaz4205:part0:1.1` preset.
3. Review new LUT/FF/DSP/BRAM utilization and DRC.
4. Add/validate exact MII I/O delays from the actual PHY/board timing data and close timing.
5. Implementation + bitstream.
6. Linux boot, Ethernet PHY link and `ping`.
7. Load DMA/UIO support and run `sw/host/npu_board_selftest.py` against the board.
8. Benchmark realistic layers and then optimize DDR/DMA scheduling.

## Explicit non-claims / future v3 work

- MatMul/Dense now supports the usual per-output-column INT32 bias through an
  optional stream preamble. Arbitrary per-element MxN bias matrices are not
  exposed by the network protocol.
- No hardware Softmax/GELU/LayerNorm; these are poor first targets for the tiny
  XC7Z010 once 90% of DSPs are already occupied.
- No complete graph compiler, automatic fusion planner, sparsity engine or
  multi-cluster scheduler.
- The full spatial Conv memory-side engine exists as RTL research/integration
  work, while the network-ready Conv path intentionally uses software-packed
  windows for deterministic first-board bring-up.

## Canonical final gate

The canonical one-command build is `./scripts/build_ebaz4205_final.sh`. On the 4 GiB development laptop it defaults to one Vivado worker and disables XSim elaboration multithreading; use `VIVADO_JOBS`/`XSIM_MT_LEVEL` only to opt into more parallelism on a larger machine. It runs
source validation and the strict 28/28 XSim gate before attempting full-board
synthesis/implementation/bitstream. Physical Ethernet link, DMA and numerical
self-test remain mandatory after programming the real board.

## Packaged-source validation result

The final packaged source was revalidated after the streamed MatMul-bias,
persistent-session, benchmark and strict compiler changes:

- legacy audit: `50/50 PASS`
- five-pass source audit: `25/25 PASS`
- final release audit: `36/36 PASS`
- second five-pass audit: `30/30 PASS`
- third five-pass audit: `30/30 PASS`
- userspace C: warning-clean
- Linux DMA proxy kernel module: compile PASS against the available 6.12 headers
- exact validation transcript: `docs/FINAL_STATIC_VALIDATION.txt`

These are source/static/build checks, **not** a substitute for the required
Vivado 2020.2 XSim/synthesis/timing/implementation run or physical-board test.
