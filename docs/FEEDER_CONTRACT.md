# MatMul feeder contract

For one output tile `(tile_m, tile_n)`, the engine exposes `feed_step=t` and asserts `feed_req`.
A transfer occurs only when `feed_req && feed_valid` is true.

The external feeder must present already-skewed edge vectors:

- row lane `r`: `a_left[r] = A[tile_m*N + r][t-r]` when `0 <= t-r < K`, otherwise zero.
- column lane `c`: `b_top[c] = B[t-c][tile_n*N + c]` when `0 <= t-c < K`, otherwise zero.

For partial M/N edge tiles, invalid row/column lanes should be driven to zero. The result mask `out_lane_valid` marks which output lanes are architecturally valid.

The controller requests exactly `K + N - 1` feed transfers, then performs `N - 1` zero flush cycles to drain the internal PE forwarding pipeline.

`feed_step` advances only after an accepted transfer, so the source may stall for an arbitrary number of cycles while keeping its current data stable.

## Postprocess stability contract
`bias_flat` must remain stable from the controller's `post_start` event until the shared tile postprocessor completes (`post_done`). The accumulator array is already held stable during this interval.


## Conv stream configuration contract
`conv2d_stream_engine` latches `bias`, `relu_en`, `qmul`, `qshift`, and `zero_point` when a START is accepted. The external source may therefore change those configuration inputs after START without changing the in-flight output. The first activation/weight sample is also allowed on the same cycle as START.
