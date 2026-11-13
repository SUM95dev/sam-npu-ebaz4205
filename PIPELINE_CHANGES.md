# Current revision: pipelined postprocess review candidate

## Evidence and scope

User FULLFIX build completed routing with zero unrouted nets, but setup
WNS=-18.791 ns, TNS=-16428.223 ns. Router hold slack was +0.024 ns.
The log mentions optimization of long MatMul postprocess and Conv product,
bias, scaling, shift and output logic. This supports addressing those chains;
it is not a replacement for detailed critical-path reports.
PS7/MIO LOC and generated-XDC warnings remain unresolved without the user's
detailed DRC/constraints. They have NOT been hidden or waived.

## Integrated corrections

1. MatMul final accepted feed beat deasserts feed_req immediately for the next
   cycle, preventing continuous DMA input crossing a tile boundary.
2. CONTROL mode writes honor byte-zero WSTRB; zero/high-only strobes preserve mode.
3. Added npu_postprocess_pipe: biased sum, DSP-sized partial products, two
   registered adder levels, registered variable shift, and final ReLU/zero-point/
   saturation. Six stages, initiation interval one. The old combinational
   npu_postprocess remains for reference/legacy tests, not production hierarchy.
4. Tile postprocess issues one lane per cycle and tracks its index through the
   pipeline. It drains all results before DONE; it does not clear accumulators
   or publish the tile before the final lane is stored.
5. Conv holds the final accumulator and applies pipelined postprocessing.
   sample_ready blocks new MAC samples while the scalar is being finalized.
   The job wrapper respects core readiness. Completion latency has increased;
   external packet format and numerical operations remain unchanged.
6. tb_conv_stream now waits for out_valid rather than assuming zero extra
   postprocess latency. Numerical expectation remains 26.
7. SNPU example regenerated as v2. Unsupported report -force options removed.
8. Bitstream generation is now gated after routed setup/hold checks.
9. Vivado worker count and general.maxThreads default to one. XSim runtime is
   finite at 200us, enough for the 10000-vector equivalence test.

## Executed checks

- Icarus Verilog 12.0, Verilog-2005: 51/51 regressions PASS.
- Includes original 28 benches, 20 8x8 continuous-stream shapes/bias cases,
  2 extra continuous/WSTRB tests, and one pipeline equivalence regression.
- Equivalence test drives 10000 cycles with valid bubbles and checks 9230
  valid outputs, including signed extremes and randomized quantization settings.
- Existing source validation: PASS, after inventory assertions were updated
  to explicitly check all 51 test tops and the new production hierarchy.
- C userspace builds PASS; kernel module compile SKIPPED: headers unavailable.
- New XSim flow includes the additional tests, not just the original 28.

Full transcripts are in verification/evidence. No old test was deleted. These
checks establish functional simulation evidence only. No Vivado synthesis,
DSP utilization, routing, timing closure or board measurement exists for this
pipeline revision. Do not claim that 100 MHz is closed before measuring it.

## Use

Extract into a separate directory; retain the old FULLFIX project and reports.
Do not use resume_fullfix.sh to install this revision: that script resumes an
old checkpoint and cannot incorporate changed RTL without rebuilding.

Optional local RTL regression (requires installed Icarus):
    python3 verification/run_iverilog.py

Canonical complete Vivado build from this new directory:
    bash scripts/build_ebaz4205_final.sh

Expected XSim gate is now SIM SUMMARY: PASS=51 FAIL=0.
The exact EBAZ4205 board revision, DDR preset and PHY clock option still apply.

## Explicit remaining findings

- Full board timing/DRC and PS7/MIO warnings need generated reports.
- External MII input/output delays remain board-specific and unvalidated.
- Production Conv remains software-window-packed scalar MAC, not the systolic
  Conv research path. Pipeline finalization adds scalar latency.
- No graph executor/model-resident service is claimed by the SNPU packer.
- UIO diagnostic BUSY/IRQ bit labels were corrected. Bare-metal DMA
  completion/error recovery still needs target-specific validation; use the network test path for bring-up and inspect
  hardware outputs against golden results.
- A successful new bitstream build still needs physical DMA/Ethernet/numeric tests.
