# Sam NPU — Second Independent Five-Pass Source Audit

This review was performed after the original five-pass audit and the Final Maxed
feature integration. It deliberately used five different failure models rather
than repeating the same scan.

## Pass 1 — Production hierarchy and reachability

- Built a source-level module dependency graph from `npu_bd_top`.
- Confirmed 17 RTL modules are reachable in the production NPU hierarchy.
- Classified 11 additional RTL modules as legacy/research-only and verified none
  is silently required by the production top.
- Checked duplicate module definitions, merge-conflict markers, and the AXI/AXIS
  production interfaces.

## Pass 2 — Widths, ranges, and arithmetic safety

- Rechecked INT8/INT32 packer range enforcement.
- Added a worst-case INT32 accumulation guard for streaming Conv: no output scalar
  may contain more than 131071 signed INT8 MAC samples.
- Widened legacy Conv geometry/product arithmetic before capability comparisons so
  oversized values cannot wrap and be accepted as small configurations.
- Rechecked postprocess 33x32 widened arithmetic.

## Pass 3 — Protocol/state and multi-tile behavior

- Found that raw hardware MatMul output is compact tile-major for matrices larger
  than one tile. The network ABI now reorders it to conventional row-major before
  returning the result.
- Added `tb_matmul_multitile_order.v`; the strict Vivado suite is now 28 tests.
- Added a C layout unit test plus 300 randomized independent layout checks.
- Rechecked the Tcl verification gate so a test that prints `FAIL` cannot be
  counted as PASS merely because XSim exited normally.

## Pass 4 — Software/RTL contract safety

- Removed remaining silent INT8 clamping from deploy packers.
- Changed the UIO example into a safe register diagnostic; it no longer starts a
  datapath while DMA is unarmed.
- Corrected the bare-metal example to model the real 32-bit DMA result words and
  added a tile-major-to-row-major INT8 unpack helper.
- Rechecked C builds, DMA ownership/close behavior, socket timeouts, and abort paths.

## Pass 5 — Build and reproducibility gates

- Rechecked deterministic NPU/DMA address assignments and EBAZ board-preset guard.
- Added/verified explicit setup **and hold** slack gates after implementation;
  `impl_1` being merely `Complete` is not considered timing success.
- Rechecked known Vivado 2020.2 regressions (`run all`, `report_bd_layout`, and the
  incorrect `presets.xml` name).
- Rechecked all Python sources and the canonical 28/28 build gate.

## Result

`python3 scripts/five_more_pass_audit.py`

Expected source-only result:

`SECOND_FIVE_PASS_AUDIT PASS: 30/30 checks`

This remains a source/static audit. It does **not** replace the required Vivado
2020.2 28/28 XSim run, synthesis/timing/implementation, bitstream generation, or
physical Ethernet/DMA/numerical validation on the EBAZ4205.
