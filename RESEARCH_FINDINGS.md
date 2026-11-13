> Historical review of the preceding RESEARCH_CANDIDATE. For this revised pipeline source see PIPELINE_CHANGES.md. Its counts and timing statements supersede this historical report.

# Sam NPU — focused research and executable RTL review

Date: 2026-10-30. Baseline: FULLFIX ZIP SHA-256
`ca9b89d8b25d43ad350dd1f66a20ed3c99969e8cf1371142dc546dc5595b648e`.
This is a separate review candidate. The user's active build was not modified.

## New confirmed RTL defect: continuous input crosses a tile boundary

In `rtl/matmul_controller.v`, the final accepted S_FEED beat changes the FSM
to S_FLUSH but leaves registered `feed_req` asserted for another cycle.
`axis_matmul_feeder` uses that request directly as AXIS readiness. A continuously
valid DMA stream therefore transfers the first beat of the next tile too early.
That beat can contaminate the current calculation, be lost for the next tile,
or be interpreted as a bias preamble while the controller is flushing.

Reproduction on untouched FULLFIX, 8x8 array, M=1 N=9 K=1:
`MISMATCH idx=0 got=-4 expected=-2`, 8/9 outputs, DONE remains zero.
The exact generated RTL test is `verification/extra/case_0_0.v`.
Before/after transcripts are in `verification/evidence/`.

Fix: assign `feed_req <= 0` on the same edge accepting the last feed beat.
The last beat is still accepted using the pre-edge value; the next cycle is
no longer advertised as ready. Flush timing remains unchanged.

## Previously reported CONTROL WSTRB defect, now dynamically reproduced

CONTROL mode fields changed even with `wr_strb[0]=0`, although START was guarded.
`verification/extra/tb_control_wstrb.v` fails on baseline and passes after gating
the CONTROL case on `wr_strb[0]`. Zero-strobe and high-byte-only writes are checked.

## Other included corrections

- Regenerated the shipped SNPU example as v2 using the existing packer.
- Removed `-force` from report commands in the board-build Tcl; retained it on
  commands with different semantics such as `write_hw_platform`.
- Original FULLFIX files were preserved separately; this archive is not a
  replacement of the source currently used by the running Vivado build.

## Executed verification

Icarus Verilog 12.0, Verilog-2005 mode: **50/50 PASS**.
- Original 28 supplied testbenches, with no test expectation weakened.
- 20 fixed-vector 8x8 system tests: ten M/N/K shapes, each with and without
  streamed bias; uninterrupted input, periodic output backpressure, numeric
  comparison of every output, TLAST and completion checks.
- One additional 2x2 continuous-input reproduction.
- One CONTROL byte-strobe regression.

`verification/run_iverilog.py` runs these cases using installed `iverilog`/`vvp`.
It returns a nonzero exit on compilation failure, timeout, missing PASS, FAIL,
or a numerical MISMATCH, and writes full results to evidence JSON.

`scripts/validate_release.sh` also passed. Kernel-module compilation was skipped
because this environment has no suitable headers. The 28-test Vivado suite is
unchanged; the 22 additional tests live under `verification/extra` and are NOT
automatically included by the old XSim Tcl. Run them via the supplied Icarus
runner or explicitly add them to a separate XSim verification project.

No new Vivado synthesis, timing, implementation, power measurement, or physical
DMA/network test was performed on this candidate. Prior FULLFIX synthesis and
XSim evidence must not be attributed to this changed RTL revision.

## Primary sources inspected and engineering takeaways

1. https://github.com/ZipCPU/wb2axip/blob/master/rtl/easyaxil.v
   Read the Verilog write/read handshake, byte-strobe merge and formal-property
   sections. Useful reference for separating accepted transactions from output
   response holding and preserving untouched bytes.
2. https://github.com/alexforencich/verilog-axis/blob/master/rtl/axis_register.v
   Read the Verilog simple-buffer and skid-buffer implementation, including
   ready lookahead and temporary payload/sideband storage. The practical lesson
   for Sam NPU is to test continuous traffic and READY transitions at boundaries,
   not only individual beats separated by idle cycles.
3. https://github.com/ucb-bar/gemmini
   Read architecture documentation on banked scratchpads, accumulator memory,
   independent load/store/execute controllers and tiling. This is architectural
   reference material; its generator is Chisel, not drop-in Verilog for Zynq-7010.
   Such buffering/data reuse remains a future performance change in Sam NPU.
4. https://github.com/nvdla/hw
   Inspected repository scope and architecture references. Individual requested
   MAC source pages could not be fetched, so no line-by-line NVDLA MAC comparison
   or NVDLA simulation is claimed.

Several smaller systolic projects were located, but individual source fetches
were unavailable. README performance claims were not treated as verified facts.
No third-party RTL was copied into this candidate.

## Integration caution

Do not copy this candidate over an active Vivado run. Finish the current run
and retain its logs first. This candidate changes RTL and requires a fresh
synthesis/implementation in a separate project before hardware validation.
The previously supplied resume script only resumes the existing FULLFIX design;
it does not install these RTL fixes into the checkpoint.
