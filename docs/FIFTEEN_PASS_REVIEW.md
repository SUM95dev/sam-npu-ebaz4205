# Passes 11–15 review summary

This package continues the earlier ten review passes with five additional independent checks.

## Pass 11 — Controller/flush timing
Found and fixed a registered-control off-by-one bug in the systolic drain phase.
Previously `flush_en` was asserted too late, so the array saw one fewer zero-flush beat than required; for N=2 it could see zero flush beats. The controller now pre-asserts `flush_en` when the final feed beat is accepted, and deasserts it only after the N-1th drain edge has actually reached the PE array.

Added `tb_controller_flush_cycles.v` to require exactly 1 flush beat for N=2 and 7 for N=8.

## Pass 12 — Arithmetic/resource review
Rechecked signed INT8 multiply, INT32 accumulation, 33-bit bias addition, 65-bit requant product, arithmetic shift, ReLU, zero point and saturation. No new numerical-width bug found in this pass.

The tile postprocessor intentionally shares one requant unit across all lanes to avoid replicating a large programmable multiplier 64 times.

## Pass 13 — Start/config race
Found and fixed a one-clock race after START acceptance. Engine `busy` rises one clock after `start_pulse`, so configuration writes could previously slip into that gap. `npu_regs` now locks configuration while either `busy` or `start_pulse` is asserted.

Added `tb_regs_start_lock.v`.

## Pass 14 — Independent cycle/dataflow audit
An independent Python model tested 1000 random matrix shapes across systolic sizes 1, 2, 4 and 8, all output tiles, and random feeder stalls. All valid output lanes matched software matrix multiplication.

The model uses K+N-1 accepted skewed input beats followed by exactly N-1 zero flush beats.

## Pass 15 — Integration/testability audit
Rechecked module hierarchy, real instantiation sites, lexical begin/end/module/bracket balance, feeder contract, partial-tile mask ordering, register status semantics and top-level testbench compatibility.

No additional RTL bug was found after the pass-11 and pass-13 fixes.

## Important remaining verification boundary
No Verilog compiler/simulator is installed in the generation environment. Therefore syntax/elaboration/xsim execution and Vivado synthesis/timing are still required before claiming hardware-verified RTL.
