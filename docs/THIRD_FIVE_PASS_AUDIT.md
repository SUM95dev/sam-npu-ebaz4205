# Third independent five-pass audit

This review is the third set of five distinct source-review passes after the original ten-pass release.

## Passes

1. Reset/clock/CDC discipline.
2. AXI/AXIS protocol and state-machine corner cases.
3. Arithmetic width, sign, and overflow behavior.
4. Host/network/DMA/RTL ABI consistency.
5. Vivado build reproducibility and low-memory safety.

## Fixes made

- Suppressed duplicate memory requests in `conv2d_memory_top` while its registered `sample_fire` pulse is being consumed.
- Widened all `conv2d_addrgen` index arithmetic before multiply/shift, including the INT32 bias offset.
- Defaulted Vivado synthesis/implementation to one worker (`VIVADO_JOBS=1`) for the 4 GiB development laptop.
- Defaulted XSim elaboration multithreading to `off` (`XSIM_MT_LEVEL=off`) to reduce peak RAM usage.
- Added a real 100 MHz `aclk` constraint to core-only synthesis so WNS/TNS are meaningful instead of `NA`.
- Reduced kernel-module validation to `-j1`.

Static third-pass audit result: **30/30 PASS**.

Vivado/XSim and physical-board validation are still required after these source changes.
