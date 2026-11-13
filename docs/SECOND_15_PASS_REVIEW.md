# Second 15-pass review (passes 16–30)

This review was performed on the actual Sam_NPU_v4_15_FifteenPass_Reviewed source tree.
No RTL source changes were required during these additional 15 passes.

## Passes
1. Module inventory and source-tree consistency.
2. Named-port / hierarchy consistency across RTL and simulation sources.
3. MatMul FSM state-transition review.
4. feed_req/feed_valid handshake and stall behavior.
5. Systolic feed/flush timing review.
6. PE clear/reset/pipeline-state behavior.
7. INT8 multiply / INT32 accumulation width review.
8. Bias/requant signedness, saturation and shift review.
9. M/N partial-tile masking and edge-lane behavior.
10. Register START/busy/sticky-DONE/config-error semantics.
11. Conv streaming primitive handshake and first/last-sample behavior.
12. Double-buffer controller ordering and pending-bank behavior.
13. Parameter/corner review (N=1, non-power-of-two N, K up to 65535).
14. Independent randomized cycle/dataflow model with stalls.
15. End-to-end integration-contract audit.

## Automated/model results
- Named-port consistency: 0 mismatches across 12 RTL modules and supplied testbenches.
- Existing Python golden model: PASS.
- Existing cycle audit: PASS (1000 random matrix shapes in package script).
- Additional independent tile/dataflow audit: PASS, 4000 randomized cases across N=1,2,3,4,8, including random stalls and edge tiles.
- Worst conservative INT8 accumulation bound for K=65535: 1,073,725,440, which fits signed INT32.

## Important integration contracts (not RTL errors)
- The external MatMul feeder must follow docs/FEEDER_CONTRACT.md and hold the presented beat stable until feed_req && feed_valid is accepted.
- `bias_flat` must remain stable from `post_start` until the shared tile postprocessor asserts `post_done`.
- The Conv block is a streaming dot-product primitive; a full spatial Conv2D window/address/channel scheduler is still not implemented.
- Real AXI-Lite, PS7 DDR, AXI HP/DMA integration, xsim execution, synthesis and timing closure remain external verification/integration stages.

## Current conclusion
After these additional 15 static/manual/model passes, no new RTL logic error was found. This is not a substitute for Vivado xvlog/xelab/xsim and synthesis/timing checks.
