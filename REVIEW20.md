# بازبینی نسخهٔ اصلاح‌شده — ۲۰ محور

این نسخه شامل اصلاحات تازه و شواهد اجرای تست است. «۲۰ محور بررسی» به معنی ۲۰ بار اثبات کامل تمام پروژه نیست. هیچ ادعایی مبنی بر نبود همهٔ باگ‌ها، بسته‌شدن timing یا آماده‌بودن برد مطرح نمی‌شود.

## Changes in this revision

- **Conv final-input fence:** after accepting the final scalar's final sample, do not accept any further input until completion and a new START. Previously a stalled final output allowed an extra sample to enter the core. The new test fails against INTEGRATED_FIX and passes here, including restart.
- **Integer fidelity:** model, MatMul, Conv and network packers now require integer inputs via `operator.index`; fractional floats, NaN and infinity cannot silently become quantized tensor values. This intentionally rejects even integral floats and numeric strings. Quantize explicitly before packing.
- **SNPU inspection:** reject empty layer lists, zero matrix dimensions, zero Conv geometry/stride and kernels larger than the padded input; close files deterministically.
- **Network reply framing:** check reply length against the requested output size (or the 28-byte INFO record) before reading a body. Close the connection on mismatch.
- **Bare-metal DMA:** include cache declarations; validate exact feed/result sizes; reject busy hardware; flush output before DMA; wait for both channels after NPU completion; cancel/reset DMA on submission failure and timeout; bound reset polling. The mock checks sequencing and failure recovery, not real BSP/cache behavior. Callers must use dedicated, properly aligned cache-line buffers and a configured simple-mode DMA.
- **ONNX rejection paths:** preserve string attributes; reject unsupported auto-padding, pool dilation/ceil/storage-order and indices outputs; reject nonconstant Conv/Gemm bias rather than silently dropping it. Full ONNX integration was not run because ONNX is not installed.
- Add the Conv regression to both Icarus and the Vivado suite; increase the build gate to **52**. Keep the long exhaustive Add test separate from XSim's 200us per-test limit.

## Review record

These are 20 scoped review passes with different concerns. They are not 20 independent whole-project certifications. Static audit assertions and simulation tests are different kinds of evidence.

| Pass | Concern | Evidence / finding |
|---|---|---|
| 1 | Source inventory and production hierarchy | 29 RTL files; 17 reachable production modules; 12 legacy/research modules. Inventory audit retained. |
| 2 | AXI-Lite read/write sequencing | Existing independent AW/W/read tests in the 52-case dynamic suite pass. |
| 3 | Register strobes and configuration locking | Existing WSTRB, invalid-configuration and config-lock tests pass. Streamed-bias bit is meaningful only in MatMul mode. |
| 4 | MatMul tile scheduling and feed boundaries | Continuous-input regression and 20 shape/bias regressions pass; previous feed_req fix retained. |
| 5 | Signed MAC and skew/drain behavior | Numerical golden tests and cycle audit pass; cycle audit covers 1000 random shapes with stalls. |
| 6 | MatMul bias stream and padding | Existing preamble and edge-tile tests pass; independent host/standalone packer comparisons pass. |
| 7 | Requantization pipeline | Existing equivalence test passes, including 9230 valid outputs, signed extremes and bubbles. |
| 8 | Output ordering and backpressure | Multi-tile order, lane-mask and DONE-after-final-output tests pass. Userspace layout test compiles and runs in audits. |
| 9 | Conv scalar accumulation and configuration | Existing Conv bias/configuration/multi-output tests pass with pipelined latency. |
| 10 | Conv end-of-job and restart | New final-fence defect reproduced before fix; regression now passes under final-output stall and continuous next input. |
| 11 | Add arithmetic and saturation | Exhaustively tested all 65536 signed INT8 pairs, both ReLU settings: **131072 comparisons**, with periodic backpressure. |
| 12 | MaxPool signed comparison and packet grouping | Existing dynamic MaxPool test passes. Raw malformed streams still require software validation/timeout; arbitrary early TLAST is not repaired by hardware. |
| 13 | Reset, abort, IRQ and counters | Existing reset/abort/register/IRQ tests in dynamic suite pass; physical IRQ/DMA cancellation still needs board testing. |
| 14 | Tensor integer/range/shape validation | Fractional truncation fixed; boundary, malformed-input and cross-packer tests pass. |
| 15 | SNPU binary validation | Empty/zero/invalid geometry fixed; valid package, every truncation and trailing-byte checks pass. |
| 16 | ONNX subset preservation | Unsupported spatial attributes/dynamic bias rejected; attribute helper tests pass. Actual ONNX model conversion is **not integration-tested** here; graph topology/runtime is still limited. |
| 17 | TCP framing and disconnect recovery | Mock fragmented reply, wrong ID/magic/status, disconnect and oversized body tests pass. No live board/network test. |
| 18 | C userspace, bare-metal and kernel lifetime | Userspace warning-clean builds pass; new bare-metal mocks pass. Kernel build skipped: headers unavailable. DMA proxy is a bring-up driver; concurrent same-fd ioctls and device removal with open mappings remain unvalidated and require hardening before general deployment. |
| 19 | Vivado flow, constraints and timing gates | Shell/static/Tcl structure checks pass; 52-case XSim gate integrated. No Vivado execution here. PHY I/O delays, PS7/MIO warnings and routed timing remain open hardware acceptance items. |
| 20 | Regression, packaging and evidence | Full 52-case RTL suite passes, 11 software test methods pass, exhaustive Add passes, static release gates pass. Source hashes and ZIP CRC checked at packaging. |

## Reproduce

```bash
bash scripts/validate_release.sh
python3 verification/run_iverilog.py
python3 verification/review20/run_exhaustive.py
```

The last two need Icarus Verilog (`iverilog`, `vvp`). Optional environment variables: `IVERILOG`, `VVP`, `IVERILOG_BASE`. `validate_release.sh` runs the software and bare-metal mock tests and builds Linux userspace programs. A real Xilinx BSP build and target kernel-module build remain necessary.

## Hardware acceptance still required

Use a **fresh full build** for this changed RTL, not a routed checkpoint from FULLFIX:

```bash
bash scripts/build_ebaz4205_final.sh
```

The historical FULLFIX run routed but failed setup with WNS **−18.791 ns**. That number is not a timing result for this revision. The new pipeline is functionally tested; only a new Vivado route can establish its timing and utilization. Confirm exact board/speed grade, PS7 DDR/MIO preset, MII I/O timing, DRC and unconstrained paths, then run Ethernet/DMA selftests on the physical board. Do not disable checks or add blanket false paths to claim success.

## Evidence

`verification/evidence/review20_*.log` and `iverilog_results.json` contain this run's results. Files without the `review20_` prefix may contain historical evidence; `iverilog_results.json` is current. Historical documents below this root do not supersede this file.

Bare-metal sequencing reference: AMD/Xilinx's official [simple polling example](https://github.com/Xilinx/embeddedsw/blob/master/XilinxProcessorIPLib/drivers/axidma/examples/xaxidma_example_simple_poll.c), which checks both DMA directions before consuming received data. Our reset/error tests use host mocks.
