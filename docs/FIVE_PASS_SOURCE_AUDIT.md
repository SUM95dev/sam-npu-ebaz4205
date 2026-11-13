# Five-Pass Full-Source Audit

This release was reviewed in five deliberately different passes so that repeating the same static check would not create false confidence.

## Pass 1 — Structural / source integrity
- scanned all RTL and simulation sources for merge markers and basic lexical balance
- checked duplicate module names and named-port consistency
- removed the unused known-broken legacy Conv frontend from the release instead of shipping dead experimental RTL
- reran the existing 50-point static/dataflow audit and randomized cycle-model checks
- verified every listed testbench exists

## Pass 2 — RTL arithmetic, state, handshake and backpressure
Findings/fixes:
- `conv2d_memory_top`: guarded output-width geometry against zero stride / invalid kernel geometry
- `conv2d_memory_top`: ignored stale memory responses unless a matching request is outstanding (or accepted zero-latency)
- `conv2d_gemm_feeder`: guarded variable division/modulo against zero dimensions
- `npu_axis_system_top`: MatMul DONE/BUSY now waits for the final AXI-Stream output packet to drain; config/mode cannot be changed while the serializer is still active
- added `tb_system_done_after_stream.v` to verify the final-beat/backpressure contract

## Pass 3 — Verification integrity
Finding/fix:
- the old Vivado Tcl summary counted a test as PASS whenever XSim returned normally. Most testbenches print `FAIL` and then call normal `$finish`, so a logical failure could have been counted as a pass.
- the verification flow now parses each `simulate.log`, rejects any line beginning with `FAIL`, and requires an explicit line beginning with `PASS`.
- all 22 testbenches contain explicit PASS and FAIL markers.
- `run all` remains removed and simulator runtime is finite.

This means the previous `PASS=20 FAIL=0` result is useful evidence that Vivado ran the suite, but it is not by itself a proof that all 20 logical checks passed. The updated 22-test flow must be rerun.

## Pass 4 — EBAZ4205 board integration
- checked Ethernet pin map against EBAZ4205 references; 14/14 PHY signals match
- kept Ethernet as GEM0 over EMIO/MII
- added 25 MHz clocks for the external MII RX/TX clocks in XDC
- optional PHY-reference clock on U18 remains opt-in because EBAZ4205 hardware variants differ
- NPU and AXI-DMA control windows are deterministic (64 KiB each)
- bitstream helper now calls the canonical guarded board build rather than an obsolete project path

Exact MII I/O delays are intentionally **not guessed**; timing closure must use the actual PHY/board timing requirements.

## Pass 5 — Linux, DMA, network and host contract
Findings/fixes:
- DMA proxy RX `mmap`: normalized `vm_pgoff` before mapping the separate RX coherent allocation
- DMA proxy: added single-owner open/release handling and terminates pending descriptors on close/crash
- DMA proxy source compiled successfully against available Linux 6.12 headers during the audit
- UIO example: added a finite timeout instead of waiting forever if DMA was not armed
- Device-tree UIO fragment no longer overwrites the system's entire `bootargs`
- network server validates alignment and exact MatMul input/output byte counts before starting DMA
- MatMul packers reject empty/ragged/incompatible matrices and oversized dimensions
- Conv packer uses one 32-bit sample in each 128-bit AXI beat, matching the current RTL consumer
- DMA smoke test cancels armed channels before exit

## Remaining proof obligations
1. Run the updated 22-test XSim suite and require `PASS=22 FAIL=0`.
2. Run full-system synthesis with the real EBAZ4205 board preset.
3. Review utilization and timing; add/validate external MII I/O delays from the actual PHY/board timing data.
4. Run implementation and generate bitstream.
5. Boot Linux, verify PHY link and ping, load DMA/UIO support, then run a network MatMul golden test followed by Conv tests.

No source-only audit can replace those five tool/hardware checks.
