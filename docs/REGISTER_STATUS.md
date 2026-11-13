# Sam NPU v2 control/status register map

AXI-Lite base in the EBAZ4205 block design: `0x43C00000` (64 KiB window).
The implemented local register aperture is the low 64 bytes.

| Offset | Name | Access | Meaning |
|---:|---|---|---|
| `0x00` | CONTROL / STATUS | R/W | R: bit0 BUSY, bit1 DONE_STICKY, bit2 CONFIG_ERROR_STICKY, bit3 IRQ. W: bit0 START, bit1 CONV, bit2 MAXPOOL2, bit3 ADD, bit4 MATMUL_BIAS_STREAM. With mode bits 1..3 all zero, START launches MatMul. Bit4 is an option, not a separate execution mode. |
| `0x04` | M | R/W | MatMul rows, 16-bit. |
| `0x08` | N | R/W | MatMul columns, 16-bit. |
| `0x0C` | K | R/W | MatMul reduction dimension, 16-bit. |
| `0x10` | ACT | R/W | bit0 ReLU enable. Used by MatMul/Conv and optional Add-ReLU. |
| `0x14` | COMMAND / IRQ | R/W | R bit0 IRQ_EN. W bit0 IRQ_EN value, bit1 ACK_DONE (W1C), bit2 ACK_ERROR (W1C), bit3 PERF_CLEAR pulse, bit4 ABORT pulse. Use read-modify-write if IRQ_EN must be preserved while issuing a command. |
| `0x18` | QMUL | R/W | signed 32-bit requant multiplier. |
| `0x1C` | QSHIFT | R/W | arithmetic right shift, low 6 bits. |
| `0x20` | ZERO_POINT | R/W | signed INT8 output zero point. |
| `0x24` | VERSION | R | `0x00020000` = hardware/register API v2.0. |
| `0x28` | CAPABILITIES | R | `[31:24]=ACC_W`, `[23:16]=DATA_W`, `[15:8]=array N`; bits 0..7 = MatMul, Conv, MaxPool2x2, Add, Conv per-output bias, IRQ, Abort, streamed MatMul/Dense column bias. |
| `0x2C` | TOTAL_CYCLES | R | Free-running cycles since reset/PERF_CLEAR. |
| `0x30` | BUSY_CYCLES | R | Cycles with an NPU job active. |
| `0x34` | JOB_COUNT | R | Completed jobs. |
| `0x38` | ERROR_COUNT | R | Rejected invalid START requests. |
| `0x3C` | LAST_JOB_CYCLES | R | Busy-cycle count for the most recently completed job. |

## START rules

Only one of CONV/MAXPOOL2/ADD may be selected. All three zero means MatMul.
MatMul additionally requires non-zero M, N and K. MATMUL_BIAS_STREAM may be combined only with the MatMul mode; it makes each tile consume an 8xINT32 bias preamble before the normal A/B feed. An invalid START does not
launch the datapath and sets CONFIG_ERROR_STICKY.

Configuration is locked from accepted START until BUSY clears. The command
register remains writable while BUSY so software can ACK flags or ABORT a
stalled job. ABORT resets datapath state but preserves configuration and
performance registers; software must also cancel pending DMA descriptors.

DONE is sticky so polling cannot miss a one-cycle completion. With IRQ_EN=1,
IRQ stays level-high while DONE_STICKY is set and is cleared by ACK_DONE or by
an accepted new START.
